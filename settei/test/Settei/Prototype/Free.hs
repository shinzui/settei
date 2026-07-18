module Settei.Prototype.Free
  ( freeNecessaryKeys,
    freePossibleKeys,
  )
where

import Control.Selective (select)
import Control.Selective.Free
  ( Select,
    getEffects,
    getNecessaryEffects,
    liftSelect,
  )
import Settei.Key (Key)
import Settei.Prelude

data Probe a = Probe !Key a
  deriving stock (Generic)

instance Functor Probe where
  fmap mapValue (Probe key value) = Probe key (mapValue value)

freePossibleKeys :: Key -> Key -> [Key]
freePossibleKeys environment password =
  fmap probeKey (getEffects (prototype environment password))

freeNecessaryKeys :: Key -> Key -> [Key]
freeNecessaryKeys environment password =
  fmap probeKey (getNecessaryEffects (prototype environment password))

prototype :: Key -> Key -> Select Probe ()
prototype environment password =
  select
    (liftSelect (Probe environment (Left ())))
    (liftSelect (Probe password id))

probeKey :: Probe a -> Key
probeKey (Probe key _) = key
