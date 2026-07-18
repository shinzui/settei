---
id: 5
slug: add-kdl-configuration-support
title: "Add KDL configuration support"
kind: exec-plan
created_at: 2026-07-16T23:50:10Z
intention: "intention_01kxr36cqgem8tmxjjtnq0t6ns"
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

- [x] (2026-07-17 21:35 -0700) Inspected the then-registered `kdl-hs` 1.0.1 source and
  probed its public AST/parser behavior: it implements KDL v2, retains duplicate entries,
  represents numbers as exact `Scientific` values, and emits one-based spans when enabled.
- [x] (2026-07-17 22:05 -0700) Added the top-level `settei-kdl` package and registered
  it in Cabal, Nix, and Mori; its initial dependency selection was `kdl-hs` 1.0.1.
- [x] (2026-07-17 21:56 -0700) Implemented and tested the canonical KDL-to-raw-tree
  mapping for scalars, argument arrays, nulls, properties, children, and repeated sibling
  arrays, with explicit rejection of every ambiguous form.
- [x] (2026-07-17 21:56 -0700) Preserved exact one-based success spans in origins and
  annotations, primary and related spans in mapping errors, and the safe header location
  from syntax errors while discarding parser excerpts.
- [x] (2026-07-17 21:56 -0700) Added focused tests for hierarchy, repeated nodes,
  duplicate properties, property/child collisions, mixed shapes, precedence, array
  replacement, Kubernetes annotations, file IO, and secret redaction.
- [x] (2026-07-17 22:05 -0700) Published the KDL guide and ADR 0005 with canonical
  examples, provenance behavior, rejected forms, and the one-element argument-array
  limitation.
- [x] (2026-07-17 22:20 -0700) Passed `nix fmt`, all five Cabal builds and package
  checks, all 100 workspace tests, Haddocks with 100% coverage for `Settei.Kdl`, all
  source distributions, Mori inventory, the dedicated and default Nix builds, and the
  full host-platform flake check.
- [x] (2026-07-18) Audited the current Hackage release and upstream `v1.1.1` source,
  replaced the stale 1.0.1 exact bound and archive with the audited 1.1 release line, and
  confirmed that the parser-facing implementation and all KDL semantics remain unchanged.
- [x] (2026-07-18) Passed all 18 KDL tests and all 121 workspace tests against `kdl-hs`
  1.1.1, the dedicated Nix package build, full host-platform flake check, `cabal check`,
  source-distribution generation, formatting, and pre-commit validation.


## Surprises & Discoveries

- Observation: `kdl-hs` 1.1.1's convenience `getProps` helper converts entries with
  `Map.fromList` and would silently keep the final duplicate property, but the exported
  `Node.entries` list preserves both properties and their individual spans.
  Evidence: upstream `v1.1.1` source inspection of `KDL.Types` plus a parser probe of
  `service port=1 port=2` returned two ordered `Entry` values at columns 9 and 16.
  Impact: Settei must translate the entry list directly and reject the second property;
  it must not use `getProps` at the ambiguity boundary.

- Observation: Mori's `kdl-hs` checkout is a stale 1.0.1 source snapshot, not a release
  index; Hackage and upstream publish 1.1.1, while the locked nixpkgs set exposes 1.1.0.
  Evidence: `mori registry show brandonchinn178/kdl-hs --full`, `cabal list
  --simple-output kdl-hs`, the Hackage 1.1.1 package description, upstream release tags,
  and `nix eval` report the three distinct versions.
  Impact: Cabal supports `>=1.1.1 && <1.2`, Nix locks the 1.1.1 Hackage archive, and
  future dependency selection uses Mori to locate source but checks upstream before
  choosing a release or workaround.

- Observation: successful AST elements have exact one-based spans, but the public parser
  reduces a failed Megaparsec bundle to rendered `Text` that includes a source excerpt.
  Evidence: a malformed-node probe returned a `1:18:` header followed by the input line.
  Impact: syntax failures retain only line and column parsed from the header and discard
  the remainder so a pre-sensitivity error can never retain a secret source excerpt.

- Observation: the canonical positional-argument rule distinguishes a scalar from an
  array solely by cardinality: one argument is a scalar and two or more are an array.
  Evidence: the first precedence test supplied `names "three"`; core correctly rejected
  that scalar for an array decoder, while `names "three" "four"` resolved as an array.
  Impact: argument-style arrays cannot express exactly one element in version one. The
  guide and format ADR must state this rather than implying that every array cardinality
  has a direct spelling.


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

- Decision: Create the package at top-level root `settei-kdl/`, after the sibling-layout
  migration in Plan 8.
  Rationale: every publishable Settei package now uses a same-named repository-root
  directory; creating another package beneath the obsolete `packages/` wrapper would
  immediately require a second move.
  Date: 2026-07-17

- Decision: Support the KDL v2 grammar implemented by upstream-audited `kdl-hs` 1.1.1,
  reject every node or value type annotation in version one of the adapter, and reject
  `#inf`, `#-inf`, and `#nan` rather than coercing them.
  Rationale: finite `Scientific` values convert exactly to the core `Rational`, while
  annotations and non-finite numbers have no lossless format-independent `RawValue`
  meaning.
  Date: 2026-07-18

- Decision: The initial exact `kdl-hs` 1.0.1 Cabal and Nix pin is superseded.
  Rationale: it treated the version in Mori's stale corpus checkout as a release ceiling
  even though newer upstream releases were available.
  Date: 2026-07-18

- Decision: Support `kdl-hs >=1.1.1 && <1.2` in Cabal, lock its 1.1.1 Hackage archive for
  Nix, and continue using the public `parseWith` API.
  Rationale: a reusable library should state the audited compatible release line, while
  Nix should reproducibly validate the current upstream patch release. The 1.1.1 parser
  still returns rendered text on failure, so keeping only its first location header and
  discarding source excerpts remains necessary for pre-sensitivity redaction.
  Date: 2026-07-18


## Outcomes & Retrospective

EP-5 completed on 2026-07-17. `settei-kdl` now translates KDL v2 directly from the
upstream-audited `kdl-hs` 1.1.1 AST into core `RawValue` trees without introducing a
second schema or merge layer. The package implements the canonical scalar, positional
array, null, property/object, child, and repeated-sibling mappings; rejects duplicate or
ambiguous structures, annotations, invalid key segments, and non-finite numbers; and
preserves one-based starts plus complete spans in secret-safe provenance.

The implementation exposed two compatibility constraints that are now durable in the
guide and ADR 0005. Direct `Node.entries` traversal is required because `getProps` would
collapse duplicate properties, and argument cardinality means a one-element array has no
version-one argument spelling. The latter finding was propagated to EP-7's conformance
fixture design. A 2026-07-18 maintenance audit replaced the stale corpus-driven 1.0.1
exact pin with Cabal compatibility for `>=1.1.1 && <1.2` and a reproducible Nix 1.1.1
archive. Upstream 1.1.1 retains the parser and AST behaviors on which those decisions rest,
so no adapter API, mapping, provenance, error, or EP-7 fixture change is required.

The completed package uses the canonical package-local GHC2024 common stanza in its
library and test suite and passes the shared prelude, strict-record, explicit-deriving,
lens, and qualified-import conventions. Its 18 focused tests bring the workspace total
to 100. All Cabal builds, tests, package checks, Haddocks, and source distributions pass;
the KDL archive contains its public module, characterization and behavior tests, and
fixtures. Mori lists all five package roots, both dedicated and default Nix builds pass,
and the full host-platform flake check is clean.


## Context and Orientation

This plan depends on
`docs/plans/2-implement-hierarchical-resolution-provenance-and-derived-defaults.md` and
`docs/plans/8-move-settei-packages-to-top-level-sibling-directories.md`. The core plan
supplies the raw value tree, ordered `Source` semantics, per-key origin extension,
locations, structured errors, and redaction. The layout plan moves the core to `settei/`
and establishes same-named top-level roots for adapters. Read their actual implementation,
the relevant ADRs, and the relocated core modules before coding.

`mori registry search kdl` locates the `kdl-hs` project at
`/Users/shinzui/Keikaku/hub/kdl-hs-project`, whose corpus checkout is package version
1.0.1. The current upstream and Hackage release is 1.1.1. Use Mori first to locate source
and documentation, but verify Hackage and upstream release tags before selecting the
version. Inspect the selected release's parser, AST, Applicative, Arrow, and span modules;
use the names and constructors in that release rather than treating a corpus snapshot or
an illustrative signature in this plan as current.

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

Create `settei-kdl/settei-kdl.cabal`, expose `Settei.Kdl`, and register the
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

Run from `/Users/shinzui/Keikaku/bokuno/settei`. Locate the dependency, determine the
current upstream release, and read the selected release's source before importing
anything:

```bash
mori show --full
mori registry search kdl
mori registry search generic-lens
mori registry show ekmett/lens --full
mori registry show shinzui/haskell-jitsurei --full
mori registry docs shinzui/haskell-jitsurei
cabal list --simple-output kdl-hs
git ls-remote --tags https://github.com/brandonchinn178/kdl-hs.git
```

Use the qualified result returned by the registry:

```bash
mori registry show QUALIFIED_KDL_PROJECT --full
mori registry docs QUALIFIED_KDL_PROJECT
```

Read the source path reported by Mori with scoped searches. If its checkout is older than
the selected upstream release, obtain that release from Hackage or its upstream tag and
run the same scoped source audit there:

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

If the selected upstream `kdl-hs` API differs from the planning snapshot, update this plan
with the actual version and evidence before adapting imports. If a desired span is unavailable,
report the nearest substantiated enclosing span and document the precision; never synthesize
line numbers. If the raw tree cannot represent a scalar losslessly, return a mapping error
instead of coercing it.


## Interfaces and Dependencies

Package `settei-kdl` depends on `settei`, `base`, `containers`, `text`, and upstream-audited
`kdl-hs >=1.1.1 && <1.2`, plus only the numeric or path dependencies required by its AST.
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

2026-07-17: Made the completed sibling-layout migration in Plan 8 a hard dependency and
changed the future package root from `packages/settei-kdl/` to `settei-kdl/`. This keeps
the plan self-contained against the relocated `settei/` core and prevents new work from
reintroducing the rejected package container.

2026-07-17: Reconciled the plan with the implemented `kdl-hs` 1.0.1 AST translator. The
living sections now record the duplicate-preserving entry traversal, parser-excerpt
redaction, exact Cabal/Nix pin, supported KDL v2 scalar policy, and the cardinality rule
that prevents an argument-style one-element array. ADR 0005 now owns those durable format
decisions.

2026-07-18: Corrected the corpus-driven dependency choice after auditing Hackage and the
upstream `v1.1.1` source. The stale 1.0.1 exact bound and archive were replaced by Cabal's
audited 1.1 release range and a reproducible Nix 1.1.1 archive. The latest AST still
preserves entries and spans, `getProps` still collapses duplicates, and parse failures
still contain excerpts, so the canonical mapping, direct traversal, redaction boundary,
one-element-array limitation, and all other adapter decisions remain unchanged.
