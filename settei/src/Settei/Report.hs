-- |
-- Module: Settei.Report
-- Description: Secret-safe data describing one resolution run.
module Settei.Report
  ( BranchTrace (..),
    Derivation (..),
    ResolutionNode (..),
    ResolutionOutcome (..),
    ResolutionReport (..),
    InvariantStatus (..),
    InvariantOutcome (..),
    ValidationReport (..),
    validationOutcomes,
    reportBranches,
    reportNodes,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Settei.Error (InvariantRule)
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

-- | The result of one application rule, without retaining application values.
data InvariantStatus
  = InvariantPassed
  | InvariantFailed !Int
  | InvariantSkipped !(NonEmpty InvariantRule)
  | InvariantNotRun
  deriving stock (Generic, Eq, Show)

-- | Public declaration metadata and one rule's execution status.
data InvariantOutcome = InvariantOutcome
  { rule :: !InvariantRule,
    keys :: ![Key],
    expectation :: !Text,
    prerequisites :: ![InvariantRule],
    status :: !InvariantStatus
  }
  deriving stock (Generic, Eq, Show)

newtype ValidationReport = ValidationReport
  { invariants :: [InvariantOutcome]
  }
  deriving stock (Generic, Eq, Show)

-- | Outcomes in validator declaration order.
validationOutcomes :: ValidationReport -> [InvariantOutcome]
validationOutcomes value = value ^. #invariants
