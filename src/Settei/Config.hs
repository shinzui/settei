module Settei.Config
  ( Config,
    describe,
    optional,
    required,
  )
where

import Settei.Internal.Config
  ( Config,
    describeConfig,
    optionalConfig,
    requiredConfig,
  )
import Settei.Schema (Schema)
import Settei.Setting (Setting)

-- | Require one setting when this declaration path is evaluated.
required :: Setting a -> Config a
required = requiredConfig

-- | Request a setting without failing when no source supplies it.
optional :: Setting a -> Config (Maybe a)
optional = optionalConfig

-- | Inspect every possible request without reading configuration sources.
describe :: Config a -> Schema
describe = describeConfig
