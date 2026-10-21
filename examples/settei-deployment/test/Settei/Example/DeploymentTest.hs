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
    [ testCase "environment bindings validate at construction" $
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
        deploymentStandardError result @?= "server.webhookSecret: must be at least 16 characters\n"
        assertBool "short value leaked" (not ("SHORT" `Text.isInfixOf` deploymentStandardError result)),
      testCase "worker rejects insufficient visibility timeout" $ do
        result <- run Worker (replace "WORKER_VISIBILITY_TIMEOUT_SECONDS" "1" productionInputs) ["--check-config"]
        deploymentExitCode result @?= resolutionExitCode
        deploymentStandardError result @?= "workers.visibilityTimeoutSeconds: must be at least twice workers.concurrency\n",
      testCase "worker rejects the development secret in production" $ do
        result <- run Worker (filter ((/= "WEBHOOK_SECRET") . fst) productionInputs) ["--check-config"]
        deploymentExitCode result @?= resolutionExitCode
        deploymentStandardError result @?= "server.webhookSecret: development default is forbidden in production\n",
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
