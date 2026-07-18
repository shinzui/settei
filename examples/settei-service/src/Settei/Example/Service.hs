-- |
-- Module: Settei.Example.Service
-- Description: Kubernetes-shaped service configuration composed from public Settei APIs.
module Settei.Example.Service
  ( DatabaseConfig,
    HttpConfig,
    RuntimeEnvironment (..),
    SecretText,
    ServiceConfig,
    ServiceDiagnosticMode (..),
    ServiceFileFormat (..),
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

import Control.Applicative qualified as Applicative
import Control.Selective (select)
import Data.Generics.Labels ()
import Data.Text qualified as Text
import Options.Applicative (Parser, ParserInfo)
import Options.Applicative qualified as Options
import Settei
import Settei.Dhall qualified as Dhall
import Settei.Env
import Settei.Kdl qualified as Kdl
import Settei.Prelude
import Settei.Yaml qualified as Yaml

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

-- | Explicit adapter tag accepted for a mounted file.
data ServiceFileFormat = ServiceYaml | ServiceKdl | ServiceDhall
  deriving stock (Generic, Eq, Ord, Show)

data ServiceInput = ServiceInput
  { format :: !ServiceFileFormat,
    path :: !FilePath
  }
  deriving stock (Generic, Eq, Show)

-- | Normal startup or one validation/explanation action.
data ServiceDiagnosticMode
  = StartService
  | CheckServiceConfiguration
  | ExplainServiceConfigurationText
  | ExplainServiceConfigurationJson
  deriving stock (Generic, Eq, Ord, Show)

-- | Parsed command line before the mounted file is loaded.
data ServiceOptions = ServiceOptions
  { configInput :: !(Maybe ServiceInput),
    diagnosticMode :: !ServiceDiagnosticMode
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
    <*> Options.parserOptionGroup "Diagnostics" diagnosticModeParser

configInputParser :: Parser (Maybe ServiceInput)
configInputParser =
  Applicative.optional
    ( Options.option
        serviceInputReader
        ( Options.long "config"
            <> Options.metavar "FORMAT:PATH"
            <> Options.help "Load one mounted yaml:PATH, kdl:PATH, or dhall:PATH"
        )
    )

diagnosticModeParser :: Parser ServiceDiagnosticMode
diagnosticModeParser =
  Options.flag' CheckServiceConfiguration (Options.long "check-config" <> Options.help "Validate configuration and exit")
    Applicative.<|> Options.flag' ExplainServiceConfigurationText (Options.long "explain-config" <> Options.help "Print a redacted text explanation")
    Applicative.<|> Options.flag' ExplainServiceConfigurationJson (Options.long "explain-config-json" <> Options.help "Print a redacted JSON explanation")
    Applicative.<|> pure StartService

serviceInputReader :: Options.ReadM ServiceInput
serviceInputReader = Options.eitherReader $ \input ->
  let (formatName, separatorAndPath) = break (== ':') input
      filePath = drop 1 separatorAndPath
   in if null separatorAndPath || null filePath
        then Left "expected FORMAT:PATH"
        else case formatName of
          "yaml" -> Right (ServiceInput ServiceYaml filePath)
          "kdl" -> Right (ServiceInput ServiceKdl filePath)
          "dhall" -> Right (ServiceInput ServiceDhall filePath)
          _ -> Left "FORMAT must be yaml, kdl, or dhall"

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
productionPassword = select selector branch
  where
    selector =
      (\environment -> if environment == Production then Left () else Right Nothing)
        <$> required environmentSetting
    branch = (\password _ -> Just password) <$> required databasePasswordSetting

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
environmentBindings :: [EnvBinding]
environmentBindings =
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

-- | Load, resolve, and render one capturable run against an injected snapshot.
runServiceWithSnapshot :: EnvSnapshot -> ServiceOptions -> IO ServiceRun
runServiceWithSnapshot snapshot options = do
  resolved <- resolveServiceOptions snapshot options
  pure $ case resolved of
    Left (InputFailure message) -> failedRun sourceExitCode message
    Left (ResolveFailure problems) -> failedRun resolutionExitCode (renderErrorsText problems)
    Right result -> successfulRun (renderServiceSuccess options result)

-- | Resolve the parsed mounted-file option followed by the environment source.
resolveServiceOptions :: EnvSnapshot -> ServiceOptions -> IO (Either ServiceFailure (ResolveResult ServiceConfig))
resolveServiceOptions snapshot options = do
  loaded <- traverse loadServiceInput (options ^. #configInput)
  pure $ do
    fileSources <- case loaded of
      Nothing -> Right []
      Just (Left message) -> Left (InputFailure message)
      Just (Right value) -> Right [value]
    case resolveServiceSources fileSources snapshot of
      Left problems -> Left (ResolveFailure problems)
      Right value -> Right value

-- | Resolve already loaded file sources followed by an injected environment snapshot.
resolveServiceSources :: [Source] -> EnvSnapshot -> Either (NonEmpty ConfigError) (ResolveResult ServiceConfig)
resolveServiceSources fileSources snapshot = do
  environmentSource <-
    case envSource "environment" environmentBindings snapshot of
      Left problems -> error (show problems)
      Right value -> Right value
  resolve defaultResolveOptions (fileSources <> [environmentSource]) serviceConfig

data ServiceFailure
  = InputFailure !Text
  | ResolveFailure !(NonEmpty ConfigError)

loadServiceInput :: ServiceInput -> IO (Either Text Source)
loadServiceInput input =
  let sourceLabel = Text.pack (input ^. #path)
      mountedReference = kubernetesRef ConfigMapObject Nothing "settei-example-service" (Just "application.yaml")
   in case input ^. #format of
        ServiceYaml ->
          fmap
            (either (Left . Text.pack . show) Right)
            ( Yaml.readYamlSource
                (Yaml.fromKubernetesMountedFile mountedReference (Yaml.yamlSourceOptions sourceLabel))
                (input ^. #path)
            )
        ServiceKdl ->
          fmap
            (either (Left . Text.pack . show) Right)
            ( Kdl.readKdlSource
                (Kdl.fromKubernetesMountedFile mountedReference (Kdl.kdlSourceOptions sourceLabel))
                (input ^. #path)
            )
        ServiceDhall ->
          fmap
            (either (Left . Text.pack . show) Right)
            ( Dhall.loadDhallSource
                ( Dhall.annotateDhallSourceOptions
                    (kubernetesAnnotations mountedReference)
                    (Dhall.dhallSourceOptions sourceLabel Dhall.NoImports)
                )
                (Dhall.DhallFile (input ^. #path))
            )

-- | Render only allowlisted non-secret startup fields.
safeStartupSummary :: ServiceConfig -> Text
safeStartupSummary config =
  Text.unlines
    [ "settei example service ready",
      "environment: " <> renderEnvironment (config ^. #environment),
      "http: " <> config ^. #http . #host <> ":" <> Text.pack (show (config ^. #http . #port)),
      "database: " <> config ^. #database . #host <> ":" <> Text.pack (show (config ^. #database . #port)),
      "database pool size: " <> Text.pack (show (config ^. #database . #poolSize))
    ]

renderServiceSuccess :: ServiceOptions -> ResolveResult ServiceConfig -> Text
renderServiceSuccess options result =
  case options ^. #diagnosticMode of
    CheckServiceConfiguration -> "configuration valid\n"
    ExplainServiceConfigurationText -> renderResolutionText (result ^. #report)
    ExplainServiceConfigurationJson -> renderResolutionJson (result ^. #report) <> "\n"
    StartService -> safeStartupSummary (result ^. #value)

successfulRun :: Text -> ServiceRun
successfulRun output = ServiceRun {exitCode = 0, standardOutput = output, standardError = ""}

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
httpPortSetting = publicInteger httpPortKey "HTTP bind port"

databaseHostSetting :: Setting Text
databaseHostSetting = publicSetting databaseHostKey "Database host" textDecoder

databasePortSetting :: Setting Int
databasePortSetting = publicInteger databasePortKey "Database port"

databasePoolSizeSetting :: Setting Int
databasePoolSizeSetting = publicInteger databasePoolSizeKey "Database pool size"

databasePasswordSetting :: Setting SecretText
databasePasswordSetting = secretSetting databasePasswordKey "Database password" secretTextDecoder

serviceTagsSetting :: Setting [Text]
serviceTagsSetting = publicSetting serviceTagsKey "Conformance service tags" textListDecoder

publicInteger :: Key -> Text -> Setting Int
publicInteger key description =
  publicSettingWithRenderer key description boundedIntegralDecoder (Text.pack . show)

secretTextDecoder :: Decoder SecretText
secretTextDecoder = decoder $ \key -> \case
  RawText value -> Right (SecretText value)
  _ -> Left (decodeFailure key "text")

textListDecoder :: Decoder [Text]
textListDecoder = decoder $ \key -> \case
  RawArray values -> traverse (textElement key) values
  _ -> Left (decodeFailure key "an array of text")

textElement :: Key -> RawValue -> Either DecodeFailure Text
textElement key = \case
  RawText value -> Right value
  _ -> Left (decodeFailure key "an array of text")

renderEnvironment :: RuntimeEnvironment -> Text
renderEnvironment Development = "development"
renderEnvironment Test = "test"
renderEnvironment Production = "production"

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
