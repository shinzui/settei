-- |
-- Module: Settei.Error
-- Description: Structured, secret-safe configuration failures.
module Settei.Error
  ( RawShape (..),
    StructuralError (..),
  )
where

import Settei.Key (Key)
import Settei.Origin (Origin)
import Settei.Prelude

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
