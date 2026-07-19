{-# LANGUAGE ImportQualifiedPost #-}

module Settei.DhallTest (tests) where

import Data.Foldable (traverse_)
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Dhall.Core qualified as DhallCore
import Dhall.Import qualified as DhallImport
import Dhall.Parser qualified as DhallParser
import Paths_settei_dhall qualified as Paths
import Settei
import Settei.Dhall
import Settei.Prelude
import System.Directory qualified as Directory
import System.FilePath qualified as FilePath
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Dhall"
    [ testCase "a typed record becomes a nested source" $ do
        loaded <-
          expectDetailed
            noImportOptions
            ( dhallExpression
                "direct record"
                "{ service = { host = \"api.internal\", port = 8080, enabled = True, tags = [ \"api\", \"public\" ] } }"
            )
        dhallLoadedImports loaded @?= []
        host <- expectCandidate serviceHost (dhallLoadedSource loaded)
        assertRaw (RawText "api.internal") (candidateValue host)
        port <- expectCandidate servicePort (dhallLoadedSource loaded)
        assertRaw (RawNumber 8080) (candidateValue port)
        enabled <- expectCandidate serviceEnabled (dhallLoadedSource loaded)
        assertRaw (RawBool True) (candidateValue enabled)
        tags <- expectCandidate serviceTags (dhallLoadedSource loaded)
        assertRaw (RawArray [RawText "api", RawText "public"]) (candidateValue tags),
      testCase "optional values, unions, and association lists retain the official JSON shape" $ do
        input <-
          expectSource
            noImportOptions
            ( dhallExpression
                "conversion shapes"
                ( Text.unlines
                    [ "{ present = Some \"yes\"",
                      ", absent = None Text",
                      ", choice = < Left : Text | Right : Natural >.Left \"selected\"",
                      ", entries = [ { mapKey = \"one\", mapValue = 1 }, { mapKey = \"two\", mapValue = 2 } ]",
                      "}"
                    ]
                )
            )
        candidateValue <$> expectCandidate presentKey input >>= assertRaw (RawText "yes")
        candidateValue <$> expectCandidate absentKey input >>= assertRaw RawNull
        candidateValue <$> expectCandidate choiceKey input >>= assertRaw (RawText "selected")
        entries <- candidateValue <$> expectCandidate entriesKey input
        assertBool "association list was silently collapsed into an object" (isTwoEntryArray entries),
      testCase "a constructor applies schema defaults before conversion" $ do
        input <-
          expectSource
            noImportOptions
            ( dhallExpression
                "schema evolution"
                ( Text.unlines
                    [ "let Input = { name : Text }",
                      "let Output = { name : Text, description : Optional Text, tags : List Text }",
                      "let default : { description : Optional Text, tags : List Text } =",
                      "      { description = None Text, tags = [] : List Text }",
                      "let make = \\(input : Input) -> default // input",
                      "let value : Output = make { name = \"my-service\" }",
                      "in  { service = value }"
                    ]
                )
            )
        candidateValue <$> expectCandidate serviceName input >>= assertRaw (RawText "my-service")
        candidateValue <$> expectCandidate serviceDescription input >>= assertRaw RawNull
        candidateValue <$> expectCandidate serviceTags input >>= assertRaw (RawArray []),
      testCase "NoImports rejects before opening a missing import" $ do
        problem <- expectError noImportOptions (dhallExpression "disabled import" "./never-opened.dhall")
        dhallErrorCategory problem @?= DhallImportPolicyError
        dhallErrorMessage problem @?= "imports are disabled",
      testCase "local-only records a transitive closure and honest provenance" $
        withSystemTempDirectory "settei-dhall-local" $ \root -> do
          let application = root FilePath.</> "application.dhall"
              service = root FilePath.</> "service.dhall"
              database = root FilePath.</> "database.dhall"
          TextIO.writeFile application "let Service = ./service.dhall in { service = Service }"
          TextIO.writeFile service "let Database = ./database.dhall in { host = \"api.internal\", port = 8080, database = Database }"
          TextIO.writeFile database "{ host = \"db.internal\" }"
          loaded <- expectDetailed (localOptions root) (DhallFile application)
          fmap (FilePath.takeFileName . dhallImportPath) (dhallLoadedImports loaded)
            @?= ["database.dhall", "service.dhall"]
          let input = dhallLoadedSource loaded
          port <- expectCandidate servicePort input
          port ^? to candidateOrigin . #location . _Just . #path
            @?= Just (Text.pack application)
          let annotations = port ^. to candidateOrigin . #annotations
          annotations ^. at "dhall.import-count" @?= Just "2"
          annotations ^. at "dhall.provenance-precision"
            @?= Just "root-and-import-closure; leaf-level import attribution unavailable after normalization"
          let result = resolve defaultResolveOptions [input] (required portSetting)
          _ <- expectResolution result
          let rendered = renderResolutionText (result ^. #report)
          assertBool "text report omitted Dhall root" (Text.pack application `Text.isInfixOf` rendered)
          assertBool
            "text report fabricated leaf attribution"
            ("leaf-level import attribution unavailable after normalization" `Text.isInfixOf` rendered),
      testCase "the packaged local-import fixture survives source distribution" $ do
        application <- Paths.getDataFileName "test/fixtures/characterization/local/application.dhall"
        loaded <- expectDetailed (localOptions (FilePath.takeDirectory application)) (DhallFile application)
        fmap (FilePath.takeFileName . dhallImportPath) (dhallLoadedImports loaded)
          @?= ["database.dhall", "service.dhall"],
      testCase "local-only rejects parent and symlink escapes" $
        withSystemTempDirectory "settei-dhall-escape" $ \workspace -> do
          let allowed = workspace FilePath.</> "allowed"
              externalFile = workspace FilePath.</> "outside.dhall"
              link = allowed FilePath.</> "linked.dhall"
          Directory.createDirectory allowed
          TextIO.writeFile externalFile "{ escaped = True }"
          parentProblem <- expectError (localOptions allowed) (dhallExpression "parent escape" "../outside.dhall")
          dhallErrorCategory parentProblem @?= DhallImportPolicyError
          Directory.createFileLink externalFile link
          symlinkProblem <- expectError (localOptions allowed) (dhallExpression "symlink escape" "./linked.dhall")
          dhallErrorCategory symlinkProblem @?= DhallImportPolicyError,
      testCase "local-only rejects environment, remote, missing, and alternative imports" $
        withSystemTempDirectory "settei-dhall-capabilities" $ \root -> do
          let options = localOptions root
          environment <- expectError options (dhallExpression "environment" "env:SETTEI_DHALL_TEST_SECRET")
          remote <- expectError options (dhallExpression "remote" "https://example.com/config.dhall")
          missing <- expectError options (dhallExpression "missing" "missing")
          alternative <- expectError options (dhallExpression "alternative" "./one.dhall ? ./two.dhall")
          fmap dhallErrorCategory [environment, remote, missing, alternative]
            @?= replicate 4 DhallImportPolicyError,
      testCase "local-only reports an import cycle without recursing forever" $
        withSystemTempDirectory "settei-dhall-cycle" $ \root -> do
          TextIO.writeFile (root FilePath.</> "a.dhall") "./b.dhall"
          TextIO.writeFile (root FilePath.</> "b.dhall") "./a.dhall"
          problem <- expectError (localOptions root) (dhallExpression "cycle" "./a.dhall")
          dhallErrorCategory problem @?= DhallImportError,
      testCase "semantic hashes and raw-text modes remain structural provenance" $
        withSystemTempDirectory "settei-dhall-hash" $ \root -> do
          let hashed = root FilePath.</> "hashed.dhall"
              message = root FilePath.</> "message.txt"
              hashedExpression = "{ value = True }"
          TextIO.writeFile hashed hashedExpression
          TextIO.writeFile message "hello from raw text"
          semanticHash <- hashExpression hashedExpression
          loaded <-
            expectDetailed
              (localOptions root)
              ( dhallExpression
                  "hashed and raw text"
                  ( "{ hashed = ./hashed.dhall "
                      <> semanticHash
                      <> ", message = ./message.txt as Text }"
                  )
              )
          let imports = dhallLoadedImports loaded
          length imports @?= 2
          assertBool "semantic hash was discarded" (any ((/= Nothing) . dhallImportSemanticHash) imports)
          assertBool "raw-text mode was discarded" (any ((== DhallRawTextImport) . dhallImportMode) imports)
          candidateValue <$> expectCandidate messageKey (dhallLoadedSource loaded)
            >>= assertRaw (RawText "hello from raw text"),
      testCase "a changed local import is not hidden by upstream cache state" $
        withSystemTempDirectory "settei-dhall-cache" $ \root -> do
          let imported = root FilePath.</> "value.dhall"
              rootExpression = dhallExpression "cache repeat" "{ service = ./value.dhall }"
              options = localOptions root
          TextIO.writeFile imported "{ port = 8000 }"
          firstSource <- expectSource options rootExpression
          candidateValue <$> expectCandidate servicePort firstSource >>= assertRaw (RawNumber 8000)
          TextIO.writeFile imported "{ port = 9000 }"
          secondSource <- expectSource options rootExpression
          candidateValue <$> expectCandidate servicePort secondSource >>= assertRaw (RawNumber 9000),
      testCase "higher Dhall sources override leaves through the core resolver" $ do
        low <- expectSource (dhallSourceOptions "low" NoImports) (dhallExpression "low" "{ service = { host = \"old.internal\", port = 7000 } }")
        high <- expectSource (dhallSourceOptions "high" NoImports) (dhallExpression "high" "{ service = { port = 9000 } }")
        let result =
              resolve
                defaultResolveOptions
                [low, high]
                ((,) <$> required hostSetting <*> required portSetting)
        value <- expectResolution result
        value @?= ("old.internal", 9000),
      testCase "stable error phases and Show output never retain source secrets" $ do
        let cases =
              [ (dhallExpression "parse" ("{ password = \"" <> secretSentinel <> "\", broken ="), DhallParseError),
                (dhallExpression "type" ("{ password = \"" <> secretSentinel <> "\", broken = if True then True else 1 }"), DhallTypeError),
                (dhallExpression "conversion" ("{ password = \"" <> secretSentinel <> "\", bytes = 0x\"00\" }"), DhallConversionError),
                (dhallExpression "key" ("{ `service.port` = 8080, password = \"" <> secretSentinel <> "\" }"), DhallInvalidKey),
                (dhallExpression "top-level" "[ 1, 2 ]", DhallTopLevelType)
              ]
        traverse_
          ( \(root, expectedCategory) -> do
              problem <- expectError noImportOptions root
              dhallErrorCategory problem @?= expectedCategory
              assertBool
                "secret reached structured Dhall error"
                (not (secretSentinel `Text.isInfixOf` Text.pack (show problem)))
          )
          cases,
      testCase "root parse errors carry exact one-based positions" $ do
        firstProblem <- expectError noImportOptions (dhallExpression "broken" "{ port =")
        dhallErrorCategory firstProblem @?= DhallParseError
        dhallErrorLine firstProblem @?= Just 1
        dhallErrorColumn firstProblem @?= Just 9
        secondProblem <-
          expectError
            noImportOptions
            (dhallExpression "broken2" "let a = 1\nin { port = }")
        dhallErrorCategory secondProblem @?= DhallParseError
        dhallErrorLine secondProblem @?= Just 2
        dhallErrorColumn secondProblem @?= Just 13
        dhallErrorMessage secondProblem @?= "invalid Dhall syntax",
      testCase "local-import parse errors retain the imported-file position" $
        withSystemTempDirectory "settei-dhall-parse-position" $ \root -> do
          let imported = root FilePath.</> "broken.dhall"
          TextIO.writeFile imported "let a = 1\nin { port = }"
          problem <-
            expectError
              (localOptions root)
              (dhallExpression "importing root" "./broken.dhall")
          dhallErrorCategory problem @?= DhallParseError
          dhallErrorPath problem @?= Just imported
          dhallErrorLine problem @?= Just 2
          dhallErrorColumn problem @?= Just 13
          dhallErrorMessage problem @?= "invalid syntax in local import",
      testCase "resolved secret values are redacted while Dhall provenance remains" $ do
        input <-
          expectSource
            noImportOptions
            (dhallExpression "secret root" ("{ database = { password = \"" <> secretSentinel <> "\" } }"))
        let result = resolve defaultResolveOptions [input] (required passwordSetting)
        value <- expectResolution result
        value @?= secretSentinel
        let textOutput = renderResolutionText (result ^. #report)
            jsonOutput = renderResolutionJson (result ^. #report)
        assertBool "secret reached text report" (not (secretSentinel `Text.isInfixOf` textOutput))
        assertBool "secret reached JSON report" (not (secretSentinel `Text.isInfixOf` jsonOutput))
        assertBool "Dhall provenance was redacted with the value" ("secret root" `Text.isInfixOf` textOutput)
    ]

noImportOptions :: DhallSourceOptions
noImportOptions = dhallSourceOptions "application Dhall" NoImports

localOptions :: FilePath -> DhallSourceOptions
localOptions root = dhallSourceOptions "application Dhall" (LocalImportsWithin root)

expectDetailed :: DhallSourceOptions -> DhallRoot -> IO DhallLoadedSource
expectDetailed options root = do
  result <- loadDhallSourceDetailed options root
  case result of
    Left problems -> assertFailure (show problems) >> error "unreachable"
    Right value -> pure value

expectSource :: DhallSourceOptions -> DhallRoot -> IO Source
expectSource options root = dhallLoadedSource <$> expectDetailed options root

expectError :: DhallSourceOptions -> DhallRoot -> IO DhallSourceError
expectError options root = do
  result <- loadDhallSource options root
  case result of
    Left problems -> pure (NonEmpty.head problems)
    Right _ -> assertFailure "expected Dhall loading to fail" >> error "unreachable"

expectCandidate :: Key -> Source -> IO Candidate
expectCandidate key input = case lookupSource key input of
  Right (Just found) -> pure found
  _ -> assertFailure "expected Dhall candidate" >> error "unreachable"

expectResolution :: ResolveResult a -> IO a
expectResolution result = case result ^. #answer of
  Left _ -> assertFailure "expected Dhall resolution to succeed" >> error "unreachable"
  Right value -> pure value

hashExpression :: Text -> IO Text
hashExpression input = case DhallParser.exprFromText "hash fixture" input of
  Left problem -> assertFailure (show problem) >> error "unreachable"
  Right parsed -> do
    resolved <- DhallImport.assertNoImports parsed
    pure (DhallImport.hashExpressionToCode (DhallCore.normalize (DhallCore.denote resolved)))

isTwoEntryArray :: RawValue -> Bool
isTwoEntryArray = \case
  RawArray [RawObject firstEntry, RawObject secondEntry] ->
    Map.lookup "mapKey" firstEntry == Just (RawText "one")
      && Map.lookup "mapValue" firstEntry == Just (RawNumber 1)
      && Map.lookup "mapKey" secondEntry == Just (RawText "two")
      && Map.lookup "mapValue" secondEntry == Just (RawNumber 2)
  _ -> False

assertRaw :: RawValue -> RawValue -> IO ()
assertRaw expected actual = assertBool "raw Dhall value did not match" (actual == expected)

hostSetting :: Setting Text
hostSetting = publicSetting serviceHost "Service host" textDecoder

portSetting :: Setting Int
portSetting = publicSetting servicePort "Service port" boundedIntegralDecoder

passwordSetting :: Setting Text
passwordSetting = secretSetting databasePassword "Database password" textDecoder

serviceHost, servicePort, serviceEnabled, serviceTags, serviceName, serviceDescription, presentKey, absentKey, choiceKey, entriesKey, messageKey, databasePassword :: Key
serviceHost = validKey "service.host"
servicePort = validKey "service.port"
serviceEnabled = validKey "service.enabled"
serviceTags = validKey "service.tags"
serviceName = validKey "service.name"
serviceDescription = validKey "service.description"
presentKey = validKey "present"
absentKey = validKey "absent"
choiceKey = validKey "choice"
entriesKey = validKey "entries"
messageKey = validKey "message"
databasePassword = validKey "database.password"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

secretSentinel :: Text
secretSentinel = "never-render-this-dhall-secret"
