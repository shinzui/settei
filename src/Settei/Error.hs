-- |
-- Module: Settei.Error
-- Description: Structured, secret-safe configuration failures.
module Settei.Error
  ( ConfigError (..),
    ConfigWarning (..),
    DecodeProblem (..),
    MissingProblem (..),
    RawShape (..),
    StructuralError (..),
    UnknownKeyProblem (..),
  )
where

import Settei.Key (Key)
import Settei.Origin (Origin)
import Settei.Prelude
import Settei.Provenance (ReportedValue)

-- | The coarse shape that prevented traversal through a source tree.
data RawShape = NullShape | ScalarShape | ArrayShape
  deriving stock (Generic, Eq, Ord, Show)

-- | A declared key attempted to traverse through a non-object value.
data StructuralError = StructuralError
  { key :: !Key,
    blockedAt :: !Key,
    origin :: !Origin,
    shape :: !RawShape
  }
  deriving stock (Generic, Eq, Show)

-- | A required setting that had no winning source candidate.
data MissingProblem = MissingProblem
  { key :: !Key
  }
  deriving stock (Generic, Eq, Show)

-- | A winning candidate that did not satisfy its setting decoder.
data DecodeProblem = DecodeProblem
  { key :: !Key,
    expected :: !Text,
    origin :: !Origin,
    rejected :: !ReportedValue
  }
  deriving stock (Generic, Eq, Show)

-- | An addressable source leaf that no declaration recognizes.
data UnknownKeyProblem = UnknownKeyProblem
  { key :: !Key,
    origin :: !Origin
  }
  deriving stock (Generic, Eq, Show)

-- | A fatal resolver error. Every constructor is safe to render or show.
data ConfigError
  = MissingRequired !MissingProblem
  | DecodeError !DecodeProblem
  | StructuralConflict !StructuralError
  | UnknownKeyError !UnknownKeyProblem
  deriving stock (Generic, Eq, Show)

-- | A non-fatal resolver diagnostic.
data ConfigWarning
  = UnknownKeyWarning !UnknownKeyProblem
  deriving stock (Generic, Eq, Show)
