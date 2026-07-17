-- |
-- Module: Settei.Provenance
-- Description: Raw candidates paired with their structured origin.
module Settei.Provenance
  ( Candidate,
    candidate,
    candidateOrigin,
    candidateValue,
  )
where

import Data.Generics.Labels ()
import Settei.Origin (Origin)
import Settei.Prelude
import Settei.Value (RawValue)

-- | One source's value for one declared key.
--
-- There is deliberately no 'Show' instance: the raw value may be secret.
data Candidate = Candidate
  { value :: !RawValue,
    origin :: !Origin
  }
  deriving stock (Generic, Eq)

candidate :: RawValue -> Origin -> Candidate
candidate value origin = Candidate {value, origin}

candidateValue :: Candidate -> RawValue
candidateValue value = value ^. #value

candidateOrigin :: Candidate -> Origin
candidateOrigin value = value ^. #origin
