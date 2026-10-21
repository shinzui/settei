module Settei.Example.CliTest (tests) where

import Control.Exception (IOException, try)
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
    [ testCase "all static modes skip the executable environment reader and file reads" $ do
        mapM_
          ( \flag -> do
              options <- expectOptions (["--config", "yaml:/definitely/missing.yaml"] <> [flag])
              result <- runCliWithEnvironment (ioError (userError "environment reader invoked")) options
              cliExitCode result @?= 0
              cliStandardError result @?= ""
          )
          ["--describe-config", "--describe-config-json", "--deployment-contract", "--deployment-contract-json"],
      testCase "check mode invokes the executable environment reader" $ do
        options <- expectOptions ["--check-config"]
        result <- try (runCliWithEnvironment (ioError (userError "environment reader invoked")) options) :: IO (Either IOException CliRun)
        case result of Left _ -> pure (); Right _ -> fail "reader was skipped",
      testCase "contract modes ignore snapshots and name bindings and defaults" $ do
        mapM_
          ( \flag -> do
              options <- expectOptions (["--config", "yaml:/definitely/missing.yaml"] <> [flag])
              empty <- runCliWithSnapshot (envSnapshot []) options
              secret <- runCliWithSnapshot (envSnapshot [("DATABASE_PASSWORD", "CONTRACT-SNAPSHOT-SENTINEL"), ("SERVICE_TOKEN", "CONTRACT-SNAPSHOT-SENTINEL")]) options
              empty @?= secret
              cliExitCode empty @?= 0
              assertBool "sentinel leaked" (not ("CONTRACT-SNAPSHOT-SENTINEL" `Text.isInfixOf` cliStandardOutput empty))
              mapM_
                (\value -> assertBool (Text.unpack value) (value `Text.isInfixOf` cliStandardOutput empty))
                ["SERVICE_ENDPOINT", "credentials.token", "SERVICE_TOKEN", "settei-example-cli"]
          )
          ["--deployment-contract", "--deployment-contract-json"],
      testCase "environment bindings validate at construction" $
        length (bindingsList environmentBindings) @?= 5,
      suppliedEnvironmentTests,
      testCase "cli overrides environment overrides ordered files" $ do
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
      testCase "describe JSON works without loading sources" $ do
        options <- expectOptions ["--config", "yaml:/definitely/missing.yaml", "--describe-config-json"]
        result <- runCliWithSnapshot (envSnapshot []) options
        cliExitCode result @?= 0
        assertBool "schema JSON version missing" ("\"schemaVersion\":1" `Text.isInfixOf` cliStandardOutput result),
      testCase "successful resolution renders warnings to stderr" $ do
        options <- expectOptions ["--set", "undeclared.setting=value", "--check-config"]
        result <- runCliWithSnapshot (envSnapshot []) options
        cliExitCode result @?= 0
        cliStandardOutput result @?= "configuration valid\n"
        assertBool "unknown-key warning missing from stderr" ("undeclared.setting" `Text.isInfixOf` cliStandardError result),
      testCase "help groups options by intent" $ do
        case Options.execParserPure Options.defaultPrefs cliParserInfo ["--help"] of
          Options.Failure failure -> do
            let (helpText, _) = Options.renderFailure failure "settei-example-cli"
            assertBool "Configuration group missing" ("Configuration\n" `isInfixOf` helpText)
            assertBool "Diagnostics group missing" ("Diagnostics\n" `isInfixOf` helpText)
            let configurationHelp = takeWhile (/= "Diagnostics") (lines helpText)
            assertBool "supplied-env missing from Configuration group" ("--supplied-env NAME" `isInfixOf` unlines configurationHelp)
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

suppliedEnvironmentTests :: TestTree
suppliedEnvironmentTests =
  testGroup
    "supplied environment names"
    [ testCase "accepted environment names validate at construction" $
        length (acceptedNamesList acceptedEnvironmentNames) @?= 6,
      testCase "absent bound variables use built-in defaults" $ do
        options <- expectOptions ["--supplied-env", "HASKELL_ENV", "--supplied-env", "SERVICE_ENDPOINT", "--check-config"]
        let snapshot = envSnapshot [("HASKELL_ENV", "production"), ("SERVICE_ENDPOINT", "https://environment.example")]
        result <- runCliWithSnapshot snapshot options
        cliExitCode result @?= 0
        cliStandardOutput result @?= "configuration valid\n"
        resolved <- resolveCliOptions snapshot options >>= expectResolution
        config <- expectAnswer resolved
        config ^. #timeout @?= 30
        config ^. #outputFormat @?= TextOutput
        mapM_
          ( \key -> case resolved ^. #report . #nodes . at (validKey key) of
              Just node -> do
                fmap (^. #kind) (node ^. #origin) @?= Just BuiltInSource
                fmap (^. #name) (node ^. #origin) @?= Just "CLI built-in defaults"
              Nothing -> fail "expected defaulted report node"
          )
          ["service.timeout", "output.format"],
      testCase "typo is rejected only when explicitly supplied" $ do
        let snapshot = envSnapshot [("ENVIRONMENT", "production")]
        permissive <- expectOptions ["--check-config"] >>= runCliWithSnapshot snapshot
        cliExitCode permissive @?= 0
        options <- expectOptions ["--supplied-env", "ENVIRONMENT", "--check-config"]
        result <- runCliWithSnapshot snapshot options
        cliExitCode result @?= sourceExitCode
        cliStandardOutput result @?= ""
        cliStandardError result @?= "supplied environment variable ENVIRONMENT: no binding or allowance accepts it\n",
      testCase "allowance and bound name ignore inherited process names" $ do
        options <- expectOptions ["--supplied-env", "HTTPS_PROXY", "--supplied-env", "HASKELL_ENV", "--check-config"]
        result <- runCliWithSnapshot (envSnapshot [("HTTPS_PROXY", "https://proxy.example"), ("HASKELL_ENV", "production"), ("PATH", "bin"), ("HOME", "home")]) options
        cliExitCode result @?= 0
        cliStandardOutput result @?= "configuration valid\n",
      testCase "rejects duplicate declarations" $ do
        options <- expectOptions ["--supplied-env", "HASKELL_ENV", "--supplied-env", "HASKELL_ENV", "--check-config"]
        result <- runCliWithSnapshot (envSnapshot []) options
        cliExitCode result @?= sourceExitCode
        cliStandardError result @?= "supplied environment variable HASKELL_ENV: supplied more than once\n",
      testCase "name validation precedes file loading" $ do
        options <- expectOptions ["--config", "yaml:/definitely/missing.yaml", "--supplied-env", "BOGUS", "--check-config"]
        result <- runCliWithSnapshot (envSnapshot []) options
        cliExitCode result @?= sourceExitCode
        cliStandardError result @?= "supplied environment variable BOGUS: no binding or allowance accepts it\n",
      testCase "schema and contract diagnostics precede name validation" $
        mapM_
          ( \flag -> do
              options <- expectOptions ["--config", "yaml:/definitely/missing.yaml", "--supplied-env", "BOGUS", flag]
              result <- runCliWithEnvironment (ioError (userError "unexpected environment read")) options
              cliExitCode result @?= 0
          )
          ["--describe-config", "--describe-config-json", "--deployment-contract", "--deployment-contract-json"],
      testCase "failure modes contain names only and JSON follows text" $
        mapM_
          ( \flag -> do
              options <- expectOptions ["--supplied-env", "SERVICE_TOKEN", "--supplied-env", "BOGUS_SECRET", flag]
              let unknownSentinel = "unknown-cli-value-sentinel"
              result <- runCliWithSnapshot (envSnapshot [("SERVICE_TOKEN", secretSentinel), ("BOGUS_SECRET", unknownSentinel)]) options
              cliExitCode result @?= sourceExitCode
              cliStandardOutput result @?= ""
              let expectedText = "supplied environment variable BOGUS_SECRET: no binding or allowance accepts it\n"
                  expectedJson = "{\"schemaVersion\":1,\"type\":\"settei.supplied-names\",\"errors\":[{\"kind\":\"unsupported-supplied-name\",\"name\":\"BOGUS_SECRET\"}]}\n"
              cliStandardError result @?= expectedText <> (if flag == "--explain-config-json" then expectedJson else "")
              sequence_ [assertBool "sentinel leaked" (not (sentinel `Text.isInfixOf` output)) | output <- [Text.pack (show result), cliStandardOutput result, cliStandardError result], sentinel <- [secretSentinel, unknownSentinel]]
          )
          ["--check-config", "--explain-config", "--explain-config-json"],
      testCase "ordinary unsupported name has exact JSON and text explain output" $
        mapM_
          ( \flag -> do
              options <- expectOptions ["--supplied-env", "ENVIRONMENT", flag]
              result <- runCliWithSnapshot (envSnapshot [("ENVIRONMENT", "production")]) options
              cliExitCode result @?= sourceExitCode
              cliStandardOutput result @?= ""
              cliStandardError result
                @?= "supplied environment variable ENVIRONMENT: no binding or allowance accepts it\n"
                  <> (if flag == "--explain-config-json" then "{\"schemaVersion\":1,\"type\":\"settei.supplied-names\",\"errors\":[{\"kind\":\"unsupported-supplied-name\",\"name\":\"ENVIRONMENT\"}]}\n" else "")
          )
          ["--explain-config", "--explain-config-json"],
      testCase "successful supplied-name check still redacts secret JSON" $ do
        options <- expectOptions ["--supplied-env", "SERVICE_TOKEN", "--explain-config-json"]
        result <- runCliWithSnapshot secretSnapshot options
        cliExitCode result @?= 0
        assertBool "secret leaked after successful name check" (not (secretSentinel `Text.isInfixOf` (cliStandardOutput result <> cliStandardError result))),
      testCase "hostile supplied name cannot forge text lines or JSON documents" $
        mapM_
          ( \flag -> do
              options <- expectOptions ["--supplied-env", "BAD\"\\\n\SOHNAME", flag]
              result <- runCliWithSnapshot (envSnapshot []) options
              cliExitCode result @?= sourceExitCode
              cliStandardOutput result @?= ""
              let expectedText = "supplied environment variable \"BAD\\\"\\\\\\n\\u0001NAME\": no binding or allowance accepts it"
                  expectedJson = "{\"schemaVersion\":1,\"type\":\"settei.supplied-names\",\"errors\":[{\"kind\":\"unsupported-supplied-name\",\"name\":\"BAD\\\"\\\\\\n\\u0001NAME\"}]}"
              Text.lines (cliStandardError result) @?= [expectedText] <> [expectedJson | flag == "--explain-config-json"]
              cliStandardError result @?= Text.unlines ([expectedText] <> [expectedJson | flag == "--explain-config-json"])
          )
          ["--check-config", "--explain-config", "--explain-config-json"]
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
