module Settei.Internal.Schema
  ( Condition (..),
    Presence (..),
    Requirement (..),
    Schema (..),
    SchemaSetting (..),
    combineSchema,
    conditionalSchema,
    emptySchema,
    requestSchema,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Settei.Key (Key)
import Settei.Prelude
import Settei.Setting
  ( Sensitivity,
    Setting,
    settingDescription,
    settingKey,
    settingSensitivity,
  )

-- | Whether absence of a candidate is an error at runtime.
data Requirement = Required | Optional
  deriving stock (Generic, Eq, Ord, Show)

-- | Whether a declaration is evaluated on every execution path.
data Presence = Necessary | Conditional
  deriving stock (Generic, Eq, Ord, Show)

-- | Static metadata for one possible setting request.
data SchemaSetting = SchemaSetting
  { key :: !Key,
    description :: !Text,
    sensitivity :: !Sensitivity,
    requirement :: !Requirement,
    presence :: !Presence
  }
  deriving stock (Generic, Eq, Show)

-- | A conservative relationship introduced by a selective branch.
data Condition = Condition
  { dependencies :: !(Set Key),
    settings :: !(Set Key)
  }
  deriving stock (Generic, Eq, Show)

-- | The complete static over-approximation of a configuration declaration.
data Schema = Schema
  { settings :: !(Map Key SchemaSetting),
    conditions :: ![Condition]
  }
  deriving stock (Generic, Eq, Show)

emptySchema :: Schema
emptySchema = Schema {settings = Map.empty, conditions = []}

requestSchema :: Requirement -> Setting a -> Schema
requestSchema requirement settingSpec =
  Schema
    { settings = Map.singleton key entry,
      conditions = []
    }
  where
    key = settingKey settingSpec
    entry =
      SchemaSetting
        { key,
          description = settingDescription settingSpec,
          sensitivity = settingSensitivity settingSpec,
          requirement,
          presence = Necessary
        }

combineSchema :: Schema -> Schema -> Schema
combineSchema left right =
  Schema
    { settings =
        Map.unionWith mergeSetting (left ^. #settings) (right ^. #settings),
      conditions = left ^. #conditions <> right ^. #conditions
    }

conditionalSchema :: Schema -> Schema -> Schema
conditionalSchema selector branch =
  combined
    & #conditions
    %~ (<> newCondition)
  where
    branchSettings = branch ^. #settings & each . #presence .~ Conditional
    branchKeys = Map.keysSet branchSettings
    selectorKeys = Map.keysSet (selector ^. #settings)
    conditionalBranch = branch & #settings .~ branchSettings
    combined = combineSchema selector conditionalBranch
    newCondition
      | Set.null branchKeys = []
      | otherwise = [Condition {dependencies = selectorKeys, settings = branchKeys}]

mergeSetting :: SchemaSetting -> SchemaSetting -> SchemaSetting
mergeSetting left right =
  left
    & #requirement
    .~ mergeRequirement (left ^. #requirement) (right ^. #requirement)
    & #presence
    .~ mergePresence (left ^. #presence) (right ^. #presence)

mergeRequirement :: Requirement -> Requirement -> Requirement
mergeRequirement Required _ = Required
mergeRequirement _ Required = Required
mergeRequirement Optional Optional = Optional

mergePresence :: Presence -> Presence -> Presence
mergePresence Necessary _ = Necessary
mergePresence _ Necessary = Necessary
mergePresence Conditional Conditional = Conditional
