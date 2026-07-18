-- |
-- Module: Settei.Env
-- Description: Explicit, pure environment-variable sources for Settei.
module Settei.Env
  ( EnvName (..),
    EnvSnapshot (..),
    EnvBinding,
    EnvError (..),
    annotateBinding,
    binding,
    bindingAnnotations,
    bindingKey,
    bindingName,
    envSnapshot,
    envSource,
    fromKubernetesObject,
    prefixedBindings,
    readEnvSource,
  )
where

import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Settei
import Settei.Prelude
import System.Environment qualified as Environment

-- | An environment-variable name. 'envSource' validates its portable spelling.
newtype EnvName = EnvName Text
  deriving stock (Generic, Eq, Ord, Show)

-- | A complete injectable view of the process environment.
newtype EnvSnapshot = EnvSnapshot (Map EnvName Text)
  deriving stock (Generic, Eq)

-- | One explicit mapping from an environment variable to a structural Settei key.
data EnvBinding = EnvBinding
  { name :: !EnvName,
    key :: !Key,
    annotations :: !(Map Text Text)
  }
  deriving stock (Generic, Eq)

-- | Why a set of environment bindings cannot form one hierarchical source.
data EnvError
  = InvalidEnvironmentName !EnvName
  | DuplicateEnvironmentName !EnvName
  | DuplicateTargetKey !Key
  | ConflictingTargetKeys !Key !Key
  | PrefixedNameCollision !EnvName !(NonEmpty Key)
  deriving stock (Generic, Eq, Show)

-- | Construct one explicit binding with no caller annotations.
binding :: EnvName -> Key -> EnvBinding
binding name key = EnvBinding {name, key, annotations = Map.empty}

-- | Add trusted descriptive metadata to a binding.
--
-- Adapter-owned metadata such as @environment.variable@ still takes precedence.
annotateBinding :: Map Text Text -> EnvBinding -> EnvBinding
annotateBinding annotations bindingValue =
  bindingValue & #annotations %~ (annotations <>)

-- | Return the variable name used by a binding.
bindingName :: EnvBinding -> EnvName
bindingName value = value ^. #name

-- | Return the structural key targeted by a binding.
bindingKey :: EnvBinding -> Key
bindingKey value = value ^. #key

-- | Return trusted annotations supplied by the caller.
bindingAnnotations :: EnvBinding -> Map Text Text
bindingAnnotations value = value ^. #annotations

-- | Build an injectable snapshot from textual name/value pairs.
--
-- Repeated names use the final supplied value, matching the behavior of a map snapshot.
envSnapshot :: [(Text, Text)] -> EnvSnapshot
envSnapshot values =
  EnvSnapshot
    (Map.fromList [(EnvName name, value) | (name, value) <- values])

-- | Translate explicitly bound variables from one snapshot into a Settei source.
--
-- Missing variables are absent leaves. Values remain 'RawText'; target decoding and
-- sensitivity handling stay in the core declaration and resolver.
envSource :: Text -> [EnvBinding] -> EnvSnapshot -> Either (NonEmpty EnvError) Source
envSource sourceLabel bindings (EnvSnapshot snapshot) =
  case NonEmpty.nonEmpty (bindingErrors bindings) of
    Just errors -> Left errors
    Nothing ->
      Right
        ( annotateSourceAt
            annotationsFor
            (source sourceLabel EnvironmentSource root)
        )
  where
    presentBindings =
      [ (bindingValue, rawValue)
      | bindingValue <- bindings,
        Just value <- [Map.lookup (bindingValue ^. #name) snapshot],
        let rawValue = RawText value
      ]
    root =
      foldl
        (\tree (bindingValue, rawValue) -> insertRawValue (bindingValue ^. #key) rawValue tree)
        (RawObject Map.empty)
        presentBindings
    perKeyAnnotations =
      Map.fromList
        [ ( bindingValue ^. #key,
            Map.singleton "environment.variable" (renderEnvName (bindingValue ^. #name))
              <> bindingValue ^. #annotations
          )
        | (bindingValue, _) <- presentBindings
        ]
    annotationsFor key = Map.findWithDefault Map.empty key perKeyAnnotations

-- | Snapshot the process environment once and pass it through the pure translator.
readEnvSource :: Text -> [EnvBinding] -> IO (Either (NonEmpty EnvError) Source)
readEnvSource sourceLabel bindings = do
  values <- Environment.getEnvironment
  pure
    ( envSource
        sourceLabel
        bindings
        (envSnapshot [(Text.pack name, Text.pack value) | (name, value) <- values])
    )

-- | Derive explicit bindings using @PREFIX_KEY_SEGMENTS@ names.
--
-- Non-alphanumeric characters become underscores and letters become uppercase. Any
-- collision introduced by that normalization is returned instead of being guessed away.
prefixedBindings :: Text -> [Key] -> Either (NonEmpty EnvError) [EnvBinding]
prefixedBindings prefix keys =
  case NonEmpty.nonEmpty errors of
    Just found -> Left found
    Nothing -> Right generated
  where
    generated = fmap (\key -> binding (prefixedName prefix key) key) keys
    invalidErrors =
      [ InvalidEnvironmentName name
      | bindingValue <- generated,
        let name = bindingValue ^. #name,
        not (validEnvName name)
      ]
    duplicateKeyErrors = fmap DuplicateTargetKey (duplicates keys)
    groupedByName =
      Map.fromListWith
        (<>)
        [ (bindingValue ^. #name, bindingValue ^. #key :| [])
        | bindingValue <- generated
        ]
    collisionErrors =
      [ PrefixedNameCollision name targetKeys
      | (name, targetKeys) <- Map.toAscList groupedByName,
        NonEmpty.length targetKeys > 1
      ]
    errors = invalidErrors <> duplicateKeyErrors <> collisionErrors <> overlapErrors keys

-- | Attach a trusted Kubernetes object reference without querying a cluster.
fromKubernetesObject :: KubernetesRef -> EnvBinding -> EnvBinding
fromKubernetesObject reference bindingValue =
  annotateBinding (kubernetesAnnotations reference) bindingValue

bindingErrors :: [EnvBinding] -> [EnvError]
bindingErrors bindings =
  [ InvalidEnvironmentName name
  | bindingValue <- bindings,
    let name = bindingValue ^. #name,
    not (validEnvName name)
  ]
    <> fmap DuplicateEnvironmentName (duplicates (fmap (^. #name) bindings))
    <> fmap DuplicateTargetKey (duplicates (fmap (^. #key) bindings))
    <> overlapErrors (fmap (^. #key) bindings)

overlapErrors :: [Key] -> [EnvError]
overlapErrors keys =
  [ ConflictingTargetKeys lower higher
  | (positionIndex, lower) <- zip [0 :: Int ..] keys,
    higher <- drop (positionIndex + 1) keys,
    lower /= higher,
    isPrefixKey lower higher || isPrefixKey higher lower
  ]

duplicates :: (Ord a) => [a] -> [a]
duplicates values =
  Map.keys (Map.filter (> (1 :: Int)) (Map.fromListWith (+) [(value, 1) | value <- values]))

validEnvName :: EnvName -> Bool
validEnvName (EnvName value) =
  case Text.uncons value of
    Nothing -> False
    Just (firstCharacter, rest) ->
      validInitial firstCharacter && Text.all validContinuation rest
  where
    validInitial character = asciiLetter character || character == '_'
    validContinuation character = validInitial character || isDigit character

asciiLetter :: Char -> Bool
asciiLetter character = isAsciiLower character || isAsciiUpper character

prefixedName :: Text -> Key -> EnvName
prefixedName prefix key =
  EnvName
    ( Text.intercalate
        "_"
        (normalizeNamePart prefix : fmap normalizeNamePart (NonEmpty.toList (keySegments key)))
    )

normalizeNamePart :: Text -> Text
normalizeNamePart =
  Text.toUpper
    . Text.map
      (\character -> if asciiLetter character || isDigit character || character == '_' then character else '_')

renderEnvName :: EnvName -> Text
renderEnvName (EnvName value) = value

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
    go _ _ = error "validated environment keys cannot overlap"
