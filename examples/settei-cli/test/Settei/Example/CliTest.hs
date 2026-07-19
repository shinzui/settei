module Settei.Example.CliTest (tests) where

import Data.Generics.Labels ()
import Data.List (isInfixOf)
import Data.Text qualified as Text
import Options.Applicative qualified as Options
import Paths_settei_example_cli qualified as Paths
import Settei
import Settei.Env
import Settei.Example.Cli
import Settei.Prelude
import System.Exit (ExitCode (ExitFailure))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Example.Cli"
    [ testCase "cli overrides environment overrides ordered files" $ do
        fixture <- Paths.getDataFileName "test/fixtures/application.yaml"
        options <- expectOptions ["--config", "yaml:" <> fixture, "--set", "service.timeout=9000", "--set", "service.timeout=9001", "--check-config"]
        resolved <- resolveCliOptions environmentSnapshot options >>= expectResolution
        config <- expectAnswer resolved
        config ^. #timeout @?= 9001
        case resolved ^. #report . #nodes . at (validKey "service.timeout") of
          Just node -> fmap (^. #name) (node ^. #shadowed) @?= ["arguments --set #1", "environment", Text.pack fixture, "CLI built-in defaults"]
          Nothing -> fail "expected service.timeout report node",
      testCase "describe works without loading sources" $ do
        options <- expectOptions ["--config", "yaml:/definitely/missing.yaml", "--describe-config"]
        result <- runCliWithSnapshot (envSnapshot []) options
        cliExitCode result @?= 0
        assertBool "schema omitted conditional token" ("credentials.token" `Text.isInfixOf` cliStandardOutput result),
      testCase "help groups options by intent" $ do
        case Options.execParserPure Options.defaultPrefs cliParserInfo ["--help"] of
          Options.Failure failure -> do
            let (helpText, _) = Options.renderFailure failure "settei-example-cli"
            assertBool "Configuration group missing" ("Configuration\n" `isInfixOf` helpText)
            assertBool "Diagnostics group missing" ("Diagnostics\n" `isInfixOf` helpText)
          _ -> fail "expected --help to return a rendered help failure",
      testCase "source and resolution failures use distinct exit codes" $ do
        missing <- expectOptions ["--config", "yaml:/definitely/missing.yaml", "--check-config"]
        missingResult <- runCliWithSnapshot (envSnapshot []) missing
        cliExitCode missingResult @?= sourceExitCode
        malformed <- expectOptions ["--set", "service.timeout=broken", "--check-config"]
        malformedResult <- runCliWithSnapshot (envSnapshot []) malformed
        cliExitCode malformedResult @?= resolutionExitCode
        cliStandardOutput malformedResult @?= ""
        assertBool
          "check mode unexpectedly printed a failure report"
          ( not ("settei.resolution" `Text.isInfixOf` cliStandardError malformedResult)
              && not ("<missing>" `Text.isInfixOf` cliStandardError malformedResult)
              && not ("<not selected>" `Text.isInfixOf` cliStandardError malformedResult)
          ),
      testCase "resolution failure in explain modes prints provenance to stderr" $ do
        textOptions <- expectOptions ["--set", "service.timeout=broken", "--explain-config"]
        textResult <- runCliWithSnapshot (envSnapshot []) textOptions
        cliExitCode textResult @?= resolutionExitCode
        cliStandardOutput textResult @?= ""
        let textError = cliStandardError textResult
        assertBool
          "text explain failure omitted the decode error"
          ("service.timeout: expected" `Text.isInfixOf` textError)
        let (_, reportSuffix) = Text.breakOn "service.timeout = " textError
        assertBool
          "text explain failure omitted the report after the error"
          ( not (Text.null reportSuffix)
              && "from command-line option" `Text.isInfixOf` reportSuffix
          )

        jsonOptions <- expectOptions ["--set", "service.timeout=broken", "--explain-config-json"]
        jsonResult <- runCliWithSnapshot (envSnapshot []) jsonOptions
        cliExitCode jsonResult @?= resolutionExitCode
        cliStandardOutput jsonResult @?= ""
        let jsonError = cliStandardError jsonResult
        assertBool "JSON failure omitted schema version" ("\"schemaVersion\":1" `Text.isInfixOf` jsonError)
        assertBool "JSON failure omitted document type" ("\"type\":\"settei.resolution\"" `Text.isInfixOf` jsonError),
      testCase "JSON explanations redact environment secrets" $ do
        options <- expectOptions ["--explain-config-json"]
        result <- runCliWithSnapshot secretSnapshot options
        cliExitCode result @?= 0
        assertBool "JSON schema version missing" ("\"schemaVersion\":1" `Text.isInfixOf` cliStandardOutput result)
        assertBool "secret reached JSON explanation" (not (secretSentinel `Text.isInfixOf` cliStandardOutput result)),
      testCase "usage errors use the documented exit code" $ do
        case Options.execParserPure Options.defaultPrefs cliParserInfo ["--config", "toml:application.toml"] of
          Options.Failure failure -> do
            let (_, exit) = Options.renderFailure failure "settei-example-cli"
            exit @?= ExitFailure usageExitCode
          _ -> fail "expected unknown format to fail"
    ]

environmentSnapshot :: EnvSnapshot
environmentSnapshot =
  envSnapshot
    [ ("HASKELL_ENV", "production"),
      ("SERVICE_ENDPOINT", "https://environment.example"),
      ("SERVICE_TIMEOUT", "8000"),
      ("OUTPUT_FORMAT", "json")
    ]

secretSnapshot :: EnvSnapshot
secretSnapshot =
  envSnapshot
    [ ("SERVICE_TOKEN", secretSentinel)
    ]

secretSentinel :: Text
secretSentinel = "never-render-this-cli-secret"

expectOptions :: [String] -> IO CliOptions
expectOptions arguments =
  case Options.execParserPure Options.defaultPrefs cliParserInfo arguments of
    Options.Success value -> pure value
    _ -> fail "expected command-line arguments to parse"

expectResolution :: Either a (ResolveResult b) -> IO (ResolveResult b)
expectResolution = \case
  Left _ -> fail "expected CLI resolution to succeed"
  Right value -> pure value

expectAnswer :: ResolveResult a -> IO a
expectAnswer result = case result ^. #answer of
  Left _ -> fail "expected CLI resolution answer to succeed"
  Right value -> pure value

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
