module Settei.Example.ConformanceTest (tests) where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text qualified as Text
import Options.Applicative (ParserInfo)
import Options.Applicative qualified as Options
import Paths_settei_example_conformance qualified as Paths
import Settei
import Settei.Dhall qualified as Dhall
import Settei.Env qualified as Env
import Settei.Example.Cli qualified as Cli
import Settei.Example.Service qualified as Service
import Settei.Kdl qualified as Kdl
import Settei.Prelude
import Settei.Yaml qualified as Yaml
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei"
    [ testGroup
        "Conformance"
        [ testCase "YAML KDL and Dhall produce equal typed values" $ do
            sources <- loadFixtureSources
            results <- resolveFixtureSources sources
            let yamlValue = resolvedAnswer (results ^. #yaml)
            assertBool "KDL typed value differed from YAML" (resolvedAnswer (results ^. #kdl) == yamlValue)
            assertBool "Dhall typed value differed from YAML" (resolvedAnswer (results ^. #dhall) == yamlValue),
          testCase "normalized explanation structure is format-independent" $ do
            sources <- loadFixtureSources
            results <- resolveFixtureSources sources
            let yamlReport = normalizeReport (results ^. #yaml . #report)
            normalizeReport (results ^. #kdl . #report) @?= yamlReport
            normalizeReport (results ^. #dhall . #report) @?= yamlReport,
          testCase "each format retains its honest origin precision" $ do
            sources <- loadFixtureSources
            yamlOrigin <- candidateOrigin <$> expectCandidate httpHostKey (sources ^. #yaml)
            yamlOrigin ^? #location . _Just . #line @?= Just (Just 4)
            assertBool "YAML fixture path missing" (originPathEndsWith "service.yaml" yamlOrigin)

            kdlOrigin <- candidateOrigin <$> expectCandidate httpHostKey (sources ^. #kdl)
            kdlOrigin ^? #location . _Just . #line @?= Just (Just 5)
            kdlOrigin ^. #annotations . at "kdl.span.end-line" @?= Just "5"
            assertBool "KDL fixture path missing" (originPathEndsWith "service.kdl" kdlOrigin)

            dhallOrigin <- candidateOrigin <$> expectCandidate httpHostKey (sources ^. #dhall)
            assertBool "Dhall root path missing" (originPathEndsWith "service.dhall" dhallOrigin)
            dhallOrigin ^. #annotations . at "dhall.import-policy" @?= Just "no-imports"
            dhallOrigin ^. #annotations . at "dhall.import-count" @?= Just "0"
            assertBool
              "Dhall precision limitation missing"
              ( maybe
                  False
                  (Text.isInfixOf "leaf-level import attribution unavailable")
                  (dhallOrigin ^. #annotations . at "dhall.provenance-precision")
              ),
          testCase "source ordering and malformed higher values follow core policy" $ do
            let low = minimalServiceSource 7000
                high = source "higher file" (FileSource "memory") (nestedNumber "http" "port" 7100)
                environment = expectEnvSource (Env.envSnapshot [("HTTP_PORT", "8000")])
            defaultsResult <- expectResolution (resolve defaultResolveOptions [minimalServiceSourceWithoutDefaults] Service.serviceConfig)
            resolvedAnswer defaultsResult ^. #http . #port @?= 8080
            resolvedAnswer defaultsResult ^. #database . #poolSize @?= 2
            assertDerivation "http.port" "http-port-by-environment" defaultsResult

            fileResult <- expectResolution (resolve defaultResolveOptions [low, high] Service.serviceConfig)
            resolvedAnswer fileResult ^. #http . #port @?= 7100
            assertShadowCount "http.port" 1 fileResult

            environmentResult <- expectResolution (resolve defaultResolveOptions [low, environment] Service.serviceConfig)
            resolvedAnswer environmentResult ^. #http . #port @?= 8000
            assertShadowCount "http.port" 1 environmentResult

            let malformed = source "malformed higher file" (FileSource "memory") (nestedText "http" "port" "broken")
            case (resolve defaultResolveOptions [low, malformed] Service.serviceConfig) ^. #answer of
              Left problems -> fmap problemKey (NonEmpty.toList problems) @?= [httpPortKey]
              Right _ -> fail "malformed higher value unexpectedly fell back",
          testCase "CLI overrides environment after the shared file" $ do
            yamlPath <- Paths.getDataFileName "test/fixtures/service.yaml"
            options <-
              expectOptions
                Cli.cliParserInfo
                [ "--config",
                  "yaml:" <> yamlPath,
                  "--set",
                  "service.timeout=9000",
                  "--set",
                  "service.timeout=9001",
                  "--check-config"
                ]
            result <-
              Cli.resolveCliOptions
                (Env.envSnapshot [("SERVICE_TIMEOUT", "8000")])
                options
                >>= either (const (fail "CLI conformance resolution failed")) pure
            _ <- expectResolution result
            resolvedAnswer result ^. #timeout @?= 9001
            assertShadowCount "service.timeout" 4 result,
          testCase "Development and Production select the password branch correctly" $ do
            sources <- loadFixtureSources
            development <- expectResolution (resolve defaultResolveOptions [sources ^. #yaml] Service.serviceConfig)
            assertOutcome "database.password" NotSelected development

            let production = expectEnvSource (Env.envSnapshot [("HASKELL_ENV", "production")])
            case (resolve defaultResolveOptions [sources ^. #yaml, production] Service.serviceConfig) ^. #answer of
              Left problems -> fmap problemKey (NonEmpty.toList problems) @?= [databasePasswordKey]
              Right _ -> fail "Production unexpectedly resolved without a password"

            let withSecret =
                  expectEnvSource
                    ( Env.envSnapshot
                        [ ("HASKELL_ENV", "production"),
                          ("DATABASE_PASSWORD", secretSentinel)
                        ]
                    )
            secured <- expectResolution (resolve defaultResolveOptions [sources ^. #yaml, withSecret] Service.serviceConfig)
            assertBool "Production did not retain the selected password" (isJust (resolvedAnswer secured ^. #database . #password))
            let rendered = renderResolutionText (secured ^. #report) <> renderResolutionJson (secured ^. #report)
            assertBool "Secret sentinel reached a report" (not (secretSentinel `Text.isInfixOf` rendered))
        ],
      testGroup
        "Security"
        [ testCase "no captured output contains secret sentinels" $ do
            yamlPath <- Paths.getDataFileName "test/fixtures/service.yaml"
            cliOptions <- expectOptions Cli.cliParserInfo ["--explain-config-json"]
            cliRun <-
              Cli.runCliWithSnapshot
                (Env.envSnapshot [("SERVICE_TOKEN", secretSentinel)])
                cliOptions
            serviceOptions <- expectOptions Service.serviceParserInfo ["--config", "yaml:" <> yamlPath, "--explain-config-json"]
            serviceRun <-
              Service.runServiceWithSnapshot
                ( Env.envSnapshot
                    [ ("HASKELL_ENV", "production"),
                      ("DATABASE_PASSWORD", secretSentinel)
                    ]
                )
                serviceOptions
            let captured =
                  Cli.cliStandardOutput cliRun
                    <> Cli.cliStandardError cliRun
                    <> Service.serviceStandardOutput serviceRun
                    <> Service.serviceStandardError serviceRun
            assertBool "captured output leaked a secret sentinel" (not (secretSentinel `Text.isInfixOf` captured))
            assertBool "captured explanations did not show redaction" ("<redacted>" `Text.isInfixOf` captured)
        ]
    ]

data FixtureSources = FixtureSources
  { yaml :: !Source,
    kdl :: !Source,
    dhall :: !Source
  }
  deriving stock (Generic)

data FixtureResults = FixtureResults
  { yaml :: !(ResolveResult (Service.ServiceConfig, [Text])),
    kdl :: !(ResolveResult (Service.ServiceConfig, [Text])),
    dhall :: !(ResolveResult (Service.ServiceConfig, [Text]))
  }
  deriving stock (Generic)

data NormalizedOutcome
  = NormalizedResolved !Text
  | NormalizedMissing
  | NormalizedSkipped
  deriving stock (Generic, Eq, Show)

data NormalizedNode = NormalizedNode
  { key :: !Key,
    outcome :: !NormalizedOutcome,
    sourceClass :: !(Maybe Text),
    shadowCount :: !Int,
    derivation :: !(Maybe (Text, [Key]))
  }
  deriving stock (Generic, Eq, Show)

data NormalizedBranch = NormalizedBranch
  { dependencies :: ![Key],
    settings :: ![Key],
    selected :: !Bool
  }
  deriving stock (Generic, Eq, Show)

data NormalizedReport = NormalizedReport
  { nodes :: ![NormalizedNode],
    branches :: ![NormalizedBranch]
  }
  deriving stock (Generic, Eq, Show)

loadFixtureSources :: IO FixtureSources
loadFixtureSources = do
  yamlPath <- Paths.getDataFileName "test/fixtures/service.yaml"
  kdlPath <- Paths.getDataFileName "test/fixtures/service.kdl"
  dhallPath <- Paths.getDataFileName "test/fixtures/service.dhall"
  yaml <- Yaml.readYamlSource (Yaml.yamlSourceOptions "conformance YAML") yamlPath >>= expectLoaded
  kdl <- Kdl.readKdlSource (Kdl.kdlSourceOptions "conformance KDL") kdlPath >>= expectLoaded
  dhall <-
    Dhall.loadDhallSource
      (Dhall.dhallSourceOptions "conformance Dhall" Dhall.NoImports)
      (Dhall.DhallFile dhallPath)
      >>= expectLoaded
  pure FixtureSources {yaml, kdl, dhall}

resolveFixtureSources :: FixtureSources -> IO FixtureResults
resolveFixtureSources sources = do
  yaml <- expectResolution (resolve defaultResolveOptions [sources ^. #yaml] Service.serviceConformanceConfig)
  kdl <- expectResolution (resolve defaultResolveOptions [sources ^. #kdl] Service.serviceConformanceConfig)
  dhall <- expectResolution (resolve defaultResolveOptions [sources ^. #dhall] Service.serviceConformanceConfig)
  pure FixtureResults {yaml, kdl, dhall}

normalizeReport :: ResolutionReport -> NormalizedReport
normalizeReport report =
  NormalizedReport
    { nodes = fmap normalizeNode (reportNodes report),
      branches = fmap normalizeBranch (reportBranches report)
    }

normalizeNode :: ResolutionNode -> NormalizedNode
normalizeNode node =
  NormalizedNode
    { key = node ^. #key,
      outcome = case node ^. #outcome of
        Resolved value -> NormalizedResolved (renderReportedValue value)
        MissingValue -> NormalizedMissing
        NotSelected -> NormalizedSkipped,
      sourceClass = fmap (sourceKindClass . (^. #kind)) (node ^. #origin),
      shadowCount = length (node ^. #shadowed),
      derivation = fmap (\value -> (value ^. #rule, value ^. #dependencies)) (node ^. #derivation)
    }

normalizeBranch :: BranchTrace -> NormalizedBranch
normalizeBranch branch =
  NormalizedBranch
    { dependencies = branch ^. #dependencies,
      settings = branch ^. #settings,
      selected = branch ^. #selected
    }

sourceKindClass :: SourceKind -> Text
sourceKindClass = \case
  BuiltInSource -> "built-in"
  FileSource _ -> "file"
  EnvironmentSource -> "environment"
  CommandLineSource -> "command-line"
  DerivedSource -> "derived"
  CustomSource _ -> "custom"

originPathEndsWith :: Text -> Origin -> Bool
originPathEndsWith suffix origin =
  maybe False (Text.isSuffixOf suffix . (^. #path)) (origin ^. #location)

minimalServiceSourceWithoutDefaults :: Source
minimalServiceSourceWithoutDefaults =
  source
    "minimal service file"
    (FileSource "memory")
    ( RawObject
        ( Map.fromList
            [ ("runtime", RawObject (Map.singleton "environment" (RawText "development"))),
              ("http", RawObject (Map.singleton "host" (RawText "0.0.0.0"))),
              ("database", RawObject (Map.singleton "host" (RawText "postgres.internal")))
            ]
        )
    )

minimalServiceSource :: Integer -> Source
minimalServiceSource port =
  source
    "service file"
    (FileSource "memory")
    ( mergeObjects
        [ minimalServiceValue,
          nestedNumber "http" "port" port
        ]
    )

minimalServiceValue :: RawValue
minimalServiceValue =
  RawObject
    ( Map.fromList
        [ ("runtime", RawObject (Map.singleton "environment" (RawText "development"))),
          ("http", RawObject (Map.singleton "host" (RawText "0.0.0.0"))),
          ("database", RawObject (Map.singleton "host" (RawText "postgres.internal")))
        ]
    )

mergeObjects :: [RawValue] -> RawValue
mergeObjects values = RawObject (foldl merge Map.empty values)
  where
    merge accumulator (RawObject object) = Map.unionWith mergeNested object accumulator
    merge accumulator _ = accumulator
    mergeNested (RawObject high) (RawObject low) = RawObject (Map.union high low)
    mergeNested high _ = high

nestedNumber :: Text -> Text -> Integer -> RawValue
nestedNumber parent child value =
  RawObject (Map.singleton parent (RawObject (Map.singleton child (RawNumber (fromInteger value)))))

nestedText :: Text -> Text -> Text -> RawValue
nestedText parent child value =
  RawObject (Map.singleton parent (RawObject (Map.singleton child (RawText value))))

expectEnvSource :: Env.EnvSnapshot -> Source
expectEnvSource snapshot =
  case Env.envSource "environment" Service.environmentBindings snapshot of
    Left problems -> error (show problems)
    Right value -> value

expectCandidate :: Key -> Source -> IO Candidate
expectCandidate key input =
  case lookupSource key input of
    Right (Just value) -> pure value
    _ -> fail "expected source candidate"

expectLoaded :: (Show error) => Either (NonEmpty error) Source -> IO Source
expectLoaded = either (fail . show) pure

expectResolution :: ResolveResult value -> IO (ResolveResult value)
expectResolution result = case result ^. #answer of
  Left errors -> fail (Text.unpack (renderErrorsText errors))
  Right _ -> pure result

resolvedAnswer :: ResolveResult value -> value
resolvedAnswer result = case result ^. #answer of
  Left errors -> error (Text.unpack (renderErrorsText errors))
  Right value -> value

expectOptions :: ParserInfo options -> [String] -> IO options
expectOptions parserInfo arguments =
  case Options.execParserPure Options.defaultPrefs parserInfo arguments of
    Options.Success value -> pure value
    _ -> fail "expected example options to parse"

assertDerivation :: Text -> Text -> ResolveResult value -> IO ()
assertDerivation keyText rule result =
  case result ^. #report . #nodes . at (validKey keyText) of
    Just node -> fmap (^. #rule) (node ^. #derivation) @?= Just rule
    Nothing -> fail "expected a derived resolution node"

assertShadowCount :: Text -> Int -> ResolveResult value -> IO ()
assertShadowCount keyText expected result =
  case result ^. #report . #nodes . at (validKey keyText) of
    Just node -> length (node ^. #shadowed) @?= expected
    Nothing -> fail "expected a shadowed resolution node"

assertOutcome :: Text -> ResolutionOutcome -> ResolveResult value -> IO ()
assertOutcome keyText expected result =
  case result ^. #report . #nodes . at (validKey keyText) of
    Just node -> node ^. #outcome @?= expected
    Nothing -> fail "expected a resolution node"

problemKey :: ConfigError -> Key
problemKey = \case
  MissingRequired problem -> problem ^. #key
  DecodeError problem -> problem ^. #key
  StructuralConflict problem -> problem ^. #key
  UnknownKeyError problem -> problem ^. #key
  DefaultError problem -> problem ^. #key
  DefaultCycle _ -> error "cycle has no key"
  SensitivityConflict problem -> problem ^. #key

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

httpHostKey, httpPortKey, databasePasswordKey :: Key
httpHostKey = validKey "http.host"
httpPortKey = validKey "http.port"
databasePasswordKey = validKey "database.password"

secretSentinel :: Text
secretSentinel = "never-render-this-conformance-secret"
