---
id: 2
slug: implement-hierarchical-resolution-provenance-and-derived-defaults
title: "Implement hierarchical resolution, provenance, and derived defaults"
kind: exec-plan
created_at: 2026-07-16T23:50:01Z
intention: intention_01kxr36cqgem8tmxjjtnq0t6ns
master_plan: "docs/masterplans/1-build-settei-as-a-provenance-aware-configuration-library-for-haskell.md"
---

# Implement hierarchical resolution, provenance, and derived defaults

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture

After this plan, an application can give Settei an ordered collection of hierarchical
sources and a typed `Config` declaration and receive both the application value and a
complete, secret-safe account of its construction. Each resolved leaf says what won, what
was shadowed, and why. Missing settings and bad high-priority values produce structured
errors. Constant defaults and named defaults derived from other declared settings are
first-class origins, so a report can say that a production port came from rule
`service-port-by-environment` because `runtime.environment` resolved to `Production`.

The result is format-independent. File, environment, and CLI packages implemented by later
plans only construct `Source` values and origin metadata; they never implement their own
merge logic.


## Progress

- [x] Define the source tree, candidates, origin extension points, and resolution errors.
- [ ] Implement deterministic leaf-wise precedence and unknown-key diagnostics.
- [ ] Add constant and dependency-aware default declarations.
- [ ] Interpret selective branches while recording dependency and branch traces.
- [ ] Render redacted text and JSON schema and resolution reports.
- [ ] Add law, golden, and adversarial redaction tests and record the semantics in an ADR.


## Surprises & Discoveries

- The raw tree and candidate types cannot safely derive `Show`: both can carry a secret
  before Settei knows the owning setting's sensitivity. Tests compare them without
  interpolating rejected values into failures.


## Decision Log

- Decision: Accept sources from lowest to highest precedence and choose the rightmost
  present candidate independently for each declared key.
  Rationale: this makes common stacks read naturally as defaults, global file, local file,
  environment, then CLI, while allowing a high layer to override only one nested leaf.
  Date: 2026-07-16

- Decision: Treat a present but malformed winning candidate as an error, not as a reason to
  try a lower-precedence value.
  Rationale: silent fallback hides deployment mistakes and can unexpectedly activate stale
  credentials or endpoints.
  Date: 2026-07-16

- Decision: Replace arrays and non-object values wholesale; recursively combine object
  paths only through independent declared leaf lookups.
  Rationale: implicit list concatenation has no format-independent or generally safe
  meaning. Per-setting decoders remain in control of complex values.
  Date: 2026-07-16

- Decision: Make defaults named declarations with explicit `Config` dependencies rather
  than arbitrary functions over the final application record.
  Rationale: the evaluator can statically inspect dependencies and the explanation can
  show a truthful derivation chain.
  Date: 2026-07-16

- Decision: Redaction is enforced by core report and error data types, not only by terminal
  renderers.
  Rationale: an unredacted intermediate report could leak through JSON, logs, tests, or an
  accidentally derived `Show` instance.
  Date: 2026-07-16

- Decision: Extend the convention baseline established by Plan 1 rather than introducing
  provenance-prefixed record fields or direct record access.
  Rationale: shared labels such as `name`, `kind`, `key`, `value`, `location`, and
  `annotations` are clearer under `DuplicateRecordFields`; generic-lens keeps access and
  updates unambiguous without encoding type names into the public API.
  Date: 2026-07-16

- Decision: Represent origin customization as exact-key locations plus ordered source
  annotations, with the core constructing the common `Origin` fields.
  Rationale: adapters retain spans and domain metadata without gaining the ability to
  change logical keys or precedence in an origin factory. Standard Kubernetes references
  are encoded through shared typed constructors and stable annotation names.
  Date: 2026-07-17


## Outcomes & Retrospective

To be filled during and after implementation. Completion requires a resolution-semantics
ADR and evidence that no supported renderer or error path reveals a marked secret. It also
requires the new modules and tests to retain Plan 1's common GHC2024 stanza, custom
prelude, strict unprefixed records, explicit deriving, lens access, and import style.


## Context and Orientation

This plan depends on the checked-in design in
`docs/plans/1-bootstrap-settei-and-prove-the-inspectable-configuration-algebra.md`.
That plan establishes a root package named `settei`, a non-empty segmented `Key`, a common
`RawValue`, typed `Setting` declarations, a `Config` with Functor, Applicative, and
Selective composition, and static `Schema` inspection. Read its resulting ADR and actual
modules before implementing this plan; if implementation names differ, update this living
document to use the checked-in names.

A source is a labeled hierarchical data tree plus enough metadata to construct an origin
when a logical key is found. A candidate is one source's value and origin for one declared
key. Provenance is not just the winning source: it includes shadowed candidates, default
rules, dependency edges, and selective branch decisions. A resolution report describes a
particular run, while the schema from Plan 1 describes every possible run.

Seihou is useful prior art for human-facing explanations: it has layered `VarSource`,
`ResolvedVar`, and `formatExplain` concepts. Rei and Mori provide file-discovery examples
but track provenance at coarser granularity. Locate their registered paths with `mori`
before consulting source; do not copy consumer-specific types into Settei. The goal is the
generalized contract required by all later adapters.

Plan 1 owns the applicable `shinzui/haskell-jitsurei` baseline. Import `Settei.Prelude` in
new modules, import `Data.Generics.Labels ()` locally wherever `#label` is used, and keep
the orphan instance out of the prelude. Use strict fields and no type-name field prefixes;
derive instances with explicit `stock`, `newtype`, or `anyclass` strategies. Read and
update records with lens operators, including `at` and `ix` for maps, and write qualified
imports as `import Module qualified as Alias`. Function-valued records may derive
`Generic`, but must not derive `Show` when doing so could expose raw or secret-bearing
values. The durable rationale is in
[ADR 0001](../adr/0001-haskell-project-conventions.md); the algebra produced by Plan 1 is
recorded in `docs/adr/0002-inspectable-configuration-algebra.md`.


## Plan of Work

### Milestone 1: define source and origin data

Add `src/Settei/Source.hs`, `src/Settei/Origin.hs`, and
`src/Settei/Provenance.hs`. A source has a stable name, a `RawValue` tree, its precedence
position from caller-provided order, and an origin factory. Keep the origin extensible
without a closed dependency on YAML, KDL, Dhall, environment, or CLI packages. A core
origin should contain a source kind, source name, logical `Key`, optional location, and
ordered annotations. Later packages can populate standardized annotations such as an
environment variable, CLI spelling, path, document span, Kubernetes object kind and name,
or Dhall imports.

Use structured public data rather than pre-rendered strings. At minimum expose concepts
equivalent to:

```haskell
data SourceKind
  = BuiltInSource
  | FileSource !Text
  | EnvironmentSource
  | CommandLineSource
  | DerivedSource
  | CustomSource !Text
  deriving stock (Generic, Eq, Ord, Show)

data Origin = Origin
  { kind :: !SourceKind
  , name :: !Text
  , key :: !Key
  , location :: !(Maybe SourceLocation)
  , annotations :: !(Map Text Text)
  }
  deriving stock (Generic, Eq)

data Source = Source
  { name :: !Text
  , kind :: !SourceKind
  , root :: !RawValue
  , locationAt :: !(Key -> Maybe SourceLocation)
  , originAt :: !(Key -> Maybe SourceLocation -> Origin)
  }
  deriving stock (Generic)
```

Use smart constructors if this exact record would expose invalid states. Source
annotations are descriptive, never used to alter precedence. `locationAt` lets an
adapter retain a successful node span without changing the common raw tree; returning
`Nothing` is honest when its parser discarded that information. Keep source order outside
`Source`, so the same source can be placed at different precedence by different apps.

Define typed constructors or stable annotation names for Kubernetes ConfigMap and Secret
references in `Settei.Origin`. They contain optional namespace, object name, and object key
only and perform no cluster lookup. All adapters can then attach the same metadata without
depending on one another or inventing incompatible text keys.

Implement structural lookup by `Key` segments. An object is traversed one segment at a
time. A scalar or array may be returned at its exact declared key; trying to traverse
through it produces a structural error. Do not flatten keys with string-prefix tricks.

### Milestone 2: implement deterministic resolution

Add `src/Settei/Resolve.hs` and `src/Settei/Error.hs`. Interpret a `Config a` against
`[Source]`, explicitly documented as low-to-high precedence. For each setting, collect
all present candidates in source order, choose the last, decode it once, and retain the
earlier candidates as shadowed provenance. Absence is not an error until the declaration
requires the setting and no default applies.

Do not decode lower candidates merely to decide whether the winner is valid. A malformed
winner produces a `DecodeError` containing the key, expected type or decoder description,
origin, and a redacted value representation. A malformed shadowed value may produce a
non-fatal diagnostic if doing so cannot expose secrets; the default policy should avoid
decoding values that do not affect the result.

Detect unused object leaves after resolution and return them as diagnostics with their
source origins. Make strictness a resolver option: default to warnings for unknown keys so
mixed documents remain usable, and allow applications and tests to promote them to
errors. Conflicting scalar/object shapes at a declared traversal path are always errors.

The result must separate success from diagnostics:

```haskell
data ResolveOptions = ResolveOptions
  { unknownKeyPolicy :: !UnknownKeyPolicy
  }
  deriving stock (Generic, Eq, Show)

data ResolveResult a = ResolveResult
  { value :: !a
  , report :: !ResolutionReport
  , warnings :: ![ConfigWarning]
  }
  deriving stock (Generic)

resolve
  :: ResolveOptions
  -> [Source]
  -> Config a
  -> Either (NonEmpty ConfigError) (ResolveResult a)
```

If the chosen algebra supports independent applicative error accumulation, return all
independent errors in deterministic declaration order. A selective branch must report
only errors from effects actually evaluated on that branch.

### Milestone 3: add inspectable defaults and conditional requirements

Add `src/Settei/Default.hs` and extend `Settei.Config` with optional settings that have
defaults. A constant default has a rule name, explanation, and value. A
derived default additionally declares a `Config d` dependency and a pure function from
that dependency to the target value. The dependency remains part of the schema and the
runtime trace. A default inherits sensitivity from its target `Setting`; it cannot
downgrade or independently relabel the target.

The intended interface is:

```haskell
newtype RuleName = RuleName Text
  deriving stock (Generic, Eq, Ord, Show)

data Default a

constantDefault
  :: RuleName -> Text -> a -> Default a

derivedDefault
  :: RuleName -> Text -> Config d -> (d -> a) -> Default a

withDefault
  :: Setting a -> Default a -> Config a
```

Add a finite case helper for the common environment pattern. It should be a normal named
derived rule, not a separate evaluator escape hatch:

```haskell
caseDefault
  :: (Ord d, Show d)
  => RuleName
  -> Text
  -> Config d
  -> NonEmpty (d, a)
  -> Maybe a
  -> Default a
```

If a user supplies the target setting, its winning source overrides the default. If the
target is absent, evaluate only the default's declared dependencies, record their report
nodes, and create a derived origin that references the rule and those nodes. Reject cycles
between default rules during schema validation before source evaluation. Avoid exposing a
function from a completed application record to a default because its dependencies would
be unknowable.

Use the Selective instance established in Plan 1 for settings that are conditionally
required, such as a password only in production. Derived values alone do not require
Selective; Applicative dependencies are sufficient. Keep these two concepts distinct in
documentation and tests.

Follow the record convention in production and test helpers: construct records with
unprefixed labels, inspect them with `(^.)`, and update them with `(.~)`, `(%~)`, `(?~)`,
`at`, or `ix`. Do not reintroduce generated selector calls or record update syntax in the
resolver merely because many report structures share field names.

### Milestone 4: build safe reports and renderers

Add `src/Settei/Report.hs` and `src/Settei/Render.hs`. Represent each evaluated setting as
a stable node with its key, sensitivity, outcome, chosen origin, shadowed origins, and
derivation or conditional edges. Store display values only in a redaction-aware type whose
secret constructor cannot be unwrapped by public reporting functions. The typed
The `value` in `ResolveResult` remains available to the application.

Provide deterministic text and JSON renderers for `Schema`, `ResolutionReport`, errors,
and warnings. Text should optimize for `--explain-config`; JSON should be versioned with a
top-level schema version. Both renderers must distinguish a value omitted because it is
not needed on the selected branch from a missing required value.

An explanation should communicate at least:

```text
service.port = 443
  from default rule service-port-by-environment
  because runtime.environment = Production
    from environment variable HASKELL_ENV
  shadowed: built-in constant 8080
database.password = <redacted>
  from environment variable DATABASE_PASSWORD
```

Exact whitespace is controlled by golden tests. Never put real secrets in golden update
output, test failure messages, `Show` output, or JSON snapshots.

### Milestone 5: laws, adversarial tests, and ADR

Add unit and property tests for source ordering, hierarchical paths, array replacement,
bad winners, unknown-key policy, independent error accumulation, selective skipping,
default cycles, derivation chains, stable ordering, and all renderers. Generate secret
strings containing unusual punctuation and assert that none occurs anywhere in rendered
reports or errors.

Create `docs/adr/0003-resolution-provenance-and-default-semantics.md`. Include source
ordering, leaf semantics, array replacement, malformed-winner behavior, warning policy,
redaction boundary, and the difference between static schema and actual resolution trace.


## Concrete Steps

Run commands from `/Users/shinzui/Keikaku/bokuno/settei`. First inspect the completed
algebra and prior art through Mori:

```bash
mori show --full
mori registry list
mori registry search seihou
mori registry search rei
mori registry search mori
mori registry search generic-lens
mori registry show ekmett/lens --full
mori registry show shinzui/haskell-jitsurei --full
mori registry docs shinzui/haskell-jitsurei
```

Use the qualified names returned by search rather than guessing them:

```bash
mori registry show QUALIFIED_PROJECT_NAME --full
mori registry docs QUALIFIED_PROJECT_NAME
```

After each milestone, run:

```bash
nix fmt
cabal test settei-tests --test-show-details=direct
```

At completion, run the whole project validation:

```bash
cabal build all
cabal test all --test-show-details=direct
nix flake check
```

Expected behavior-focused test names include:

```text
Settei.Resolve
  rightmost source wins per leaf: OK
  malformed winner does not fall back: OK
  arrays replace rather than concatenate: OK
Settei.Default
  production port records environment dependency: OK
  cyclic defaults fail before evaluation: OK
Settei.Render
  every output redacts marked secrets: OK
All tests passed
```


## Validation and Acceptance

Build three in-memory sources: a built-in tree with host and port, a file tree overriding
only host, and an environment-shaped tree overriding only port. Resolving in that order
must return the file host and environment port. The report must show each winner and its
shadowed candidates. Reversing the source order must predictably change the winners.

Make the highest source contain `service.port = "not-a-port"` and a lower source contain a
valid port. Resolution must fail at the high source's origin and must not return the lower
value. Mark a password setting secret, use a unique sentinel as its source value, then
assert the sentinel is absent from all text, JSON, error, warning, and `show`-based outputs.

Declare `runtime.environment` and an optional `service.port` whose named default maps
Development to 8080, Test to 8081, and Production to 443. With only environment supplied,
the value must match the case and the report must contain the rule and dependency edge. An
explicit port must win and place the unused default outside the chosen provenance path.

Declare `database.password` through a selective production-only branch. Development must
resolve without it and report it as not selected; Production must require it. The static
schema must continue to list it as possible in both cases. A pair of mutually dependent
defaults must be rejected as a cycle without trying to read a source.


## Idempotence and Recovery

All tests and formatters are repeatable. The resolver is pure and tests must use in-memory
sources, so implementation does not mutate process environment or user files. Golden files
may be regenerated only after inspecting diffs for accidental secret material.

Add new public types incrementally and keep the package compiling at each milestone. If a
report representation proves insufficient, adapt internal nodes while preserving the
`ResolveResult`, smart constructors, and schema behavior already established. Record any
semantic change in this plan and the ADR before updating adapter work.


## Interfaces and Dependencies

This plan extends package `settei` with public modules `Settei.Source`, `Settei.Origin`,
`Settei.Provenance`, `Settei.Resolve`, `Settei.Default`, `Settei.Error`, `Settei.Report`,
and `Settei.Render`; `Settei` re-exports the ordinary application-facing surface. Keep raw
interpreter machinery internal.

Prefer existing core dependencies from Plan 1. JSON rendering can use the already-inspected
Aeson dependency if `RawValue` chose it; otherwise inspect Aeson with Mori or upstream
source before adding it. Property testing may use a registered QuickCheck package after
the required Mori lookup. `lens` and `generic-lens` remain baseline core dependencies;
every module that uses `#label` imports `Data.Generics.Labels ()` itself. No adapter parser
library belongs in the core.


## Revision Note

2026-07-16: Aligned the resolver and provenance design with the shared Haskell conventions.
Illustrative APIs now use strict unprefixed fields and explicit deriving, and the plan
requires `Settei.Prelude`, local generic-lens instance imports, lens-based record and map
updates, and postpositive qualified imports throughout implementation and tests. The
durable convention baseline is in `docs/adr/0001-haskell-project-conventions.md`, and the
resolution ADR moves to number 0003 after the algebra ADR.
