{-# LANGUAGE ImportQualifiedPost #-}

module Settei.DhallPrototypeTest (tests) where

import Control.Exception (SomeException, try)
import Control.Lens qualified as Lens
import Control.Monad (foldM, unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT, runExceptT, throwE)
import Control.Monad.Trans.State.Strict qualified as State
import Data.Foldable qualified as Foldable
import Data.List.NonEmpty qualified as NonEmpty
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Dhall.Core qualified as Dhall
import Dhall.Import qualified as DhallImport
import Dhall.Parser qualified as DhallParser
import System.Directory qualified as Directory
import System.FilePath qualified as FilePath
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

data PrototypeFailure
  = ImportAlternative
  | DisallowedImport
  | OutsideRoot
  | MissingLocalFile
  | InvalidImportedFile
  deriving stock (Eq, Show)

data ObservedLocalImport = ObservedLocalImport
  { path :: !FilePath,
    mode :: !Dhall.ImportMode,
    semanticHash :: !(Maybe Text)
  }
  deriving stock (Eq, Ord, Show)

tests :: TestTree
tests =
  testGroup
    "Dhall import-policy prototype"
    [ testCase "NoImports rejects before loading" $ do
        expression <- parse "no-imports" "./not-created.dhall"
        rejected <- try @SomeException (DhallImport.assertNoImports expression)
        assertBool "assertNoImports unexpectedly accepted an import" (either (const True) (const False) rejected),
      testCase "local-only records a transitive import closure" $
        withSystemTempDirectory "settei-dhall-prototype" $ \root -> do
          let first = root FilePath.</> "first.dhall"
              second = root FilePath.</> "second.dhall"
          TextIO.writeFile first "./second.dhall"
          TextIO.writeFile second "{ service = { port = 8080 } }"
          expression <- parse "root" "./first.dhall"
          result <- preflightLocal root root expression
          case result of
            Left problem -> assertFailure (show problem)
            Right imports -> fmap FilePath.takeFileName imports @?= ["first.dhall", "second.dhall"],
      testCase "local-only rejects a parent escape" $
        withSystemTempDirectory "settei-dhall-prototype" $ \workspace -> do
          let allowed = workspace FilePath.</> "allowed"
              outside = workspace FilePath.</> "outside.dhall"
          Directory.createDirectory allowed
          TextIO.writeFile outside "{ escaped = True }"
          expression <- parse "root" "../outside.dhall"
          result <- preflightLocal allowed allowed expression
          result @?= Left OutsideRoot,
      testCase "local-only rejects a symlink escape" $
        withSystemTempDirectory "settei-dhall-prototype" $ \workspace -> do
          let allowed = workspace FilePath.</> "allowed"
              outside = workspace FilePath.</> "outside.dhall"
              link = allowed FilePath.</> "linked.dhall"
          Directory.createDirectory allowed
          TextIO.writeFile outside "{ escaped = True }"
          Directory.createFileLink outside link
          expression <- parse "root" "./linked.dhall"
          result <- preflightLocal allowed allowed expression
          result @?= Left OutsideRoot,
      testCase "local-only rejects environment and remote capabilities without using them" $ do
        environment <- parse "environment" "env:SETTEI_DHALL_PROTOTYPE_SECRET"
        remote <- parse "remote" "https://example.com/config.dhall"
        withSystemTempDirectory "settei-dhall-prototype" $ \root -> do
          preflightLocal root root environment >>= (@?= Left DisallowedImport)
          preflightLocal root root remote >>= (@?= Left DisallowedImport),
      testCase "local-only rejects missing and alternative imports" $
        withSystemTempDirectory "settei-dhall-prototype" $ \root -> do
          missing <- parse "missing" "missing"
          alternative <- parse "alternative" "./one.dhall ? ./two.dhall"
          preflightLocal root root missing >>= (@?= Left DisallowedImport)
          preflightLocal root root alternative >>= (@?= Left ImportAlternative),
      testCase "local-only retains a semantic integrity hash structurally" $
        withSystemTempDirectory "settei-dhall-prototype" $ \root -> do
          let imported = root FilePath.</> "hashed.dhall"
          TextIO.writeFile imported "{ value = True }"
          expression <-
            parse
              "hashed"
              "./hashed.dhall sha256:0000000000000000000000000000000000000000000000000000000000000000"
          result <- preflightLocalDetailed root root expression
          case result of
            Left problem -> assertFailure (show problem)
            Right [observed] -> assertBool "semantic hash was discarded" (semanticHash observed /= Nothing)
            Right observed -> assertFailure ("unexpected import closure: " <> show observed)
    ]

parse :: FilePath -> Text -> IO (Dhall.Expr DhallParser.Src Dhall.Import)
parse label input = case DhallParser.exprFromText label input of
  Left problem -> assertFailure (show problem) >> error "unreachable"
  Right expression -> pure expression

preflightLocal :: FilePath -> FilePath -> Dhall.Expr DhallParser.Src Dhall.Import -> IO (Either PrototypeFailure [FilePath])
preflightLocal allowedRoot baseDirectory expression =
  fmap (fmap (fmap path)) (preflightLocalDetailed allowedRoot baseDirectory expression)

preflightLocalDetailed ::
  FilePath ->
  FilePath ->
  Dhall.Expr DhallParser.Src Dhall.Import ->
  IO (Either PrototypeFailure [ObservedLocalImport])
preflightLocalDetailed allowedRoot baseDirectory expression = do
  canonicalRoot <- Directory.canonicalizePath allowedRoot
  fmap
    (fmap (Set.toAscList . snd))
    (runExceptT (visitExpression canonicalRoot Set.empty Set.empty baseDirectory expression))

visitExpression ::
  FilePath ->
  Set FilePath ->
  Set ObservedLocalImport ->
  FilePath ->
  Dhall.Expr DhallParser.Src Dhall.Import ->
  ExceptT PrototypeFailure IO (Set FilePath, Set ObservedLocalImport)
visitExpression allowedRoot visited observed baseDirectory expression = do
  when (hasImportAlternative expression) (throwE ImportAlternative)
  foldM
    (visitImport allowedRoot baseDirectory)
    (visited, observed)
    (Foldable.toList expression)

visitImport ::
  FilePath ->
  FilePath ->
  (Set FilePath, Set ObservedLocalImport) ->
  Dhall.Import ->
  ExceptT PrototypeFailure IO (Set FilePath, Set ObservedLocalImport)
visitImport allowedRoot baseDirectory (visited, observed) importValue =
  case Dhall.importType (Dhall.importHashed importValue) of
    Dhall.Local {} -> do
      candidate <- liftIO (resolveLocalPath baseDirectory importValue)
      exists <- liftIO (Directory.doesFileExist candidate)
      unless exists (throwE MissingLocalFile)
      canonical <- liftIO (Directory.canonicalizePath candidate)
      unless (isWithin allowedRoot canonical) (throwE OutsideRoot)
      let descriptor =
            ObservedLocalImport
              { path = canonical,
                mode = Dhall.importMode importValue,
                semanticHash = fmap (Text.pack . show) (Dhall.hash (Dhall.importHashed importValue))
              }
          observedWithImport = Set.insert descriptor observed
      if Dhall.importMode importValue /= Dhall.Code || Set.member canonical visited
        then pure (visited, observedWithImport)
        else do
          input <- liftIO (TextIO.readFile canonical)
          imported <- case DhallParser.exprFromText canonical input of
            Left _ -> throwE InvalidImportedFile
            Right value -> pure value
          visitExpression
            allowedRoot
            (Set.insert canonical visited)
            observedWithImport
            (FilePath.takeDirectory canonical)
            imported
    _ -> throwE DisallowedImport

resolveLocalPath :: FilePath -> Dhall.Import -> IO FilePath
resolveLocalPath baseDirectory importValue = do
  canonicalBase <- Directory.canonicalizePath baseDirectory
  let status = DhallImport.emptyStatus canonicalBase
      parent = NonEmpty.head (DhallImport._stack status)
  chained <- State.evalStateT (DhallImport.chainImport parent importValue) status
  case Dhall.importType (Dhall.importHashed (DhallImport.chainedImport chained)) of
    Dhall.Local prefix file -> DhallImport.localToPath prefix file
    _ -> error "local import did not remain local after chaining"

hasImportAlternative :: Dhall.Expr s a -> Bool
hasImportAlternative Dhall.ImportAlt {} = True
hasImportAlternative expression = Lens.anyOf Dhall.subExpressions hasImportAlternative expression

isWithin :: FilePath -> FilePath -> Bool
isWithin root candidate =
  let relative = FilePath.makeRelative root candidate
   in not (FilePath.isAbsolute relative)
        && case FilePath.splitDirectories relative of
          ".." : _ -> False
          _ -> True
