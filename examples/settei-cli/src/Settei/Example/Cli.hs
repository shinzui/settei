-- |
-- Module: Settei.Example.Cli
-- Description: Public-API composition for a layered Settei command-line application.
module Settei.Example.Cli
  ( CliConfig,
    CliOptions,
    CliRun,
    ConfigFormat (..),
    ConfigInput,
    DiagnosticMode (..),
    OutputFormat (..),
    RuntimeEnvironment (..),
    cliConfig,
    cliExitCode,
    cliOptionsParser,
    cliParserInfo,
    cliStandardError,
    cliStandardOutput,
    configInputFormat,
    configInputPath,
    environmentBindings,
    resolveCliOptions,
    runCliWithSnapshot,
    sourceExitCode,
    usageExitCode,
    resolutionExitCode,
  )
where

import Control.Applicative qualified as Applicative
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Options.Applicative (Parser, ParserInfo)
import Options.Applicative qualified as Options
import Settei
import Settei.Dhall qualified as Dhall
import Settei.Env
import Settei.Kdl qualified as Kdl
import Settei.Optparse
import Settei.Prelude
import Settei.Yaml qualified as Yaml

-- | Deployment environment accepted by the example declaration.
data RuntimeEnvironment = Development | Test | Production
  deriving stock (Generic, Eq, Ord, Show)

-- | Output mode selected by configuration rather than diagnostic flags.
data OutputFormat = TextOutput | JsonOutput
  deriving stock (Generic, Eq, Ord, Show)

newtype SecretText = SecretText Text
  deriving stock (Generic, Eq)

-- | Fully resolved application configuration; the secret-bearing constructor stays private.
data CliConfig = CliConfig
  { environment :: !RuntimeEnvironment,
    endpoint :: !Text,
    timeout :: !Int,
    outputFormat :: !OutputFormat,
    token :: !(Maybe SecretText)
  }
  deriving stock (Generic, Eq)

-- | Explicit format tag required for each input file.
data ConfigFormat = YamlFormat | KdlFormat | DhallFormat
  deriving stock (Generic, Eq, Ord, Show)

-- | One ordered, explicitly tagged configuration file.
data ConfigInput = ConfigInput
  { format :: !ConfigFormat,
    path :: !FilePath
  }
  deriving stock (Generic, Eq, Show)

-- | Source-free schema inspection or one post-resolution action.
data DiagnosticMode
  = RunExample
  | DescribeConfiguration
  | ExplainConfigurationText
  | ExplainConfigurationJson
  | CheckConfiguration
  deriving stock (Generic, Eq, Ord, Show)

-- | Parsed command line before sources are loaded.
data CliOptions = CliOptions
  { configInputs :: ![ConfigInput],
    overrides :: ![CliOverride],
    diagnosticMode :: !DiagnosticMode
  }
  deriving stock (Generic, Eq)

-- | Capturable process result used by the executable and end-to-end tests.
data CliRun = CliRun
  { exitCode :: !Int,
    standardOutput :: !Text,
    standardError :: !Text
  }
  deriving stock (Generic, Eq, Show)

usageExitCode, sourceExitCode, resolutionExitCode :: Int

-- | Exit code reserved for optparse-applicative usage failures.
usageExitCode = 2

-- | Exit code reserved for file IO or adapter parsing failures.
sourceExitCode = 3

-- | Exit code reserved for typed resolution failures.
resolutionExitCode = 4

-- | Return the process exit code chosen by a completed run.
cliExitCode :: CliRun -> Int
cliExitCode value = value ^. #exitCode

-- | Return captured standard output.
cliStandardOutput :: CliRun -> Text
cliStandardOutput value = value ^. #standardOutput

-- | Return captured standard error.
cliStandardError :: CliRun -> Text
cliStandardError value = value ^. #standardError

-- | Return an input's explicit adapter tag.
configInputFormat :: ConfigInput -> ConfigFormat
configInputFormat value = value ^. #format

-- | Return an input's filesystem path.
configInputPath :: ConfigInput -> FilePath
configInputPath value = value ^. #path

-- | Complete parser metadata, help, and usage-error policy.
cliParserInfo :: ParserInfo CliOptions
cliParserInfo =
  Options.info
    (cliOptionsParser Options.<**> Options.helper)
    ( Options.fullDesc
        <> Options.progDesc "Resolve and explain layered Settei configuration"
        <> Options.failureCode usageExitCode
    )

-- | Parser for ordered files, overrides, and diagnostic intent.
cliOptionsParser :: Parser CliOptions
cliOptionsParser =
  CliOptions
    <$> Options.parserOptionGroup "Configuration" configurationOptions
    <*> Options.parserOptionGroup "Configuration" overrideOptions
    <*> Options.parserOptionGroup "Diagnostics" diagnosticOptions
  where
    configurationOptions =
      Applicative.many
        ( Options.option
            configInputReader
            ( Options.long "config"
                <> Options.metavar "FORMAT:PATH"
                <> Options.help "Load yaml:PATH, kdl:PATH, or dhall:PATH in occurrence order"
            )
        )

diagnosticOptions :: Parser DiagnosticMode
diagnosticOptions =
  Options.flag' DescribeConfiguration (Options.long "describe-config" <> Options.help "Print the static configuration schema")
    Applicative.<|> Options.flag' ExplainConfigurationText (Options.long "explain-config" <> Options.help "Print the resolved configuration explanation")
    Applicative.<|> Options.flag' ExplainConfigurationJson (Options.long "explain-config-json" <> Options.help "Print the versioned JSON explanation")
    Applicative.<|> Options.flag' CheckConfiguration (Options.long "check-config" <> Options.help "Validate configuration without running the example action")
    Applicative.<|> pure RunExample

configInputReader :: Options.ReadM ConfigInput
configInputReader = Options.eitherReader $ \input ->
  let (formatName, separatorAndPath) = break (== ':') input
      filePath = drop 1 separatorAndPath
   in if null separatorAndPath || null filePath
        then Left "expected FORMAT:PATH"
        else case formatName of
          "yaml" -> Right (ConfigInput YamlFormat filePath)
          "kdl" -> Right (ConfigInput KdlFormat filePath)
          "dhall" -> Right (ConfigInput DhallFormat filePath)
          _ -> Left "FORMAT must be yaml, kdl, or dhall"

-- | Inspectable declaration shared by the executable and tests.
cliConfig :: Config CliConfig
cliConfig =
  CliConfig
    <$> required environmentSetting
    <*> required endpointSetting
    <*> required timeoutSetting
    <*> required outputFormatSetting
    <*> optional tokenSetting

-- | Explicit environment-variable bindings used by the example.
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
          binding (EnvName "SERVICE_ENDPOINT") serviceEndpointKey,
          binding (EnvName "SERVICE_TIMEOUT") serviceTimeoutKey,
          binding (EnvName "OUTPUT_FORMAT") outputFormatKey,
          fromKubernetesObject
            (kubernetesRef SecretObject Nothing "settei-example-cli" (Just "token"))
            (binding (EnvName "SERVICE_TOKEN") serviceTokenKey)
        ]
    )

-- | Load, resolve, and render one capturable run against an injected snapshot.
runCliWithSnapshot :: EnvSnapshot -> CliOptions -> IO CliRun
runCliWithSnapshot snapshot options =
  case options ^. #diagnosticMode of
    DescribeConfiguration -> pure (successfulRun (renderSchemaText (describe cliConfig)))
    _ -> do
      resolved <- resolveCliOptions snapshot options
      pure $ case resolved of
        Left (InputFailure message) -> failedRun sourceExitCode message
        Right result -> case result ^. #answer of
          Left problems ->
            failedRun
              resolutionExitCode
              (renderErrorsText problems <> failureReport options result)
          Right config -> successfulRun (renderSuccess options config result)

-- | Resolve ordered built-ins, files, environment, and command-line sources.
resolveCliOptions :: EnvSnapshot -> CliOptions -> IO (Either CliFailure (ResolveResult CliConfig))
resolveCliOptions snapshot options = do
  loaded <- traverse loadConfigInput (options ^. #configInputs)
  pure $ do
    fileSources <- firstInputFailure loaded
    Right
      ( resolve
          defaultResolveOptions
          ( [builtInSource]
              <> fileSources
              <> [environmentSource environmentBindings snapshot]
              <> cliSources "arguments" (options ^. #overrides)
          )
          cliConfig
      )

data CliFailure
  = InputFailure !Text

firstInputFailure :: [Either Text Source] -> Either CliFailure [Source]
firstInputFailure = traverse (either (Left . InputFailure) Right)

loadConfigInput :: ConfigInput -> IO (Either Text Source)
loadConfigInput input =
  let sourceLabel = Text.pack (input ^. #path)
   in case input ^. #format of
        YamlFormat ->
          fmap
            (either (Left . Yaml.renderYamlErrorsText) Right)
            (Yaml.readYamlSource (Yaml.yamlSourceOptions sourceLabel) (input ^. #path))
        KdlFormat ->
          fmap
            (either (Left . Kdl.renderKdlErrorsText) Right)
            (Kdl.readKdlSource (Kdl.kdlSourceOptions sourceLabel) (input ^. #path))
        DhallFormat ->
          fmap
            (either (Left . Dhall.renderDhallErrorsText) Right)
            (Dhall.loadDhallSource (Dhall.dhallSourceOptions sourceLabel Dhall.NoImports) (Dhall.DhallFile (input ^. #path)))

-- | Append provenance to a resolution failure only in an explicit explain mode.
failureReport :: CliOptions -> ResolveResult CliConfig -> Text
failureReport options result =
  case options ^. #diagnosticMode of
    ExplainConfigurationText -> renderResolutionText (result ^. #report)
    ExplainConfigurationJson -> renderResolutionJson (result ^. #report) <> "\n"
    _ -> ""

renderSuccess :: CliOptions -> CliConfig -> ResolveResult CliConfig -> Text
renderSuccess options config result =
  case options ^. #diagnosticMode of
    ExplainConfigurationText -> renderResolutionText (result ^. #report)
    ExplainConfigurationJson -> renderResolutionJson (result ^. #report) <> "\n"
    CheckConfiguration -> "configuration valid\n"
    RunExample ->
      Text.unlines
        [ "settei example action",
          "endpoint: " <> config ^. #endpoint,
          "timeout: " <> Text.pack (show (config ^. #timeout)),
          "output: " <> renderOutputFormat (config ^. #outputFormat)
        ]
    DescribeConfiguration -> renderSchemaText (describe cliConfig)

successfulRun :: Text -> CliRun
successfulRun output = CliRun {exitCode = 0, standardOutput = output, standardError = ""}

failedRun :: Int -> Text -> CliRun
failedRun code message = CliRun {exitCode = code, standardOutput = "", standardError = message}

builtInSource :: Source
builtInSource =
  source
    "CLI built-in defaults"
    BuiltInSource
    ( RawObject
        ( Map.fromList
            [ ("runtime", RawObject (Map.singleton "environment" (RawText "development"))),
              ( "service",
                RawObject
                  ( Map.fromList
                      [ ("endpoint", RawText "https://localhost:8443"),
                        ("timeout", RawNumber 30)
                      ]
                  )
              ),
              ("output", RawObject (Map.singleton "format" (RawText "text")))
            ]
        )
    )

environmentSetting :: Setting RuntimeEnvironment
environmentSetting =
  publicSettingWithRenderer
    runtimeEnvironmentKey
    "Runtime environment"
    (enumDecoder [("development", Development), ("test", Test), ("production", Production)])
    renderRuntimeEnvironment

endpointSetting :: Setting Text
endpointSetting = publicSetting serviceEndpointKey "Service endpoint" textDecoder

timeoutSetting :: Setting Int
timeoutSetting =
  publicSettingWithRenderer serviceTimeoutKey "Request timeout in seconds" boundedIntegralDecoder (Text.pack . show)

outputFormatSetting :: Setting OutputFormat
outputFormatSetting =
  publicSettingWithRenderer
    outputFormatKey
    "Output format"
    (enumDecoder [("text", TextOutput), ("json", JsonOutput)])
    renderOutputFormat

tokenSetting :: Setting SecretText
tokenSetting =
  secretSetting serviceTokenKey "Service authentication token" (SecretText <$> textDecoder)

renderRuntimeEnvironment :: RuntimeEnvironment -> Text
renderRuntimeEnvironment Development = "development"
renderRuntimeEnvironment Test = "test"
renderRuntimeEnvironment Production = "production"

renderOutputFormat :: OutputFormat -> Text
renderOutputFormat TextOutput = "text"
renderOutputFormat JsonOutput = "json"

runtimeEnvironmentKey, serviceEndpointKey, serviceTimeoutKey, outputFormatKey, serviceTokenKey :: Key
runtimeEnvironmentKey = validKey "runtime.environment"
serviceEndpointKey = validKey "service.endpoint"
serviceTimeoutKey = validKey "service.timeout"
outputFormatKey = validKey "output.format"
serviceTokenKey = validKey "credentials.token"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
