module Settei.Example.ServiceTest (tests) where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Text qualified as Text
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
    [ testCase "development derives defaults without a password" $ do
        result <- expectResolution (resolveServiceSources [publicSource] (envSnapshot [("HASKELL_ENV", "development")]))
        result ^. #value . #http . #port @?= 8080
        result ^. #value . #database . #poolSize @?= 2
        assertBool "development must not select a password" (isNothing (result ^. #value . #database . #password))
        assertRule "http.port" "http-port-by-environment" result
        assertRule "database.poolSize" "database-pool-size-by-environment" result
        case result ^. #report . #nodes . at (validKey "database.password") of
          Just node -> node ^. #outcome @?= NotSelected
          Nothing -> fail "expected not-selected password node",
      testCase "production requires an annotated password" $ do
        case resolveServiceSources [publicSource] (envSnapshot [("HASKELL_ENV", "production")]) of
          Left problems -> fmap problemKey (NonEmpty.toList problems) @?= [validKey "database.password"]
          Right _ -> fail "production unexpectedly resolved without a password"
        result <- expectResolution (resolveServiceSources [publicSource] productionSnapshot)
        let reportText = renderResolutionText (result ^. #report)
            reportJson = renderResolutionJson (result ^. #report)
            startup = safeStartupSummary (result ^. #value)
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
        result <- expectResolution (resolveServiceSources [input] (envSnapshot [("HASKELL_ENV", "development")]))
        let rendered = renderResolutionText (result ^. #report)
        assertBool "ConfigMap origin missing" ("settei-example-service" `Text.isInfixOf` rendered),
      testCase "normal mode prints only a safe startup summary" $ do
        result <- expectResolution (resolveServiceSources [publicSource] productionSnapshot)
        let summary = safeStartupSummary (result ^. #value)
        assertBool "summary omitted HTTP address" ("0.0.0.0:8080" `Text.isInfixOf` summary)
        assertBool "summary leaked secret" (not (secretSentinel `Text.isInfixOf` summary))
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

expectResolution :: Either a b -> IO b
expectResolution = \case
  Left _ -> fail "expected service resolution to succeed"
  Right value -> pure value

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
