# Dhall configuration

`settei-dhall` evaluates a typed Dhall expression into a provenance-aware Settei
`Source`. It uses the source-inspected `dhall` 1.42.3 and `dhall-json` 1.7.12 libraries.
The adapter owns parsing, import control, type checking, normalization, and value
conversion; the core still owns ordered source precedence, setting decoders, defaults,
redaction, and reports.

Version one intentionally supports only import-free expressions and local import graphs
contained by one canonical directory. It does not expose Dhall's unrestricted standard
resolver because the maintained upstream API cannot intercept local and environment reads
while also producing a complete cache-independent import closure.


## Load an import-free expression

Use a stable, secret-safe label for expression text. Neither `DhallRoot` nor source values
have a `Show` instance because they can contain secrets.

```haskell
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Settei
import Settei.Dhall
import Settei.Prelude

loadGenerated :: Text -> IO (Either Text Source)
loadGenerated input = do
  loaded <-
    loadDhallSource
      (dhallSourceOptions "generated Dhall" NoImports)
      (dhallExpression "generated application configuration" input)
  pure (either (Left . renderProblems) Right loaded)

renderProblems :: NonEmpty DhallSourceError -> Text
renderProblems =
  Text.intercalate "\n"
    . fmap
      ( \problem ->
          Text.pack (show (dhallErrorCategory problem))
            <> ": "
            <> dhallErrorMessage problem
      )
    . NonEmpty.toList
```

`NoImports` rejects every embedded local, environment, remote, missing, raw-text, bytes,
or location import before it can be resolved. A missing local path therefore produces
`DhallImportPolicyError`, not an IO attempt.


## Load a contained local graph

`LocalImportsWithin root` canonicalizes `root`, the root file, and every transitive local
import. A root file or import outside that directory fails. `..` escapes and symlink
escapes are checked after canonicalization. Environment, remote, missing, and alternative
imports fail during preflight and are never passed to the upstream evaluator.

```haskell
loadApplicationFile :: FilePath -> FilePath -> IO (Either (NonEmpty DhallSourceError) Source)
loadApplicationFile allowedRoot path =
  loadDhallSource
    (dhallSourceOptions "application Dhall" (LocalImportsWithin allowedRoot))
    (DhallFile path)
```

The policy supports code, raw-text, raw-bytes, and location modes when the referenced local
file exists inside the allowed root. The resulting normalized value must still be
JSON-compatible, so a raw bytes value normally ends in `DhallConversionError`. Semantic
integrity hashes are enforced by Dhall and retained in structured provenance.

Containment is a configuration capability boundary, not an operating-system sandbox.
Preflight validates canonical paths before upstream evaluation, but an attacker able to
replace files or symlinks concurrently could race those two phases. Do not use a writable,
hostile directory as an allowed root.


## Supported values

The top-level result must be a Dhall record because Settei sources are hierarchical key
trees. Record fields become structural key segments, and empty or dotted fields fail
instead of becoming implicit nested paths.

The adapter follows the official `dhall-json` conversion for records, lists, `Bool`,
`Natural`, `Integer`, finite `Double`, `Text`, `Optional`, and unions. `Some x` becomes
`x`, `None T` becomes explicit `RawNull`, and a selected union alternative becomes its
payload or its alternative name when it has no payload. Natural and integer values remain
exact; finite doubles use Aeson's finite JSON number representation. Non-finite doubles,
bytes, functions, types, and other values without a JSON representation fail with
`DhallConversionError`.

The adapter selects `Dhall.JSON.NoConversion`. An association list such as this remains an
array of records:

```dhall
{ entries =
    [ { mapKey = "one", mapValue = 1 }
    , { mapKey = "two", mapValue = 2 }
    ]
}
```

It is not silently collapsed into an object, because duplicate `mapKey` values are valid
list data and object conversion would discard that distinction.


## Schema evolution with defaults

Dhall record fields are always required. `Optional Text` means that the field's value may
be absent; it does not let a caller omit the record field. Preserve old inputs by keeping a
small input type, defining the complete output type separately, and applying new fields in
a constructor. This pattern is adapted from the registered
`dhall-schema-evolution-pattern` guide and is exercised by the adapter test suite:

```dhall
let Input = { name : Text }

let Output = { name : Text, description : Optional Text, tags : List Text }

let default : { description : Optional Text, tags : List Text } =
      { description = None Text, tags = [] : List Text }

let make = \(input : Input) -> default // input

let value : Output = make { name = "my-service" }

in  { service = value }
```

An exported schema module can expose these local declarations as fields named `Input`,
`Type`, `default`, and `make`; inside the module, use a non-reserved local name such as
`Output` for the final type.


## Provenance and precision

`loadDhallSourceDetailed` returns both the `Source` and a sorted, de-duplicated list of
`DhallImport` records. Each import retains its canonical path, interpretation mode, and
optional semantic hash. The simpler `loadDhallSource` discards that side channel while
retaining equivalent annotations on every source origin.

Reserved annotations include `dhall.root`, `dhall.import-policy`, `dhall.import-count`,
`dhall.provenance-precision`, and indexed `dhall.import.N.*` fields. Caller annotations are
trusted, secret-safe metadata; reserved Dhall keys win collisions. A report says, for
example:

```text
service.port = 8080
  from file source application Dhall (Dhall) rooted at /etc/service/application.dhall evaluated with 2 local imports; leaf-level import attribution unavailable after normalization
```

That limitation is deliberate. Normalization can combine, discard, or transform imported
expressions, so the adapter reports the substantiated root and complete local import
closure without fabricating one contributing file for each leaf.


## Ordering, Kubernetes, caches, and secrets

Pass sources to `resolve` from lowest to highest precedence. Dhall does not merge Settei
layers: the core chooses the rightmost present leaf, replaces arrays wholesale, and never
falls back from a malformed winner.

Kubernetes metadata remains an application assertion. Attach the core annotations without
performing cluster discovery:

```haskell
mountedOptions :: FilePath -> DhallSourceOptions
mountedOptions root =
  annotateDhallSourceOptions
    (kubernetesAnnotations (kubernetesRef SecretObject (Just "production") "service-config" (Just "application.dhall")))
    (dhallSourceOptions "mounted Dhall" (LocalImportsWithin root))
```

Local evaluation disables Dhall's semantic integrity cache for the run, but upstream
1.42.3 has a separate semi-semantic cache with no public off switch. Settei's closure is
collected by preflight and is therefore independent of cache hits. Applications that need
cache isolation should set `XDG_CACHE_HOME` for the process before loading configuration;
the test executable points it at a temporary directory before any test begins.

Parsing and type checking happen before Settei knows which settings are secret. Structured
adapter errors therefore contain only a stable phase, source name, optional safe path, and
fixed message. They never retain source snippets or upstream exceptions. Root labels,
paths, and caller annotations can appear in reports, so callers must keep those metadata
fields secret-safe. Actual secret values remain available to the typed application result
and are redacted by the core from text, JSON, errors, warnings, and shadow traces.
