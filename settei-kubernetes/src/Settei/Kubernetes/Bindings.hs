-- |
-- Module: Settei.Kubernetes.Bindings
-- Description: Derive validated environment bindings from Kubernetes object references.
module Settei.Kubernetes.Bindings
  ( ObjectKeyBinding (..),
    bindingsFromConfigMap,
    bindingsFromSecret,
    objectKeyBinding,
  )
where

import Data.Generics.Labels ()
import Settei
import Settei.Env
import Settei.Prelude

-- | One row of a derivation: this data key feeds this variable at this target key.
--
-- Holds only names and keys, never configuration values.
data ObjectKeyBinding = ObjectKeyBinding
  { objectKey :: !Text,
    envName :: !EnvName,
    targetKey :: !Key
  }
  deriving stock (Generic, Eq, Show)

-- | Construct one derivation row.
objectKeyBinding :: Text -> EnvName -> Key -> ObjectKeyBinding
objectKeyBinding objectKey envName targetKey =
  ObjectKeyBinding {objectKey, envName, targetKey}

-- | Derive validated bindings from one Secret: namespace, object name, key rows.
--
-- Every generated binding carries the annotations of a per-key reference whose
-- @kubernetes.object-key@ is the row's data key, so the provenance annotation cannot
-- drift from the binding. Validation is settei-env's: invalid or duplicate variable
-- names and duplicate or overlapping target keys are rejected as 'EnvError's.
bindingsFromSecret ::
  Maybe Text -> Text -> [ObjectKeyBinding] -> Either (NonEmpty EnvError) Bindings
bindingsFromSecret = bindingsFromObject SecretObject

-- | 'bindingsFromSecret' for a ConfigMap reference.
bindingsFromConfigMap ::
  Maybe Text -> Text -> [ObjectKeyBinding] -> Either (NonEmpty EnvError) Bindings
bindingsFromConfigMap = bindingsFromObject ConfigMapObject

bindingsFromObject ::
  KubernetesObjectKind ->
  Maybe Text ->
  Text ->
  [ObjectKeyBinding] ->
  Either (NonEmpty EnvError) Bindings
bindingsFromObject kind namespace objectName rows = bindings (fmap derive rows)
  where
    derive row =
      fromKubernetesObject
        (kubernetesRef kind namespace objectName (Just (row ^. #objectKey)))
        (binding (row ^. #envName) (row ^. #targetKey))
