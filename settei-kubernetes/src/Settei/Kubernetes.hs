{-# LANGUAGE ImportQualifiedPost #-}

-- |
-- Module: Settei.Kubernetes
-- Description: Kubernetes mounted-directory sources for Settei.
--
-- Kubernetes ConfigMap and Secret volumes normally appear as a directory with one
-- visible file per object key. Kubelet's atomic writer implements those files as
-- symlinks through a hidden @..data@ directory; this module reads the visible names and
-- follows those links, while 'unboundMountedFiles' ignores the hidden writer entries.
-- File names are bound explicitly because Kubernetes data keys commonly contain dots,
-- which must not be confused with Settei's structural dotted-key syntax.
--
-- By default one trailing newline is removed from every decoded UTF-8 value. Use
-- 'keepTrailingNewline' for byte-faithful text. A single-file @subPath@ mount can use a
-- format adapter such as @settei-yaml@, or a one-entry 'FileBindings' value here.
--
-- A typical Secret mount can be loaded as follows:
--
-- @
-- passwordKey <- either fail pure (parseKey "database.password")
-- validated <- either (fail . show) pure (fileBindings [fileBinding "password" passwordKey])
-- let reference = kubernetesRef SecretObject (Just "prod") "app-credentials" Nothing
-- readMountedDirectorySource
--   (mountedDirectoryOptions "app-secrets" reference)
--   validated
--   "/etc/app-secrets"
-- @
module Settei.Kubernetes
  ( FileBinding,
    FileBindings,
    KubernetesErrorCategory (..),
    KubernetesSourceError,
    MountedDirectoryOptions,
    annotateFileBinding,
    annotateMountedDirectoryOptions,
    fileBinding,
    fileBindingAnnotations,
    fileBindingKey,
    fileBindingName,
    fileBindings,
    fileBindingsList,
    keepTrailingNewline,
    kubernetesErrorCategory,
    kubernetesErrorMessage,
    kubernetesErrorName,
    kubernetesErrorPath,
    mountedDirectoryAnnotations,
    mountedDirectoryKeepsTrailingNewline,
    mountedDirectoryName,
    mountedDirectoryOptions,
    mountedDirectoryRef,
    readMountedDirectorySource,
    renderKubernetesErrorText,
    renderKubernetesErrorsText,
    unboundMountedFiles,
  )
where

import Control.Exception (IOException, displayException, try)
import Data.ByteString qualified as ByteString
import Data.Generics.Labels ()
import Data.List (sort)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time.Clock (UTCTime, getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Settei
import Settei.Prelude
import System.Directory qualified as Directory
import System.FilePath ((</>))
import System.IO.Error qualified as IOError

-- | One explicit mapping from a visible mounted file to a structural Settei key.
data FileBinding = FileBinding
  { fileName :: !Text,
    key :: !Key,
    annotations :: !(Map Text Text)
  }
  deriving stock (Generic, Eq)

-- | A collection of file bindings proven valid at construction.
--
-- The constructor is private. 'fileBindings' rejects invalid or reserved names,
-- duplicates, and target keys whose tree positions overlap.
newtype FileBindings = ValidatedFileBindings [FileBinding]
  deriving stock (Eq)

-- | Stable classes of mounted-directory and binding failure.
--
-- No constructor retains raw file content.
data KubernetesErrorCategory
  = KubernetesInvalidFileName
  | KubernetesDuplicateFileName
  | KubernetesDuplicateTargetKey
  | KubernetesConflictingTargetKeys
  | KubernetesNotADirectory
  | KubernetesIoError
  | KubernetesInvalidUtf8
  deriving stock (Generic, Eq, Ord, Show)

-- | A secret-safe mounted-directory input failure.
data KubernetesSourceError = KubernetesSourceError
  { category :: !KubernetesErrorCategory,
    name :: !(Maybe Text),
    path :: !(Maybe FilePath),
    message :: !Text
  }
  deriving stock (Generic, Eq, Show)

-- | Naming, provenance, annotations, and text policy for one mounted directory.
--
-- The optional key already present in the 'KubernetesRef' is ignored: each present
-- mounted file supplies its own @kubernetes.object-key@ annotation.
data MountedDirectoryOptions = MountedDirectoryOptions
  { name :: !Text,
    ref :: !KubernetesRef,
    annotations :: !(Map Text Text),
    keepsTrailingNewline :: !Bool
  }
  deriving stock (Generic, Eq)

-- | Construct one file binding with no caller annotations.
fileBinding :: Text -> Key -> FileBinding
fileBinding fileName key = FileBinding {fileName, key, annotations = Map.empty}

-- | Add trusted descriptive metadata to one binding.
--
-- Adapter-owned @kubernetes.*@ annotations take precedence on name collisions.
annotateFileBinding :: Map Text Text -> FileBinding -> FileBinding
annotateFileBinding annotations bindingValue =
  bindingValue & #annotations %~ (annotations <>)

-- | Return the visible mounted file name.
fileBindingName :: FileBinding -> Text
fileBindingName value = value ^. #fileName

-- | Return the structural Settei key targeted by a binding.
fileBindingKey :: FileBinding -> Key
fileBindingKey value = value ^. #key

-- | Return trusted annotations supplied by the caller.
fileBindingAnnotations :: FileBinding -> Map Text Text
fileBindingAnnotations value = value ^. #annotations

-- | Validate a static binding list, accumulating every independent problem.
--
-- An empty list is valid and produces a source with no leaves.
fileBindings :: [FileBinding] -> Either (NonEmpty KubernetesSourceError) FileBindings
fileBindings values =
  case NonEmpty.nonEmpty (bindingErrors values) of
    Just errors -> Left errors
    Nothing -> Right (ValidatedFileBindings values)

-- | Inspect validated bindings without exposing the collection constructor.
fileBindingsList :: FileBindings -> [FileBinding]
fileBindingsList (ValidatedFileBindings values) = values

-- | Start options for one asserted Kubernetes object and stable source name.
mountedDirectoryOptions :: Text -> KubernetesRef -> MountedDirectoryOptions
mountedDirectoryOptions name ref =
  MountedDirectoryOptions
    { name,
      ref,
      annotations = Map.empty,
      keepsTrailingNewline = False
    }

-- | Add trusted source-wide annotations.
annotateMountedDirectoryOptions :: Map Text Text -> MountedDirectoryOptions -> MountedDirectoryOptions
annotateMountedDirectoryOptions annotations options =
  options & #annotations %~ (annotations <>)

-- | Preserve file text verbatim instead of removing one trailing newline.
keepTrailingNewline :: MountedDirectoryOptions -> MountedDirectoryOptions
keepTrailingNewline options = options & #keepsTrailingNewline .~ True

-- | Return the stable source name used in reports.
mountedDirectoryName :: MountedDirectoryOptions -> Text
mountedDirectoryName options = options ^. #name

-- | Return the asserted Kubernetes object reference.
mountedDirectoryRef :: MountedDirectoryOptions -> KubernetesRef
mountedDirectoryRef options = options ^. #ref

-- | Return caller-supplied source-wide annotations.
mountedDirectoryAnnotations :: MountedDirectoryOptions -> Map Text Text
mountedDirectoryAnnotations options = options ^. #annotations

-- | Report whether trailing newlines are preserved.
mountedDirectoryKeepsTrailingNewline :: MountedDirectoryOptions -> Bool
mountedDirectoryKeepsTrailingNewline options = options ^. #keepsTrailingNewline

-- | Return an error's stable category.
kubernetesErrorCategory :: KubernetesSourceError -> KubernetesErrorCategory
kubernetesErrorCategory problem = problem ^. #category

-- | Return the source name associated with an error, when construction reached a source.
kubernetesErrorName :: KubernetesSourceError -> Maybe Text
kubernetesErrorName problem = problem ^. #name

-- | Return the mounted directory or file path associated with an error, when known.
kubernetesErrorPath :: KubernetesSourceError -> Maybe FilePath
kubernetesErrorPath problem = problem ^. #path

-- | Return the concise secret-safe error message.
kubernetesErrorMessage :: KubernetesSourceError -> Text
kubernetesErrorMessage problem = problem ^. #message

-- | Read explicitly bound UTF-8 values from a projected-volume directory.
--
-- Visible file symlinks are followed normally. Bound files that do not exist contribute
-- no leaf. All other I/O and UTF-8 failures are accumulated, and no raw content enters
-- an error. Each present leaf receives its exact file path and Kubernetes object/key
-- annotations. Source-wide annotations retain the requested mount path and read time;
-- each present key also records the modification time of the file that was read.
readMountedDirectorySource ::
  MountedDirectoryOptions ->
  FileBindings ->
  FilePath ->
  IO (Either (NonEmpty KubernetesSourceError) Source)
readMountedDirectorySource options (ValidatedFileBindings bindingsValue) directory = do
  isDirectory <- Directory.doesDirectoryExist directory
  if not isDirectory
    then pure (Left (NonEmpty.singleton (notDirectoryError options directory)))
    else do
      readAt <- getCurrentTime
      outcomes <- traverse (readBinding options directory) bindingsValue
      let errors = [problem | Left problem <- outcomes]
          present = [value | Right (Just value) <- outcomes]
      pure $ case NonEmpty.nonEmpty errors of
        Just found -> Left found
        Nothing -> Right (buildSource options directory readAt present)

-- | List visible mounted entries that have no explicit binding.
--
-- Hidden atomic-writer entries beginning with @..@ are omitted without being statted or
-- traversed. Directory-listing 'IOException's propagate. This helper is intended for a
-- deliberate startup diagnostic rather than source construction.
unboundMountedFiles :: FileBindings -> FilePath -> IO [Text]
unboundMountedFiles (ValidatedFileBindings bindingsValue) directory = do
  entries <- fmap Text.pack <$> Directory.listDirectory directory
  let boundNames = Map.fromList [(bindingValue ^. #fileName, ()) | bindingValue <- bindingsValue]
  pure
    ( sort
        [ entry
        | entry <- entries,
          not (".." `Text.isPrefixOf` entry),
          Map.notMember entry boundNames
        ]
    )

-- | Render one mounted-directory failure as a single operator-readable line.
renderKubernetesErrorText :: KubernetesSourceError -> Text
renderKubernetesErrorText problem =
  prefix <> problem ^. #message
  where
    prefix = case (problem ^. #name, problem ^. #path) of
      (Just mountedName, Just sourcePath) ->
        mountedName <> " (" <> Text.pack sourcePath <> "): "
      (Just mountedName, Nothing) -> mountedName <> ": "
      (Nothing, Just sourcePath) -> Text.pack sourcePath <> ": "
      (Nothing, Nothing) -> "file bindings: "

-- | Render every mounted-directory failure, one line per problem and a trailing newline.
renderKubernetesErrorsText :: NonEmpty KubernetesSourceError -> Text
renderKubernetesErrorsText =
  Text.unlines . fmap renderKubernetesErrorText . NonEmpty.toList

type PresentBinding = (FileBinding, Text, FilePath, UTCTime)

readBinding ::
  MountedDirectoryOptions ->
  FilePath ->
  FileBinding ->
  IO (Either KubernetesSourceError (Maybe PresentBinding))
readBinding options directory bindingValue = do
  let filePath = directory </> Text.unpack (bindingValue ^. #fileName)
  result <-
    try @IOException $ do
      bytes <- ByteString.readFile filePath
      modifiedAt <- Directory.getModificationTime filePath
      pure (bytes, modifiedAt)
  pure $ case result of
    Left exception
      | IOError.isDoesNotExistError exception -> Right Nothing
      | otherwise ->
          Left
            ( sourceError
                options
                KubernetesIoError
                (Just filePath)
                (Text.pack (displayException exception))
            )
    Right (bytes, modifiedAt) -> case TextEncoding.decodeUtf8' bytes of
      Left _ ->
        Left
          ( sourceError
              options
              KubernetesInvalidUtf8
              (Just filePath)
              "file content is not valid UTF-8"
          )
      Right decoded ->
        Right
          ( Just
              ( bindingValue,
                applyNewlinePolicy options decoded,
                filePath,
                modifiedAt
              )
          )

applyNewlinePolicy :: MountedDirectoryOptions -> Text -> Text
applyNewlinePolicy options value
  | options ^. #keepsTrailingNewline = value
  | otherwise = fromMaybe value (Text.stripSuffix "\n" value)

buildSource :: MountedDirectoryOptions -> FilePath -> UTCTime -> [PresentBinding] -> Source
buildSource options directory readAt present =
  annotateSource freshnessAnnotations
    . annotateSource (options ^. #annotations)
    . annotateSourceAt freshnessFor
    . annotateSourceAt annotationsFor
    . locateSource locationFor
    $ source
      (options ^. #name)
      (CustomSource "kubernetes-mounted-directory")
      root
  where
    root =
      foldl
        (\tree (bindingValue, value, _, _) -> insertRawValue (bindingValue ^. #key) (RawText value) tree)
        (RawObject Map.empty)
        present
    locations =
      Map.fromList
        [ ( bindingValue ^. #key,
            SourceLocation
              { path = Text.pack filePath,
                line = Nothing,
                column = Nothing
              }
          )
        | (bindingValue, _, filePath, _) <- present
        ]
    annotationsByKey =
      Map.fromList
        [ ( bindingValue ^. #key,
            kubernetesAnnotations (options ^. #ref & #key .~ Just (bindingValue ^. #fileName))
              <> bindingValue ^. #annotations
          )
        | (bindingValue, _, _, _) <- present
        ]
    modifiedByKey =
      Map.fromList
        [ (bindingValue ^. #key, modifiedAt)
        | (bindingValue, _, _, modifiedAt) <- present
        ]
    freshnessAnnotations =
      Map.fromList
        [ ("kubernetes.mount-path", Text.pack directory),
          ("kubernetes.read-at", renderUtcTime readAt)
        ]
    locationFor target = Map.lookup target locations
    annotationsFor target = Map.findWithDefault Map.empty target annotationsByKey
    freshnessFor target =
      maybe
        Map.empty
        (Map.singleton "kubernetes.file-modified" . renderUtcTime)
        (Map.lookup target modifiedByKey)

renderUtcTime :: UTCTime -> Text
renderUtcTime = Text.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"

bindingErrors :: [FileBinding] -> [KubernetesSourceError]
bindingErrors values =
  [ bindingError
      KubernetesInvalidFileName
      ("file name " <> quoted fileName <> " contains a path separator or is reserved")
  | bindingValue <- values,
    let fileName = bindingValue ^. #fileName,
    not (validFileName fileName)
  ]
    <> fmap duplicateFileNameError (duplicates (fmap (^. #fileName) values))
    <> fmap duplicateTargetKeyError (duplicates (fmap (^. #key) values))
    <> overlapErrors (fmap (^. #key) values)

validFileName :: Text -> Bool
validFileName value =
  not (Text.null value)
    && not (Text.any (\character -> character == '/' || character == '\NUL') value)
    && value /= "."
    && not (".." `Text.isPrefixOf` value)

duplicates :: (Ord a) => [a] -> [a]
duplicates values =
  Map.keys (Map.filter (> (1 :: Int)) (Map.fromListWith (+) [(value, 1) | value <- values]))

overlapErrors :: [Key] -> [KubernetesSourceError]
overlapErrors keys =
  [ bindingError
      KubernetesConflictingTargetKeys
      ("target keys " <> renderKey lower <> " and " <> renderKey higher <> " overlap")
  | (positionIndex, lower) <- zip [0 :: Int ..] keys,
    higher <- drop (positionIndex + 1) keys,
    lower /= higher,
    isPrefixKey lower higher || isPrefixKey higher lower
  ]

duplicateFileNameError :: Text -> KubernetesSourceError
duplicateFileNameError fileName =
  bindingError
    KubernetesDuplicateFileName
    ("file name " <> quoted fileName <> " is bound more than once")

duplicateTargetKeyError :: Key -> KubernetesSourceError
duplicateTargetKeyError target =
  bindingError
    KubernetesDuplicateTargetKey
    ("target key " <> renderKey target <> " is bound more than once")

bindingError :: KubernetesErrorCategory -> Text -> KubernetesSourceError
bindingError category message =
  KubernetesSourceError
    { category,
      name = Nothing,
      path = Nothing,
      message
    }

notDirectoryError :: MountedDirectoryOptions -> FilePath -> KubernetesSourceError
notDirectoryError options directory =
  sourceError
    options
    KubernetesNotADirectory
    (Just directory)
    "mounted path is not a directory"

sourceError ::
  MountedDirectoryOptions ->
  KubernetesErrorCategory ->
  Maybe FilePath ->
  Text ->
  KubernetesSourceError
sourceError options category path message =
  KubernetesSourceError
    { category,
      name = Just (options ^. #name),
      path,
      message
    }

quoted :: Text -> Text
quoted value = "\"" <> value <> "\""

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
            . fromMaybe (RawObject Map.empty)
        )
    go _ _ = error "validated file-binding keys cannot overlap"
