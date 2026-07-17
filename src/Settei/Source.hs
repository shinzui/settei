{-# LANGUAGE ImportQualifiedPost #-}

-- |
-- Module: Settei.Source
-- Description: Ordered, hierarchical configuration inputs.
module Settei.Source
  ( Source,
    annotateSource,
    locateSource,
    lookupSource,
    source,
    sourceAnnotations,
    sourceKind,
    sourceLeaves,
    sourceName,
  )
where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Settei.Error (RawShape (..), StructuralError (..))
import Settei.Key (Key, keySegments, mkKey)
import Settei.Origin (Origin (..), SourceKind, SourceLocation)
import Settei.Prelude
import Settei.Provenance (Candidate, candidate)
import Settei.Value (RawValue (..))

-- | A reusable source tree. Precedence is supplied by its position in @[Source]@.
--
-- There is deliberately no 'Show' instance because 'root' may contain secrets.
data Source = Source
  { name :: !Text,
    kind :: !SourceKind,
    root :: !RawValue,
    locationAt :: !(Key -> Maybe SourceLocation),
    annotations :: !(Map Text Text)
  }
  deriving stock (Generic)

-- | Construct a source with no retained locations or annotations.
source :: Text -> SourceKind -> RawValue -> Source
source name kind root =
  Source
    { name,
      kind,
      root,
      locationAt = const Nothing,
      annotations = Map.empty
    }

-- | Attach adapter-specific descriptive metadata. It never changes precedence.
annotateSource :: Map Text Text -> Source -> Source
annotateSource annotations sourceValue = sourceValue & #annotations .~ annotations

-- | Attach exact-key locations retained by an adapter parser.
locateSource :: (Key -> Maybe SourceLocation) -> Source -> Source
locateSource locationAt sourceValue = sourceValue & #locationAt .~ locationAt

-- | Return a source's stable descriptive name.
sourceName :: Source -> Text
sourceName value = value ^. #name

-- | Return a source's format-independent category.
sourceKind :: Source -> SourceKind
sourceKind value = value ^. #kind

-- | Return descriptive annotations shared by every candidate from the source.
sourceAnnotations :: Source -> Map Text Text
sourceAnnotations value = value ^. #annotations

-- | Look up one exact structural key.
--
-- A scalar or array is a valid value at the final segment. Traversing through one is a
-- structural error; dotted textual prefix tricks are never used.
lookupSource :: Key -> Source -> Either StructuralError (Maybe Candidate)
lookupSource target sourceValue =
  walk [] (NonEmpty.toList (keySegments target)) (sourceValue ^. #root)
  where
    walk _ [] rawValue = Right (Just (candidate rawValue (originFor target sourceValue)))
    walk prefix (segment : rest) rawValue = case rawValue of
      RawObject object ->
        case Map.lookup segment object of
          Nothing -> Right Nothing
          Just child -> walk (prefix <> [segment]) rest child
      RawNull -> Left (blocked prefix NullShape)
      RawArray _ -> Left (blocked prefix ArrayShape)
      RawText _ -> Left (blocked prefix ScalarShape)
      RawBool _ -> Left (blocked prefix ScalarShape)
      RawNumber _ -> Left (blocked prefix ScalarShape)

    blocked prefix shape =
      StructuralError
        { key = target,
          blockedAt = prefixKey target prefix,
          origin = originFor (prefixKey target prefix) sourceValue,
          shape
        }

-- | Enumerate addressable leaves in key order for unknown-key diagnostics.
--
-- Arrays and scalars are whole leaves. Empty objects contain no leaves.
sourceLeaves :: Source -> [(Key, Candidate)]
sourceLeaves sourceValue = go [] (sourceValue ^. #root)
  where
    go prefix = \case
      RawObject object ->
        concatMap
          (\(segment, rawValue) -> go (prefix <> [segment]) rawValue)
          (Map.toAscList object)
      rawValue -> case NonEmpty.nonEmpty prefix of
        Nothing -> []
        Just segments -> case mkKey segments of
          Left _ -> []
          Right key -> [(key, candidate rawValue (originFor key sourceValue))]

originFor :: Key -> Source -> Origin
originFor key sourceValue =
  Origin
    { kind = sourceValue ^. #kind,
      name = sourceValue ^. #name,
      key,
      location = (sourceValue ^. #locationAt) key,
      annotations = sourceValue ^. #annotations
    }

prefixKey :: Key -> [Text] -> Key
prefixKey target prefix =
  case NonEmpty.nonEmpty prefix >>= either (const Nothing) Just . mkKey of
    Just key -> key
    Nothing -> target
