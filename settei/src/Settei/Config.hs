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
--   whenEq (required environmentSetting) "production" (required passwordSetting)
-- @
--
-- Inspection needs no environment variables or files:
--
-- @
-- fmap (renderKey . schemaSettingKey) (schemaNecessary (describe productionPassword))
-- -- ["runtime.environment"]
-- @
--
-- For arbitrary selective branch shapes, use 'Control.Selective.select' directly; the
-- production-only declaration above desugars to:
--
-- @
-- select
--   ((\environment -> if environment == "production" then Left () else Right Nothing)
--     '<$>' required environmentSetting)
--   ((\password _ -> Just password) '<$>' required passwordSetting)
-- @
--
-- 'Config' intentionally has no 'Monad' instance. Monadic binding could construct new
-- keys from resolved values and would make complete static inspection impossible.
module Settei.Config
  ( Config,
    describe,
    fallbackTo,
    optional,
    required,
    whenConfig,
    whenEq,
    withDefault,
  )
where

import Control.Selective (select)
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

-- | Evaluate a declaration only when a condition is 'True'.
--
-- Desugars to 'Control.Selective.select'; no new syntax is introduced. Schema
-- footprint: every setting inside the condition keeps its presence (a 'required'
-- condition setting stays necessary); every setting inside the branch becomes
-- conditional; one 'Settei.Schema.Condition' row is recorded whose dependencies are the
-- condition's possible keys and whose activated settings are the branch's possible keys.
-- At resolution time a 'False' condition reports the branch's settings as not selected
-- rather than missing.
whenConfig :: Config Bool -> Config a -> Config (Maybe a)
whenConfig condition branch =
  select
    ((\flag -> if flag then Left () else Right Nothing) <$> condition)
    ((\value () -> Just value) <$> branch)

-- | Evaluate a declaration only when a scrutinee equals an expected value.
--
-- @'whenEq' (required environmentSetting) Production (required passwordSetting)@
-- requires the password only when the resolved environment is @Production@. Schema
-- footprint is identical to 'whenConfig': scrutinee settings keep their presence,
-- branch settings become conditional, and one 'Settei.Schema.Condition' row links them.
whenEq :: (Eq d) => Config d -> d -> Config a -> Config (Maybe a)
whenEq scrutinee expected = whenConfig ((== expected) <$> scrutinee)

-- | Use the first declaration's value when present; otherwise evaluate the fallback.
--
-- This is the key-migration idiom:
-- @optional newSetting `fallbackTo` required oldSetting@ reads a renamed key and
-- consults the old key only when no source supplies the new one.
--
-- Desugars to 'Control.Selective.select'. Schema footprint: the primary declaration's
-- settings keep their presence; the fallback's settings become conditional; one
-- 'Settei.Schema.Condition' row records the primary's possible keys as dependencies and
-- the fallback's possible keys as activated settings. The alias is declaration-level,
-- not per-source: a value for the primary key in any source, however low its precedence,
-- suppresses the fallback entirely.
fallbackTo :: Config (Maybe a) -> Config a -> Config a
fallbackTo primary fallback =
  select
    (maybe (Left ()) Right <$> primary)
    (const <$> fallback)

-- | Request a setting, evaluating its named fallback only when no source supplies it.
withDefault :: Setting a -> Default a -> Config a
withDefault = withDefaultConfig

-- | Inspect every possible request without reading configuration sources.
describe :: Config a -> Schema
describe = describeConfig
