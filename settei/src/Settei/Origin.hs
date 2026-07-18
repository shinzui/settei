{-# LANGUAGE ImportQualifiedPost #-}

-- |
-- Module: Settei.Origin
-- Description: Adapter-neutral metadata describing where a candidate came from.
module Settei.Origin
  ( KubernetesObjectKind (..),
    KubernetesRef,
    Origin (..),
    SourceKind (..),
    SourceLocation (..),
    kubernetesAnnotations,
    kubernetesRef,
    kubernetesRefKey,
    kubernetesRefKind,
    kubernetesRefName,
    kubernetesRefNamespace,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Settei.Key (Key)
import Settei.Prelude

-- | A format-independent category for a configuration source.
data SourceKind
  = BuiltInSource
  | FileSource !Text
  | EnvironmentSource
  | CommandLineSource
  | DerivedSource
  | CustomSource !Text
  deriving stock (Generic, Eq, Ord, Show)

-- | An optional source location retained by an adapter.
data SourceLocation = SourceLocation
  { path :: !Text,
    line :: !(Maybe Int),
    column :: !(Maybe Int)
  }
  deriving stock (Generic, Eq, Ord, Show)

-- | Structured provenance for one logical configuration key.
data Origin = Origin
  { kind :: !SourceKind,
    name :: !Text,
    key :: !Key,
    location :: !(Maybe SourceLocation),
    annotations :: !(Map Text Text)
  }
  deriving stock (Generic, Eq, Show)

-- | Kubernetes object categories shared by independent adapters.
data KubernetesObjectKind = ConfigMapObject | SecretObject
  deriving stock (Generic, Eq, Ord, Show)

-- | A cluster-independent Kubernetes object reference.
data KubernetesRef = KubernetesRef
  { kind :: !KubernetesObjectKind,
    namespace :: !(Maybe Text),
    name :: !Text,
    key :: !(Maybe Text)
  }
  deriving stock (Generic, Eq, Ord, Show)

-- | Construct a reference without performing a cluster lookup.
kubernetesRef :: KubernetesObjectKind -> Maybe Text -> Text -> Maybe Text -> KubernetesRef
kubernetesRef kind namespace name key = KubernetesRef {kind, namespace, name, key}

-- | Return the referenced Kubernetes object kind.
kubernetesRefKind :: KubernetesRef -> KubernetesObjectKind
kubernetesRefKind value = value ^. #kind

-- | Return the optional Kubernetes namespace.
kubernetesRefNamespace :: KubernetesRef -> Maybe Text
kubernetesRefNamespace value = value ^. #namespace

-- | Return the Kubernetes object name.
kubernetesRefName :: KubernetesRef -> Text
kubernetesRefName value = value ^. #name

-- | Return the optional key within the Kubernetes object.
kubernetesRefKey :: KubernetesRef -> Maybe Text
kubernetesRefKey value = value ^. #key

-- | Stable annotations understood across Kubernetes-aware adapters.
kubernetesAnnotations :: KubernetesRef -> Map Text Text
kubernetesAnnotations value =
  Map.fromList
    ( [ ("kubernetes.object-kind", renderObjectKind (value ^. #kind)),
        ("kubernetes.object-name", value ^. #name)
      ]
        <> maybe [] (pure . ("kubernetes.namespace",)) (value ^. #namespace)
        <> maybe [] (pure . ("kubernetes.object-key",)) (value ^. #key)
    )

renderObjectKind :: KubernetesObjectKind -> Text
renderObjectKind ConfigMapObject = "ConfigMap"
renderObjectKind SecretObject = "Secret"
