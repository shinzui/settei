-- |
-- Module: Settei.Env
-- Description: Explicit, pure environment sources and supplied-name validation.
module Settei.Env
  ( AcceptedNames,
    Allowance,
    Bindings,
    EnvName (..),
    EnvSnapshot (..),
    EnvBinding,
    EnvError (..),
    NameAcceptance (..),
    SuppliedNameError (..),
    acceptedBindings,
    acceptedNames,
    acceptedNamesList,
    allowance,
    allowanceConsumer,
    allowanceName,
    annotateBinding,
    binding,
    bindingAnnotations,
    bindingKey,
    bindingName,
    bindings,
    bindingsList,
    checkSuppliedNames,
    checkedEnvSource,
    checkedEnvironmentSource,
    envSnapshot,
    envSource,
    environmentSource,
    fromKubernetesObject,
    inputBindings,
    mergeBindings,
    prefixedBindings,
    readEnvSource,
    readEnvironmentSource,
    renderEnvErrorText,
    renderEnvErrorsText,
    renderSuppliedNameErrorText,
    renderSuppliedNameErrorsJson,
    renderSuppliedNameErrorsText,
    snapshotNames,
  )
where

import Data.Char (isAsciiLower, isAsciiUpper, isDigit, ord)
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Numeric (showHex)
import Settei
import Settei.Prelude
import System.Environment qualified as Environment

-- | An environment-variable name. 'bindings' validates its portable spelling.
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

-- | A collection of bindings proven valid at construction.
--
-- The constructor is private: 'bindings' and 'prefixedBindings' are the only ways to
-- obtain a value, so every 'Bindings' is free of invalid names, duplicate names,
-- duplicate target keys, and prefix-overlapping target keys. Binding lists are static
-- program data; resolve 'bindings' once at startup (or force it in a unit test) so an
-- invalid list is a fail-fast programming-error report, not a runtime branch.
newtype Bindings = Bindings [EnvBinding]
  deriving stock (Eq)

-- | One variable consumed outside Settei, with a trusted consumer label.
-- Validated together with bindings by 'acceptedNames'.
data Allowance = Allowance !Text !EnvName
  deriving stock (Eq)

-- | Declare a consumer label and its variable name; no value is retained.
allowance :: Text -> EnvName -> Allowance
allowance = Allowance

-- | Inspect the trusted external-consumer label.
allowanceConsumer :: Allowance -> Text
allowanceConsumer (Allowance consumer _) = consumer

-- | Inspect the variable consumed outside Settei.
allowanceName :: Allowance -> EnvName
allowanceName (Allowance _ name) = name

-- | How a declared name is accepted.
data NameAcceptance = BoundTo !Key | ConsumedBy !Text
  deriving stock (Generic, Eq, Show)

-- | Bindings and external-consumer allowances validated together.
-- The private constructor and absence of Generic preserve the invariant.
data AcceptedNames = AcceptedNames !Bindings ![Allowance]
  deriving stock (Eq)

-- | Validate static allowances, rejecting invalid or repeated names (including
-- names already bound). Invalid names precede ascending duplicate-name errors.
acceptedNames :: Bindings -> [Allowance] -> Either (NonEmpty EnvError) AcceptedNames
acceptedNames validated allowances =
  case NonEmpty.nonEmpty errors of
    Just problems -> Left problems
    Nothing -> Right (AcceptedNames validated allowances)
  where
    names = fmap allowanceName allowances
    errors =
      [InvalidEnvironmentName name | name <- names, not (validEnvName name)]
        <> fmap DuplicateEnvironmentName (duplicates (fmap bindingName (bindingsList validated) <> names))

-- | Recover the original validated bindings for ordinary source translation.
acceptedBindings :: AcceptedNames -> Bindings
acceptedBindings (AcceptedNames validated _) = validated

-- | Bound names in binding order followed by allowances in declaration order.
acceptedNamesList :: AcceptedNames -> [(EnvName, NameAcceptance)]
acceptedNamesList (AcceptedNames validated allowances) =
  [(bindingName value, BoundTo (bindingKey value)) | value <- bindingsList validated]
    <> [(allowanceName value, ConsumedBy (allowanceConsumer value)) | value <- allowances]

-- | Runtime supplied-name failures retain original names only, never values.
data SuppliedNameError
  = UnsupportedSuppliedName !EnvName
  | DuplicateSuppliedName !EnvName
  deriving stock (Generic, Eq, Show)

-- | Check exactly the supplied collection. Absence is never an error.
-- Unsupported names are reported at their first occurrence; duplicates once at
-- their second occurrence. Diagnostic order follows encounter order.
checkSuppliedNames :: AcceptedNames -> [EnvName] -> Either (NonEmpty SuppliedNameError) ()
checkSuppliedNames accepted supplied =
  case NonEmpty.nonEmpty (go Set.empty Set.empty supplied) of
    Just problems -> Left problems
    Nothing -> Right ()
  where
    allowed = Set.fromList (fmap fst (acceptedNamesList accepted))
    go _ _ [] = []
    go seen reportedDuplicates (name : rest)
      | Set.member name reportedDuplicates = go seen reportedDuplicates rest
      | Set.member name seen = DuplicateSuppliedName name : go seen (Set.insert name reportedDuplicates) rest
      | otherwise =
          [UnsupportedSuppliedName name | Set.notMember name allowed]
            <> go (Set.insert name seen) reportedDuplicates rest

-- | Render a single safe physical line. Portable names are verbatim; other names
-- are quoted and escaped without changing the retained name or comparison.
renderSuppliedNameErrorText :: SuppliedNameError -> Text
renderSuppliedNameErrorText = \case
  UnsupportedSuppliedName name ->
    "supplied environment variable " <> displaySuppliedName name <> ": no binding or allowance accepts it"
  DuplicateSuppliedName name ->
    "supplied environment variable " <> displaySuppliedName name <> ": supplied more than once"

-- | One sentence and terminating newline per problem.
renderSuppliedNameErrorsText :: NonEmpty SuppliedNameError -> Text
renderSuppliedNameErrorsText = Text.unlines . fmap renderSuppliedNameErrorText . NonEmpty.toList

-- | One compact @settei.supplied-names@ schema-version-1 document, without a
-- trailing newline. JSON encodes the original names, independently of text display.
renderSuppliedNameErrorsJson :: NonEmpty SuppliedNameError -> Text
renderSuppliedNameErrorsJson errors =
  jsonObject
    [ ("schemaVersion", "1"),
      ("type", jsonString "settei.supplied-names"),
      ("errors", jsonArray (fmap renderError (NonEmpty.toList errors)))
    ]
  where
    renderError problem =
      let (kind, name) = case problem of
            UnsupportedSuppliedName value -> ("unsupported-supplied-name", value)
            DuplicateSuppliedName value -> ("duplicate-supplied-name", value)
       in jsonObject [("kind", jsonString kind), ("name", jsonString (renderEnvName name))]

displaySuppliedName :: EnvName -> Text
displaySuppliedName name
  | validEnvName name = renderEnvName name
  | otherwise = "\"" <> Text.concatMap escapeDisplayChar (renderEnvName name) <> "\""
  where
    escapeDisplayChar character
      | (character >= '\x7f' && character <= '\x9f') || character == '\x2028' || character == '\x2029' =
          "\\u" <> paddedHex (ord character)
      | otherwise = escapeJsonChar character

jsonObject :: [(Text, Text)] -> Text
jsonObject fields =
  "{" <> Text.intercalate "," [jsonString key <> ":" <> value | (key, value) <- fields] <> "}"

jsonArray :: [Text] -> Text
jsonArray values = "[" <> Text.intercalate "," values <> "]"

jsonString :: Text -> Text
jsonString value = "\"" <> Text.concatMap escapeJsonChar value <> "\""

escapeJsonChar :: Char -> Text
escapeJsonChar = \case
  '"' -> "\\\""
  '\\' -> "\\\\"
  '\b' -> "\\b"
  '\f' -> "\\f"
  '\n' -> "\\n"
  '\r' -> "\\r"
  '\t' -> "\\t"
  character
    | ord character < 0x20 -> "\\u" <> paddedHex (ord character)
    | otherwise -> Text.singleton character

paddedHex :: Int -> Text
paddedHex value =
  let rendered = Text.pack (showHex value "")
   in Text.replicate (4 - Text.length rendered) "0" <> rendered

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

-- | Validate a static binding list once, yielding a collection usable with the total
-- source builders.
bindings :: [EnvBinding] -> Either (NonEmpty EnvError) Bindings
bindings values =
  case NonEmpty.nonEmpty (bindingErrors values) of
    Just errors -> Left errors
    Nothing -> Right (Bindings values)

-- | Inspect the validated bindings, for example to count or display them.
bindingsList :: Bindings -> [EnvBinding]
bindingsList (Bindings values) = values

-- | Merge validated collections into one, re-validating cross-collection conflicts.
--
-- Two individually valid collections can still collide with each other (a variable
-- name bound in both, or target keys that overlap across them), so merging returns
-- the same 'EnvError' vocabulary as 'bindings'. The empty list yields the valid empty
-- collection. Order is preserved: earlier collections contribute earlier bindings.
mergeBindings :: [Bindings] -> Either (NonEmpty EnvError) Bindings
mergeBindings = bindings . concatMap bindingsList

-- | Render one binding-validation failure as a single operator-readable sentence.
--
-- Only variable names and structural keys appear; environment values are never
-- retained by 'EnvError' and therefore cannot leak.
renderEnvErrorText :: EnvError -> Text
renderEnvErrorText = \case
  InvalidEnvironmentName name ->
    "environment binding " <> renderEnvName name <> ": invalid variable name"
  DuplicateEnvironmentName name ->
    "environment binding " <> renderEnvName name <> ": variable bound more than once"
  DuplicateTargetKey key ->
    "bindings target the same key " <> renderKey key <> " twice"
  ConflictingTargetKeys lower higher ->
    "bindings target overlapping keys " <> renderKey lower <> " and " <> renderKey higher
  PrefixedNameCollision name keys ->
    "environment binding "
      <> renderEnvName name
      <> ": normalized name collides for keys "
      <> Text.intercalate ", " (fmap renderKey (NonEmpty.toList keys))

-- | Render every binding-validation failure, one line per problem, matching
-- 'Settei.Render.renderErrorsText' in shape and trailing newline.
renderEnvErrorsText :: NonEmpty EnvError -> Text
renderEnvErrorsText = Text.unlines . fmap renderEnvErrorText . NonEmpty.toList

-- | Build an injectable snapshot from textual name/value pairs.
--
-- Repeated names use the final supplied value, matching the behavior of a map snapshot.
envSnapshot :: [(Text, Text)] -> EnvSnapshot
envSnapshot values =
  EnvSnapshot
    (Map.fromList [(EnvName name, value) | (name, value) <- values])

-- | Snapshot keys in ascending order. A map has already collapsed duplicate
-- entries; check ordered deployment entries as a list before making a snapshot.
snapshotNames :: EnvSnapshot -> [EnvName]
snapshotNames (EnvSnapshot snapshot) = Map.keys snapshot

-- | Opt in to checking every name in an injected snapshot, then translate using
-- the ordinary source builder. This never reads the process environment itself.
checkedEnvSource :: Text -> AcceptedNames -> EnvSnapshot -> Either (NonEmpty SuppliedNameError) Source
checkedEnvSource label accepted snapshot = do
  checkSuppliedNames accepted (snapshotNames snapshot)
  pure (envSource label (acceptedBindings accepted) snapshot)

-- | 'checkedEnvSource' with the conventional @"environment"@ label.
checkedEnvironmentSource :: AcceptedNames -> EnvSnapshot -> Either (NonEmpty SuppliedNameError) Source
checkedEnvironmentSource = checkedEnvSource "environment"

-- | Translate explicitly bound variables from one snapshot into a Settei source.
--
-- Total: a 'Bindings' value is valid by construction, so no error branch exists.
-- Missing variables are absent leaves. Values remain 'RawText'; target decoding and
-- sensitivity handling stay in the core declaration and resolver.
envSource :: Text -> Bindings -> EnvSnapshot -> Source
envSource sourceLabel (Bindings values) (EnvSnapshot snapshot) =
  annotateSourceAt annotationsFor (source sourceLabel EnvironmentSource root)
  where
    presentBindings =
      [ (bindingValue, rawValue)
      | bindingValue <- values,
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

-- | 'envSource' with the conventional source label @"environment"@.
environmentSource :: Bindings -> EnvSnapshot -> Source
environmentSource = envSource "environment"

-- | Snapshot the process environment once and pass it through the pure translator.
readEnvSource :: Text -> Bindings -> IO Source
readEnvSource sourceLabel validated = do
  boundValues <- Environment.getEnvironment
  pure
    ( envSource
        sourceLabel
        validated
        (envSnapshot [(Text.pack name, Text.pack value) | (name, value) <- boundValues])
    )

-- | 'readEnvSource' with the conventional source label @"environment"@.
readEnvironmentSource :: Bindings -> IO Source
readEnvironmentSource = readEnvSource "environment"

-- | Derive explicit bindings using @PREFIX_KEY_SEGMENTS@ names.
--
-- Non-alphanumeric characters become underscores and letters become uppercase. Any
-- collision introduced by that normalization is returned instead of being guessed away.
-- The successful result is already validated: pass it straight to 'envSource'.
prefixedBindings :: Text -> [Key] -> Either (NonEmpty EnvError) Bindings
prefixedBindings prefix keys =
  case NonEmpty.nonEmpty errors of
    Just found -> Left found
    Nothing -> Right (Bindings generated)
  where
    generated = fmap (\key -> binding (prefixedName prefix key) key) keys
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
    sharedErrors = filter (not . isDuplicateNameError) (bindingErrors generated)
    errors = sharedErrors <> collisionErrors

isDuplicateNameError :: EnvError -> Bool
isDuplicateNameError (DuplicateEnvironmentName _) = True
isDuplicateNameError _ = False

-- | Attach a trusted Kubernetes object reference without querying a cluster.
fromKubernetesObject :: KubernetesRef -> EnvBinding -> EnvBinding
fromKubernetesObject reference bindingValue =
  annotateBinding (kubernetesAnnotations reference) bindingValue

bindingErrors :: [EnvBinding] -> [EnvError]
bindingErrors values =
  [ InvalidEnvironmentName name
  | bindingValue <- values,
    let name = bindingValue ^. #name,
    not (validEnvName name)
  ]
    <> fmap DuplicateEnvironmentName (duplicates (fmap (^. #name) values))
    <> fmap DuplicateTargetKey (duplicates (fmap (^. #key) values))
    <> overlapErrors (fmap (^. #key) values)

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
    -- 'Bindings' construction rejects prefix-overlapping target keys, so by the time this
    -- fold runs, no path can descend through a previously written leaf. This branch is
    -- unreachable by construction and exists only to satisfy exhaustiveness honestly.
    go _ _ = error "validated environment keys cannot overlap"

-- | Inspect validated bindings without reading any environment values.
-- Adapter-owned variable identity wins over caller annotations, as in envSource.
inputBindings :: Bindings -> [InputBinding]
inputBindings = fmap convert . bindingsList
  where
    convert bindingValue =
      let variable = renderEnvName (bindingName bindingValue)
       in annotateInputBinding
            (Map.singleton "environment.variable" variable <> bindingAnnotations bindingValue)
            (inputBinding EnvironmentVariable variable (bindingKey bindingValue))
