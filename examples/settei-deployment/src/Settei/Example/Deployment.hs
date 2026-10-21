-- | A notification-hub-shaped first-deployment workflow using public APIs only.
module Settei.Example.Deployment
  ( Role (..),
    DeploymentConfig,
    DeploymentOptions,
    DeploymentRun,
    deploymentConfig,
    builtInDefaultsSource,
    environmentBindings,
    productionProfile,
    deploymentContractInputs,
    deploymentParserInfo,
    runDeploymentWithSnapshot,
    runDeploymentWithStartup,
    runDeploymentWithEnvironment,
    serverValidators,
    workerValidators,
    roleValidators,
    usageExitCode,
    sourceExitCode,
    resolutionExitCode,
    deploymentExitCode,
    deploymentStandardOutput,
    deploymentStandardError,
  )
where

import Data.Generics.Labels ()
import Data.Text qualified as Text
import Options.Applicative (ParserInfo)
import Options.Applicative qualified as Options
import Settei
import Settei.Env
import Settei.Optparse
import Settei.Prelude
import Settei.Yaml qualified as Yaml

data Role = Server | Worker
  deriving stock (Generic, Eq, Show)

data RuntimeEnvironment = Development | Test | Production
  deriving stock (Generic, Eq, Ord, Show)

-- Deliberately no Show: the typed configuration retains real secrets.
data DeploymentConfig = DeploymentConfig
  { environment :: !RuntimeEnvironment,
    databaseUrl :: !Text,
    poolSize :: !Int,
    host :: !Text,
    port :: !Int,
    webhookSecret :: !Text,
    deliveryEndpoint :: !Text,
    concurrency :: !Int,
    visibilityTimeoutSeconds :: !Int,
    serviceName :: !Text,
    emailCredentials :: !(Maybe Text)
  }
  deriving stock (Generic, Eq)

newtype DeploymentOptions = DeploymentOptions {options :: SetteiOptions}
  deriving stock (Generic, Eq)

data DeploymentRun = DeploymentRun
  {exitCode :: !Int, standardOutput :: !Text, standardError :: !Text}
  deriving stock (Generic, Eq, Show)

usageExitCode, sourceExitCode, resolutionExitCode :: Int
usageExitCode = 2
sourceExitCode = 3
resolutionExitCode = 4

deploymentExitCode :: DeploymentRun -> Int
deploymentExitCode value = value ^. #exitCode

deploymentStandardOutput :: DeploymentRun -> Text
deploymentStandardOutput value = value ^. #standardOutput

deploymentStandardError :: DeploymentRun -> Text
deploymentStandardError value = value ^. #standardError

validKey :: Text -> Key
validKey = either (error . show) id . parseKey

textSetting :: Text -> Text -> Setting Text
textSetting target description = publicShowSetting (validKey target) description textDecoder

intSetting :: Text -> Text -> Setting Int
intSetting target description = publicShowSetting (validKey target) description boundedIntegralDecoder

secretText :: Text -> Text -> Setting Text
secretText target description = secretSetting (validKey target) description textDecoder

environmentSetting :: Setting RuntimeEnvironment
environmentSetting =
  publicSettingWithRenderer
    (validKey "runtime.environment")
    "Runtime environment"
    (enumDecoder [("development", Development), ("test", Test), ("production", Production)])
    environmentText

environmentText :: RuntimeEnvironment -> Text
environmentText = \case Development -> "development"; Test -> "test"; Production -> "production"

deploymentConfig :: Config DeploymentConfig
deploymentConfig =
  DeploymentConfig
    <$> required environmentSetting
    <*> required (secretText "database.url" "PostgreSQL connection string")
    <*> required (intSetting "database.poolSize" "Database pool size")
    <*> required (textSetting "server.host" "HTTP bind host")
    <*> required (intSetting "server.port" "HTTP port")
    <*> required (secretText "server.webhookSecret" "Delivery webhook HMAC secret")
    <*> required (textSetting "workers.deliveryEndpoint" "Delivery endpoint")
    <*> withDefault
      (intSetting "workers.concurrency" "Concurrent delivery handlers")
      ( caseDefault
          (RuleName "worker-concurrency-by-environment")
          "Choose capacity for the runtime environment"
          (required environmentSetting)
          ((Development, 2) :| [(Test, 4), (Production, 16)])
          Nothing
      )
    <*> withDefault
      (intSetting "workers.visibilityTimeoutSeconds" "Delivery visibility timeout in seconds")
      (constantDefault (RuleName "worker-visibility-timeout") "Default lease duration" 180)
    <*> withDefault
      (textSetting "telemetry.serviceName" "OpenTelemetry service name")
      ( derivedDefault
          (RuleName "telemetry-service-name-by-environment")
          "Name telemetry for the runtime environment"
          (required environmentSetting)
          (("notification-hub-" <>) . environmentText)
      )
    <*> whenEq
      (required environmentSetting)
      Production
      (required (secretText "email.credentials" "Email account credentials as JSON"))

builtInDefaultsSource :: Source
builtInDefaultsSource =
  either
    (error . show)
    id
    ( sourceFromPairs
        "built-in defaults"
        BuiltInSource
        [ (validKey target, value)
        | (target, value) <-
            [ ("runtime.environment", RawText "development"),
              ("database.poolSize", RawNumber 10),
              ("server.host", RawText "127.0.0.1"),
              ("server.port", RawNumber 8080),
              ("server.webhookSecret", RawText developmentWebhookSecret),
              ("workers.deliveryEndpoint", RawText "http://127.0.0.1:18091")
            ]
        ]
    )

developmentWebhookSecret :: Text
developmentWebhookSecret = "development-only-change-me"

environmentBindings :: Bindings
environmentBindings =
  either
    (error . Text.unpack . renderEnvErrorsText)
    id
    ( bindings
        [ binding (EnvName variable) (validKey target)
        | (variable, target) <-
            [ ("ENVIRONMENT", "runtime.environment"),
              ("DATABASE_URL", "database.url"),
              ("DATABASE_POOL_SIZE", "database.poolSize"),
              ("HTTP_HOST", "server.host"),
              ("PORT", "server.port"),
              ("WEBHOOK_SECRET", "server.webhookSecret"),
              ("DELIVERY_ENDPOINT", "workers.deliveryEndpoint"),
              ("WORKER_CONCURRENCY", "workers.concurrency"),
              ("WORKER_VISIBILITY_TIMEOUT_SECONDS", "workers.visibilityTimeoutSeconds"),
              ("OTEL_SERVICE_NAME", "telemetry.serviceName"),
              ("EMAIL_CREDENTIALS_JSON", "email.credentials")
            ]
        ]
    )

productionProfile :: DeploymentProfile
productionProfile =
  deploymentProfile
    "production"
    [ (validKey "runtime.environment", "state the deployment's environment explicitly"),
      (validKey "server.webhookSecret", "the development webhook secret must never reach production"),
      (validKey "workers.deliveryEndpoint", "the loopback endpoint is a local development default")
    ]

deploymentContractInputs :: ContractInputs
deploymentContractInputs = ContractInputs (inputBindings environmentBindings) [builtInDefaultsSource] (Just productionProfile)

deploymentParserInfo :: Role -> ParserInfo DeploymentOptions
deploymentParserInfo role =
  Options.info
    (DeploymentOptions <$> setteiOptions Options.<**> Options.helper)
    (Options.fullDesc <> Options.progDesc ("Validate notification delivery " <> show role <> " configuration") <> Options.failureCode usageExitCode)

-- | Application-owned validation; error strings never contain rejected values.
-- Each domain rule is declared once and shared by the relevant process roles.
serverWebhookSecretLength, workerVisibility, productionWebhookSecret :: Validator DeploymentConfig
serverWebhookSecretLength =
  check
    (InvariantRule "server-webhook-secret-length")
    [validKey "server.webhookSecret"]
    "must be at least 16 characters"
    (\config -> Text.length (config ^. #webhookSecret) >= 16)
workerVisibility =
  check
    (InvariantRule "worker-visibility-covers-concurrency")
    (fmap validKey ["workers.visibilityTimeoutSeconds", "workers.concurrency"])
    "workers.visibilityTimeoutSeconds must be at least twice workers.concurrency"
    (\config -> toInteger (config ^. #visibilityTimeoutSeconds) >= 2 * toInteger (config ^. #concurrency))
productionWebhookSecret =
  check
    (InvariantRule "production-webhook-secret")
    (fmap validKey ["server.webhookSecret", "runtime.environment"])
    "the development webhook secret must never reach production"
    (\config -> config ^. #environment /= Production || config ^. #webhookSecret /= developmentWebhookSecret)

serverValidators, workerValidators :: Validators DeploymentConfig
serverValidators = checkedValidators [serverWebhookSecretLength]
workerValidators = checkedValidators [workerVisibility, productionWebhookSecret]

checkedValidators :: [Validator DeploymentConfig] -> Validators DeploymentConfig
checkedValidators = either (error . Text.unpack . renderValidatorErrorsText) id . validators deploymentConfig

roleValidators :: Role -> Validators DeploymentConfig
roleValidators Server = serverValidators
roleValidators Worker = workerValidators

-- | Static diagnostics precede every file read and resolution.
runDeploymentWithSnapshot :: Role -> EnvSnapshot -> DeploymentOptions -> IO DeploymentRun
runDeploymentWithSnapshot role snapshot = runDeploymentWithStartup (pure ()) role (pure snapshot)

-- | Inject resource acquisition after every diagnostic path has declined.
runDeploymentWithStartup :: IO () -> Role -> IO EnvSnapshot -> DeploymentOptions -> IO DeploymentRun
runDeploymentWithStartup startup role readEnvironment parsed =
  case prepareDiagnostic mode (describe deploymentConfig) (Just (deploymentContract deploymentContractInputs deploymentConfig)) of
    DiagnosticRendered output -> pure (success output "")
    DiagnosticRejected problems -> pure (failure resolutionExitCode problems)
    DiagnosticNeedsRuntime runtimeMode -> do
      snapshot <- readEnvironment
      loaded <- traverse (Yaml.readYamlSource (Yaml.yamlSourceOptions "configuration file")) (options ^. #configPaths)
      case traverse (either (Left . Yaml.renderYamlErrorsText) Right) loaded of
        Left problems -> pure (failure sourceExitCode problems)
        Right files -> do
          let result =
                resolve
                  defaultResolveOptions
                  ([builtInDefaultsSource] <> files <> [environmentSource environmentBindings snapshot] <> cliSources "arguments" (options ^. #overrides))
                  deploymentConfig
              validated = validate (roleValidators role) result
          case validatedDiagnostic runtimeMode validated of
            DiagnosticFailure problems -> pure (failure resolutionExitCode problems)
            DiagnosticOutput output -> pure (success output (renderWarningsText (validated ^. #warnings)))
            DiagnosticContinue _ -> do
              startup
              pure (success ("notification delivery " <> Text.pack (show role) <> " configuration ready\n") (renderWarningsText (validated ^. #warnings)))
  where
    options = parsed ^. #options
    mode = options ^. #diagnosticMode
    success output warnings = DeploymentRun 0 output warnings
    failure code message = DeploymentRun code "" message

-- | The executable's environment reader is deferred until static dispatch finishes.
runDeploymentWithEnvironment :: Role -> IO EnvSnapshot -> DeploymentOptions -> IO DeploymentRun
runDeploymentWithEnvironment = runDeploymentWithStartup (pure ())
