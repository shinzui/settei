-- |
-- Module: Settei.Optparse
-- Description: optparse-applicative parsers that produce ordered Settei sources.
module Settei.Optparse
  ( CliOverride,
    ExplainMode (..),
    SetteiOptions (..),
    cliOverride,
    cliOverrideKey,
    cliOverrideSpelling,
    cliOverrideValue,
    cliSources,
    configPathOptions,
    configPathOptionsWith,
    explainModeOptions,
    explainModeOptionsWith,
    namedOption,
    overrideOptions,
    overrideOptionsWith,
    setteiOptions,
  )
where

import Control.Applicative qualified as Applicative
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Options.Applicative (FlagFields, Mod, OptionFields, Parser)
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

-- | Whether an application should print a configuration explanation.
data ExplainMode = NoExplain | ExplainText | ExplainJson
  deriving stock (Generic, Eq, Ord, Show)

-- | Reusable configuration and diagnostic command-line options.
data SetteiOptions = SetteiOptions
  { configPaths :: ![FilePath],
    overrides :: ![CliOverride],
    explainMode :: !ExplainMode
  }
  deriving stock (Generic, Eq)

data ConfigurationOptions = ConfigurationOptions
  { configPaths :: ![FilePath],
    overrides :: ![CliOverride]
  }
  deriving stock (Generic, Eq)

newtype DiagnosticOptions = DiagnosticOptions
  { explainMode :: ExplainMode
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

-- | Parse the default mutually exclusive explanation flags.
explainModeOptions :: Parser ExplainMode
explainModeOptions =
  explainModeOptionsWith
    (Options.long "explain-config" <> Options.help "Explain the resolved configuration as text")
    (Options.long "explain-config-json" <> Options.help "Explain the resolved configuration as JSON")

-- | Parse caller-named mutually exclusive text and JSON explanation flags.
explainModeOptionsWith :: Mod FlagFields ExplainMode -> Mod FlagFields ExplainMode -> Parser ExplainMode
explainModeOptionsWith textModifiers jsonModifiers =
  Options.flag' ExplainText textModifiers
    Applicative.<|> Options.flag' ExplainJson jsonModifiers
    Applicative.<|> pure NoExplain

-- | Parse the reusable Configuration and Diagnostics option groups.
setteiOptions :: Parser SetteiOptions
setteiOptions = assemble <$> configurationOptions <*> diagnosticOptions
  where
    assemble configuration diagnostics =
      SetteiOptions
        { configPaths = configuration ^. #configPaths,
          overrides = configuration ^. #overrides,
          explainMode = diagnostics ^. #explainMode
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
    (DiagnosticOptions <$> explainModeOptions)

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
