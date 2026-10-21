module Settei.Example.DeploymentTest (tests) where

import Control.Exception (IOException, try)
import Data.Generics.Labels ()
import Data.Text qualified as Text
import Options.Applicative qualified as Options
import Paths_settei_example_deployment qualified as Paths
import Settei
import Settei.Env
import Settei.Example.Deployment
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Example.Deployment"
    [ validationTests,
      testCase "environment bindings validate at construction" $
        length (bindingsList environmentBindings) @?= 11,
      testCase "all four static modes skip environment and missing files for both roles" $
        mapM_
          ( \role ->
              mapM_
                ( \flag -> do
                    options <- expectOptions role ["--config", "/definitely/missing.yaml", flag]
                    result <- runDeploymentWithEnvironment role (ioError (userError "environment reader invoked")) options
                    deploymentExitCode result @?= 0
                )
                ["--describe-config", "--describe-config-json", "--deployment-contract", "--deployment-contract-json"]
          )
          [Server, Worker],
      testCase "check mode invokes the environment reader" $
        mapM_
          ( \role -> do
              options <- expectOptions role ["--check-config"]
              result <- try (runDeploymentWithEnvironment role (ioError (userError "environment reader invoked")) options) :: IO (Either IOException DeploymentRun)
              case result of Left _ -> pure (); Right _ -> fail "reader was skipped"
          )
          [Server, Worker],
      testCase "check mode reads files that static modes ignore" $
        mapM_
          ( \role -> do
              result <- run role [] ["--config", "/definitely/missing.yaml", "--check-config"]
              deploymentExitCode result @?= sourceExitCode
          )
          [Server, Worker],
      testCase "contract exports all bindings and expected input verdicts without credentials" $ do
        let contract = either (error . show) id (deploymentContract deploymentContractInputs deploymentConfig)
        fmap (\entry -> (renderKey (entry ^. #key), entry ^. #externalInput)) (contractSettings contract)
          @?= [ ("database.poolSize", InputDefaulted CoveredBySource),
                ("database.url", InputRequired NoDefault),
                ("email.credentials", InputConditional NoDefault),
                ("runtime.environment", InputRequired ProfileRequirement),
                ("server.host", InputDefaulted CoveredBySource),
                ("server.port", InputDefaulted CoveredBySource),
                ("server.webhookSecret", InputRequired ProfileRequirement),
                ("telemetry.serviceName", InputDefaulted (CoveredByDeclaration [validKey "runtime.environment"])),
                ("workers.concurrency", InputDefaulted (CoveredByDeclaration [validKey "runtime.environment"])),
                ("workers.deliveryEndpoint", InputRequired ProfileRequirement),
                ("workers.visibilityTimeoutSeconds", InputDefaulted (CoveredByDeclaration []))
              ]
        mapM_
          ( \role ->
              mapM_
                ( \flag -> do
                    result <- run role [] ["--config", "/definitely/missing.yaml", flag]
                    deploymentExitCode result @?= 0
                    deploymentStandardError result @?= ""
                    mapM_ (\bindingValue -> assertBool "binding missing" (inputBindingName bindingValue `Text.isInfixOf` deploymentStandardOutput result)) (inputBindings environmentBindings)
                    assertBool "development secret leaked" (not ("development-only-change-me" `Text.isInfixOf` deploymentStandardOutput result))
                )
                ["--deployment-contract", "--deployment-contract-json"]
          )
          [Server, Worker],
      testCase "profile requirements retain defaults and no-profile export reports source coverage" $ do
        let contract = either (error . show) id (deploymentContract (deploymentContractInputs & #profile .~ Nothing) deploymentConfig)
            targets = ["runtime.environment", "server.webhookSecret", "workers.deliveryEndpoint"]
        mapM_
          ( \target -> case filter ((== validKey target) . view #key) (contractSettings contract) of
              [entry] -> do
                entry ^. #externalInput @?= InputDefaulted CoveredBySource
                assertBool "source default lost" (case entry ^. #sourceDefault of Just _ -> True; Nothing -> False)
              _ -> fail "missing target"
          )
          targets,
      testCase "snapshots cannot change static contract or leak their sentinels" $
        mapM_
          ( \role ->
              mapM_
                ( \flag -> do
                    empty <- run role [] [flag]
                    secret <- run role [("DATABASE_URL", sentinel), ("WEBHOOK_SECRET", sentinel)] [flag]
                    empty @?= secret
                    assertBool "snapshot sentinel leaked" (not (sentinel `Text.isInfixOf` (deploymentStandardOutput secret <> deploymentStandardError secret)))
                )
                ["--deployment-contract", "--deployment-contract-json"]
          )
          [Server, Worker],
      testCase "incomplete production inputs list missing database and email credentials" $
        mapM_
          ( \role -> do
              result <- run role [("ENVIRONMENT", "production")] ["--check-config"]
              deploymentExitCode result @?= resolutionExitCode
              deploymentStandardError result @?= "database.url: required value is missing\nemail.credentials: required value is missing\n"
          )
          [Server, Worker],
      testCase "server rejects a short webhook secret without echoing it" $ do
        result <- run Server (replace "WEBHOOK_SECRET" "SHORT" productionInputs) ["--check-config"]
        deploymentExitCode result @?= resolutionExitCode
        deploymentStandardError result @?= "server.webhookSecret: invariant server-webhook-secret-length failed: must be at least 16 characters\n"
        assertBool "short value leaked" (not ("SHORT" `Text.isInfixOf` deploymentStandardError result)),
      testCase "worker rejects insufficient visibility timeout" $ do
        result <- run Worker (replace "WORKER_VISIBILITY_TIMEOUT_SECONDS" "1" productionInputs) ["--check-config"]
        deploymentExitCode result @?= resolutionExitCode
        deploymentStandardError result @?= "workers.visibilityTimeoutSeconds, workers.concurrency: invariant worker-visibility-covers-concurrency failed: workers.visibilityTimeoutSeconds must be at least twice workers.concurrency\n",
      testCase "worker rejects the development secret in production" $ do
        result <- run Worker (filter ((/= "WEBHOOK_SECRET") . fst) productionInputs) ["--check-config"]
        deploymentExitCode result @?= resolutionExitCode
        deploymentStandardError result @?= "server.webhookSecret, runtime.environment: invariant production-webhook-secret failed: the development webhook secret must never reach production\n",
      testCase "complete production snapshot resolves real defaults and passes both roles" $
        mapM_
          ( \role -> do
              result <- run role productionInputs ["--check-config"]
              deploymentExitCode result @?= 0
              deploymentStandardOutput result @?= "configuration valid\n"
              deploymentStandardError result @?= ""
          )
          [Server, Worker],
      testCase "packaged proposed production YAML passes both roles" $ do
        fixture <- Paths.getDataFileName "test/fixtures/proposed-production.yaml"
        mapM_
          ( \role -> do
              result <- run role [] ["--config", fixture, "--check-config"]
              deploymentExitCode result @?= 0
              deploymentStandardOutput result @?= "configuration valid\n"
          )
          [Server, Worker],
      testCase "file environment and repeated CLI overrides retain precedence" $ do
        fixture <- Paths.getDataFileName "test/fixtures/proposed-production.yaml"
        result <-
          run
            Server
            (replace "WEBHOOK_SECRET" "short" productionInputs)
            ["--config", fixture, "--set", "server.webhookSecret=bad", "--set", "server.webhookSecret=explicit-production-test-secret", "--check-config"]
        deploymentExitCode result @?= 0,
      testCase "existing schema document remains separate from the contract" $ do
        schema <- run Server [] ["--describe-config-json"]
        assertBool "schema type changed" ("\"type\":\"settei.schema\"" `Text.isInfixOf` deploymentStandardOutput schema)
        assertBool "schema acquired defaults" (not ("sourceDefault" `Text.isInfixOf` deploymentStandardOutput schema))
    ]

validKey :: Text -> Key
validKey = either (error . show) id . parseKey

expectOptions :: Role -> [String] -> IO DeploymentOptions
expectOptions role args = case Options.execParserPure Options.defaultPrefs (deploymentParserInfo role) args of
  Options.Success value -> pure value
  _ -> fail "expected valid example arguments"

run :: Role -> [(Text, Text)] -> [String] -> IO DeploymentRun
run role snapshot args = expectOptions role args >>= runDeploymentWithSnapshot role (envSnapshot snapshot)

replace :: Text -> Text -> [(Text, Text)] -> [(Text, Text)]
replace name value inputs = (name, value) : filter ((/= name) . fst) inputs

productionInputs :: [(Text, Text)]
productionInputs =
  [ ("ENVIRONMENT", "production"),
    ("DATABASE_URL", "postgres://example.invalid/notification"),
    ("EMAIL_CREDENTIALS_JSON", "{\"account\":\"dummy\"}"),
    ("WEBHOOK_SECRET", "explicit-production-test-secret"),
    ("DELIVERY_ENDPOINT", "https://delivery.example.invalid")
  ]

sentinel :: Text
sentinel = "DEPLOYMENT-SNAPSHOT-SENTINEL"

validationTests :: TestTree
validationTests =
  testGroup
    "structured validation"
    [ testCase "role declarations validate and preserve successful typed values" $
        mapM_
          ( \role -> do
              let base = resolve defaultResolveOptions [builtInDefaultsSource, environmentSource environmentBindings (envSnapshot productionInputs)] deploymentConfig
                  result = validate (roleValidators role) base
              assertBool "typed answer changed" (result ^. #answer == base ^. #answer)
              fmap (^. #status) (validationOutcomes (describeValidators (roleValidators role))) @?= replicate (if role == Server then 1 else 2) InvariantNotRun
              assertBool "fixture failed resolution" (case base ^. #answer of Right _ -> True; _ -> False)
          )
          [Server, Worker],
      testCase "worker failure rejects startup and every dynamic mode with retained provenance" $
        mapM_
          ( \args -> do
              result <- run Worker invalidWorker args
              deploymentExitCode result @?= 4
              deploymentStandardOutput result @?= ""
              let output = deploymentStandardError result
              assertBool "rule missing" ("worker-visibility-covers-concurrency" `Text.isInfixOf` output)
              assertBool "false check success" (not ("configuration valid" `Text.isInfixOf` output))
              case args of
                ["--explain-config"] -> do
                  assertBool "winning value missing" ("workers.visibilityTimeoutSeconds = \"1\"" `Text.isInfixOf` output)
                  assertBool "origin missing" ("from environment variable WORKER_VISIBILITY_TIMEOUT_SECONDS" `Text.isInfixOf` output)
                  filter (Text.isPrefixOf "invariant ") (Text.lines output)
                    @?= [ "invariant worker-visibility-covers-concurrency [failed (1 violation)]: workers.visibilityTimeoutSeconds, workers.concurrency",
                          "invariant production-webhook-secret [passed]: server.webhookSecret, runtime.environment"
                        ]
                ["--explain-config-json"] -> case Text.lines output of
                  [errors, report] -> do
                    assertBool "structured error missing" ("\"kind\":\"invariant\",\"rule\":\"worker-visibility-covers-concurrency\"" `Text.isInfixOf` errors)
                    assertBool "origin missing" ("\"environment.variable\":\"WORKER_VISIBILITY_TIMEOUT_SECONDS\"" `Text.isInfixOf` report)
                    assertBool "trace missing" ("\"invariants\":[{\"rule\":\"worker-visibility-covers-concurrency\"" `Text.isInfixOf` report)
                  _ -> fail "expected two JSON documents"
                _ -> length (Text.lines output) @?= 1
          )
          [[], ["--check-config"], ["--explain-config"], ["--explain-config-json"]],
      testCase "timeout comparison preserves rejection beyond Int multiplication bounds" $ do
        result <- run Worker (replace "WORKER_CONCURRENCY" (Text.pack (show (maxBound :: Int))) (replace "WORKER_VISIBILITY_TIMEOUT_SECONDS" (Text.pack (show (maxBound :: Int))) productionInputs)) ["--check-config"]
        deploymentExitCode result @?= 4,
      testCase "worker rules accumulate and the server retains role applicability" $ do
        let inputs = filter ((/= "WEBHOOK_SECRET") . fst) invalidWorker
        result <- run Worker inputs ["--check-config"]
        deploymentExitCode result @?= 4
        length (Text.lines (deploymentStandardError result)) @?= 2
        assertBool "rule order changed" ("workers.visibilityTimeoutSeconds, workers.concurrency:" `Text.isPrefixOf` deploymentStandardError result)
        server <- run Server inputs ["--check-config"]
        deploymentExitCode server @?= 0,
      testCase "missing and decode failures retain their type with not-run rules" $
        mapM_
          ( \inputs -> do
              text <- run Worker inputs ["--explain-config"]
              deploymentExitCode text @?= 4
              length (filter (Text.isInfixOf "[not run]") (Text.lines (deploymentStandardError text))) @?= 2
              assertBool "invariant error invented" (not ("failed:" `Text.isInfixOf` deploymentStandardError text))
              json <- run Worker inputs ["--explain-config-json"]
              deploymentExitCode json @?= 4
              case Text.lines (deploymentStandardError json) of
                [errors, report] -> do
                  assertBool "error type missing" ("{\"schemaVersion\":1,\"type\":\"settei.errors\"" `Text.isPrefixOf` errors)
                  assertBool "invariant error invented" (not ("\"kind\":\"invariant\"" `Text.isInfixOf` errors))
                  assertBool "not run missing" ("\"status\":\"not-run\"" `Text.isInfixOf` report)
                _ -> fail "expected two JSON documents"
          )
          [filter ((/= "DATABASE_URL") . fst) productionInputs, replace "WORKER_CONCURRENCY" "broken" productionInputs],
      testCase "secret markers never enter either stream in any mode on success or failure" $
        mapM_
          ( \role ->
              mapM_
                ( \inputs ->
                    mapM_
                      ( \args -> do
                          result <- run role inputs args
                          let output = deploymentStandardOutput result <> deploymentStandardError result
                          assertBool "secret retained in stream" (not (any (`Text.isInfixOf` output) [validationSentinel, "SETTEI_VALIDATION_SECRET_29"]))
                      )
                      allModes
                )
                [secretInputs, replace "WORKER_VISIBILITY_TIMEOUT_SECONDS" "1" secretInputs, replace "WORKER_CONCURRENCY" "broken" secretInputs]
          )
          [Server, Worker]
    ]
  where
    invalidWorker = replace "WORKER_VISIBILITY_TIMEOUT_SECONDS" "1" productionInputs
    secretInputs = foldr (\name inputs -> replace name validationSentinel inputs) productionInputs ["DATABASE_URL", "WEBHOOK_SECRET", "EMAIL_CREDENTIALS_JSON"]
    allModes = [[], ["--check-config"], ["--explain-config"], ["--explain-config-json"], ["--describe-config"], ["--describe-config-json"], ["--deployment-contract"], ["--deployment-contract-json"]]
    validationSentinel = "SETTEI_VALIDATION_SECRET_29\"\\\n秘密"
