module Settei.Example.ServiceTest (tests) where

import Data.Foldable (for_)
import Data.Generics.Labels ()
import Data.List (nub)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing, listToMaybe)
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Options.Applicative qualified as Options
import Paths_settei_example_service qualified as Paths
import Settei
import Settei.Env
import Settei.Example.Service
import Settei.Prelude
import Settei.Yaml qualified as Yaml
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Example.Service"
    [ testCase "environment bindings validate at construction" $
        length (bindingsList environmentBindings) @?= 8,
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
          ),
      testCase "mounted secrets directory resolves the production password" $
        withMountedSecret secretSentinel $ \directory -> do
          mounted <- expectMountedSecrets directory
          let result =
                resolveServiceSources
                  [publicSource, mounted]
                  (envSnapshot [("HASKELL_ENV", "production")])
          config <- expectResolution result
          assertBool
            "mounted password did not satisfy the Production requirement"
            (not (isNothing (config ^. #database . #password))),
      testCase "mounted-directory origin carries identity mount path and freshness" $
        withMountedSecret secretSentinel $ \directory -> do
          mounted <- expectMountedSecrets directory
          let result =
                resolveServiceSources
                  [publicSource, mounted]
                  (envSnapshot [("HASKELL_ENV", "production")])
          _ <- expectResolution result
          origin <- expectChosenOrigin databasePasswordKey result
          origin ^. #annotations . at "kubernetes.object-name"
            @?= Just "settei-example-service-database"
          origin ^. #annotations . at "kubernetes.object-key" @?= Just "password"
          origin ^. #annotations . at "kubernetes.mount-path" @?= Just (Text.pack directory)
          assertBool
            "file modification annotation missing"
            (not (isNothing (origin ^. #annotations . at "kubernetes.file-modified")))
          assertBool
            "source read timestamp missing"
            (not (isNothing (origin ^. #annotations . at "kubernetes.read-at")))
          let rendered = renderResolutionText (result ^. #report)
          assertBool "mounted file path missing" (Text.pack directory `Text.isInfixOf` rendered)
          assertBool "mounted report leaked password" (not (secretSentinel `Text.isInfixOf` rendered))
          assertBool "mounted report omitted redaction" ("<redacted>" `Text.isInfixOf` rendered),
      testCase "environment shadows the mounted secret" $
        withMountedSecret "mounted-secret-sentinel" $ \directory -> do
          mounted <- expectMountedSecrets directory
          let result =
                resolveServiceSources
                  [publicSource, mounted]
                  ( envSnapshot
                      [ ("HASKELL_ENV", "production"),
                        ("DATABASE_PASSWORD", "environment-secret-sentinel")
                      ]
                  )
          _ <- expectResolution result
          case result ^. #report . #nodes . at databasePasswordKey of
            Just node -> do
              fmap (^. #kind) (node ^. #origin) @?= Just EnvironmentSource
              length (node ^. #shadowed) @?= 1
              fmap (^. #kind) (listToMaybe (node ^. #shadowed))
                @?= Just (CustomSource "kubernetes-mounted-directory")
            Nothing -> fail "expected database.password report node",
      testCase "missing and invalid secrets paths are source failures" $
        withSystemTempDirectory "settei-service-source-errors" $ \directory -> do
          let missingPath = directory </> "missing"
              regularFile = directory </> "not-a-directory"
          TextIO.writeFile regularFile "not a mount"
          for_ [missingPath, regularFile] $ \path -> do
            options <- expectOptions ["--secrets-dir", path, "--check-config"]
            result <- runServiceWithSnapshot completeProductionSnapshot options
            serviceExitCode result @?= sourceExitCode
            assertBool
              "mounted-directory source error omitted the stable message"
              ("mounted path is not a directory" `Text.isInfixOf` serviceStandardError result)
            assertBool
              "mounted-directory source error used a derived Show representation"
              (not ("KubernetesSourceError" `Text.isInfixOf` serviceStandardError result)),
      testCase "absent password file remains a resolution failure" $
        withSystemTempDirectory "settei-service-empty-secret" $ \directory -> do
          options <- expectOptions ["--secrets-dir", directory, "--check-config"]
          result <- runServiceWithSnapshot completeProductionSnapshot options
          serviceExitCode result @?= resolutionExitCode
          assertBool
            "missing mounted password did not reach typed resolution"
            ("database.password: required value is missing" `Text.isInfixOf` serviceStandardError result),
      testCase "downward API namespace is visible when supplied" $ do
        let result =
              resolveServiceSources
                [publicSource]
                ( envSnapshot
                    [ ("POD_NAMESPACE", "production"),
                      ("HASKELL_ENV", "development")
                    ]
                )
        _ <- expectResolution result
        let rendered = renderResolutionText (result ^. #report)
        assertBool "namespace setting missing" ("kubernetes.namespace" `Text.isInfixOf` rendered)
        assertBool "namespace value missing" ("production" `Text.isInfixOf` rendered),
      testCase "check-config accepts a mounted Secret directory" $
        withMountedSecret secretSentinel $ \directory -> do
          fixture <- Paths.getDataFileName "test/fixtures/application.yaml"
          options <-
            expectOptions
              [ "--config",
                "yaml:" <> fixture,
                "--secrets-dir",
                directory,
                "--check-config"
              ]
          result <- runServiceWithSnapshot (envSnapshot [("HASKELL_ENV", "production")]) options
          serviceExitCode result @?= 0
          serviceStandardOutput result @?= "configuration valid\n"
          assertBool "check output leaked mounted secret" (not (secretSentinel `Text.isInfixOf` serviceStandardOutput result)),
      testCase "explain-config reports the mounted Secret safely" $
        withMountedSecret secretSentinel $ \directory -> do
          fixture <- Paths.getDataFileName "test/fixtures/application.yaml"
          options <-
            expectOptions
              [ "--config",
                "yaml:" <> fixture,
                "--secrets-dir",
                directory,
                "--explain-config"
              ]
          result <- runServiceWithSnapshot (envSnapshot [("HASKELL_ENV", "production")]) options
          serviceExitCode result @?= 0
          let output = serviceStandardOutput result
          assertBool "mounted object identity missing" ("settei-example-service-database" `Text.isInfixOf` output)
          assertBool "mounted path missing" (Text.pack directory `Text.isInfixOf` output)
          assertBool "freshness suffix missing" ("(modified " `Text.isInfixOf` output)
          assertBool "explanation leaked mounted secret" (not (secretSentinel `Text.isInfixOf` output))
          assertBool "explanation omitted redaction" ("<redacted>" `Text.isInfixOf` output),
      testCase "deploy manifests reference only real service flags" $ do
        paths <- traverse Paths.getDataFileName deployManifestPaths
        manifests <- traverse TextIO.readFile paths
        let manifestFlags =
              nub
                [ token
                | manifest <- manifests,
                  token <- Text.words manifest,
                  "--" `Text.isPrefixOf` token
                ]
            helpText = serviceHelpText
        assertBool "deploy manifests contain no service flags" (not (null manifestFlags))
        for_ manifestFlags $ \flag ->
          assertBool
            ("deploy manifest references unknown flag " <> Text.unpack flag)
            (flag `Text.isInfixOf` helpText)
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

completeProductionSnapshot :: EnvSnapshot
completeProductionSnapshot =
  envSnapshot
    [ ("HASKELL_ENV", "production"),
      ("HTTP_HOST", "0.0.0.0"),
      ("DATABASE_HOST", "postgres.internal")
    ]

secretSentinel :: Text
secretSentinel = "never-render-this-service-secret"

withMountedSecret :: Text -> (FilePath -> IO a) -> IO a
withMountedSecret value action =
  withSystemTempDirectory "settei-service-mounted-secret" $ \directory -> do
    TextIO.writeFile (directory </> "password") value
    action directory

expectMountedSecrets :: FilePath -> IO Source
expectMountedSecrets directory =
  loadMountedSecretsSource directory >>= either (fail . Text.unpack) pure

expectChosenOrigin :: Key -> ResolveResult a -> IO Origin
expectChosenOrigin key result =
  case result ^. #report . #nodes . at key >>= (^. #origin) of
    Just origin -> pure origin
    Nothing -> fail "expected chosen origin"

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

serviceHelpText :: Text
serviceHelpText =
  case Options.execParserPure Options.defaultPrefs serviceParserInfo ["--help"] of
    Options.Failure failure -> Text.pack (fst (Options.renderFailure failure "settei-example-service"))
    _ -> error "service --help unexpectedly parsed without producing help"

deployManifestPaths :: [FilePath]
deployManifestPaths =
  [ "deploy/base/deployment.yaml",
    "deploy/base/kustomization.yaml",
    "deploy/overlays/dev/configmap.yaml",
    "deploy/overlays/dev/kustomization.yaml",
    "deploy/overlays/dev/secret.yaml",
    "deploy/overlays/production/configmap.yaml",
    "deploy/overlays/production/kustomization.yaml",
    "deploy/overlays/production/secret.yaml",
    "deploy/overlays/test/configmap.yaml",
    "deploy/overlays/test/kustomization.yaml",
    "deploy/overlays/test/secret.yaml"
  ]

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

databasePasswordKey :: Key
databasePasswordKey = validKey "database.password"
