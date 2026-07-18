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
        resolved ^. #value . #timeout @?= 9001
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
        cliExitCode malformedResult @?= resolutionExitCode,
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

expectResolution :: Either a b -> IO b
expectResolution = \case
  Left _ -> fail "expected CLI resolution to succeed"
  Right value -> pure value

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
