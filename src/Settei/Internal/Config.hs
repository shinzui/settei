{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Settei.Internal.Config
  ( Config (..),
    Default (..),
    Request (..),
    RuleName (..),
    caseDefaultConfig,
    constantDefaultConfig,
    describeConfig,
    derivedDefaultConfig,
    optionalConfig,
    renderRuleName,
    requiredConfig,
    runConfig,
    withDefaultConfig,
  )
where

import Control.Selective (Selective (..))
import Data.List.NonEmpty qualified as NonEmpty
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

-- | Stable identity for a default derivation rule.
newtype RuleName = RuleName Text
  deriving stock (Generic, Eq, Ord, Show)

-- | An inspectable fallback with explicit dependencies.
--
-- Function-bearing constructors intentionally have no 'Show' instance.
data Default a where
  ConstantDefault :: !RuleName -> !Text -> a -> Default a
  DerivedDefault :: !RuleName -> !Text -> Config d -> (d -> a) -> Default a
  CaseDefault ::
    (Ord d, Show d) =>
    !RuleName ->
    !Text ->
    Config d ->
    !(NonEmpty (d, a)) ->
    !(Maybe a) ->
    Default a

-- | The private, typed syntax tree behind the public declaration language.
data Config a where
  PureConfig :: a -> Config a
  MapConfig :: (a -> b) -> Config a -> Config b
  ApplyConfig :: Config (a -> b) -> Config a -> Config b
  RequestConfig :: !(Request a) -> Config a
  DefaultConfig :: !(Setting a) -> !(Default a) -> Config a
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

constantDefaultConfig :: RuleName -> Text -> a -> Default a
constantDefaultConfig = ConstantDefault

derivedDefaultConfig :: RuleName -> Text -> Config d -> (d -> a) -> Default a
derivedDefaultConfig = DerivedDefault

caseDefaultConfig ::
  (Ord d, Show d) =>
  RuleName ->
  Text ->
  Config d ->
  NonEmpty (d, a) ->
  Maybe a ->
  Default a
caseDefaultConfig = CaseDefault

withDefaultConfig :: Setting a -> Default a -> Config a
withDefaultConfig = DefaultConfig

-- | Render the stable textual identity of a default rule.
renderRuleName :: RuleName -> Text
renderRuleName (RuleName value) = value

-- | Interpret a declaration. Selective branches evaluate only the chosen side.
runConfig :: (Monad m) => (forall x. Request x -> m x) -> Config a -> m a
runConfig interpret = \case
  PureConfig value -> pure value
  MapConfig mapValue config -> mapValue <$> runConfig interpret config
  ApplyConfig function inputConfig ->
    runConfig interpret function <*> runConfig interpret inputConfig
  RequestConfig request -> interpret request
  DefaultConfig settingSpec defaultSpec -> do
    explicitValue <- interpret (OptionalRequest settingSpec)
    case explicitValue of
      Just value -> pure value
      Nothing -> runDefault defaultSpec
  SelectConfig selector branch -> do
    decision <- runConfig interpret selector
    case decision of
      Right value -> pure value
      Left value -> do
        applyBranch <- runConfig interpret branch
        pure (applyBranch value)
  where
    runDefault = \case
      ConstantDefault _ _ value -> pure value
      DerivedDefault _ _ dependency derive ->
        derive <$> runConfig interpret dependency
      CaseDefault _ _ dependency choices fallback -> do
        dependencyValue <- runConfig interpret dependency
        case lookup dependencyValue (NonEmpty.toList choices) of
          Just value -> pure value
          Nothing -> case fallback of
            Just value -> pure value
            Nothing -> error "Settei.Internal.Config.runConfig: unmatched case default"

describeConfig :: Config a -> Schema
describeConfig = \case
  PureConfig _ -> emptySchema
  MapConfig _ config -> describeConfig config
  ApplyConfig function inputConfig ->
    combineSchema (describeConfig function) (describeConfig inputConfig)
  RequestConfig request -> case request of
    RequiredRequest settingSpec -> requestSchema Required settingSpec
    OptionalRequest settingSpec -> requestSchema Optional settingSpec
  DefaultConfig settingSpec defaultSpec ->
    conditionalSchema
      (requestSchema Optional settingSpec)
      (describeDefault defaultSpec)
  SelectConfig selector branch ->
    conditionalSchema (describeConfig selector) (describeConfig branch)

describeDefault :: Default a -> Schema
describeDefault = \case
  ConstantDefault _ _ _ -> emptySchema
  DerivedDefault _ _ dependency _ -> describeConfig dependency
  CaseDefault _ _ dependency _ _ -> describeConfig dependency
