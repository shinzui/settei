{-# LANGUAGE ImportQualifiedPost #-}

-- |
-- Module: Settei.Source
-- Description: Ordered, hierarchical configuration inputs.
module Settei.Source
  ( Source,
    SourceConstructionError (..),
    annotateSource,
    annotateSourceAt,
    locateSource,
    lookupSource,
    source,
    sourceAnnotations,
    sourceFromPairs,
    sourceKind,
    sourceLeaves,
    sourceName,
    sourceUnaddressableLeaves,
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
    annotationsAt :: !(Key -> Map Text Text),
    annotations :: !(Map Text Text)
  }
  deriving stock (Generic)

-- | Why a list of key/value pairs cannot form one addressable source tree.
data SourceConstructionError
  = -- | The same key appears more than once.
    DuplicateSourceKey !Key
  | -- | One key is a structural prefix of another, so one leaf would sit
    -- inside the object the other needs to traverse.
    OverlappingSourceKeys !Key !Key
  deriving stock (Generic, Eq, Show)

-- | Construct a source with no retained locations or annotations.
--
-- This function performs no validation. Leaves below object keys that are empty or
-- contain dots cannot be addressed by 'lookupSource' and are silently absent from
-- 'sourceLeaves'. Prefer 'sourceFromPairs' for hand-built sources; this function is the
-- unvalidated escape hatch used by adapters that already guarantee valid trees.
source :: Text -> SourceKind -> RawValue -> Source
source name kind root =
  Source
    { name,
      kind,
      root,
      locationAt = const Nothing,
      annotationsAt = const Map.empty,
      annotations = Map.empty
    }

-- | Build a source from validated keys, rejecting duplicates and prefix overlaps.
--
-- Every leaf of the result is addressable by 'lookupSource' and enumerated by
-- 'sourceLeaves'. This is the recommended constructor for hand-built sources; 'source'
-- is the unvalidated escape hatch.
sourceFromPairs ::
  Text ->
  SourceKind ->
  [(Key, RawValue)] ->
  Either (NonEmpty SourceConstructionError) Source
sourceFromPairs name kind pairs =
  case NonEmpty.nonEmpty constructionErrors of
    Just errors -> Left errors
    Nothing ->
      Right
        ( source
            name
            kind
            (foldl (\rootValue (key, value) -> insertRawValue key value rootValue) (RawObject Map.empty) pairs)
        )
  where
    keys = fmap fst pairs
    duplicateErrors = fmap DuplicateSourceKey (duplicates keys)
    overlapErrors =
      [ OverlappingSourceKeys lower higher
      | (positionIndex, lower) <- zip [0 :: Int ..] keys,
        higher <- drop (positionIndex + 1) keys,
        lower /= higher,
        isPrefixKey lower higher || isPrefixKey higher lower
      ]
    constructionErrors = duplicateErrors <> overlapErrors

-- | Attach adapter-specific descriptive metadata. It never changes precedence.
--
-- Repeated calls merge: annotations from a later call win when the same annotation
-- name is already present, and entries under other names are retained. Per-key
-- annotations from 'annotateSourceAt' still take precedence over source-wide entries.
annotateSource :: Map Text Text -> Source -> Source
annotateSource annotations sourceValue =
  sourceValue & #annotations %~ (annotations <>)

-- | Attach descriptive metadata for individual keys.
--
-- Later calls compose with earlier hooks. New per-key entries take precedence over
-- earlier per-key and source-wide entries with the same annotation name.
annotateSourceAt :: (Key -> Map Text Text) -> Source -> Source
annotateSourceAt additions sourceValue =
  sourceValue
    & #annotationsAt
    %~ \existing key -> additions key <> existing key

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
-- Arrays and scalars are whole leaves. Empty objects contain no leaves. Sources created
-- through the unvalidated 'source' escape hatch may contain leaves below empty or dotted
-- object keys; those leaves cannot form a 'Key' and are silently absent here. Prefer
-- 'sourceFromPairs' for hand-built sources and use 'sourceUnaddressableLeaves' to inspect
-- an existing source.
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

-- | Return the raw segment paths of leaves that no 'Key' can address.
--
-- A non-empty result means the source was built by hand with object keys that are empty
-- or contain dots; such leaves are invisible to 'lookupSource', 'sourceLeaves', and
-- unknown-key diagnostics. Only key paths are returned; raw values are never exposed
-- because they may be secret. A scalar at the root has an empty path and is excluded.
sourceUnaddressableLeaves :: Source -> [[Text]]
sourceUnaddressableLeaves sourceValue = go [] (sourceValue ^. #root)
  where
    go prefix = \case
      RawObject object ->
        concatMap
          (\(segment, rawValue) -> go (prefix <> [segment]) rawValue)
          (Map.toAscList object)
      _ -> case NonEmpty.nonEmpty prefix of
        Nothing -> []
        Just segments -> case mkKey segments of
          Left _ -> [prefix]
          Right _ -> []

duplicates :: (Ord a) => [a] -> [a]
duplicates values =
  Map.keys (Map.filter (> (1 :: Int)) (Map.fromListWith (+) [(value, 1) | value <- values]))

isPrefixKey :: Key -> Key -> Bool
isPrefixKey prefix candidateKey =
  NonEmpty.toList (keySegments prefix)
    `isListPrefixOf` NonEmpty.toList (keySegments candidateKey)

isListPrefixOf :: (Eq a) => [a] -> [a] -> Bool
isListPrefixOf [] _ = True
isListPrefixOf _ [] = False
isListPrefixOf (left : leftRest) (right : rightRest) =
  left == right && isListPrefixOf leftRest rightRest

insertRawValue :: Key -> RawValue -> RawValue -> RawValue
insertRawValue key value = go (NonEmpty.toList (keySegments key))
  where
    go [] _ = value
    go (segment : rest) (RawObject object) =
      RawObject
        ( object
            & at segment
            %~ Just
            . go rest
            . maybe (RawObject Map.empty) id
        )
    go _ _ = error "validated source keys cannot overlap"

originFor :: Key -> Source -> Origin
originFor key sourceValue =
  Origin
    { kind = sourceValue ^. #kind,
      name = sourceValue ^. #name,
      key,
      location = (sourceValue ^. #locationAt) key,
      annotations =
        (sourceValue ^. #annotationsAt) key
          <> sourceValue ^. #annotations
    }

prefixKey :: Key -> [Text] -> Key
prefixKey target prefix =
  case NonEmpty.nonEmpty prefix >>= either (const Nothing) Just . mkKey of
    Just key -> key
    Nothing -> target
