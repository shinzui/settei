-- |
-- Module: Settei.Report
-- Description: Secret-safe data describing one resolution run.
module Settei.Report
  ( BranchTrace (..),
    Derivation (..),
    ResolutionNode (..),
    ResolutionOutcome (..),
    ResolutionReport (..),
    reportBranches,
    reportNodes,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Settei.Key (Key)
import Settei.Origin (Origin)
import Settei.Prelude
import Settei.Provenance (ReportedValue)
import Settei.Setting (Sensitivity)

-- | What happened to a statically possible setting in this run.
data ResolutionOutcome
  = Resolved !ReportedValue
  | MissingValue
  | NotSelected
  deriving stock (Generic, Eq, Show)

-- | A named default rule that produced a setting value.
data Derivation = Derivation
  { rule :: !Text,
    explanation :: !Text,
    dependencies :: ![Key]
  }
  deriving stock (Generic, Eq, Show)

-- | One evaluated or skipped setting, keyed independently in the report map.
data ResolutionNode = ResolutionNode
  { key :: !Key,
    sensitivity :: !Sensitivity,
    outcome :: !ResolutionOutcome,
    origin :: !(Maybe Origin),
    shadowed :: ![Origin],
    derivation :: !(Maybe Derivation)
  }
  deriving stock (Generic, Eq, Show)

-- | Whether one selective branch was evaluated for this run.
data BranchTrace = BranchTrace
  { dependencies :: ![Key],
    settings :: ![Key],
    selected :: !Bool
  }
  deriving stock (Generic, Eq, Show)

-- | Complete, secret-safe trace for one resolution attempt.
data ResolutionReport = ResolutionReport
  { nodes :: !(Map Key ResolutionNode),
    branches :: ![BranchTrace]
  }
  deriving stock (Generic, Eq, Show)

-- | Return resolution nodes in stable key order.
reportNodes :: ResolutionReport -> [ResolutionNode]
reportNodes value = value ^. #nodes . to Map.elems

-- | Return branch decisions in evaluation order.
reportBranches :: ResolutionReport -> [BranchTrace]
reportBranches value = value ^. #branches
