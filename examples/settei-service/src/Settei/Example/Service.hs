-- |
-- Module: Settei.Example.Service
-- Description: Kubernetes-shaped service configuration composed from public Settei APIs.
module Settei.Example.Service
  ( DatabaseConfig,
    HttpConfig,
    RuntimeEnvironment (..),
    SecretText,
    ServiceConfig,
    DiagnosticMode (..),
    ServiceOptions,
    ServiceRun,
    environmentBindings,
    resolutionExitCode,
    resolveServiceOptions,
    resolveServiceSources,
    runServiceWithSnapshot,
    safeStartupSummary,
    serviceConfig,
    serviceConformanceConfig,
    serviceExitCode,
    serviceParserInfo,
    serviceStandardError,
    serviceStandardOutput,
    sourceExitCode,
    usageExitCode,
  )
where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Options.Applicative (Parser, ParserInfo)
import Options.Applicative qualified as Options
import Settei
import Settei.Env
import Settei.Formats
import Settei.Formats.Optparse (configInputReader)
import Settei.Optparse
import Settei.Prelude
import Text.Printf (printf)

-- | Runtime environment that selects the service's named defaults and secret branch.
data RuntimeEnvironment = Development | Test | Production
  deriving stock (Generic, Eq, Ord, Show)

-- | Password wrapper deliberately lacking a revealing 'Show' instance.
newtype SecretText = SecretText Text
  deriving stock (Generic, Eq)

-- | Fully resolved service configuration; the secret-bearing constructor stays private.
data ServiceConfig = ServiceConfig
  { environment :: !RuntimeEnvironment,
    http :: !HttpConfig,
    database :: !DatabaseConfig
  }
  deriving stock (Generic, Eq)

-- | Public HTTP listener configuration.
data HttpConfig = HttpConfig
  { host :: !Text,
    port :: !Int
  }
  deriving stock (Generic, Eq, Show)

-- | Database configuration whose constructor and secret-bearing fields stay private.
data DatabaseConfig = DatabaseConfig
  { host :: !Text,
    port :: !Int,
    poolSize :: !Int,
    password :: !(Maybe SecretText)
  }
  deriving stock (Generic, Eq)

-- | Parsed command line before the mounted file is loaded.
data ServiceOptions = ServiceOptions
  { configInput :: !(Maybe ConfigInput),
    diagnosticMode :: !DiagnosticMode
  }
  deriving stock (Generic, Eq, Show)

-- | Capturable process result used by the executable and security tests.
data ServiceRun = ServiceRun
  { exitCode :: !Int,
    standardOutput :: !Text,
    standardError :: !Text
  }
  deriving stock (Generic, Eq, Show)

usageExitCode, sourceExitCode, resolutionExitCode :: Int

-- | Exit code reserved for optparse-applicative usage failures.
usageExitCode = 2

-- | Exit code reserved for mounted-file IO or adapter parsing failures.
sourceExitCode = 3

-- | Exit code reserved for typed resolution failures.
resolutionExitCode = 4

-- | Return the process exit code chosen by a completed run.
serviceExitCode :: ServiceRun -> Int
serviceExitCode value = value ^. #exitCode

-- | Return captured standard output.
serviceStandardOutput :: ServiceRun -> Text
serviceStandardOutput value = value ^. #standardOutput

-- | Return captured standard error.
serviceStandardError :: ServiceRun -> Text
serviceStandardError value = value ^. #standardError

-- | Complete parser metadata, help, and usage-error policy.
serviceParserInfo :: ParserInfo ServiceOptions
serviceParserInfo =
  Options.info
    (serviceOptionsParser Options.<**> Options.helper)
    ( Options.fullDesc
        <> Options.progDesc "Load and explain Kubernetes-shaped service configuration"
        <> Options.failureCode usageExitCode
    )

serviceOptionsParser :: Parser ServiceOptions
serviceOptionsParser =
  ServiceOptions
    <$> Options.parserOptionGroup "Configuration" configInputParser
    <*> Options.parserOptionGroup "Diagnostics" diagnosticModeOptions

configInputParser :: Parser (Maybe ConfigInput)
configInputParser =
  Options.optional
    ( Options.option
        configInputReader
        ( Options.long "config"
            <> Options.metavar "FORMAT:PATH"
            <> Options.help "Load one mounted yaml:PATH, kdl:PATH, or dhall:PATH"
        )
    )

-- | Service declaration with named defaults and a Production-only password.
serviceConfig :: Config ServiceConfig
serviceConfig =
  ServiceConfig
    <$> required environmentSetting
    <*> httpConfig
    <*> databaseConfig

-- | Service declaration paired with the list used by cross-format conformance tests.
serviceConformanceConfig :: Config (ServiceConfig, [Text])
serviceConformanceConfig =
  (,)
    <$> serviceConfig
    <*> required serviceTagsSetting

httpConfig :: Config HttpConfig
httpConfig =
  HttpConfig
    <$> required httpHostSetting
    <*> withDefault httpPortSetting httpPortDefault

databaseConfig :: Config DatabaseConfig
databaseConfig =
  DatabaseConfig
    <$> required databaseHostSetting
    <*> withDefault databasePortSetting databasePortDefault
    <*> withDefault databasePoolSizeSetting databasePoolSizeDefault
    <*> productionPassword

productionPassword :: Config (Maybe SecretText)
productionPassword =
  whenEq (required environmentSetting) Production (required databasePasswordSetting)

httpPortDefault :: Default Int
httpPortDefault =
  caseDefault
    (RuleName "http-port-by-environment")
    "Choose the HTTP port for the runtime environment"
    (required environmentSetting)
    ((Development, 8080) :| [(Test, 18080), (Production, 8080)])
    Nothing

databasePoolSizeDefault :: Default Int
databasePoolSizeDefault =
  caseDefault
    (RuleName "database-pool-size-by-environment")
    "Choose the database pool size for the runtime environment"
    (required environmentSetting)
    ((Development, 2) :| [(Test, 1), (Production, 20)])
    Nothing

databasePortDefault :: Default Int
databasePortDefault =
  constantDefault
    (RuleName "postgres-default-port")
    "Use PostgreSQL's conventional port"
    5432

-- | Explicit environment bindings, including the annotated Kubernetes Secret value.
--
-- Validated once at module level; the test suite forces this CAF so an invalid edit
-- fails in tests before it can fail at startup.
environmentBindings :: Bindings
environmentBindings =
  either
    (error . Text.unpack . renderEnvErrorsText)
    id
    ( bindings
        [ binding (EnvName "HASKELL_ENV") runtimeEnvironmentKey,
          binding (EnvName "HTTP_HOST") httpHostKey,
          binding (EnvName "HTTP_PORT") httpPortKey,
          binding (EnvName "DATABASE_HOST") databaseHostKey,
          binding (EnvName "DATABASE_PORT") databasePortKey,
          binding (EnvName "DATABASE_POOL_SIZE") databasePoolSizeKey,
          fromKubernetesObject
            (kubernetesRef SecretObject Nothing "settei-example-service-database" (Just "password"))
            (binding (EnvName "DATABASE_PASSWORD") databasePasswordKey)
        ]
    )

-- | Load, resolve, and render one capturable run against an injected snapshot.
runServiceWithSnapshot :: EnvSnapshot -> ServiceOptions -> IO ServiceRun
runServiceWithSnapshot snapshot options = do
  case schemaDiagnostic (options ^. #diagnosticMode) (describe serviceConfig) of
    Just output -> pure (successfulRun output "")
    Nothing -> do
      resolved <- resolveServiceOptions snapshot options
      pure $ case resolved of
        Left (InputFailure message) -> failedRun sourceExitCode message
        Right result -> case result ^. #answer of
          Left problems ->
            failedRun
              resolutionExitCode
              (renderErrorsText problems <> failureReport options result)
          Right config ->
            successfulRun
              (maybe (safeStartupSummary config) id (resolutionDiagnostic (options ^. #diagnosticMode) result))
              (renderWarningsText (result ^. #warnings))

-- | Resolve the parsed mounted-file option followed by the environment source.
resolveServiceOptions :: EnvSnapshot -> ServiceOptions -> IO (Either ServiceFailure (ResolveResult ServiceConfig))
resolveServiceOptions snapshot options = do
  loaded <- traverse (loadConfigInput loadOptions) (options ^. #configInput)
  pure $ do
    fileSources <- case loaded of
      Nothing -> Right []
      Just (Left problems) -> Left (InputFailure (renderFormatLoadErrorsText problems))
      Just (Right value) -> Right [value]
    Right (resolveServiceSources fileSources snapshot)

-- | Resolve already loaded file sources followed by an injected environment snapshot.
resolveServiceSources :: [Source] -> EnvSnapshot -> ResolveResult ServiceConfig
resolveServiceSources fileSources snapshot =
  resolve
    defaultResolveOptions
    (fileSources <> [environmentSource environmentBindings snapshot])
    serviceConfig

data ServiceFailure
  = InputFailure !Text

loadOptions :: LoadOptions
loadOptions =
  fromKubernetesMountedFile
    (kubernetesRef ConfigMapObject Nothing "settei-example-service" (Just "application.yaml"))
    defaultLoadOptions

renderFormatLoadErrorsText :: NonEmpty FormatLoadError -> Text
renderFormatLoadErrorsText = Text.concat . fmap renderFormatLoadErrorText . NonEmpty.toList

-- | Render only allowlisted non-secret startup fields.
safeStartupSummary :: ServiceConfig -> Text
safeStartupSummary config =
  Text.unlines
    [ "settei example service ready",
      "environment: " <> renderEnvironment (config ^. #environment),
      "http: " <> config ^. #http . #host <> ":" <> renderInt (config ^. #http . #port),
      "database: " <> config ^. #database . #host <> ":" <> renderInt (config ^. #database . #port),
      "database pool size: " <> renderInt (config ^. #database . #poolSize)
    ]

-- | Append provenance to a resolution failure only in an explicit explain mode.
failureReport :: ServiceOptions -> ResolveResult ServiceConfig -> Text
failureReport options result =
  case options ^. #diagnosticMode of
    ExplainText -> renderResolutionText (result ^. #report)
    ExplainJson -> renderResolutionJson (result ^. #report) <> "\n"
    _ -> ""

successfulRun :: Text -> Text -> ServiceRun
successfulRun output warnings = ServiceRun {exitCode = 0, standardOutput = output, standardError = warnings}

failedRun :: Int -> Text -> ServiceRun
failedRun code message = ServiceRun {exitCode = code, standardOutput = "", standardError = message}

environmentSetting :: Setting RuntimeEnvironment
environmentSetting =
  publicSettingWithRenderer
    runtimeEnvironmentKey
    "Runtime environment"
    (enumDecoder [("development", Development), ("test", Test), ("production", Production)])
    renderEnvironment

httpHostSetting :: Setting Text
httpHostSetting = publicSetting httpHostKey "HTTP bind host" textDecoder

httpPortSetting :: Setting Int
httpPortSetting = publicShowSetting httpPortKey "HTTP bind port" boundedIntegralDecoder

databaseHostSetting :: Setting Text
databaseHostSetting = publicSetting databaseHostKey "Database host" textDecoder

databasePortSetting :: Setting Int
databasePortSetting = publicShowSetting databasePortKey "Database port" boundedIntegralDecoder

databasePoolSizeSetting :: Setting Int
databasePoolSizeSetting =
  publicShowSetting databasePoolSizeKey "Database pool size" boundedIntegralDecoder

databasePasswordSetting :: Setting SecretText
databasePasswordSetting =
  secretSetting databasePasswordKey "Database password" (SecretText <$> textDecoder)

serviceTagsSetting :: Setting [Text]
serviceTagsSetting =
  publicSetting serviceTagsKey "Conformance service tags" (listDecoder textDecoder)

renderEnvironment :: RuntimeEnvironment -> Text
renderEnvironment Development = "development"
renderEnvironment Test = "test"
renderEnvironment Production = "production"

renderInt :: Int -> Text
renderInt value = Text.pack (printf "%d" value)

runtimeEnvironmentKey, httpHostKey, httpPortKey, databaseHostKey, databasePortKey, databasePoolSizeKey, databasePasswordKey, serviceTagsKey :: Key
runtimeEnvironmentKey = validKey "runtime.environment"
httpHostKey = validKey "http.host"
httpPortKey = validKey "http.port"
databaseHostKey = validKey "database.host"
databasePortKey = validKey "database.port"
databasePoolSizeKey = validKey "database.poolSize"
databasePasswordKey = validKey "database.password"
serviceTagsKey = validKey "service.tags"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
