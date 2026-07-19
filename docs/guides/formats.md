# Tagged multi-format configuration

Use `settei-formats` when an application accepts YAML, KDL, and Dhall files through one
ordered `--config FORMAT:PATH` option. The package parses the explicit format tag and
dispatches each input to the matching Settei adapter, so applications do not need to
duplicate that policy.

Applications that support only one format should depend on that adapter directly. The
umbrella package is for applications that deliberately offer all three formats.

## Add the dependency

```cabal
build-depends:
  , containers
  , optparse-applicative
  , settei
  , settei-dhall
  , settei-formats
  , text
```

`settei-formats` already depends on the YAML, KDL, and Dhall adapters. The direct
`settei-dhall` dependency above is needed only when application code names
`DhallImportPolicy` constructors such as `LocalImportsWithin`.

## Accept tagged inputs

`configInputOptions` parses zero or more `--config FORMAT:PATH` occurrences and preserves
their order. It accepts only the lowercase tags `yaml`, `kdl`, and `dhall`:

```text
--config yaml:config/base.yaml
--config kdl:config/local.kdl
--config dhall:config/application.dhall
```

Add the parser to the application's configuration option group:

```haskell
import Options.Applicative qualified as Options
import Settei.Formats (ConfigInput)
import Settei.Formats.Optparse (configInputOptions)

configInputs :: Options.Parser [ConfigInput]
configInputs =
  Options.parserOptionGroup "Configuration" configInputOptions
```

Parsing does not open a file. A missing colon or empty path reports
`expected FORMAT:PATH`; an unsupported tag reports
`FORMAT must be yaml, kdl, or dhall`. Use `configInputOption` when the application needs
a different long name, metavar, or help text.

## Load tagged inputs

`loadConfigInput` returns a structured `FormatLoadError` while retaining the originating
adapter errors. Load the parsed inputs in occurrence order, then place the resulting
sources at the intended point in the application's low-to-high precedence list:

```haskell
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Settei
  ( KubernetesObjectKind (ConfigMapObject),
    KubernetesRef,
    Source,
    kubernetesRef,
  )
import Settei.Dhall qualified as Dhall
import Settei.Formats
import Settei.Prelude ((&))

loadInputs
  :: LoadOptions
  -> [ConfigInput]
  -> IO (Either (NonEmpty FormatLoadError) [Source])
loadInputs options inputs = do
  loaded <- traverse (loadConfigInput options) inputs
  pure (sequence loaded)

mountedOptions :: FilePath -> LoadOptions
mountedOptions allowedDhallDirectory =
  defaultLoadOptions
    & annotateLoadOptions (Map.singleton "deployment" "production")
    & fromKubernetesMountedFile mountedReference
    & withDhallImportPolicy
        (Dhall.LocalImportsWithin allowedDhallDirectory)

mountedReference :: KubernetesRef
mountedReference =
  kubernetesRef
    ConfigMapObject
    Nothing
    "my-service"
    (Just "application.yaml")

renderLoadErrors :: NonEmpty FormatLoadError -> Text
renderLoadErrors =
  Text.intercalate "\n"
    . fmap renderFormatLoadErrorText
    . NonEmpty.toList
```

`annotateLoadOptions` adds trusted, secret-safe origin metadata to every produced
`Source`. `fromKubernetesMountedFile` adds the stable Kubernetes object annotations used
by reports; it does not contact a cluster. YAML and KDL use their mounted-file helpers,
while Dhall receives the same annotations through its source options.

`defaultLoadOptions` always selects `Dhall.NoImports`. A general-purpose loader must not
silently widen its file-read capability just because the input tag is `dhall`. If an
application needs local imports, opt in with
`withDhallImportPolicy (Dhall.LocalImportsWithin directory)` and name the allowed
directory explicitly.

The [CLI application](cli-application.md) and
[Kubernetes service](kubernetes-service.md) guides currently show the dispatch policy in
full so each adapter call remains visible. The reference applications adopt this package
and remove that duplicated code in
[EP-21](../plans/21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md).
