{-# LANGUAGE ImportQualifiedPost #-}

-- |
-- Module: Settei.Dhall
-- Description: Typed Dhall sources with enforceable import policies.
module Settei.Dhall
  ( DhallErrorCategory (..),
    DhallImport,
    DhallImportMode (..),
    DhallImportPolicy (..),
    DhallLoadedSource,
    DhallRoot (..),
    DhallSourceError,
    DhallSourceOptions,
    annotateDhallSourceOptions,
    dhallErrorCategory,
    dhallErrorColumn,
    dhallErrorLine,
    dhallErrorMessage,
    dhallErrorName,
    dhallErrorPath,
    dhallExpression,
    dhallImportMode,
    dhallImportPath,
    dhallImportSemanticHash,
    dhallLoadedImports,
    dhallLoadedSource,
    dhallSourceAnnotations,
    dhallSourceImportPolicy,
    dhallSourceName,
    dhallSourceOptions,
    loadDhallSource,
    loadDhallSourceDetailed,
  )
where

import Control.Exception (AsyncException, IOException, SomeException, fromException, throwIO, try)
import Control.Monad (foldM, unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT, runExceptT, throwE)
import Control.Monad.Trans.State.Strict qualified as State
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Bifunctor (first)
import Data.Foldable qualified as Foldable
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Data.Void (Void)
import Dhall.Core qualified as Dhall
import Dhall.Import qualified as UpstreamImport
import Dhall.JSON qualified as DhallJSON
import Dhall.Parser qualified as DhallParser
import Dhall.TypeCheck qualified as DhallTypeCheck
import Settei
import Settei.Prelude
import System.Directory qualified as Directory
import System.FilePath qualified as FilePath
import Text.Megaparsec qualified as Megaparsec

-- | Import capabilities available to version-one callers.
--
-- 'NoImports' rejects every embedded import. 'LocalImportsWithin' accepts only
-- canonical local paths contained by the named directory. Environment, remote,
-- missing, and alternative imports are rejected before upstream evaluation.
data DhallImportPolicy
  = NoImports
  | LocalImportsWithin !FilePath
  deriving stock (Generic, Eq, Show)

-- | A Dhall root supplied as labeled expression text or a file path.
--
-- No 'Show' instance is provided because expression text can contain secrets.
data DhallRoot
  = DhallExpression
      { name :: !Text,
        text :: !Text
      }
  | DhallFile !FilePath
  deriving stock (Generic, Eq)

-- | Construct a labeled in-memory expression without exposing its text through 'Show'.
dhallExpression :: Text -> Text -> DhallRoot
dhallExpression name text = DhallExpression {name, text}

-- | Source naming, policy, and trusted secret-safe annotations.
data DhallSourceOptions = DhallSourceOptions
  { name :: !Text,
    importPolicy :: !DhallImportPolicy,
    annotations :: !(Map Text Text)
  }
  deriving stock (Generic, Eq)

-- | How a local import is interpreted by Dhall.
data DhallImportMode
  = DhallCodeImport
  | DhallRawTextImport
  | DhallRawBytesImport
  | DhallLocationImport
  deriving stock (Generic, Eq, Ord, Show)

-- | One substantiated local import in a cache-independent transitive closure.
data DhallImport = DhallImport
  { path :: !FilePath,
    mode :: !DhallImportMode,
    semanticHash :: !(Maybe Text)
  }
  deriving stock (Generic, Eq, Ord, Show)

-- | A translated source together with its structured import closure.
data DhallLoadedSource = DhallLoadedSource
  { value :: !Source,
    imports :: ![DhallImport]
  }
  deriving stock (Generic)

-- | Stable phases of Dhall adapter failure.
data DhallErrorCategory
  = DhallIoError
  | DhallParseError
  | DhallImportPolicyError
  | DhallImportError
  | DhallTypeError
  | DhallConversionError
  | DhallInvalidKey
  | DhallTopLevelType
  deriving stock (Generic, Eq, Ord, Show)

-- | A secret-safe Dhall input failure.
--
-- The error retains only a stable category, source name, optional safe path, optional
-- one-based position, and fixed message. It never retains source text or an upstream
-- exception.
data DhallSourceError = DhallSourceError
  { category :: !DhallErrorCategory,
    name :: !Text,
    path :: !(Maybe FilePath),
    line :: !(Maybe Int),
    column :: !(Maybe Int),
    message :: !Text
  }
  deriving stock (Generic, Eq, Show)

data PreparedRoot = PreparedRoot
  { label :: !Text,
    baseDirectory :: !FilePath,
    filePath :: !(Maybe FilePath),
    input :: !Text
  }
  deriving stock (Generic)

data PreflightFailure = PreflightFailure
  { category :: !DhallErrorCategory,
    path :: !(Maybe FilePath),
    line :: !(Maybe Int),
    column :: !(Maybe Int),
    message :: !Text
  }
  deriving stock (Generic)

-- | Construct source options with no annotations.
dhallSourceOptions :: Text -> DhallImportPolicy -> DhallSourceOptions
dhallSourceOptions name importPolicy =
  DhallSourceOptions {name, importPolicy, annotations = Map.empty}

-- | Add trusted, secret-safe annotations. Dhall's reserved provenance keys win collisions.
annotateDhallSourceOptions :: Map Text Text -> DhallSourceOptions -> DhallSourceOptions
annotateDhallSourceOptions annotations options = options & #annotations %~ (annotations <>)

-- | Return the source's report name.
dhallSourceName :: DhallSourceOptions -> Text
dhallSourceName options = options ^. #name

-- | Return the enforced import policy.
dhallSourceImportPolicy :: DhallSourceOptions -> DhallImportPolicy
dhallSourceImportPolicy options = options ^. #importPolicy

-- | Return caller-supplied annotations.
dhallSourceAnnotations :: DhallSourceOptions -> Map Text Text
dhallSourceAnnotations options = options ^. #annotations

-- | Return a stable error category.
dhallErrorCategory :: DhallSourceError -> DhallErrorCategory
dhallErrorCategory problem = problem ^. #category

-- | Return the source name associated with an error.
dhallErrorName :: DhallSourceError -> Text
dhallErrorName problem = problem ^. #name

-- | Return a safe relevant path when one is known.
dhallErrorPath :: DhallSourceError -> Maybe FilePath
dhallErrorPath problem = problem ^. #path

-- | Return the one-based line associated with an error, when known.
dhallErrorLine :: DhallSourceError -> Maybe Int
dhallErrorLine problem = problem ^. #line

-- | Return the one-based column associated with an error, when known.
dhallErrorColumn :: DhallSourceError -> Maybe Int
dhallErrorColumn problem = problem ^. #column

-- | Return a fixed secret-safe error message.
dhallErrorMessage :: DhallSourceError -> Text
dhallErrorMessage problem = problem ^. #message

-- | Return a local import's canonical path.
dhallImportPath :: DhallImport -> FilePath
dhallImportPath imported = imported ^. #path

-- | Return how a local import was interpreted.
dhallImportMode :: DhallImport -> DhallImportMode
dhallImportMode imported = imported ^. #mode

-- | Return the import's optional semantic integrity hash.
dhallImportSemanticHash :: DhallImport -> Maybe Text
dhallImportSemanticHash imported = imported ^. #semanticHash

-- | Extract the Settei source from a detailed load result.
dhallLoadedSource :: DhallLoadedSource -> Source
dhallLoadedSource loaded = loaded ^. #value

-- | Return the sorted, de-duplicated transitive local import closure.
dhallLoadedImports :: DhallLoadedSource -> [DhallImport]
dhallLoadedImports loaded = loaded ^. #imports

-- | Evaluate one Dhall root into a Settei source.
loadDhallSource ::
  DhallSourceOptions ->
  DhallRoot ->
  IO (Either (NonEmpty DhallSourceError) Source)
loadDhallSource options root =
  fmap (fmap dhallLoadedSource) (loadDhallSourceDetailed options root)

-- | Evaluate one Dhall root and retain its structured local import closure.
--
-- Evaluation follows the registered @dhall-json@ path: parse, resolve imports,
-- type-check, normalize, convert JSON-compatible values, and translate directly
-- to 'RawValue'. Rendered Dhall or JSON text is never used as an intermediate.
loadDhallSourceDetailed ::
  DhallSourceOptions ->
  DhallRoot ->
  IO (Either (NonEmpty DhallSourceError) DhallLoadedSource)
loadDhallSourceDetailed options root = do
  preparedResult <- prepareRoot options root
  case preparedResult of
    Left problem -> pure (Left (NonEmpty.singleton problem))
    Right prepared ->
      case DhallParser.exprFromText (Text.unpack (prepared ^. #label)) (prepared ^. #input) of
        Left parseError ->
          let (line, column) = parseErrorPosition parseError
           in pure
                ( positionedFailure
                    options
                    DhallParseError
                    (prepared ^. #filePath)
                    line
                    column
                    "invalid Dhall syntax"
                )
        Right expression -> do
          resolvedResult <- resolveExpression options prepared expression
          pure $ do
            (resolved, imports) <- resolvedResult
            case DhallTypeCheck.typeOf resolved of
              Left _ -> failure options DhallTypeError (prepared ^. #filePath) "Dhall expression does not type-check"
              Right _ -> pure ()
            jsonValue <- firstOne options (prepared ^. #filePath) (convertExpression resolved)
            rawValue <- firstOne options (prepared ^. #filePath) (translateRoot jsonValue)
            let provenance = provenanceAnnotations options prepared imports
                sourceValue =
                  locateSource
                    (const (Just (SourceLocation (prepared ^. #label) Nothing Nothing)))
                    ( annotateSource
                        (provenance <> options ^. #annotations)
                        (source (options ^. #name) (FileSource "Dhall") rawValue)
                    )
            pure DhallLoadedSource {value = sourceValue, imports}

prepareRoot :: DhallSourceOptions -> DhallRoot -> IO (Either DhallSourceError PreparedRoot)
prepareRoot options = \case
  DhallExpression name text -> do
    baseResult <- policyBaseDirectory options
    pure
      ( fmap
          (\baseDirectory -> PreparedRoot {label = name, baseDirectory, filePath = Nothing, input = text})
          baseResult
      )
  DhallFile requestedPath -> do
    absoluteResult <- try @IOException (Directory.makeAbsolute requestedPath >>= Directory.canonicalizePath)
    case absoluteResult of
      Left _ -> pure (Left (singleError options DhallIoError (Just requestedPath) "cannot resolve Dhall root path"))
      Right canonicalPath -> do
        permitted <- rootPermitted options canonicalPath
        if not permitted
          then pure (Left (singleError options DhallImportPolicyError (Just canonicalPath) "Dhall root is outside the allowed directory"))
          else do
            inputResult <- try @IOException (TextIO.readFile canonicalPath)
            pure $ case inputResult of
              Left _ -> Left (singleError options DhallIoError (Just canonicalPath) "cannot read Dhall root file")
              Right input ->
                Right
                  PreparedRoot
                    { label = Text.pack canonicalPath,
                      baseDirectory = FilePath.takeDirectory canonicalPath,
                      filePath = Just canonicalPath,
                      input
                    }

policyBaseDirectory :: DhallSourceOptions -> IO (Either DhallSourceError FilePath)
policyBaseDirectory options = case options ^. #importPolicy of
  NoImports -> Right <$> Directory.getCurrentDirectory
  LocalImportsWithin requestedRoot -> do
    result <- try @IOException (Directory.makeAbsolute requestedRoot >>= Directory.canonicalizePath)
    pure $ case result of
      Left _ -> Left (singleError options DhallImportPolicyError (Just requestedRoot) "cannot resolve allowed import directory")
      Right canonicalRoot -> Right canonicalRoot

rootPermitted :: DhallSourceOptions -> FilePath -> IO Bool
rootPermitted options canonicalPath = case options ^. #importPolicy of
  NoImports -> pure True
  LocalImportsWithin requestedRoot -> do
    rootResult <- try @IOException (Directory.makeAbsolute requestedRoot >>= Directory.canonicalizePath)
    pure (either (const False) (`isWithin` canonicalPath) rootResult)

resolveExpression ::
  DhallSourceOptions ->
  PreparedRoot ->
  Dhall.Expr DhallParser.Src Dhall.Import ->
  IO (Either (NonEmpty DhallSourceError) (Dhall.Expr DhallParser.Src Void, [DhallImport]))
resolveExpression options prepared expression = case options ^. #importPolicy of
  NoImports -> do
    result <- try @UpstreamImport.ImportResolutionDisabled (UpstreamImport.assertNoImports expression)
    pure $ case result of
      Left _ -> failure options DhallImportPolicyError (prepared ^. #filePath) "imports are disabled"
      Right resolved -> Right (resolved, [])
  LocalImportsWithin requestedRoot -> do
    canonicalRootResult <- try @IOException (Directory.makeAbsolute requestedRoot >>= Directory.canonicalizePath)
    case canonicalRootResult of
      Left _ -> pure (failure options DhallImportPolicyError (Just requestedRoot) "cannot resolve allowed import directory")
      Right canonicalRoot -> do
        preflightResult <- preflightLocal canonicalRoot (prepared ^. #baseDirectory) expression
        case preflightResult of
          Left problem ->
            pure
              ( positionedFailure
                  options
                  (problem ^. #category)
                  (problem ^. #path)
                  (problem ^. #line)
                  (problem ^. #column)
                  (problem ^. #message)
              )
          Right imports -> do
            let status =
                  (UpstreamImport.emptyStatus (prepared ^. #baseDirectory))
                    { UpstreamImport._semanticCacheMode = UpstreamImport.IgnoreSemanticCache
                    }
            loaded <- try @SomeException (State.runStateT (UpstreamImport.loadWith expression) status)
            case loaded of
              Left exception -> case fromException exception :: Maybe AsyncException of
                Just asynchronous -> throwIO asynchronous
                Nothing -> pure (failure options DhallImportError (prepared ^. #filePath) "Dhall import resolution failed")
              Right (resolved, _) -> pure (Right (resolved, imports))

preflightLocal ::
  FilePath ->
  FilePath ->
  Dhall.Expr DhallParser.Src Dhall.Import ->
  IO (Either PreflightFailure [DhallImport])
preflightLocal canonicalRoot baseDirectory expression =
  fmap
    (fmap (Set.toAscList . snd))
    (runExceptT (visitExpression canonicalRoot Set.empty Set.empty baseDirectory expression))

visitExpression ::
  FilePath ->
  Set FilePath ->
  Set DhallImport ->
  FilePath ->
  Dhall.Expr DhallParser.Src Dhall.Import ->
  ExceptT PreflightFailure IO (Set FilePath, Set DhallImport)
visitExpression allowedRoot visited observed baseDirectory expression = do
  when (hasImportAlternative expression) (throwPreflight DhallImportPolicyError Nothing "import alternatives are not allowed")
  foldM
    (visitImport allowedRoot baseDirectory)
    (visited, observed)
    (Foldable.toList expression)

visitImport ::
  FilePath ->
  FilePath ->
  (Set FilePath, Set DhallImport) ->
  Dhall.Import ->
  ExceptT PreflightFailure IO (Set FilePath, Set DhallImport)
visitImport allowedRoot baseDirectory (visited, observed) importValue =
  case Dhall.importType (Dhall.importHashed importValue) of
    Dhall.Local {} -> do
      requestedResult <- liftIO (try @IOException (resolveLocalPath baseDirectory importValue))
      requestedPath <- case requestedResult of
        Left _ -> throwPreflight DhallImportError Nothing "cannot resolve local import path"
        Right value -> pure value
      exists <- liftIO (Directory.doesFileExist requestedPath)
      unless exists (throwPreflight DhallImportError (Just requestedPath) "local import does not exist")
      canonicalResult <- liftIO (try @IOException (Directory.canonicalizePath requestedPath))
      canonical <- case canonicalResult of
        Left _ -> throwPreflight DhallImportError (Just requestedPath) "cannot canonicalize local import"
        Right value -> pure value
      unless (isWithin allowedRoot canonical) (throwPreflight DhallImportPolicyError (Just canonical) "local import is outside the allowed directory")
      let descriptor =
            DhallImport
              { path = canonical,
                mode = importMode (Dhall.importMode importValue),
                semanticHash = fmap (Text.pack . show) (Dhall.hash (Dhall.importHashed importValue))
              }
          observedWithImport = Set.insert descriptor observed
      if Dhall.importMode importValue /= Dhall.Code || Set.member canonical visited
        then pure (visited, observedWithImport)
        else do
          inputResult <- liftIO (try @IOException (TextIO.readFile canonical))
          input <- case inputResult of
            Left _ -> throwPreflight DhallImportError (Just canonical) "cannot read local import"
            Right value -> pure value
          imported <- case DhallParser.exprFromText canonical input of
            Left parseError ->
              let (line, column) = parseErrorPosition parseError
               in throwPositionedPreflight
                    DhallParseError
                    (Just canonical)
                    line
                    column
                    "invalid syntax in local import"
            Right value -> pure value
          visitExpression
            allowedRoot
            (Set.insert canonical visited)
            observedWithImport
            (FilePath.takeDirectory canonical)
            imported
    Dhall.Env _ -> throwPreflight DhallImportPolicyError Nothing "environment imports are not allowed"
    Dhall.Remote _ -> throwPreflight DhallImportPolicyError Nothing "remote imports are not allowed"
    Dhall.Missing -> throwPreflight DhallImportPolicyError Nothing "missing imports are not allowed"

resolveLocalPath :: FilePath -> Dhall.Import -> IO FilePath
resolveLocalPath baseDirectory importValue = do
  canonicalBase <- Directory.canonicalizePath baseDirectory
  let status = UpstreamImport.emptyStatus canonicalBase
      parent = NonEmpty.head (UpstreamImport._stack status)
  chained <- State.evalStateT (UpstreamImport.chainImport parent importValue) status
  case Dhall.importType (Dhall.importHashed (UpstreamImport.chainedImport chained)) of
    Dhall.Local prefix file -> UpstreamImport.localToPath prefix file
    _ -> error "local import did not remain local after chaining"

hasImportAlternative :: Dhall.Expr s a -> Bool
hasImportAlternative Dhall.ImportAlt {} = True
hasImportAlternative expression = anyOf Dhall.subExpressions hasImportAlternative expression

importMode :: Dhall.ImportMode -> DhallImportMode
importMode = \case
  Dhall.Code -> DhallCodeImport
  Dhall.RawText -> DhallRawTextImport
  Dhall.RawBytes -> DhallRawBytesImport
  Dhall.Location -> DhallLocationImport

convertExpression :: Dhall.Expr s Void -> Either (DhallErrorCategory, Text) Aeson.Value
convertExpression resolved = do
  finite <-
    first
      (const (DhallConversionError, "Dhall value contains a non-finite Double"))
      ( DhallJSON.handleSpecialDoubles
          DhallJSON.ForbidWithinJSON
          (DhallJSON.convertToHomogeneousMaps DhallJSON.NoConversion resolved)
      )
  first
    (const (DhallConversionError, "Dhall value is not JSON-compatible"))
    (DhallJSON.dhallToJSON finite)

translateRoot :: Aeson.Value -> Either (DhallErrorCategory, Text) RawValue
translateRoot value = case value of
  Aeson.Object _ -> translateValue [] value
  _ -> Left (DhallTopLevelType, "top-level Dhall value must be a record")

translateValue :: [Text] -> Aeson.Value -> Either (DhallErrorCategory, Text) RawValue
translateValue path = \case
  Aeson.Null -> Right RawNull
  Aeson.String value -> Right (RawText value)
  Aeson.Bool value -> Right (RawBool value)
  Aeson.Number value -> Right (RawNumber (toRational value))
  Aeson.Array values -> RawArray <$> traverse (translateValue path) (Foldable.toList values)
  Aeson.Object object -> do
    fields <- traverse translateField (AesonKeyMap.toAscList object)
    Right (RawObject (Map.fromAscList fields))
    where
      translateField (rawKey, value) = do
        let key = AesonKey.toText rawKey
        case mkKey (key NonEmpty.:| []) of
          Left _ -> Left (DhallInvalidKey, "Dhall record field is not a valid Settei key segment")
          Right _ -> pure ()
        translated <- translateValue (path <> [key]) value
        pure (key, translated)

provenanceAnnotations :: DhallSourceOptions -> PreparedRoot -> [DhallImport] -> Map Text Text
provenanceAnnotations options prepared imports =
  Map.fromList
    [ ("dhall.root", prepared ^. #label),
      ("dhall.import-policy", policyName (options ^. #importPolicy)),
      ("dhall.import-count", Text.pack (show (length imports))),
      ("dhall.provenance-precision", "root-and-import-closure; leaf-level import attribution unavailable after normalization")
    ]
    <> Map.fromList (concatMap importAnnotations (zip [0 :: Int ..] imports))

importAnnotations :: (Int, DhallImport) -> [(Text, Text)]
importAnnotations (position, imported) =
  let prefix = "dhall.import." <> Text.pack (show position) <> "."
   in [ (prefix <> "kind", "local"),
        (prefix <> "path", Text.pack (imported ^. #path)),
        (prefix <> "mode", importModeName (imported ^. #mode))
      ]
        <> maybe [] (pure . (prefix <> "semantic-hash",)) (imported ^. #semanticHash)

policyName :: DhallImportPolicy -> Text
policyName NoImports = "no-imports"
policyName (LocalImportsWithin _) = "local-imports-within"

importModeName :: DhallImportMode -> Text
importModeName DhallCodeImport = "code"
importModeName DhallRawTextImport = "raw-text"
importModeName DhallRawBytesImport = "raw-bytes"
importModeName DhallLocationImport = "location"

throwPreflight :: DhallErrorCategory -> Maybe FilePath -> Text -> ExceptT PreflightFailure IO a
throwPreflight category path = throwPositionedPreflight category path Nothing Nothing

throwPositionedPreflight ::
  DhallErrorCategory ->
  Maybe FilePath ->
  Maybe Int ->
  Maybe Int ->
  Text ->
  ExceptT PreflightFailure IO a
throwPositionedPreflight category path line column message =
  throwE PreflightFailure {category, path, line, column, message}

isWithin :: FilePath -> FilePath -> Bool
isWithin root pathCandidate =
  let relative = FilePath.makeRelative root pathCandidate
   in not (FilePath.isAbsolute relative)
        && case FilePath.splitDirectories relative of
          ".." : _ -> False
          _ -> True

failure :: DhallSourceOptions -> DhallErrorCategory -> Maybe FilePath -> Text -> Either (NonEmpty DhallSourceError) a
failure options category path = positionedFailure options category path Nothing Nothing

positionedFailure ::
  DhallSourceOptions ->
  DhallErrorCategory ->
  Maybe FilePath ->
  Maybe Int ->
  Maybe Int ->
  Text ->
  Either (NonEmpty DhallSourceError) a
positionedFailure options category path line column message =
  Left (NonEmpty.singleton (positionedError options category path line column message))

singleError :: DhallSourceOptions -> DhallErrorCategory -> Maybe FilePath -> Text -> DhallSourceError
singleError options category path = positionedError options category path Nothing Nothing

positionedError ::
  DhallSourceOptions ->
  DhallErrorCategory ->
  Maybe FilePath ->
  Maybe Int ->
  Maybe Int ->
  Text ->
  DhallSourceError
positionedError options category path line column message =
  DhallSourceError {category, name = options ^. #name, path, line, column, message}

parseErrorPosition :: DhallParser.ParseError -> (Maybe Int, Maybe Int)
parseErrorPosition parseError =
  let bundle = DhallParser.unwrap parseError
      offset = Megaparsec.errorOffset (NonEmpty.head (Megaparsec.bundleErrors bundle))
      reached = Megaparsec.reachOffsetNoLine offset (Megaparsec.bundlePosState bundle)
      position = Megaparsec.pstateSourcePos reached
   in ( Just (Megaparsec.unPos (Megaparsec.sourceLine position)),
        Just (Megaparsec.unPos (Megaparsec.sourceColumn position))
      )

firstOne ::
  DhallSourceOptions ->
  Maybe FilePath ->
  Either (DhallErrorCategory, Text) a ->
  Either (NonEmpty DhallSourceError) a
firstOne options path = first (\(category, message) -> NonEmpty.singleton (singleError options category path message))
