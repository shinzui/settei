# YAML configuration

Use `settei-yaml` to load a YAML mapping as a provenance-aware `Source`. YAML supplies
the structural values; the application's core `Config` declaration still owns decoding,
defaults, sensitivity, and precedence.

## Add the package

```cabal
build-depends:
  , bytestring
  , settei
  , settei-yaml
  , text
```

```haskell
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Settei
import Settei.Yaml
```

## Write a supported YAML document

A configuration file contains one top-level mapping. Use nested mappings for dotted
Settei keys:

```yaml
runtime:
  environment: production

service:
  host: api.internal
  port: 8080
  names:
    - public
    - health
```

This document supplies `runtime.environment`, `service.host`, `service.port`, and
`service.names`.

Do not write dotted mapping keys:

```yaml
# Rejected: the dot is not treated as nesting.
service.port: 8080
```

## Load a file

Use `readYamlSource` at the executable's IO boundary:

```haskell
loadYaml :: FilePath -> IO (Either (NonEmpty YamlSourceError) Source)
loadYaml path =
  readYamlSource (yamlSourceOptions "application configuration") path
```

The source name appears in reports and should be stable and safe to display. The file path
passed to `readYamlSource` is retained in successful origins and structured errors. It
replaces any path already attached to the options.

If the application already has strict `ByteString` input, use the pure decoder and attach
a logical path when useful:

```haskell
decodeGeneratedYaml
  :: ByteString
  -> Either (NonEmpty YamlSourceError) Source
decodeGeneratedYaml =
  decodeYamlSource
    ( withYamlSourcePath
        "generated/application.yaml"
        (yamlSourceOptions "generated configuration")
    )
```

Use `decodeYamlSource` in parser tests and when another trusted component owns the IO. Use
`readYamlSource` when Settei should distinguish file IO failures as `YamlIoError`.

## Declare decoders and resolve the source

The declaration is independent of YAML:

```haskell
data ServiceConfig = ServiceConfig
  { host :: !Text,
    port :: !Int,
    names :: ![Text]
  }
  deriving stock (Eq)

serviceConfig :: Config ServiceConfig
serviceConfig =
  ServiceConfig
    <$> required (publicSetting (validKey "service.host") "Service host" textDecoder)
    <*> required (publicSetting (validKey "service.port") "Service port" boundedIntegralDecoder)
    <*> required (publicSetting (validKey "service.names") "Service names" textListDecoder)

textListDecoder :: Decoder [Text]
textListDecoder = decoder $ \targetKey -> \case
  RawArray values -> traverse (textElement targetKey) values
  _ -> Left (decodeFailure targetKey "an array of text")

textElement :: Key -> RawValue -> Either DecodeFailure Text
textElement targetKey = \case
  RawText value -> Right value
  _ -> Left (decodeFailure targetKey "an array of text")

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
```

Load errors and resolution errors are separate:

```haskell
resolveYamlFile
  :: FilePath
  -> IO (Either Text (ResolveResult ServiceConfig))
resolveYamlFile path = do
  loaded <- loadYaml path
  pure $ do
    yamlSource <- first renderYamlErrors loaded
    first renderErrorsText
      (resolve defaultResolveOptions [yamlSource] serviceConfig)
```

Keeping the phases separate lets a CLI assign distinct exit codes to unreadable or
malformed files and to typed configuration failures.

## Layer multiple files

Pass sources from lowest to highest precedence:

```haskell
resolveFiles
  :: Source
  -> Source
  -> Either (NonEmpty ConfigError) (ResolveResult ServiceConfig)
resolveFiles shared local =
  resolve defaultResolveOptions [shared, local] serviceConfig
```

If `shared` supplies `service.host` and `service.port`, while `local` supplies only
`service.port`, the shared host remains and the local port wins. Arrays are values rather
than mergeable collections, so a higher `service.names` array replaces the lower array in
full.

File discovery is application policy. Load one conventional path, accept repeated config
arguments, or implement another documented strategy. When combined with other adapters,
a common order is:

```haskell
orderedSources = yamlSources <> [environmentSource] <> commandLineSources
```

See [Environment and command-line configuration](environment-and-cli.md) for the later
layers.

## Understand YAML-to-Settei values

| YAML input | `RawValue` |
| --- | --- |
| string | `RawText` |
| boolean | `RawBool` |
| finite integer or decimal | exact `RawNumber` |
| `null`, `~`, or an empty plain scalar | `RawNull` |
| sequence | `RawArray` |
| mapping | `RawObject` |

Plain boolean spellings `y`, `yes`, `on`, `true`, `n`, `no`, `off`, and `false` are
recognized case-insensitively. Quote a word when the application needs text instead:

```yaml
featureLabel: "on"
```

Quoted and block scalars always remain text. Plain decimal and exponent numbers, `0x`
hexadecimal integers, and `0o` octal integers become exact rational values. Large
integers do not pass through a machine `Int`; the eventual decoder decides whether a
number fits its application type. A number whose base-10 exponent magnitude exceeds 4096
is rejected as `YamlInvalidScalar`, preventing one scalar from exhausting memory at load
time while comfortably covering practical configuration values. `.inf`, `-.inf`, and
`.nan` are rejected.

An explicit null is present input. It shadows lower-precedence candidates and reaches the
setting decoder as `RawNull`. It does not behave like an omitted key. Use a custom decoder
if null has an application-specific meaning.

YAML sequences can represent zero, one, or many elements. A higher-precedence sequence
replaces the previous sequence instead of merging element by element.

## Supported document rules

The adapter accepts an empty document or top-level null as an empty source. Otherwise it
requires exactly one top-level mapping. It rejects:

- multiple YAML documents;
- a top-level scalar or sequence;
- duplicate keys, including duplicates in flow mappings;
- non-string or dotted mapping keys;
- anchors, aliases, and merge keys;
- custom scalar or collection tags;
- invalid and non-finite numeric values;
- malformed syntax; and
- invalid UTF-8.

Strings are literal. `${NAME}` is not interpolated and loading YAML never reads the
process environment.

## Render YAML errors

`YamlSourceError` exposes stable fields for application diagnostics:

```haskell
renderYamlErrors :: NonEmpty YamlSourceError -> Text
renderYamlErrors =
  Text.intercalate "\n"
    . fmap renderYamlError
    . NonEmpty.toList

renderYamlError :: YamlSourceError -> Text
renderYamlError problem =
  Text.intercalate
    ": "
    [ Text.pack (show (yamlErrorCategory problem)),
      yamlErrorContext problem,
      yamlErrorMessage problem
    ]
```

Use `yamlErrorPath`, `yamlErrorLine`, and `yamlErrorColumn` to add a location when present.
Lines and columns are one-based. `yamlErrorContext` names a structural path such as
`$.service.names[0]`.

Successful scalar and array leaves also retain a one-based start location for resolution
reports. Adapter errors intentionally do not expose raw source excerpts or scalar values,
because parsing happens before a setting's sensitivity is known.

## Load a mounted ConfigMap or Secret

Attach Kubernetes delivery metadata when the application knows the mounted file's origin:

```haskell
mountedYamlOptions :: YamlSourceOptions
mountedYamlOptions =
  fromKubernetesMountedFile
    ( kubernetesRef
        ConfigMapObject
        (Just "production")
        "service-config"
        (Just "application.yaml")
    )
    (yamlSourceOptions "mounted application configuration")

loadMountedYaml :: IO (Either (NonEmpty YamlSourceError) Source)
loadMountedYaml =
  readYamlSource mountedYamlOptions "/etc/service/application.yaml"
```

The reference is trusted descriptive metadata; no Kubernetes API request is made. It may
appear in reports, so keep names and custom annotations safe to display. Mark every
sensitive application key with `secretSetting` regardless of whether its file was mounted
from a Secret.

## Production checklist

- Validate files with the same declaration used by the running application.
- Document the low-to-high order when more than one file is accepted.
- Quote boolean-like or numeric-looking values that must remain text.
- Treat null as explicit input and test the chosen decoder behavior.
- Render structured adapter fields instead of echoing the original YAML.
- Reject or report unknown keys according to the application's rollout policy.
- Use `fromKubernetesMountedFile` only for metadata the deployment actually guarantees.

See [Building a CLI application](cli-application.md) for file-option handling and
[Building a Kubernetes service](kubernetes-service.md) for a mounted-file deployment.
