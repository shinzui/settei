{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Settei.Internal.Config
  ( Config (..),
    Request (..),
    describeConfig,
    optionalConfig,
    requiredConfig,
    runConfig,
  )
where

import Control.Selective (Selective (..))
import Settei.Internal.Schema
  ( Requirement (..),
    Schema,
    combineSchema,
    conditionalSchema,
    emptySchema,
    requestSchema,
  )
import Settei.Prelude
import Settei.Setting (Setting)

-- | A request made by the declaration language.
data Request a where
  RequiredRequest :: !(Setting a) -> Request a
  OptionalRequest :: !(Setting a) -> Request (Maybe a)

-- | The private, typed syntax tree behind the public declaration language.
data Config a where
  PureConfig :: a -> Config a
  MapConfig :: (a -> b) -> Config a -> Config b
  ApplyConfig :: Config (a -> b) -> Config a -> Config b
  RequestConfig :: !(Request a) -> Config a
  SelectConfig :: Config (Either a b) -> Config (a -> b) -> Config b

instance Functor Config where
  fmap = MapConfig

instance Applicative Config where
  pure = PureConfig
  (<*>) = ApplyConfig

instance Selective Config where
  select = SelectConfig

requiredConfig :: Setting a -> Config a
requiredConfig = RequestConfig . RequiredRequest

optionalConfig :: Setting a -> Config (Maybe a)
optionalConfig = RequestConfig . OptionalRequest

-- | Interpret a declaration. Selective branches evaluate only the chosen side.
runConfig :: (Monad m) => (forall x. Request x -> m x) -> Config a -> m a
runConfig interpret = \case
  PureConfig value -> pure value
  MapConfig mapValue config -> mapValue <$> runConfig interpret config
  ApplyConfig function inputConfig ->
    runConfig interpret function <*> runConfig interpret inputConfig
  RequestConfig request -> interpret request
  SelectConfig selector branch -> do
    decision <- runConfig interpret selector
    case decision of
      Right value -> pure value
      Left value -> do
        applyBranch <- runConfig interpret branch
        pure (applyBranch value)

describeConfig :: Config a -> Schema
describeConfig = \case
  PureConfig _ -> emptySchema
  MapConfig _ config -> describeConfig config
  ApplyConfig function inputConfig ->
    combineSchema (describeConfig function) (describeConfig inputConfig)
  RequestConfig request -> case request of
    RequiredRequest settingSpec -> requestSchema Required settingSpec
    OptionalRequest settingSpec -> requestSchema Optional settingSpec
  SelectConfig selector branch ->
    conditionalSchema (describeConfig selector) (describeConfig branch)
