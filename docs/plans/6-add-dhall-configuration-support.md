---
id: 6
slug: add-dhall-configuration-support
title: "Add Dhall configuration support"
kind: exec-plan
created_at: 2026-07-16T23:50:13Z
master_plan: "docs/masterplans/1-build-settei-as-a-provenance-aware-configuration-library-for-haskell.md"
intention: intention_01kxr36cqgem8tmxjjtnq0t6ns
---

# Add Dhall configuration support

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture

After this plan, an application can evaluate a type-correct Dhall expression into a Settei
source and combine it with every other source. The report identifies the root expression,
the allowed import policy, and the substantiated transitive import set. It does not pretend
that a normalized leaf can always be assigned to the one imported file that originally
contributed it. Imports are controlled by an explicit policy, making network, environment,
and filesystem access visible application choices.

The package is `settei-dhall`. It owns Dhall parsing, import resolution, type checking,
normalization, conversion, and import-level origin metadata; the core still owns setting
decoding, precedence, defaults, provenance edges, redaction, and report rendering.


## Progress

- [x] (2026-07-18 13:27Z) Re-inspect registered `dhall` 1.42.3 and `dhall-json`
  1.7.12 conversion, import-status, cache, and resolver APIs through Mori.
- [x] (2026-07-18 13:31Z) Prove enforceable no-import and canonical-root local
  policies plus cache-independent transitive closure collection in seven prototype tests.
- [ ] Add and register the `settei-dhall` package.
- [x] (2026-07-18 13:47Z) Convert type-checked normalized records, lists,
  optionals, unions, booleans, text, and finite numbers directly through `dhall-json` into
  the core raw tree while preserving association lists as arrays.
- [x] (2026-07-18 13:47Z) Add structured root/import provenance, stable
  secret-safe error phases, honest text rendering, adversarial redaction coverage, and a
  test-process-local Dhall cache directory.
- [ ] Test local imports and publish a Dhall schema-evolution and limitations guide.


## Surprises & Discoveries

- Observation: upstream `Status` exposes the successful import cache and dependency graph
  and permits replacing remote fetches, but it does not expose an interception hook for
  local-file or environment reads. `IgnoreSemanticCache` also leaves the separate
  semi-semantic cache active, so a cache hit can hide a transitive graph from the current
  evaluation.
  Evidence: `Dhall.Import.loadWith` delegates local and environment imports directly to
  `Data.Text.IO.readFile` and `System.Environment.lookupEnv`; only `_remote` and
  `_remoteBytes` are configurable fields in `Dhall.Import.Types.Status`.
  Impact: version one narrows the public policy to `NoImports` and a preflighted
  `LocalImportsWithin`; unrestricted standard imports cannot promise both enforcement and
  a complete observed closure through the maintained public API.

- Observation: an additive preflight can resolve Dhall's chained relative paths through
  `Dhall.Import.chainImport`, canonicalize existing files before reading them, and inspect
  every embedded import because the expression is `Foldable`.
  Evidence: `nix develop -c cabal test settei-dhall-prototype-tests` passes seven tests,
  including transitive imports, `..` escape, symlink escape, rejected capabilities and
  alternatives, and structural semantic-hash retention.
  Impact: the production runner can remain a small adapter around public upstream APIs;
  it does not need to copy or fork Dhall's import interpreter.

- Observation: the Hackage revision for `dhall-json` 1.7.12 retains
  `aeson <2.2`, `bytestring <0.12`, and `text <2.1`, while the registered monorepo source
  for the same release has already widened those bounds to `<2.3`, `<0.13`, and `<2.2`;
  GHC 9.12's package generation uses those newer dependency lines.
  Evidence: successive GHC 9.12 Cabal solves rejected the Hackage revision on those bounds,
  while direct inspection of registered `dhall-json/dhall-json.cabal` shows the widened
  bounds.
  Impact: Cabal relaxes only the three stale `dhall-json` dependency ceilings, and Nix
  applies the equivalent package-local jailbreak while retaining `dhall-json` 1.7.12.


## Decision Log

- Decision: Base value conversion on the inspected `dhall-json` library rather than
  writing a second Dhall normalizer or ad hoc expression decoder.
  Rationale: the official conversion path already composes parsing, imports, type checking,
  normalization, and JSON-compatible conversion.
  Date: 2026-07-16

- Decision: Make import capability an explicit `DhallImportPolicy`; do not silently use
  Dhall's most permissive standard behavior.
  Rationale: configuration loading should not unexpectedly read process environment,
  arbitrary files, or the network.
  Date: 2026-07-16

- Decision: Attribute resolved leaves to the Dhall root plus import closure, not to a
  fabricated individual import.
  Rationale: this is the strongest generally truthful provenance after evaluation and
  normalization.
  Date: 2026-07-16

- Decision: Inherit the shared Haskell conventions and use strict reusable labels for
  Dhall roots and source options instead of Dhall-prefixed selectors.
  Rationale: `DuplicateRecordFields` and local generic-lens access keep the adapter aligned
  with the rest of the package family while avoiding ambiguous direct selectors.
  Date: 2026-07-16

- Decision: Create the package at top-level root `settei-dhall/`, after the sibling-layout
  migration in Plan 8.
  Rationale: every publishable Settei package now uses a same-named repository-root
  directory; creating another package beneath the obsolete `packages/` wrapper would
  immediately require a second move.
  Date: 2026-07-17

- Decision: Omit `StandardImports` from version one and reject import alternatives under
  `LocalImportsWithin`.
  Rationale: the registered upstream API cannot intercept local or environment reads and
  cannot fully disable the semi-semantic cache. Preflighting a no-alternative local graph
  can prove every canonical path is contained before reading it and can collect the exact
  transitive closure independent of upstream cache state; unrestricted or fallback graphs
  cannot provide the same guarantee without copying the upstream interpreter.
  Date: 2026-07-18

- Decision: Use `Dhall.JSON.NoConversion` at the official `dhall-json` boundary and expose
  `loadDhallSourceDetailed` alongside the simpler `loadDhallSource`.
  Rationale: retaining association lists as arrays avoids silently collapsing duplicate
  `mapKey` values, while the detailed result gives callers structured canonical paths,
  import modes, and semantic hashes without encoding them back out of flat annotations.
  Date: 2026-07-18


## Outcomes & Retrospective

To be filled during and after implementation. Completion requires evidence for the
enforceable import policies and a durable ADR or guide section documenting provenance
precision. It also requires the package and its tests to inherit the common GHC2024 stanza
by declaring it package-locally and importing it from every component, and to pass the
shared prelude, strict-record, explicit-deriving, lens, and import-style audit.


## Context and Orientation

This plan depends on
`docs/plans/2-implement-hierarchical-resolution-provenance-and-derived-defaults.md` and
`docs/plans/8-move-settei-packages-to-top-level-sibling-directories.md`. The core plan
supplies `RawValue`, `Source`, extensible origins and annotations, structured errors, and
secret-safe reports. The layout plan moves the core to `settei/` and establishes
same-named top-level roots for adapters. Read their actual implementation, the relevant
ADRs, and the relocated core modules before coding.

At planning time, Mori locates the Dhall Haskell project at
`/Users/shinzui/Keikaku/hub/haskell/dhall-haskell-project`, including package `dhall`
version 1.42.3 and `dhall-json` version 1.7.12. Re-run registry lookup because versions and
source paths can change. Read `Dhall.JSON`, `Dhall.Import`, parser, input, and exception
modules in registered source before choosing functions. Never inspect `/nix/store`.

A root is either expression text with a caller-supplied label or a file path. An import
closure is the set or graph of local, environment, remote, or missing imports the evaluator
actually resolves, including integrity hashes when the library makes them available. It is
source-level provenance, not proof that every imported resource affects every final leaf.

Plan 1 owns the applicable conventions from registered project
`shinzui/haskell-jitsurei`. Import `Settei.Prelude`, bring
`Data.Generics.Labels ()` into only the modules that use `#label`, define strict fields
without type-name prefixes, and derive instances with explicit strategies. Access option,
root, and import-graph records through lenses, including `at` and `ix` for maps. Write
qualified Dhall imports with postpositive `qualified`, and declare `generic-lens` directly
when the adapter imports the label instance.
[ADR 0001](../adr/0001-haskell-project-conventions.md) records the durable rationale and
rejected alternatives for this baseline.


## Plan of Work

### Milestone 1: prove import control and observability

Before creating the public package API, build a test-only prototype against the exact
registered Dhall version. Trace the official path used by `Dhall.JSON.codeToValue` into
`Dhall.Import` and determine where to enforce policy before an import is loaded and where
to collect the imports actually traversed. Do not guess the status or resolver APIs.

The public semantics must support at least:

```haskell
data DhallImportPolicy
  = NoImports
  | LocalImportsWithin !FilePath
  deriving stock (Generic, Eq, Show)
```

`NoImports` rejects every import before reading it. `LocalImportsWithin root` permits local
files whose canonical paths remain within `root` and rejects environment, remote, missing,
and alternative imports. Resolve symlinks and `..` before containment checks. The
registered upstream API cannot enforce and observe unrestricted standard imports through
a maintainable hook, so version one deliberately does not publish that capability.

The inspected public library cannot enforce and observe unrestricted standard imports
through a maintainable API, so version-one support is narrowed to `NoImports` plus
`LocalImportsWithin`. Do not add standard-import provenance unless a future upstream API
can collect actual imports while intercepting every capability before access.

Characterize imports nested through other imports, rejected import alternatives, integrity
hashes, environment imports, remote URLs, cycles, missing files, and cache behavior. Tests
must not contact the network or read the developer's environment.

### Milestone 2: implement value conversion

Create `settei-dhall/settei-dhall.cabal`, expose `Settei.Dhall`, and register the
package in Cabal and Nix. Repeat Plan 1's canonical package-local `common common` stanza
and import it from the library and test components. Because import resolution and cache
access are effects, expose an IO boundary rather than falsely presenting evaluation as
pure:

```haskell
data DhallRoot
  = DhallExpression { name :: !Text, text :: !Text }
  | DhallFile !FilePath
  deriving stock (Generic, Eq)

data DhallSourceOptions = DhallSourceOptions
  { name :: !Text
  , importPolicy :: !DhallImportPolicy
  , annotations :: !(Map Text Text)
  }
  deriving stock (Generic, Eq)

loadDhallSource
  :: DhallSourceOptions
  -> DhallRoot
  -> IO (Either (NonEmpty DhallSourceError) Source)
```

Use the official `dhall-json` conversion proved in Milestone 1 to obtain the JSON-shaped
value, then convert it losslessly to the core `RawValue`. Records map to objects, lists to
arrays, and primitive JSON-compatible Dhall values to their matching scalars. Characterize
and document `Optional`, unions, maps, bytes, and other conversions supported or rejected
by the chosen conversion settings. Never use rendered Dhall source as an intermediate JSON
parser input.

Reject a root that does not produce an object if the core `Source` requires an object
root; otherwise document whole-value settings precisely. Reject record field names that
violate the version-one Settei key-segment grammar, including literal dots. Dhall errors
must retain parse, import, type, normalization, or conversion category without exposing an
unstable upstream exception as the only public contract.

### Milestone 3: retain truthful provenance and protect secrets

Every resulting origin includes the root label or canonical file path, logical Settei key,
import policy, and actual import closure collected during Milestone 1. Represent import
identifiers structurally. For a local import, include a canonical or deliberately relative
safe path; for an environment import, include the variable name but never its value; for a
remote import, redact credentials and sensitive query components and prefer a semantic
hash when present.

Add a provenance precision field or standardized annotation that says the leaf was
evaluated from the root/import graph and that exact leaf attribution is unavailable. The
text explanation should be honest, for example:

```text
service.port = 443
  from Dhall root /etc/my-service/config.dhall
  evaluated with 2 local imports
  leaf-level import attribution unavailable after normalization
```

Do not include source snippets in errors by default: the adapter parses before it knows
which expressions produce secret settings, and a Dhall expression or imported environment
value may be sensitive. Ensure temporary diagnostics and upstream exception rendering do
not echo imported secret values. Run cache-sensitive tests with isolated temporary cache
directories and document upstream cache behavior for applications.

### Milestone 4: tests and documentation

Create fixtures for a direct record, nested record, list, optional values, record
completion/defaulting, a local import chain, a path escape through `..`, a symlink escape,
an import cycle, a type error, unsupported conversion, and a parse error. Test no-import
and local-only policy before any standard-import test. Compare two ordered Dhall sources to
prove that merging remains a core behavior.

Add `docs/guides/dhall.md`. Explain the supported Dhall and conversion versions, canonical
input shapes, import policies and effects, cache behavior, provenance precision, source
ordering, and secret considerations. Include the normal Dhall schema-evolution pattern of
an `Input` type, a `Type` with required fields, a `default`, and a constructor or completion
function; Dhall records themselves do not make arbitrary missing fields optional. Verify
the pattern against registered Dhall documentation before publishing it.


## Concrete Steps

Run from `/Users/shinzui/Keikaku/bokuno/settei`. Refresh the exact project and curated docs:

```bash
mori show --full
mori registry search dhall
mori registry search generic-lens
mori registry show ekmett/lens --full
mori registry show shinzui/haskell-jitsurei --full
mori registry docs shinzui/haskell-jitsurei
```

Use the qualified project name returned by Mori:

```bash
mori registry show QUALIFIED_DHALL_PROJECT --full
mori registry docs QUALIFIED_DHALL_PROJECT
```

Search only the registered source path for the relevant APIs:

```bash
rg "codeToValue|loadWith|Import|Status|ForbidWithinJSON" REGISTERED_DHALL_SOURCE
```

After the import-policy prototype and package implementation, run:

```bash
nix fmt
cabal build settei-dhall
cabal test settei-dhall-tests --test-show-details=direct
cabal test all --test-show-details=direct
nix flake check
```

Expected behavior-focused output includes:

```text
Settei.Dhall
  a typed record becomes a nested source: OK
  NoImports rejects before loading: OK
  local-only records a transitive import closure: OK
  local-only rejects path and symlink escapes: OK
  origins state leaf attribution precision: OK
  diagnostics never reveal imported secret values: OK
All tests passed
```


## Validation and Acceptance

Load a typed nested Dhall record without imports and resolve string, integer, boolean, and
list settings. The report must name the root and logical keys. A type error must fail before
core resolution with a stable Dhall error category.

Load a file that imports two local files transitively under an allowed root. The source
must contain the evaluated values, and every resolved origin must identify the root and the
actual import closure while explicitly declining exact leaf import attribution. With
`NoImports`, the same root must fail before opening the first import. With
`LocalImportsWithin`, `../` and symlink escapes must fail.

No automated test may make a network request or consume a real process environment import.
Document that version one deliberately has no standard-import mode because the maintained
upstream API cannot enforce and observe its network, environment, filesystem, and cache
effects together.

Resolve a unique secret sentinel produced through a Dhall field or controlled environment
import. The typed value may contain the sentinel, but the import graph, Dhall errors,
Settei reports, JSON, logs, goldens, and `Show` output must not.


## Idempotence and Recovery

Mori lookup, local fixture evaluation, formatting, builds, and tests are repeatable.
Isolate Dhall cache and home-directory effects in tests. Do not use remote imports in the
normal test suite, because upstream availability and cache state make them non-reproducible.

Keep policy enforcement behind one internal import runner. If the selected Dhall API
cannot support a promised policy, remove that public constructor before release, update
this living plan and documentation, and retain tests for the narrower guarantee. Never
work around import controls by pre-fetching resources outside the resolver.


## Interfaces and Dependencies

Package `settei-dhall` depends on `settei`, `base`, `containers`, `text`, registered
`dhall` 1.42.3 and `dhall-json` 1.7.12, plus Aeson or bytestring types used by the
official conversion boundary. Use the version bounds established by source inspection and
characterization tests. Add `generic-lens` directly when package modules use `#label`.

The adapter consumes core `Source`, `Origin`, `RawValue`, location, error, and report
extension points. It must not implement core merging or defaults and must not depend on
YAML, KDL, environment, CLI, Kubernetes, or effect-system packages.


## Revision Note

2026-07-16: Aligned the Dhall adapter plan with the registered core Haskell conventions.
The root, policy, and option sketches now use strict fields and explicit deriving without
type-name prefixes, and the plan requires the shared prelude, local generic-lens import,
lens-based access, a direct dependency, and postpositive qualified imports.

2026-07-17: Made the completed sibling-layout migration in Plan 8 a hard dependency and
changed the future package root from `packages/settei-dhall/` to `settei-dhall/`. This
keeps the plan self-contained against the relocated `settei/` core and prevents new work
from reintroducing the rejected package container.

2026-07-18: Narrowed the version-one import policy to `NoImports` and
`LocalImportsWithin` after source inspection proved that upstream exposes neither a
local/environment interception hook nor a complete cache-independent standard-import
closure. Local-only import alternatives are now explicitly rejected so preflight can
validate and substantiate the entire graph before evaluation.
