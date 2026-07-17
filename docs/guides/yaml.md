# YAML configuration

`settei-yaml` translates one strict YAML mapping into a provenance-aware Settei
`Source`. It only translates input: the core `Setting` declarations decode application
types, and the application decides which files to discover and where each source belongs
in the precedence order.

The accepted subset is intentionally smaller than general YAML. Ambiguous features fail
at the input boundary instead of being interpreted differently by another tool.


## Load one document

This document supplies three structural keys: `service.host`, `service.port`, and
`service.names`.

```yaml
service:
  host: api.internal
  port: 8080
  names:
    - public
    - health
```

Use `readYamlSource` at an IO boundary. The source name is a stable label for reports;
the path supplied to `readYamlSource` is retained in successful origins and errors.

```haskell
import Data.ByteString (ByteString)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Settei
import Settei.Prelude
import Settei.Yaml

loadApplicationYaml :: FilePath -> IO (Either Text Source)
loadApplicationYaml path = do
  loaded <- readYamlSource (yamlSourceOptions "application YAML") path
  pure (either (Left . renderYamlErrors) Right loaded)

renderYamlErrors :: NonEmpty YamlSourceError -> Text
renderYamlErrors =
  Text.intercalate "\n"
    . fmap
      ( \problem ->
          Text.intercalate
            ": "
            [ Text.pack (show (yamlErrorCategory problem)),
              yamlErrorContext problem,
              yamlErrorMessage problem
            ]
      )
    . NonEmpty.toList
```

For bytes already obtained by the application, use `decodeYamlSource`. A logical or real
path can still be attached for provenance:

```haskell
options :: YamlSourceOptions
options =
  withYamlSourcePath
    "generated/application.yaml"
    (yamlSourceOptions "generated YAML")

translated :: ByteString -> Either (NonEmpty YamlSourceError) Source
translated = decodeYamlSource options
```

`yamlSourceOptions` has no implicit path or annotations. `readYamlSource` always replaces
an option's existing path with the path it actually reads.


## Declare types and resolve ordered files

YAML scalar inference produces `RawText`, `RawBool`, `RawNumber`, or `RawNull`; sequences
produce `RawArray`, and mappings produce `RawObject`. Application decoders remain in the
core declaration:

```haskell
data ServiceConfig = ServiceConfig
  { host :: !Text,
    port :: !Int,
    names :: ![Text]
  }
  deriving stock (Generic, Eq)

serviceConfig :: Config ServiceConfig
serviceConfig =
  ServiceConfig
    <$> required (publicSetting (validKey "service.host") "Service host" textDecoder)
    <*> required (publicSetting (validKey "service.port") "Service port" boundedIntegralDecoder)
    <*> required (publicSetting (validKey "service.names") "Service names" textListDecoder)

textListDecoder :: Decoder [Text]
textListDecoder = decoder $ \key -> \case
  RawArray values -> traverse (textElement key) values
  _ -> Left (decodeFailure key "an array of text")

textElement :: Key -> RawValue -> Either DecodeFailure Text
textElement key = \case
  RawText value -> Right value
  _ -> Left (decodeFailure key "an array of text")

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
```

Pass sources to `resolve` from lowest to highest precedence. The following stack lets a
local file override a shared file:

```haskell
resolveFiles :: Source -> Source -> Either (NonEmpty ConfigError) (ResolveResult ServiceConfig)
resolveFiles shared local =
  resolve defaultResolveOptions [shared, local] serviceConfig
```

Merging is leaf-wise. If the shared file supplies `service.host` and `service.port` while
the local file supplies only `service.port`, the shared host remains and the local port
wins. Arrays are values rather than mergeable collections: a higher-precedence array
replaces the lower array wholesale. A malformed winning value is an error; resolution
does not silently fall back.

File discovery is not built into `settei-yaml`. An application may load one conventional
path, use repeated `--config PATH` options, or implement another explicit policy. Likewise,
the adapter does not impose a file/environment/CLI order. A typical application stack is:

```haskell
allSources = yamlSources <> [environmentSource] <> commandLineSources
```

That order makes later YAML files override earlier YAML files, environment override all
files, and command-line fragments override environment. See the
[environment and command-line guide](environment-and-cli.md) for those adapters.


## Keys, null, numbers, and locations

Nested mappings define key segments. A literal dot in a mapping key is rejected, so write:

```yaml
service:
  port: 8080
```

instead of `service.port: 8080`. Mapping keys must be scalar strings and must be unique at
their mapping level. Both block and flow duplicates fail with `YamlDuplicateKey`; no
first-wins or last-wins behavior is hidden behind the source abstraction.

An explicit YAML `null`, `~`, or empty plain scalar is a present `RawNull` candidate. It
does not mean that the source omitted the key. Whether null is accepted is therefore a
property of the setting's decoder. A higher-precedence null shadows a lower value just as
any other present candidate does.

Integers and finite decimal or exponent forms are retained as exact `Rational` values in
`RawNumber`; large integers do not pass through a machine `Int` or floating-point value.
Hexadecimal and `0o` octal integer forms are accepted. The eventual decoder decides
whether a number fits its application type. Non-finite values such as `.inf` and `.nan`
are rejected.

Successful scalar and array leaves retain the parser's start mark. Reports expose the
source path (or source name when no path was supplied) and one-based line and column.
Mapping values used only as containers have no separately addressable candidate. Syntax
and translation errors expose one-based locations when the parser can identify one.


## Mounted ConfigMaps and Secrets

`fromKubernetesMountedFile` adds a caller-asserted Kubernetes reference to every origin
from a mounted document. It performs no cluster lookup and does not verify that the file
was mounted from that object.

```haskell
mountedOptions :: YamlSourceOptions
mountedOptions =
  fromKubernetesMountedFile
    ( kubernetesRef
        SecretObject
        (Just "production")
        "service-database"
        (Just "application.yaml")
    )
    (yamlSourceOptions "mounted database configuration")

loadMountedSecret :: IO (Either (NonEmpty YamlSourceError) Source)
loadMountedSecret =
  readYamlSource mountedOptions "/var/run/config/application.yaml"
```

The resulting origin annotations can name the object kind, namespace, object name, and
object key. They are metadata only. Calling this helper does not make every setting
secret, and it cannot make a secret setting public. Sensitivity belongs exclusively to
the `Setting`; core text and JSON renderers redact candidates for `secretSetting` values.
Only trusted, secret-safe values should be passed to `annotateYamlSourceOptions`.


## Strict subset and safe errors

The adapter accepts exactly one top-level mapping. An empty document and a top-level null
produce an empty source. It rejects:

- multiple documents and top-level sequences or scalars;
- duplicate, non-string, or dotted mapping keys;
- anchors, aliases, and merge keys;
- custom scalar or collection tags;
- special or otherwise invalid numeric scalars; and
- malformed syntax and invalid UTF-8.

Quoted and block strings always remain text. Plain YAML boolean spellings are recognized.
Strings are never interpolated: `${NAME}` remains literal text, and parsing never reads
the process environment.

Failures use the stable `YamlErrorCategory` constructors and the `yamlErrorName`,
`yamlErrorPath`, `yamlErrorLine`, `yamlErrorColumn`, `yamlErrorContext`, and
`yamlErrorMessage` accessors. IO failures are distinguished as `YamlIoError`. Error values
never retain a raw scalar or source excerpt, because YAML parsing occurs before the core
knows which keys are secret. Applications should render those structured fields rather
than attaching the original input to an exception.
