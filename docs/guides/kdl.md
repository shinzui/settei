# KDL configuration

`settei-kdl` translates one KDL v2 document into a provenance-aware Settei `Source`. It
uses the upstream-audited `kdl-hs` 1.1.1 parser and consumes its AST directly. Applications
do not define a second `KDL.Applicative`, `KDL.Arrow`, or monadic decoder; the same core
`Config` declaration works for KDL, YAML, environment, command-line, and future Dhall
sources.

The adapter deliberately accepts one canonical tree mapping. Ambiguous shapes and values
that core `RawValue` cannot represent losslessly fail before resolution.


## Load one document

This document supplies `runtime.environment`, `service.http.host`, `service.http.port`,
and `service.tags`:

```kdl
runtime {
  environment "production"
}
service {
  http {
    host "0.0.0.0"
    port 8080
  }
  tags "api" "public"
}
```

Use `readKdlSource` at an IO boundary. The source name is a stable report label, and the
path supplied to `readKdlSource` is retained in successful origins and structured errors.

```haskell
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Settei
import Settei.Kdl
import Settei.Prelude

loadApplicationKdl :: FilePath -> IO (Either Text Source)
loadApplicationKdl path = do
  loaded <- readKdlSource (kdlSourceOptions "application KDL") path
  pure (either (Left . renderKdlErrors) Right loaded)

renderKdlErrors :: NonEmpty KdlSourceError -> Text
renderKdlErrors =
  Text.intercalate "\n"
    . fmap
      ( \problem ->
          Text.intercalate
            ": "
            [ Text.pack (show (kdlErrorCategory problem)),
              kdlErrorContext problem,
              kdlErrorMessage problem
            ]
      )
    . NonEmpty.toList
```

For text already obtained by the application, use `decodeKdlSource`. Attach a logical or
real path when it improves provenance:

```haskell
options :: KdlSourceOptions
options =
  withKdlSourcePath
    "generated/application.kdl"
    (kdlSourceOptions "generated KDL")

translated :: Text -> Either (NonEmpty KdlSourceError) Source
translated = decodeKdlSource options
```

`readKdlSource` always replaces an option's existing path with the path it actually reads.


## Canonical mapping

A document is one root object. Each node name becomes a field in its containing object.
Node and property names must be non-empty Settei key segments and therefore cannot contain
a literal dot; use nested nodes for hierarchy.

A node with one positional argument and no properties or children becomes that scalar. A
node with two or more positional arguments becomes an array in argument order. A node
without arguments, properties, or children becomes explicit `RawNull`:

```kdl
host "api.internal"
tags "api" "public"
optional
```

The three values are `RawText "api.internal"`, a two-element `RawArray`, and `RawNull`.
Because cardinality selects scalar versus array, argument-style arrays cannot express
exactly one element in adapter version one. This limitation is explicit compatibility
behavior, not a decoder heuristic.

Properties form object fields. Children may add other fields when their names do not
collide:

```kdl
service host="api.internal" {
  port 8080
}
```

Repeated sibling node names become an array in document order, including when their
elements are objects:

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

The root `backend` value is an array of two objects. A single sibling always has its
direct value; only repetition produces the repeated-node array shape.

Strings, raw strings, booleans, null, and finite numbers are supported. `Scientific`
numbers from `kdl-hs` become exact core rationals. KDL `#inf`, `#-inf`, and `#nan` fail
because core has no lossless non-finite numeric representation.


## Rejected ambiguous forms

The adapter returns a structured `KdlSourceError` for these forms:

- a positional argument combined with a property or children;
- duplicate properties, reported at the second property with the first as a related span;
- a property and child with the same name, with both available spans;
- an empty or dotted node or property name;
- any node or value type annotation;
- non-finite numeric values; and
- invalid KDL v2 syntax.

Comments and slash-dashed nodes or values are handled by the parser and do not reach the
translated tree. Error records contain only category, source name, optional path,
structural context, trustworthy spans, and fixed safe messages. Syntax parsing happens
before setting sensitivity is known, so the adapter discards the parser's rendered source
excerpt and retains only its line and column header.


## Provenance, ordering, and redaction

Successful origins use `FileSource "KDL v2"`, carry the logical Settei key, and retain the
value or node's one-based start location. The complete start/end span appears as safe
`kdl.span.*` annotations, and `kdl.version` is `2`. Arrays built from repeated siblings
span from the first node's start through the final node's end.

Pass sources to `resolve` from lowest to highest precedence. KDL does not merge layers: if
a low document supplies `service.host` and `service.port` while a high document supplies
only `service.port`, core retains the low host and chooses the high port. A higher array
replaces a lower array wholesale, and a malformed winner never falls back.

Kubernetes mounted-file metadata is a trusted application assertion, not cluster
discovery:

```haskell
mountedOptions :: KdlSourceOptions
mountedOptions =
  fromKubernetesMountedFile
    (kubernetesRef SecretObject (Just "production") "service-config" (Just "config.kdl"))
    (kdlSourceOptions "mounted KDL")
```

The reference may appear in reports, but setting sensitivity remains defined only by the
core `Setting`. Secret application values are available to the typed result and are
redacted before any report, error, warning, text, JSON, or `Show` representation is built.
