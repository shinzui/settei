# Dhall configuration

Use `settei-dhall` to evaluate a typed Dhall expression into a provenance-aware `Source`.
The adapter parses, checks, normalizes, and converts the expression; the core declaration
still owns application decoding, defaults, sensitivity, and source precedence.

## Add the package

```cabal
build-depends:
  , settei
  , settei-dhall
  , text
```

```haskell
import Data.Bifunctor (first)
import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Settei
import Settei.Dhall
```

Every load requires an import policy:

| Policy | Allowed input |
| --- | --- |
| `NoImports` | The root expression or root file only; every embedded import is rejected. |
| `LocalImportsWithin root` | Local imports whose canonical paths remain inside `root`. |

Neither policy permits environment, remote, missing, or alternative imports. Choose the
policy in application code rather than from untrusted configuration input.

## Load an import-free expression

For generated or embedded Dhall text, give the expression a stable, secret-safe label:

```haskell
loadGeneratedDhall
  :: Text
  -> IO (Either (NonEmpty DhallSourceError) Source)
loadGeneratedDhall input =
  loadDhallSource
    (dhallSourceOptions "generated configuration" NoImports)
    (dhallExpression "generated application.dhall" input)
```

`NoImports` rejects an import before resolving it. Use it for self-contained input and as
the safest default for applications that do not need shared Dhall modules.

`DhallRoot` and `Source` intentionally have no `Show` instance because they may contain
unredacted configuration values. Keep expression labels and source names free of secrets.

## Load a file with local imports

Use `LocalImportsWithin` when a configuration is split into trusted local files:

```haskell
loadApplicationDhall
  :: FilePath
  -> FilePath
  -> IO (Either (NonEmpty DhallSourceError) Source)
loadApplicationDhall allowedRoot path =
  loadDhallSource
    (dhallSourceOptions "application configuration" (LocalImportsWithin allowedRoot))
    (DhallFile path)
```

The root file and every transitive import must remain inside `allowedRoot` after absolute
path and symlink resolution. A `..` or symlink escape returns `DhallImportPolicyError`.
Use a read-only directory controlled by the application or deployment; the policy is not
an operating-system sandbox.

Local code, raw-text, raw-bytes, and location import modes can pass policy checks. The
final normalized expression must still be convertible to Settei values, so bytes and
other non-JSON values normally fail later with `DhallConversionError`. Dhall semantic
integrity hashes are checked during evaluation.

To load a self-contained file with no embedded imports, pass `NoImports` with
`DhallFile path`.

## Return a top-level record

Settei sources are hierarchical objects, so the evaluated top-level value must be a Dhall
record:

```dhall
{ runtime = { environment = "production" }
, service =
    { host = "api.internal"
    , port = 8080
    , names = [ "public", "health" ]
    }
}
```

This supplies `runtime.environment`, `service.host`, `service.port`, and `service.names`.
Record field names become Settei key segments. Empty or dotted fields are rejected; use
nested records for dotted Settei keys.

## Declare decoders and resolve the source

The application declaration is not specific to Dhall:

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

Keep evaluation failures separate from typed resolution failures:

```haskell
resolveDhallFile
  :: FilePath
  -> FilePath
  -> IO (Either Text (ResolveResult ServiceConfig))
resolveDhallFile allowedRoot path = do
  loaded <- loadApplicationDhall allowedRoot path
  pure $ do
    dhallSource <- first renderDhallErrorsText loaded
    pure (resolve defaultResolveOptions [dhallSource] serviceConfig)
```

The outer `Either Text` represents Dhall evaluation and conversion. Typed resolution
errors live in `ResolveResult.answer`, while the report and warnings remain available for
the failed attempt.

## Understand Dhall-to-Settei values

| Dhall result | `RawValue` |
| --- | --- |
| `Text` | `RawText` |
| `Bool` | `RawBool` |
| `Natural`, `Integer`, finite `Double` | `RawNumber` |
| `List a` | `RawArray` |
| record | `RawObject` |
| `Some x` | the converted value of `x` |
| `None T` | `RawNull` |
| union alternative with a payload | the converted payload |
| union alternative without a payload | the alternative name as `RawText` |

Natural and integer values remain exact. Non-finite doubles, bytes, functions, types, and
other results without a supported value representation return `DhallConversionError`.

Association lists remain arrays of records:

```dhall
{ entries =
    [ { mapKey = "one", mapValue = 1 }
    , { mapKey = "two", mapValue = 2 }
    ]
}
```

They are not converted into objects. Declare the corresponding setting decoder as an
array decoder.

## Evolve a Dhall schema

Dhall record fields are required by their record type. `Optional Text` allows a field's
value to be `None`; it does not allow the field itself to be omitted. To accept an older,
smaller input while producing a complete record, define a constructor with defaults:

```dhall
let Input = { name : Text }

let Output =
      { name : Text
      , description : Optional Text
      , tags : List Text
      }

let default =
      { description = None Text
      , tags = [] : List Text
      }

let make = \(input : Input) -> default // input

let value : Output = make { name = "my-service" }

in  { service = value }
```

An imported schema module can expose `Input`, `Type`, `default`, and `make`. Keep the
top-level application expression a record after applying the constructor.

This Dhall-level defaulting happens before Settei receives a source. Use Settei defaults
instead when the fallback should be shared across YAML, KDL, environment, CLI, and Dhall
inputs or should appear as a named rule in the resolution report.

## Inspect the local import closure

Use `loadDhallSourceDetailed` when the application needs the transitive imports for
auditing, file watching, or deployment validation:

```haskell
loadWithImports
  :: DhallSourceOptions
  -> DhallRoot
  -> IO (Either (NonEmpty DhallSourceError) (Source, [DhallImport]))
loadWithImports options root = do
  loaded <- loadDhallSourceDetailed options root
  pure
    ( fmap
        (\result -> (dhallLoadedSource result, dhallLoadedImports result))
        loaded
    )
```

Each `DhallImport` provides its canonical path, interpretation mode, and optional semantic
hash through `dhallImportPath`, `dhallImportMode`, and `dhallImportSemanticHash`. The list
is sorted and de-duplicated.

Resolution origins report the root and import count. They do not assign one imported file
to each final leaf, because normalization can combine values from multiple expressions.
If the application watches files, watch the returned closure rather than trying to infer
leaf ownership from the resolution report.

## Layer Dhall with other sources

Pass sources from lowest to highest precedence:

```haskell
orderedSources = dhallSources <> [environmentSource] <> commandLineSources
```

Resolution is leaf-wise across sources. A later source can override `service.port` while
retaining a Dhall `service.host`. Arrays are replaced as complete values. A malformed
winning candidate is an error and does not fall back to the Dhall value.

## Render Dhall errors

```haskell
renderDhallErrorText :: DhallSourceError -> Text
renderDhallErrorsText :: NonEmpty DhallSourceError -> Text
```

The singular renderer produces one line in the form
`NAME (PATH:LINE:COLUMN): MESSAGE`; missing location pieces are omitted. The plural
renderer emits one line per problem and includes a trailing newline. `DhallErrorCategory`
distinguishes IO, parse, policy, import, type, conversion, invalid-key, and top-level-type
failures. The individual accessors remain available for other structured presentations.
Line and column are optional one-based positions populated for parse failures. Errors do
not retain expression snippets, imported values, or upstream exception text.

## Attach Kubernetes metadata

Dhall uses the core Kubernetes annotation helper:

```haskell
mountedDhallOptions :: FilePath -> DhallSourceOptions
mountedDhallOptions allowedRoot =
  annotateDhallSourceOptions
    ( kubernetesAnnotations
        ( kubernetesRef
            ConfigMapObject
            (Just "production")
            "service-config"
            (Just "application.dhall")
        )
    )
    (dhallSourceOptions "mounted application configuration" (LocalImportsWithin allowedRoot))
```

The metadata makes no Kubernetes API request and may appear in reports. Keep it safe to
display. Mark sensitive application keys with `secretSetting`; the mounted object kind
does not determine redaction.

## Production checklist

- Prefer `NoImports` unless the application needs a local module graph.
- Use a narrow, read-only `LocalImportsWithin` directory for local graphs.
- Keep source names, expression labels, paths, and annotations free of secrets.
- Use the detailed loader when file watching or import auditing is required.
- Decide whether defaults belong in the shared Settei declaration or only in Dhall.
- Document Dhall's position relative to environment and CLI sources.
- Render structured errors instead of echoing source text.
- Isolate the process's `XDG_CACHE_HOME` when deployment policy requires a private Dhall
  cache.

See the [security model](../security.md) for the import-policy threat model and
[Building a Kubernetes service](kubernetes-service.md) for a mounted configuration
workflow.
