module Settei.OptparseTest (tests) where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Options.Applicative qualified as Options
import Settei
import Settei.Env
import Settei.Optparse
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Optparse"
    [ testCase "final repeated --set wins with shadow trace" $ do
        overrides <- expectParse overrideOptions ["--set", "service.port=9000", "--set", "service.port=9001"]
        environment <- environmentPort 8000
        let result =
              resolve
                defaultResolveOptions
                ([portSource "built-in" BuiltInSource 6000, portSource "file" (FileSource "memory") 7000, environment] <> cliSources "arguments" overrides)
                (required portSetting)
        value <- expectResolution result
        value @?= 9001
        case result ^. #report . #nodes . at servicePort of
          Just node -> do
            node ^. #origin . _Just . #annotations . at "command-line.occurrence" @?= Just "2"
            fmap (^. #name) (node ^. #shadowed)
              @?= ["arguments --set #1", "environment", "file", "built-in"]
          Nothing -> fail "expected the resolved port node",
      testCase "execParserPure rejects an invalid key" $ do
        let parsed = parse overrideOptions ["--set", "service..port=9000"]
        assertBool "invalid key unexpectedly parsed" (Options.getParseResult parsed == Nothing),
      testCase "malformed final CLI value does not fall back" $ do
        overrides <- expectParse overrideOptions ["--set", "service.port=9000", "--set", "service.port=broken"]
        environment <- environmentPort 8000
        case (resolve defaultResolveOptions (environment : cliSources "arguments" overrides) (required portSetting)) ^. #answer of
          Left errors -> case NonEmpty.toList errors of
            [DecodeError problem] -> do
              problem ^. #origin . #name @?= "arguments --set #2"
              problem ^. #origin . #annotations . at "command-line.occurrence" @?= Just "2"
            _ -> fail "expected one CLI decode error"
          Right _ -> fail "expected the malformed final override to fail",
      testCase "secret override spelling omits the value" $ do
        overrides <- expectParse overrideOptions ["--set", "database.password=" <> Text.unpack secretSentinel]
        let result = resolve defaultResolveOptions (cliSources "arguments" overrides) (required passwordSetting)
        _ <- expectResolution result
        let textOutput = renderResolutionText (result ^. #report)
            jsonOutput = renderResolutionJson (result ^. #report)
        assertBool "secret reached text output" (not (secretSentinel `Text.isInfixOf` textOutput))
        assertBool "secret reached JSON output" (not (secretSentinel `Text.isInfixOf` jsonOutput))
        case overrides of
          [override] -> cliOverrideSpelling override @?= "--set database.password"
          _ -> fail "expected one secret override",
      testCase "named option produces an optional source fragment" $ do
        input <-
          expectParse
            (namedOption "--port" servicePort (Options.long "port" <> Options.metavar "PORT"))
            ["--port", "8080"]
        case input of
          Nothing -> fail "expected the named option source"
          Just sourceValue -> do
            let result = resolve defaultResolveOptions [sourceValue] (required portSetting)
            value <- expectResolution result
            value @?= 8080,
      testCase "setteiOptions parses grouped paths, overrides, and diagnostics" $ do
        parsed <-
          expectParse
            setteiOptions
            [ "--config",
              "base.yaml",
              "--config",
              "local.yaml",
              "--set",
              "service.port=8080",
              "--explain-config-json"
            ]
        parsed ^. #configPaths @?= ["base.yaml", "local.yaml"]
        length (parsed ^. #overrides) @?= 1
        parsed ^. #explainMode @?= ExplainJson,
      testCase "explanation modes are mutually exclusive" $ do
        let parsed = parse explainModeOptions ["--explain-config", "--explain-config-json"]
        assertBool "both explanation modes unexpectedly parsed" (Options.getParseResult parsed == Nothing),
      testCase "help groups configuration and diagnostics by intent" $ do
        let parserInfo = Options.info (setteiOptions Options.<**> Options.helper) Options.fullDesc
        case Options.execParserPure Options.defaultPrefs parserInfo ["--help"] of
          Options.Failure failure -> do
            let (helpText, _) = Options.renderFailure failure "settei-example"
            assertBool "Configuration group missing" ("Configuration" `Text.isInfixOf` Text.pack helpText)
            assertBool "Diagnostics group missing" ("Diagnostics" `Text.isInfixOf` Text.pack helpText)
          _ -> fail "expected --help to produce parser help"
    ]

parse :: Options.Parser a -> [String] -> Options.ParserResult a
parse parser arguments =
  Options.execParserPure Options.defaultPrefs (Options.info parser Options.fullDesc) arguments

expectParse :: Options.Parser a -> [String] -> IO a
expectParse parser arguments =
  case Options.getParseResult (parse parser arguments) of
    Nothing -> fail "expected command-line parsing to succeed"
    Just value -> pure value

expectResolution :: ResolveResult a -> IO a
expectResolution result = case result ^. #answer of
  Left _ -> fail "expected configuration resolution to succeed"
  Right value -> pure value

environmentPort :: Int -> IO Source
environmentPort value = do
  validated <-
    either
      (fail . Text.unpack . renderEnvErrorsText)
      pure
      (bindings [binding (EnvName "SERVICE_PORT") servicePort])
  pure
    ( environmentSource
        validated
        (envSnapshot [("SERVICE_PORT", Text.pack (show value))])
    )

portSource :: Text -> SourceKind -> Int -> Source
portSource name kind value =
  source
    name
    kind
    (RawObject (Map.singleton "service" (RawObject (Map.singleton "port" (RawNumber (fromIntegral value))))))

portSetting :: Setting Int
portSetting = publicSetting servicePort "Service port" boundedIntegralDecoder

passwordSetting :: Setting Text
passwordSetting = secretSetting databasePassword "Database password" textDecoder

servicePort :: Key
servicePort = validKey "service.port"

databasePassword :: Key
databasePassword = validKey "database.password"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

secretSentinel :: Text
secretSentinel = "never-render-this-cli-secret"
