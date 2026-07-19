{-# LANGUAGE ImportQualifiedPost #-}

-- |
-- Module: Settei.Formats
-- Description: Tagged multi-format configuration inputs and a shared adapter loader.
module Settei.Formats
  ( ConfigFormat (..),
    ConfigInput,
    FormatLoadError (..),
    LoadOptions,
    annotateLoadOptions,
    configInput,
    configInputFormat,
    configInputPath,
    defaultLoadOptions,
    fromKubernetesMountedFile,
    loadConfigInput,
    loadOptionsAnnotations,
    loadOptionsDhallImportPolicy,
    loadOptionsKubernetesRef,
    parseConfigInput,
    renderFormatLoadErrorText,
    withDhallImportPolicy,
  )
where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Settei
import Settei.Dhall qualified as Dhall
import Settei.Kdl qualified as Kdl
import Settei.Prelude
import Settei.Yaml qualified as Yaml

-- | Explicit format tag required for each configuration input.
data ConfigFormat = YamlFormat | KdlFormat | DhallFormat
  deriving stock (Generic, Eq, Ord, Show)

-- | One ordered, explicitly tagged configuration file.
data ConfigInput = ConfigInput
  { format :: !ConfigFormat,
    path :: !FilePath
  }
  deriving stock (Generic, Eq, Show)

-- | Construct a tagged input programmatically.
configInput :: ConfigFormat -> FilePath -> ConfigInput
configInput format path = ConfigInput {format, path}

-- | Return an input's explicit adapter tag.
configInputFormat :: ConfigInput -> ConfigFormat
configInputFormat value = value ^. #format

-- | Return an input's filesystem path.
configInputPath :: ConfigInput -> FilePath
configInputPath value = value ^. #path

-- | Parse the @FORMAT:PATH@ grammar: @yaml:PATH@, @kdl:PATH@, or @dhall:PATH@.
--
-- A missing colon or an empty path fails with @expected FORMAT:PATH@. Any other
-- format name, including an empty one as in @:app.yaml@, fails with
-- @FORMAT must be yaml, kdl, or dhall@.
parseConfigInput :: String -> Either String ConfigInput
parseConfigInput input =
  let (formatName, separatorAndPath) = break (== ':') input
      filePath = drop 1 separatorAndPath
   in if null separatorAndPath || null filePath
        then Left "expected FORMAT:PATH"
        else case formatName of
          "yaml" -> Right (configInput YamlFormat filePath)
          "kdl" -> Right (configInput KdlFormat filePath)
          "dhall" -> Right (configInput DhallFormat filePath)
          _ -> Left "FORMAT must be yaml, kdl, or dhall"

-- | How loaded sources should be annotated and how Dhall imports are policed.
data LoadOptions = LoadOptions
  { kubernetesReference :: !(Maybe KubernetesRef),
    annotations :: !(Map Text Text),
    dhallImportPolicy :: !Dhall.DhallImportPolicy
  }
  deriving stock (Generic)

-- | No Kubernetes reference, no extra annotations, and @NoImports@ for Dhall.
--
-- The Dhall default is deliberately the most restrictive policy: a loader must
-- never follow filesystem imports unless the caller explicitly names an allowed
-- directory with 'withDhallImportPolicy'.
defaultLoadOptions :: LoadOptions
defaultLoadOptions =
  LoadOptions
    { kubernetesReference = Nothing,
      annotations = Map.empty,
      dhallImportPolicy = Dhall.NoImports
    }

-- | Attach a trusted Kubernetes reference for a mounted file. No cluster lookup occurs.
fromKubernetesMountedFile :: KubernetesRef -> LoadOptions -> LoadOptions
fromKubernetesMountedFile reference options =
  options & #kubernetesReference ?~ reference

-- | Add trusted, secret-safe annotations to every loaded source.
annotateLoadOptions :: Map Text Text -> LoadOptions -> LoadOptions
annotateLoadOptions extra options = options & #annotations %~ (extra <>)

-- | Replace the Dhall import policy (default 'Dhall.NoImports').
withDhallImportPolicy :: Dhall.DhallImportPolicy -> LoadOptions -> LoadOptions
withDhallImportPolicy policy options = options & #dhallImportPolicy .~ policy

-- | Return the optional mounted-file Kubernetes reference.
loadOptionsKubernetesRef :: LoadOptions -> Maybe KubernetesRef
loadOptionsKubernetesRef value = value ^. #kubernetesReference

-- | Return caller-supplied trusted annotations.
loadOptionsAnnotations :: LoadOptions -> Map Text Text
loadOptionsAnnotations value = value ^. #annotations

-- | Return the enforced Dhall import policy.
loadOptionsDhallImportPolicy :: LoadOptions -> Dhall.DhallImportPolicy
loadOptionsDhallImportPolicy value = value ^. #dhallImportPolicy

-- | One failed tagged load, wrapping the originating adapter's full error list.
data FormatLoadError
  = YamlLoadError !(NonEmpty Yaml.YamlSourceError)
  | KdlLoadError !(NonEmpty Kdl.KdlSourceError)
  | DhallLoadError !(NonEmpty Dhall.DhallSourceError)
  deriving stock (Generic, Eq, Show)

-- | Load one tagged input through the adapter its format names.
loadConfigInput ::
  LoadOptions ->
  ConfigInput ->
  IO (Either (NonEmpty FormatLoadError) Source)
loadConfigInput options input =
  let sourceLabel = Text.pack (input ^. #path)
      wrap wrapError = either (Left . NonEmpty.singleton . wrapError) Right
      kubernetesAnnotationsOf =
        maybe Map.empty kubernetesAnnotations (options ^. #kubernetesReference)
   in case input ^. #format of
        YamlFormat ->
          let yamlOptions =
                Yaml.annotateYamlSourceOptions
                  (options ^. #annotations)
                  ( maybe
                      id
                      Yaml.fromKubernetesMountedFile
                      (options ^. #kubernetesReference)
                      (Yaml.yamlSourceOptions sourceLabel)
                  )
           in wrap YamlLoadError <$> Yaml.readYamlSource yamlOptions (input ^. #path)
        KdlFormat ->
          let kdlOptions =
                Kdl.annotateKdlSourceOptions
                  (options ^. #annotations)
                  ( maybe
                      id
                      Kdl.fromKubernetesMountedFile
                      (options ^. #kubernetesReference)
                      (Kdl.kdlSourceOptions sourceLabel)
                  )
           in wrap KdlLoadError <$> Kdl.readKdlSource kdlOptions (input ^. #path)
        DhallFormat ->
          let dhallOptions =
                Dhall.annotateDhallSourceOptions
                  (kubernetesAnnotationsOf <> options ^. #annotations)
                  ( Dhall.dhallSourceOptions
                      sourceLabel
                      (options ^. #dhallImportPolicy)
                  )
           in wrap DhallLoadError
                <$> Dhall.loadDhallSource dhallOptions (Dhall.DhallFile (input ^. #path))

-- TODO(EP-17): replace Show-based rendering with the per-adapter
-- render<Adapter>ErrorText renderers once
-- docs/plans/17-add-error-renderers-to-every-source-adapter.md lands.

-- | Render one adapter load failure for operator-facing output.
renderFormatLoadErrorText :: FormatLoadError -> Text
renderFormatLoadErrorText = \case
  YamlLoadError problems -> Text.pack (show (NonEmpty.toList problems))
  KdlLoadError problems -> Text.pack (show (NonEmpty.toList problems))
  DhallLoadError problems -> Text.pack (show (NonEmpty.toList problems))
