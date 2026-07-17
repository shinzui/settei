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

schemaSettingKey :: SchemaSetting -> Key
schemaSettingKey schemaEntry = schemaEntry ^. #key

schemaSettingDescription :: SchemaSetting -> Text
schemaSettingDescription schemaEntry = schemaEntry ^. #description

schemaSettingSensitivity :: SchemaSetting -> Sensitivity
schemaSettingSensitivity schemaEntry = schemaEntry ^. #sensitivity

schemaSettingRequirement :: SchemaSetting -> Requirement
schemaSettingRequirement schemaEntry = schemaEntry ^. #requirement

schemaSettingPresence :: SchemaSetting -> Presence
schemaSettingPresence schemaEntry = schemaEntry ^. #presence

conditionDependencies :: Condition -> Set Key
conditionDependencies condition = condition ^. #dependencies

conditionSettings :: Condition -> Set Key
conditionSettings condition = condition ^. #settings
