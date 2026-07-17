-- |
-- Module: Settei.Schema
-- Description: Static setting and branch metadata returned by Settei.Config.describe.
--
-- Possible settings occur somewhere in a declaration. Necessary settings are
-- conservatively known to run on every path. Required versus optional is separate: it
-- controls whether absence is an error when a request actually runs.
module Settei.Schema
  ( Condition,
    Presence (..),
    Requirement (..),
    Schema,
    SchemaSetting,
    conditionDependencies,
    conditionSettings,
    schemaConditions,
    schemaNecessary,
    schemaPossible,
    schemaSettingDescription,
    schemaSettingKey,
    schemaSettingPresence,
    schemaSettingRequirement,
    schemaSettingSensitivity,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Settei.Internal.Schema
  ( Condition,
    Presence (..),
    Requirement (..),
    Schema,
    SchemaSetting,
  )
import Settei.Key (Key)
import Settei.Prelude
import Settei.Setting (Sensitivity)

-- | Every setting that may be requested, in key order.
schemaPossible :: Schema -> [SchemaSetting]
schemaPossible schema = Map.elems (schema ^. #settings)

-- | Settings evaluated on every execution path, in key order.
schemaNecessary :: Schema -> [SchemaSetting]
schemaNecessary = filter ((== Necessary) . schemaSettingPresence) . schemaPossible

-- | The conservative selective relationships in declaration order.
schemaConditions :: Schema -> [Condition]
schemaConditions schema = schema ^. #conditions

-- | Return a schema entry's validated key.
schemaSettingKey :: SchemaSetting -> Key
schemaSettingKey schemaEntry = schemaEntry ^. #key

-- | Return a schema entry's human-readable purpose.
schemaSettingDescription :: SchemaSetting -> Text
schemaSettingDescription schemaEntry = schemaEntry ^. #description

-- | Return whether reports must redact a schema entry's value.
schemaSettingSensitivity :: SchemaSetting -> Sensitivity
schemaSettingSensitivity schemaEntry = schemaEntry ^. #sensitivity

-- | Return whether absence is an error when this request runs.
schemaSettingRequirement :: SchemaSetting -> Requirement
schemaSettingRequirement schemaEntry = schemaEntry ^. #requirement

-- | Return whether this request is statically necessary or conditional.
schemaSettingPresence :: SchemaSetting -> Presence
schemaSettingPresence schemaEntry = schemaEntry ^. #presence

-- | Return the selector keys on which a condition depends.
conditionDependencies :: Condition -> Set Key
conditionDependencies condition = condition ^. #dependencies

-- | Return the setting keys activated by a condition.
conditionSettings :: Condition -> Set Key
conditionSettings condition = condition ^. #settings
