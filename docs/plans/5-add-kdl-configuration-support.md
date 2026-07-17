---
id: 5
slug: add-kdl-configuration-support
title: "Add KDL configuration support"
kind: exec-plan
created_at: 2026-07-16T23:50:10Z
master_plan: "docs/masterplans/1-build-settei-as-a-provenance-aware-configuration-library-for-haskell.md"
---

# Add KDL configuration support

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture

After this plan, applications can use KDL as a concise configuration syntax while keeping
the exact resolution and explanation behavior of every other Settei source. A canonical,
documented mapping translates nodes, arguments, properties, repeated nodes, and children
to the core raw tree. Reports identify the file, logical key, and KDL node span when the
parser provides it. Ambiguous mixtures and name collisions fail explicitly.

The package is `settei-kdl`. It uses `kdl-hs` as a syntax parser, not as a second schema or
resolution engine. Settei's format-independent `Config` remains the only declaration of
the application's settings.


## Progress

- [ ] Re-inspect the registered `kdl-hs` AST, span, and parser APIs.
- [ ] Add and register the `settei-kdl` package.
- [ ] Implement and test the canonical KDL-to-raw-tree mapping.
- [ ] Preserve useful spans in source origins and structured errors.
- [ ] Test hierarchy, repeated nodes, collisions, precedence, and redaction.
- [ ] Publish a KDL guide with canonical examples and limitations.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Parse the KDL AST directly and translate it to the core raw tree; do not ask
  consumers to write a separate `KDL.Applicative` schema.
  Rationale: one Settei declaration must work unchanged for YAML, KDL, Dhall, environment,
  and CLI sources.
  Date: 2026-07-16

- Decision: Map repeated sibling node names to an array in document order and reject a
  property/child name collision.
  Rationale: repeated nodes are a native KDL structure, while silently choosing between a
  property and child would discard data.
  Date: 2026-07-16

- Decision: Reject positional arguments mixed with properties or children in version one.
  Rationale: there is no portable object representation for an unnamed node value plus
  named fields without inventing reserved keys.
  Date: 2026-07-16

- Decision: Inherit the shared Haskell conventions and reuse strict `name` and
  `annotations` labels instead of KDL-prefixed record fields.
  Rationale: local generic-lens access and `DuplicateRecordFields` keep the public adapter
  API consistent with the other source packages without ambiguous selector usage.
  Date: 2026-07-16


## Outcomes & Retrospective

To be filled during and after implementation. Any change to the canonical mapping must be
recorded here and in the format guide because configuration files will depend on it.
Completion also requires the package to declare the canonical package-local GHC2024 common
stanza, every component to import it, and the code to pass the shared prelude, record,
deriving, lens, and import-style audit.


## Context and Orientation

This plan depends on
`docs/plans/2-implement-hierarchical-resolution-provenance-and-derived-defaults.md`.
The core supplies the raw value tree, ordered `Source` semantics, per-key origin extension,
locations, structured errors, and redaction. Read its actual implementation and ADR first.

At planning time, `mori registry search kdl` locates the `kdl-hs` project at
`/Users/shinzui/Keikaku/hub/kdl-hs-project`, package version 1.0.1. Source inspection found
the parser, AST, Applicative, and Arrow modules and node spans. Re-run Mori because the
registry and checked-out version can change. Use the names and constructors found in the
current source rather than those remembered or shown illustratively in this plan.

In the mapping below, an object is a collection of named fields, a leaf is a raw scalar or
array supplied to one setting decoder, and a span is the file region associated with a KDL
node or value. Settei key segments retain the version-one restriction from Plan 1: empty
segments and literal dots within a segment are rejected.

Plan 1 owns the applicable conventions from registered project
`shinzui/haskell-jitsurei`. Import `Settei.Prelude`, import
`Data.Generics.Labels ()` locally wherever generic-lens labels are used, use strict fields
without type-name prefixes, and derive instances with explicit strategies. Read and update
records and path-to-span maps with lenses, `at`, or `ix`; do not mix selector calls or
record updates into that code. Qualified KDL imports use postpositive `qualified` syntax,
and the package declares `generic-lens` directly when it imports the orphan label instance.
[ADR 0001](../adr/0001-haskell-project-conventions.md) records the durable rationale and
rejected alternatives for this baseline.


## Plan of Work

### Milestone 1: characterize the KDL AST and scalar conversions

Use Mori to locate and read `KDL`, the AST/type modules, parser errors, and span types in
the registered source. Write characterization tests for strings, raw strings, booleans,
null, integers, decimals, type annotations, properties, repeated properties if the grammar
permits them, repeated nodes, comments, slash-dash, and parse errors. Determine exactly
which KDL language version the selected release accepts and state it in package Haddocks
and the guide.

Map only scalar forms that the core `RawValue` represents without loss: text, boolean,
null, and supported numeric values. If KDL numeric precision exceeds the raw type, reject
out-of-range values with their span. Treat custom type annotations as unsupported in
version one unless the inspected AST exposes a lossless, clearly testable policy; never
silently erase semantic annotations.

### Milestone 2: implement the canonical document mapping

Create `packages/settei-kdl/settei-kdl.cabal`, expose `Settei.Kdl`, and register the
package in Cabal and Nix. Repeat Plan 1's canonical package-local `common common` stanza
and import it from the library and test components. Provide pure text parsing and a file
convenience:

```haskell
data KdlSourceOptions = KdlSourceOptions
  { name :: !Text
  , annotations :: !(Map Text Text)
  }
  deriving stock (Generic, Eq)

decodeKdlSource
  :: KdlSourceOptions
  -> Text
  -> Either (NonEmpty KdlSourceError) Source

readKdlSource
  :: KdlSourceOptions
  -> FilePath
  -> IO (Either (NonEmpty KdlSourceError) Source)
```

Translate a document as one root object with these rules:

- A node name is the field name in its containing object.
- A node with one positional argument and no properties or children is that scalar.
- A node with two or more positional arguments and no properties or children is an array
  of those scalars.
- A node with no arguments, properties, or children is explicit null.
- A node with properties and no positional arguments is an object whose properties become
  fields. Children may add fields to that object when their names do not collide.
- A node with children and no positional arguments is an object formed by recursively
  applying these rules.
- Repeated sibling node names become an array in document order, even when their elements
  are objects.
- A positional argument combined with properties or children is an error.
- A property and child with the same name is an error; no side silently wins.
- Invalid Settei key segments, unsupported annotations, and unrepresentable scalar values
  are errors at their original spans.

For example, this document supplies `runtime.environment`, `service.http.host`,
`service.http.port`, and `service.tags`:

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

A repeated-object array is written as:

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

The resulting root field `backend` is an array of two objects. Document that a single
sibling has its direct value while repeated siblings produce an array; setting decoders
remain responsible for the expected shape.

### Milestone 3: preserve provenance and errors

While translating, build a path-to-span index alongside the raw tree. For a scalar leaf,
use the value or enclosing-node span supported by the inspected AST. For an array formed
from arguments or repeated nodes, retain the enclosing range and, internally if the core
allows, element spans. For an object setting resolved at its whole key, retain the node
span. Do not discard locations by converting to raw values first.

Construct origins with the source name, optional file path, logical key, KDL language
version, caller annotations, and span. `readKdlSource` distinguishes IO, parse, and mapping
errors. Parse and mapping errors include the smallest trustworthy span but no source
snippet or raw scalar text, because parsing precedes knowledge of which setting is secret.
Caller annotations can describe a Kubernetes mounted ConfigMap or Secret
but are not verified by a cluster client.

### Milestone 4: integration tests and guide

Add fixture and property tests for every mapping rule, numeric boundary, repeated sibling
order, property/child collision, mixed argument/object rejection, invalid name, syntax
error, and location. Resolve equivalent nested values from two ordered KDL sources and
prove leaf-wise overrides and array replacement are performed by core.

Add `docs/guides/kdl.md` with the supported KDL language version, canonical mapping,
examples for scalar, list, object, repeated object, explicit null, source ordering,
origins, mounted-file annotations, and rejected ambiguous forms. Explain that
`KDL.Applicative` is not required by Settei consumers.


## Concrete Steps

Run from `/Users/shinzui/Keikaku/bokuno/settei`. Locate the current dependency and read its
source before importing anything:

```bash
mori show --full
mori registry search kdl
mori registry search generic-lens
mori registry show ekmett/lens --full
mori registry show shinzui/haskell-jitsurei --full
mori registry docs shinzui/haskell-jitsurei
```

Use the qualified result returned by the registry:

```bash
mori registry show QUALIFIED_KDL_PROJECT --full
mori registry docs QUALIFIED_KDL_PROJECT
```

Read the source path reported by Mori with scoped searches such as:

```bash
rg "data .*Node|data .*Value|data Span|documentSchema|parse" REGISTERED_KDL_SOURCE/src
```

After adding the package and fixtures, run:

```bash
nix fmt
cabal build settei-kdl
cabal test settei-kdl-tests --test-show-details=direct
cabal test all --test-show-details=direct
nix flake check
```

Expected behavior-focused output includes:

```text
Settei.Kdl
  nested nodes become segmented keys: OK
  repeated siblings preserve order as an array: OK
  arguments mixed with children fail at a span: OK
  property-child collisions fail: OK
  origins retain KDL spans: OK
  ordered sources use core leaf precedence: OK
All tests passed
```


## Validation and Acceptance

Parse the canonical example above and resolve matching typed settings. The report must
name the KDL source and logical key and include a trustworthy line/column or offset span.
Parse the repeated `backend` example and assert the array order and each object's values.

Every ambiguous combination listed in the mapping must fail rather than discard content.
A node with an argument and children must produce a mapping error at that node. A property
and child collision must name the colliding field and both available locations. Invalid or
unrepresentable scalar values must fail at the value span.

With a low-priority document supplying host and port and a high-priority document supplying
only port, core resolution must retain the low host and choose the high port with shadowed
provenance. A high-priority list replaces the low list. The adapter itself must contain no
merge algorithm.

Resolve a secret sentinel from a KDL string. The typed application value may contain it,
but all reports, errors, warnings, goldens, and `Show` output must be sentinel-free.


## Idempotence and Recovery

Mori lookup, characterization tests, formatting, builds, and tests are safe to repeat.
Keep the canonical mapping centralized in one translator and reuse it for bytes/file IO so
behavior cannot drift.

If the registered `kdl-hs` API differs from the planning snapshot, update this plan with
the actual version and evidence before adapting imports. If a desired span is unavailable,
report the nearest substantiated enclosing span and document the precision; never synthesize
line numbers. If the raw tree cannot represent a scalar losslessly, return a mapping error
instead of coercing it.


## Interfaces and Dependencies

Package `settei-kdl` depends on `settei`, `base`, `containers`, `text`, and the registered
`kdl-hs` package, plus only the numeric or path dependencies required by its inspected AST.
Add `generic-lens` directly when package modules use `#label`. It consumes core `Source`,
`Origin`, `SourceLocation`, `RawValue`, and error extension points.

Do not use `KDL.Applicative` or `KDL.Arrow` as the application's schema, do not duplicate
the core resolver, and do not depend on YAML, Dhall, environment, CLI, Kubernetes, or
effect-system packages.


## Revision Note

2026-07-16: Aligned the KDL adapter plan with the registered core Haskell conventions.
The option API now uses strict unprefixed fields and explicit deriving, while implementation
guidance requires the shared prelude, local generic-lens import, lens-based record and map
access, a direct package dependency, and postpositive qualified imports.
