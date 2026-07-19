{-# LANGUAGE ImportQualifiedPost #-}

-- |
-- Module: Settei.Formats.Optparse
-- Description: Reusable @--config FORMAT:PATH@ options for tagged multi-format inputs.
module Settei.Formats.Optparse
  ( configInputOption,
    configInputOptions,
    configInputReader,
  )
where

import Control.Applicative qualified as Applicative
import Options.Applicative (Mod, OptionFields, Parser)
import Options.Applicative qualified as Options
import Settei.Formats

-- | 'Options.ReadM' for the @FORMAT:PATH@ grammar of 'parseConfigInput'.
configInputReader :: Options.ReadM ConfigInput
configInputReader = Options.eitherReader parseConfigInput

-- | Parse zero or more tagged inputs using caller-supplied option metadata.
configInputOption :: Mod OptionFields ConfigInput -> Parser [ConfigInput]
configInputOption modifiers =
  Applicative.many (Options.option configInputReader modifiers)

-- | Parse zero or more default @--config FORMAT:PATH@ occurrences.
configInputOptions :: Parser [ConfigInput]
configInputOptions =
  configInputOption
    ( Options.long "config"
        <> Options.metavar "FORMAT:PATH"
        <> Options.help "Load yaml:PATH, kdl:PATH, or dhall:PATH in occurrence order"
    )
