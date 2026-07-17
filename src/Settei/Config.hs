-- |
-- Module: Settei.Config
-- Description: Compose and inspect typed configuration declarations.
--
-- A 'Config' describes configuration effects without reading a source. Independent
-- settings compose with 'Applicative'; runtime-dependent effects compose with
-- "Control.Selective". The latter preserves a static over-approximation while allowing
-- an interpreter to skip an unused branch.
--
-- For example, a caller can declare a production-only password (assuming
-- @environmentSetting :: Setting Text@ and @passwordSetting :: Setting Text@):
--
-- @
-- productionPassword :: Config (Maybe Text)
-- productionPassword =
--   select
--     ((\environment -> if environment == "production" then Left () else Right Nothing)
--       '<$>' required environmentSetting)
--     ((\password _ -> Just password) '<$>' required passwordSetting)
-- @
--
-- Inspection needs no environment variables or files:
--
-- @
-- fmap (renderKey . schemaSettingKey) (schemaNecessary (describe productionPassword))
-- -- ["runtime.environment"]
-- @
--
-- 'Config' intentionally has no 'Monad' instance. Monadic binding could construct new
-- keys from resolved values and would make complete static inspection impossible.
module Settei.Config
  ( Config,
    describe,
    optional,
    required,
    withDefault,
  )
where

import Settei.Default (Default)
import Settei.Internal.Config
  ( Config,
    describeConfig,
    optionalConfig,
    requiredConfig,
    withDefaultConfig,
  )
import Settei.Schema (Schema)
import Settei.Setting (Setting)

-- | Require one setting when this declaration path is evaluated.
required :: Setting a -> Config a
required = requiredConfig

-- | Request a setting without failing when no source supplies it.
optional :: Setting a -> Config (Maybe a)
optional = optionalConfig

-- | Request a setting, evaluating its named fallback only when no source supplies it.
withDefault :: Setting a -> Default a -> Config a
withDefault = withDefaultConfig

-- | Inspect every possible request without reading configuration sources.
describe :: Config a -> Schema
describe = describeConfig
