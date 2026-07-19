module Settei.Example.ServiceTest (tests) where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Text qualified as Text
import Options.Applicative qualified as Options
import Paths_settei_example_service qualified as Paths
import Settei
import Settei.Env
import Settei.Example.Service
import Settei.Prelude
import Settei.Yaml qualified as Yaml
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Example.Service"
    [ testCase "environment bindings validate at construction" $
        length (bindingsList environmentBindings) @?= 7,
      testCase "development derives defaults without a password" $ do
        let result = resolveServiceSources [publicSource] (envSnapshot [("HASKELL_ENV", "development")])
        config <- expectResolution result
        config ^. #http . #port @?= 8080
        config ^. #database . #poolSize @?= 2
        assertBool "development must not select a password" (isNothing (config ^. #database . #password))
        assertRule "http.port" "http-port-by-environment" result
        assertRule "database.poolSize" "database-pool-size-by-environment" result
        case result ^. #report . #nodes . at (validKey "database.password") of
          Just node -> node ^. #outcome @?= NotSelected
          Nothing -> fail "expected not-selected password node",
      testCase "production requires an annotated password" $ do
        let missing = resolveServiceSources [publicSource] (envSnapshot [("HASKELL_ENV", "production")])
        case missing ^. #answer of
          Left problems -> fmap problemKey (NonEmpty.toList problems) @?= [validKey "database.password"]
          Right _ -> fail "production unexpectedly resolved without a password"
        let result = resolveServiceSources [publicSource] productionSnapshot
        config <- expectResolution result
        let reportText = renderResolutionText (result ^. #report)
            reportJson = renderResolutionJson (result ^. #report)
            startup = safeStartupSummary config
        assertBool "Secret origin missing" ("settei-example-service-database" `Text.isInfixOf` reportText)
        assertBool "text report leaked password" (not (secretSentinel `Text.isInfixOf` reportText))
        assertBool "JSON report leaked password" (not (secretSentinel `Text.isInfixOf` reportJson))
        assertBool "startup summary leaked password" (not (secretSentinel `Text.isInfixOf` startup)),
      testCase "mounted ConfigMap provenance survives file loading" $ do
        fixture <- Paths.getDataFileName "test/fixtures/application.yaml"
        loaded <-
          Yaml.readYamlSource
            ( Yaml.fromKubernetesMountedFile
                (kubernetesRef ConfigMapObject Nothing "settei-example-service" (Just "application.yaml"))
                (Yaml.yamlSourceOptions "mounted service fixture")
            )
            fixture
        input <- either (const (fail "expected fixture to load")) pure loaded
        let result = resolveServiceSources [input] (envSnapshot [("HASKELL_ENV", "development")])
        _ <- expectResolution result
        let rendered = renderResolutionText (result ^. #report)
        assertBool "ConfigMap origin missing" ("settei-example-service" `Text.isInfixOf` rendered),
      testCase "normal mode prints only a safe startup summary" $ do
        let result = resolveServiceSources [publicSource] productionSnapshot
        config <- expectResolution result
        let summary = safeStartupSummary config
        assertBool "summary omitted HTTP address" ("0.0.0.0:8080" `Text.isInfixOf` summary)
        assertBool "summary leaked secret" (not (secretSentinel `Text.isInfixOf` summary)),
      testCase "describe modes short-circuit before loading sources" $ do
        textOptions <- expectOptions ["--config", "yaml:/definitely/missing.yaml", "--describe-config"]
        textResult <- runServiceWithSnapshot (envSnapshot []) textOptions
        serviceExitCode textResult @?= 0
        assertBool "text schema omitted database host" ("database.host" `Text.isInfixOf` serviceStandardOutput textResult)
        jsonOptions <- expectOptions ["--config", "yaml:/definitely/missing.yaml", "--describe-config-json"]
        jsonResult <- runServiceWithSnapshot (envSnapshot []) jsonOptions
        serviceExitCode jsonResult @?= 0
        assertBool "schema JSON version missing" ("\"schemaVersion\":1" `Text.isInfixOf` serviceStandardOutput jsonResult),
      testCase "successful resolution renders warnings to stderr" $ do
        fixture <- Paths.getDataFileName "test/fixtures/application.yaml"
        options <- expectOptions ["--config", "yaml:" <> fixture, "--check-config"]
        result <- runServiceWithSnapshot (envSnapshot [("HASKELL_ENV", "development")]) options
        serviceExitCode result @?= 0
        serviceStandardOutput result @?= "configuration valid\n"
        assertBool "unknown-key warning missing from stderr" ("undeclared.setting" `Text.isInfixOf` serviceStandardError result),
      testCase "production failure explains missing password without leaking" $ do
        fixture <- Paths.getDataFileName "test/fixtures/application.yaml"
        options <- expectOptions ["--config", "yaml:" <> fixture, "--explain-config"]
        result <- runServiceWithSnapshot (envSnapshot [("HASKELL_ENV", "production")]) options
        serviceExitCode result @?= resolutionExitCode
        serviceStandardOutput result @?= ""
        assertBool
          "failure omitted the missing-password error"
          ("database.password: required value is missing" `Text.isInfixOf` serviceStandardError result)
        assertBool
          "failure omitted the missing-password provenance node"
          ("database.password = <missing>" `Text.isInfixOf` serviceStandardError result)

        secretFailure <-
          runServiceWithSnapshot
            ( envSnapshot
                [ ("HASKELL_ENV", "production"),
                  ("DATABASE_PASSWORD", secretSentinel),
                  ("HTTP_PORT", "broken")
                ]
            )
            options
        serviceExitCode secretFailure @?= resolutionExitCode
        assertBool
          "secret-bearing failure leaked its sentinel"
          ( not (secretSentinel `Text.isInfixOf` serviceStandardOutput secretFailure)
              && not (secretSentinel `Text.isInfixOf` serviceStandardError secretFailure)
          )
    ]

publicSource :: Source
publicSource =
  source
    "public service settings"
    (FileSource "memory")
    ( RawObject
        ( Map.fromList
            [ ("http", RawObject (Map.singleton "host" (RawText "0.0.0.0"))),
              ("database", RawObject (Map.singleton "host" (RawText "postgres.internal")))
            ]
        )
    )

productionSnapshot :: EnvSnapshot
productionSnapshot =
  envSnapshot
    [ ("HASKELL_ENV", "production"),
      ("DATABASE_PASSWORD", secretSentinel)
    ]

secretSentinel :: Text
secretSentinel = "never-render-this-service-secret"

assertRule :: Text -> Text -> ResolveResult ServiceConfig -> IO ()
assertRule keyText expected result =
  case result ^. #report . #nodes . at (validKey keyText) of
    Just node -> fmap (^. #rule) (node ^. #derivation) @?= Just expected
    Nothing -> fail "expected derived report node"

problemKey :: ConfigError -> Key
problemKey = \case
  MissingRequired problem -> problem ^. #key
  DecodeError problem -> problem ^. #key
  StructuralConflict problem -> problem ^. #key
  UnknownKeyError problem -> problem ^. #key
  DefaultError problem -> problem ^. #key
  DefaultCycle _ -> error "cycle has no key"
  SensitivityConflict problem -> problem ^. #key

expectResolution :: ResolveResult a -> IO a
expectResolution result = case result ^. #answer of
  Left _ -> fail "expected service resolution to succeed"
  Right value -> pure value

expectOptions :: [String] -> IO ServiceOptions
expectOptions arguments =
  case Options.execParserPure Options.defaultPrefs serviceParserInfo arguments of
    Options.Success value -> pure value
    _ -> fail "expected service options to parse"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
