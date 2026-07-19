# KDL configuration

Use `settei-kdl` to load a KDL v2 document as a provenance-aware `Source`. The adapter
uses one predictable node-to-object mapping; the core declaration remains responsible for
application types, defaults, sensitivity, and precedence.

## Add the package

```cabal
build-depends:
  , settei
  , settei-kdl
  , text
```

```haskell
import Data.Bifunctor (first)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Settei
import Settei.Kdl
```

## Write a supported KDL document

Use nested nodes to express structural keys:

```kdl
runtime {
  environment "production"
}

service {
  host "api.internal"
  port 8080
  names "public" "health"
}
```

This supplies `runtime.environment`, `service.host`, `service.port`, and `service.names`.
Node and property names become key segments, so they must be non-empty and cannot contain
a literal dot.

## Load a file

Use `readKdlSource` at the executable's IO boundary:

```haskell
loadKdl :: FilePath -> IO (Either (NonEmpty KdlSourceError) Source)
loadKdl path =
  readKdlSource (kdlSourceOptions "application configuration") path
```

The source name appears in reports and should be stable and safe to display. The file path
passed to `readKdlSource` is retained in origins and errors, replacing any path already
attached to the options.

For `Text` already loaded by the application, use the pure decoder:

```haskell
decodeGeneratedKdl
  :: Text
  -> Either (NonEmpty KdlSourceError) Source
decodeGeneratedKdl =
  decodeKdlSource
    ( withKdlSourcePath
        "generated/application.kdl"
        (kdlSourceOptions "generated configuration")
    )
```

Use `decodeKdlSource` in parser tests and when another component owns the IO. Use
`readKdlSource` when Settei should distinguish file failures as `KdlIoError`.

## Declare decoders and resolve the source

The same declaration can resolve KDL, YAML, environment, command-line, and Dhall sources:

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

Keep adapter failures separate from typed resolution failures:

```haskell
resolveKdlFile
  :: FilePath
  -> IO (Either Text (ResolveResult ServiceConfig))
resolveKdlFile path = do
  loaded <- loadKdl path
  pure $ do
    kdlSource <- first renderKdlErrors loaded
    first renderErrorsText
      (resolve defaultResolveOptions [kdlSource] serviceConfig)
```

## Understand the node mapping

The document root is a `RawObject`. Each node name becomes a field in its containing
object.

### Scalars, arrays, and null

A node with one positional argument and no properties or children becomes a scalar. Two
or more positional arguments become an array. A node with no arguments, properties, or
children becomes `RawNull`:

```kdl
host "api.internal"
names "public" "health"
enabled #true
retries 3
optional
```

KDL strings and raw strings become `RawText`; booleans become `RawBool`; `#null` and an
empty node become `RawNull`; finite numbers become exact `RawNumber` values. A number
whose base-10 exponent magnitude exceeds 4096 is rejected as `KdlUnsupportedValue`,
preventing one value from exhausting memory at load time while comfortably covering
practical configuration values.

Argument count determines scalar versus array. Consequently, argument-style arrays cannot
represent exactly one element. Repeated sibling nodes work for collections that always
contain at least two elements; if zero- and one-element arrays are normal inputs, choose
YAML or Dhall for that document shape.

Empty arrays and empty objects are not representable in this KDL mapping. A node with an
empty child block has no arguments, properties, or effective children and therefore maps
to `RawNull`. Use YAML or Dhall when empty collections must be distinct from null.

### Objects

Properties become object fields. Child nodes may add more fields:

```kdl
service host="api.internal" {
  port 8080
}
```

This is equivalent to an object containing `host` and `port`. A property and child cannot
use the same name.

### Repeated nodes

Repeated sibling names become an array in document order:

```kdl
backend {
  host "one.internal"
  port 8080
}

backend {
  host "two.internal"
  port 8081
}
```

Here `backend` is an array of two objects. A single sibling has its direct value; only
repetition introduces the repeated-node array.

## Forms that return adapter errors

`decodeKdlSource` returns a structured `KdlSourceError` for:

- positional arguments combined with properties or children;
- duplicate properties;
- a property and child with the same name;
- empty or dotted node and property names;
- node or value type annotations;
- non-finite `#inf`, `#-inf`, and `#nan` values; and
- invalid KDL v2 syntax.

Comments and slash-dashed nodes or values are handled by the KDL parser. Slash-dashed
content does not become configuration input.

## Layer KDL with other sources

Pass sources from lowest to highest precedence:

```haskell
resolveFiles
  :: Source
  -> Source
  -> Either (NonEmpty ConfigError) (ResolveResult ServiceConfig)
resolveFiles shared local =
  resolve defaultResolveOptions [shared, local] serviceConfig
```

Resolution is leaf-wise. A higher document can override `service.port` while retaining a
lower `service.host`. Arrays are replaced wholesale. If the winning KDL value does not
satisfy its setting decoder, resolution fails at that origin instead of falling back.

A typical application puts all KDL files below environment variables and command-line
overrides:

```haskell
orderedSources = kdlSources <> [environmentSource] <> commandLineSources
```

## Render KDL errors and locations

```haskell
renderKdlErrors :: NonEmpty KdlSourceError -> Text
renderKdlErrors =
  Text.intercalate "\n"
    . fmap renderKdlError
    . NonEmpty.toList

renderKdlError :: KdlSourceError -> Text
renderKdlError problem =
  Text.intercalate
    ": "
    [ Text.pack (show (kdlErrorCategory problem)),
      kdlErrorContext problem,
      kdlErrorMessage problem
    ]
```

Use `kdlErrorPath` and `kdlErrorSpan` to display a location. `KdlSpan` exposes one-based
start and inclusive end positions through `kdlSpanLine`, `kdlSpanColumn`,
`kdlSpanEndLine`, and `kdlSpanEndColumn`. Collision errors may also provide
`kdlErrorRelatedSpan` for the first conflicting item.

Successful leaves retain their source span in origin metadata. Repeated sibling arrays
span from the first repeated node through the last. Error values contain structural
context and safe messages, not raw source excerpts or scalar values.

## Load a mounted ConfigMap or Secret

Attach Kubernetes delivery metadata when the application knows the mounted file's origin:

```haskell
mountedKdlOptions :: KdlSourceOptions
mountedKdlOptions =
  fromKubernetesMountedFile
    ( kubernetesRef
        ConfigMapObject
        (Just "production")
        "service-config"
        (Just "application.kdl")
    )
    (kdlSourceOptions "mounted application configuration")

loadMountedKdl :: IO (Either (NonEmpty KdlSourceError) Source)
loadMountedKdl =
  readKdlSource mountedKdlOptions "/etc/service/application.kdl"
```

The reference is descriptive metadata and does not cause a Kubernetes API request. It may
appear in reports, so keep it safe to display. Redaction is still controlled by each
core `Setting`, not by the mounted object's kind.

## Production checklist

- Validate KDL v2 files with the same declaration used at runtime.
- Teach configuration authors the positional-argument array rule.
- Test repeated-node arrays and property/child collisions when the schema uses objects.
- Document the order of multiple files and other source adapters.
- Render structured spans instead of echoing the original KDL on failure.
- Mark secrets with `secretSetting` before resolving any input.
- Use Kubernetes annotations only for delivery metadata the deployment guarantees.

See [Building a CLI application](cli-application.md) for file-option handling and
[Building a Kubernetes service](kubernetes-service.md) for a mounted-file deployment.
