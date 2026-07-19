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

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Options.Applicative (Parser, ParserInfo)
import Options.Applicative qualified as Options
import Settei
import Settei.Env
import Settei.Formats
import Settei.Formats.Optparse
import Settei.Optparse
import Settei.Prelude
import Text.Printf (printf)

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
    <$> Options.parserOptionGroup "Configuration" configInputOptions
    <*> Options.parserOptionGroup "Configuration" overrideOptions
    <*> Options.parserOptionGroup "Diagnostics" diagnosticModeOptions

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
  case schemaDiagnostic (options ^. #diagnosticMode) (describe cliConfig) of
    Just output -> pure (successfulRun output "")
    Nothing -> do
      resolved <- resolveCliOptions snapshot options
      pure $ case resolved of
        Left (InputFailure message) -> failedRun sourceExitCode message
        Right result -> case result ^. #answer of
          Left problems ->
            failedRun
              resolutionExitCode
              (renderErrorsText problems <> failureReport options result)
          Right config ->
            successfulRun
              (maybe (renderSuccess config) id (resolutionDiagnostic (options ^. #diagnosticMode) result))
              (renderWarningsText (result ^. #warnings))

-- | Resolve ordered built-ins, files, environment, and command-line sources.
resolveCliOptions :: EnvSnapshot -> CliOptions -> IO (Either CliFailure (ResolveResult CliConfig))
resolveCliOptions snapshot options = do
  loaded <- traverse (loadConfigInput defaultLoadOptions) (options ^. #configInputs)
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

firstInputFailure :: [Either (NonEmpty FormatLoadError) Source] -> Either CliFailure [Source]
firstInputFailure = traverse (either (Left . InputFailure . renderFormatLoadErrorsText) Right)

renderFormatLoadErrorsText :: NonEmpty FormatLoadError -> Text
renderFormatLoadErrorsText = Text.concat . fmap renderFormatLoadErrorText . NonEmpty.toList

-- | Append provenance to a resolution failure only in an explicit explain mode.
failureReport :: CliOptions -> ResolveResult CliConfig -> Text
failureReport options result =
  case options ^. #diagnosticMode of
    ExplainText -> renderResolutionText (result ^. #report)
    ExplainJson -> renderResolutionJson (result ^. #report) <> "\n"
    _ -> ""

renderSuccess :: CliConfig -> Text
renderSuccess config =
  Text.unlines
    [ "settei example action",
      "endpoint: " <> config ^. #endpoint,
      "timeout: " <> renderInt (config ^. #timeout),
      "output: " <> renderOutputFormat (config ^. #outputFormat)
    ]

successfulRun :: Text -> Text -> CliRun
successfulRun output warnings = CliRun {exitCode = 0, standardOutput = output, standardError = warnings}

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
  publicShowSetting serviceTimeoutKey "Request timeout in seconds" boundedIntegralDecoder

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

renderInt :: Int -> Text
renderInt value = Text.pack (printf "%d" value)

runtimeEnvironmentKey, serviceEndpointKey, serviceTimeoutKey, outputFormatKey, serviceTokenKey :: Key
runtimeEnvironmentKey = validKey "runtime.environment"
serviceEndpointKey = validKey "service.endpoint"
serviceTimeoutKey = validKey "service.timeout"
outputFormatKey = validKey "output.format"
serviceTokenKey = validKey "credentials.token"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
