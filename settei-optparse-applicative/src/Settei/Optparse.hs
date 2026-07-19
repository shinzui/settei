-- |
-- Module: Settei.Optparse
-- Description: optparse-applicative parsers that produce ordered Settei sources.
module Settei.Optparse
  ( CliOverride,
    DiagnosticMode (..),
    SetteiOptions (..),
    cliOverride,
    cliOverrideKey,
    cliOverrideSpelling,
    cliOverrideValue,
    cliSources,
    configPathOptions,
    configPathOptionsWith,
    diagnosticModeOptions,
    namedOption,
    overrideOptions,
    overrideOptionsWith,
    resolutionDiagnostic,
    schemaDiagnostic,
    setteiOptions,
  )
where

import Control.Applicative qualified as Applicative
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Options.Applicative (Mod, OptionFields, Parser)
import Options.Applicative qualified as Options
import Settei
import Settei.Prelude

-- | One parsed @--set KEY=VALUE@ override.
--
-- The constructor stays private because 'spelling' is safe origin text and must never
-- contain the raw value of a potentially secret setting.
data CliOverride = CliOverride
  { key :: !Key,
    value :: !RawValue,
    spelling :: !Text
  }
  deriving stock (Generic, Eq)

-- | Which configuration diagnostic, if any, an application should perform.
data DiagnosticMode
  = NoDiagnostic
  | ExplainText
  | ExplainJson
  | CheckConfig
  | DescribeConfigText
  | DescribeConfigJson
  deriving stock (Generic, Eq, Ord, Show)

-- | Reusable configuration and diagnostic command-line options.
data SetteiOptions = SetteiOptions
  { configPaths :: ![FilePath],
    overrides :: ![CliOverride],
    diagnosticMode :: !DiagnosticMode
  }
  deriving stock (Generic, Eq)

data ConfigurationOptions = ConfigurationOptions
  { configPaths :: ![FilePath],
    overrides :: ![CliOverride]
  }
  deriving stock (Generic, Eq)

newtype DiagnosticOptions = DiagnosticOptions
  { diagnosticMode :: DiagnosticMode
  }
  deriving stock (Generic, Eq)

-- | Construct an override programmatically while keeping its origin spelling secret-safe.
cliOverride :: Key -> Text -> CliOverride
cliOverride key value =
  CliOverride
    { key,
      value = RawText value,
      spelling = "--set " <> renderKey key
    }

-- | Return the target key.
cliOverrideKey :: CliOverride -> Key
cliOverrideKey value = value ^. #key

-- | Return the raw text value for core decoding.
cliOverrideValue :: CliOverride -> RawValue
cliOverrideValue value = value ^. #value

-- | Return a safe spelling that names the option and key but omits its value.
cliOverrideSpelling :: CliOverride -> Text
cliOverrideSpelling value = value ^. #spelling

-- | Parse zero or more generic @--set KEY=VALUE@ overrides.
overrideOptions :: Parser [CliOverride]
overrideOptions =
  overrideOptionsWith
    ( Options.long "set"
        <> Options.metavar "KEY=VALUE"
        <> Options.help "Override one configuration key"
    )

-- | Parse generic overrides using caller-supplied option metadata.
overrideOptionsWith :: Mod OptionFields CliOverride -> Parser [CliOverride]
overrideOptionsWith modifiers = Applicative.many (Options.option overrideReader modifiers)

-- | Convert parsed overrides to low-to-high source fragments.
--
-- Each fragment has its own occurrence annotation, so repeated keys retain their full
-- shadow trace and the final list item wins under normal core resolution.
cliSources :: Text -> [CliOverride] -> [Source]
cliSources sourceLabel overrides =
  zipWith (sourceForOverride sourceLabel) [1 :: Int ..] overrides

-- | Parse one optional named flag as a source fragment.
--
-- The supplied spelling should be safe display text such as @--port@. The caller controls
-- the target key and all optparse-applicative metadata.
namedOption :: Text -> Key -> Mod OptionFields Text -> Parser (Maybe Source)
namedOption spelling key modifiers =
  fmap (namedSource spelling key) <$> Applicative.optional (Options.strOption modifiers)

-- | Parse zero or more @--config PATH@ occurrences without opening any file.
configPathOptions :: Parser [FilePath]
configPathOptions =
  configPathOptionsWith
    ( Options.long "config"
        <> Options.metavar "PATH"
        <> Options.help "Read configuration from PATH"
    )

-- | Parse config paths using caller-supplied option metadata.
configPathOptionsWith :: Mod OptionFields FilePath -> Parser [FilePath]
configPathOptionsWith modifiers = Applicative.many (Options.strOption modifiers)

-- | Parse the default mutually exclusive configuration diagnostic flags.
diagnosticModeOptions :: Parser DiagnosticMode
diagnosticModeOptions =
  Options.flag' ExplainText (Options.long "explain-config" <> Options.help "Explain the resolved configuration as text")
    Applicative.<|> Options.flag' ExplainJson (Options.long "explain-config-json" <> Options.help "Explain the resolved configuration as JSON")
    Applicative.<|> Options.flag' CheckConfig (Options.long "check-config" <> Options.help "Validate configuration and exit")
    Applicative.<|> Options.flag' DescribeConfigText (Options.long "describe-config" <> Options.help "Print the static configuration schema")
    Applicative.<|> Options.flag' DescribeConfigJson (Options.long "describe-config-json" <> Options.help "Print the static configuration schema as JSON")
    Applicative.<|> pure NoDiagnostic

-- | Render a diagnostic that must not load configuration sources.
schemaDiagnostic :: DiagnosticMode -> Schema -> Maybe Text
schemaDiagnostic mode schema = case mode of
  DescribeConfigText -> Just (renderSchemaText schema)
  DescribeConfigJson -> Just (renderSchemaJson schema <> "\n")
  _ -> Nothing

-- | Render a diagnostic available after resolution.
resolutionDiagnostic :: DiagnosticMode -> ResolveResult a -> Maybe Text
resolutionDiagnostic mode result = case mode of
  ExplainText -> Just (renderResolutionText (result ^. #report))
  ExplainJson -> Just (renderResolutionJson (result ^. #report) <> "\n")
  CheckConfig -> Just "configuration valid\n"
  _ -> Nothing

-- | Parse the reusable Configuration and Diagnostics option groups.
setteiOptions :: Parser SetteiOptions
setteiOptions = assemble <$> configurationOptions <*> diagnosticOptions
  where
    assemble configuration diagnostics =
      SetteiOptions
        { configPaths = configuration ^. #configPaths,
          overrides = configuration ^. #overrides,
          diagnosticMode = diagnostics ^. #diagnosticMode
        }

configurationOptions :: Parser ConfigurationOptions
configurationOptions =
  Options.parserOptionGroup
    "Configuration"
    (ConfigurationOptions <$> configPathOptions <*> overrideOptions)

diagnosticOptions :: Parser DiagnosticOptions
diagnosticOptions =
  Options.parserOptionGroup
    "Diagnostics"
    (DiagnosticOptions <$> diagnosticModeOptions)

overrideReader :: Options.ReadM CliOverride
overrideReader = Options.eitherReader $ \input ->
  let rendered = Text.pack input
      (keyText, assignment) = Text.breakOn "=" rendered
   in if Text.null assignment
        then Left "expected KEY=VALUE"
        else case parseKey keyText of
          Left keyError -> Left ("invalid configuration key: " <> show keyError)
          Right key -> Right (cliOverride key (Text.drop 1 assignment))

sourceForOverride :: Text -> Int -> CliOverride -> Source
sourceForOverride sourceLabel occurrence override =
  annotateSource
    ( Map.fromList
        [ ("command-line.option", "--set"),
          ("command-line.occurrence", Text.pack (show occurrence)),
          ("command-line.spelling", override ^. #spelling)
        ]
    )
    ( source
        (sourceLabel <> " --set #" <> Text.pack (show occurrence))
        CommandLineSource
        (rawValueAt (override ^. #key) (override ^. #value))
    )

namedSource :: Text -> Key -> Text -> Source
namedSource spelling key value =
  annotateSource
    ( Map.fromList
        [ ("command-line.option", spelling),
          ("command-line.spelling", spelling)
        ]
    )
    (source spelling CommandLineSource (rawValueAt key (RawText value)))

rawValueAt :: Key -> RawValue -> RawValue
rawValueAt key value =
  foldr
    (\segment child -> RawObject (Map.singleton segment child))
    value
    (NonEmpty.toList (keySegments key))
