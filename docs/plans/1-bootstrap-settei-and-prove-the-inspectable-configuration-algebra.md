---
id: 1
slug: bootstrap-settei-and-prove-the-inspectable-configuration-algebra
title: "Bootstrap Settei and prove the inspectable configuration algebra"
kind: exec-plan
created_at: 2026-07-16T23:49:58Z
master_plan: "docs/masterplans/1-build-settei-as-a-provenance-aware-configuration-library-for-haskell.md"
---

# Bootstrap Settei and prove the inspectable configuration algebra

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture

After this plan, Settei is a buildable, tested Haskell library rather than only a Nix
scaffold. A library author can declare typed settings with stable keys, descriptions, and
sensitivity, compose them applicatively, branch selectively, and inspect the declaration
without loading configuration. The inspection result lists settings that are always
needed, settings that may be needed, and conditional relationships. A small executable or
test demonstrates that a production-only secret is visible in the static schema but is not
evaluated on a development branch.

This plan also settles, with executable evidence, whether `selective`'s free
representation can support Settei's static-analysis promise. It does not implement source
precedence or user-facing provenance; those are the subject of Plan 2.


## Progress

- [ ] Add the convention-compliant Cabal project, root `settei` package, test suite, and
  Nix integration.
- [ ] Define keys, raw values, decoders, setting metadata, and the public declaration API.
- [ ] Prototype free-selective interpretation and compare it with a small explicit AST.
- [ ] Implement schema inspection and conditional execution tests.
- [ ] Write the algebra ADR and public module documentation.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Keep the first package at the repository root and name it `settei`; later
  adapters live below `packages/`.
  Rationale: this satisfies the existing Nix scaffold immediately and preserves the simple
  import and package name agreed for the core.
  Date: 2026-07-16

- Decision: Model a key as a non-empty sequence of text segments and render it with dots;
  reject empty segments and literal dots within a segment in version one.
  Rationale: structural segments prevent accidental string-prefix merging, while a narrow
  external grammar is easier to explain consistently across environment, CLI, and file
  adapters. Escaped dots can be added later without changing internal equality.
  Date: 2026-07-16

- Decision: Expose Functor, Applicative, and Selective composition for `Config`, but never
  a Monad instance.
  Rationale: consumers need data-dependent branches with a statically enumerable
  over-approximation; runtime-generated setting declarations would invalidate it.
  Date: 2026-07-16

- Decision: Establish the applicable `shinzui/haskell-jitsurei` conventions in the first
  package and make every later package consume them.
  Rationale: the package family needs one GHC2024 extension baseline, one custom prelude,
  and one record/import style from the first compiling module onward; retrofitting them
  after adapters exist would create needless API and dependency churn.
  Date: 2026-07-16


## Outcomes & Retrospective

To be filled during and after implementation. Completion requires an ADR that records the
chosen representation, the analysis laws demonstrated by tests, and the deliberate absence
of a Monad instance. It also requires evidence that every Cabal component imports the
root package's GHC2024 common stanza and the initial modules follow the prelude,
strict-record, explicit-deriving, lens, and postpositive-qualified-import conventions
described below.


## Context and Orientation

The repository currently contains `flake.nix`, `nix/haskell.nix`, formatting and
pre-commit configuration, and planning skills. It has no `settei.cabal`, `cabal.project`,
`src/`, or `test/`. `nix/haskell.nix` selects GHC 9.12.4 and tries to derive a root package
named `settei`. There is no `mori.dhall`.
[ADR 0001](../adr/0001-haskell-project-conventions.md) is the relevant existing ADR: it
makes this plan the owner of the common Cabal stanza and `Settei.Prelude` and requires every
component to follow the convention baseline embedded below.

Before editing dependencies, follow the repository instruction to run `mori registry
search <package>` and inspect registered source with `mori registry show <project> --full`
and `mori registry docs <project>`. The `selective` repository was not registered during
planning, so its source was inspected from the user-authorized clone at
`/tmp/selective-config-research`. The inspected version is 0.7.0.1 and exposes free
selective analysis through `Control.Selective.Free`, including possible and necessary
effects. Re-run the lookup because the registry may change before implementation. Do not
search `/nix/store`.

A `Setting a` is metadata and a decoder for one logical value. A `Config a` is a
declaration that composes settings and pure computations without having access to any
source. A `Schema` is the conservative, static description produced from a declaration.
"Possible" means a setting occurs on at least one branch; "necessary" means it occurs on
every execution. Runtime resolution and the explanation of a particular execution are
separate interpreters added in Plan 2.

The registered convention source is `shinzui/haskell-jitsurei`, resolved with the Mori
project-details and documentation commands shown in Concrete Steps. The applicable rules
are embedded here. Every component uses GHC 9.12 or newer and imports a Cabal `common`
stanza with `default-language: GHC2024` and the default extensions `DeriveAnyClass`,
`DuplicateRecordFields`, `OverloadedLabels`, and `OverloadedStrings`. Qualified imports use
postpositive syntax, for example `import Data.Map.Strict qualified as Map`. Records have
strict fields, names such as `key` and `description` rather than `settingKey` and
`settingDescription`, and explicit deriving strategies. Modules read and update records
with generic-lens `#label` operators. A module that uses those labels imports
`Data.Generics.Labels ()` locally; the orphan instance is never re-exported from the custom
prelude. Import operators unqualified. When an operator clashes, hide it from the
`Settei.Prelude` import rather than qualifying the operator.


## Plan of Work

### Milestone 1: establish a reproducible package

Create `cabal.project` and `settei.cabal`, expose a `Settei` module, and add a
`settei-tests` Tasty test suite. Add `src/` and `test/` rather than generated source. Use
explicit dependency bounds compatible with GHC 9.12.4. The initial library needs `base`,
`containers`, `text`, `selective`, `lens`, and `generic-lens`; use `aeson` only if
`RawValue` is represented by `Data.Aeson.Value` after inspecting its registered or upstream
source. Tests use `tasty` and `tasty-hunit`, whose registered project is
`UnkindPartition/tasty` at planning time.

At the 2026-07-16 convention audit, Mori resolves both `lens` and `generic-lens` through
registered project `ekmett/lens`. The inspected checkout contains `lens` 5.3.6,
`generic-lens` 2.3.0.0, `Control.Lens`, and the documented orphan instance in
`Data.Generics.Labels`. Refresh the lookup before fixing bounds, because registry contents
may change.

Define this package-local Cabal stanza and import it from every root-package library,
executable, test, and future benchmark component:

```cabal
common common
  default-language: GHC2024
  default-extensions:
    DeriveAnyClass
    DuplicateRecordFields
    OverloadedLabels
    OverloadedStrings
```

Add and expose `src/Settei/Prelude.hs`. It re-exports the small set of `base`, `text`, and
other types actually used across Settei plus `Control.Lens`. Use a file-local
`{-# LANGUAGE PackageImports #-}` pragma and package-qualified imports only in this module
to make re-exports unambiguous; do not add `PackageImports` to the Cabal defaults. Do not
import or re-export `Data.Generics.Labels` here. Other modules import `Settei.Prelude` and
bring `Data.Generics.Labels ()` into scope only when they use generic-lens labels. Keep the
prelude deliberately small: domain types and format-specific helpers stay in their own
modules.

Each later adapter or example has a separate `.cabal` file, so it cannot import this root
package's common stanza. Those plans repeat the same stanza locally and import it from all
components in their package; Plan 1 owns the canonical contents they must copy.

Update `nix/haskell.nix` only as needed for the root Cabal package and test dependencies.
Add `mori.dhall` with `mori init --name settei`, review it rather than accepting accidental
metadata, and make `mori show --full` succeed. The milestone is complete when Cabal and Nix
can build the empty public library and execute one test.

### Milestone 2: define the declaration vocabulary

Add `src/Settei/Key.hs`, `src/Settei/Value.hs`, `src/Settei/Setting.hs`,
`src/Settei/Schema.hs`, and `src/Settei/Config.hs`, then re-export the intended stable
surface from `src/Settei.hs`. Keep constructors internal where they would let callers
bypass key validation or sensitivity.

`Key` contains a `NonEmpty Text`. `parseKey` accepts dotted text only when every segment is
non-empty and contains no dot; `renderKey` is its inverse for accepted inputs. `RawValue`
is the common scalar, array, or object tree that adapters will later construct. Define
decoders for text, booleans, bounded integral values, and explicit enumerations, returning
errors that contain the setting key but not a secret input value.

The public vocabulary must have the following shape, with names allowed to change only if
the ADR explains a clearer alternative:

```haskell
data Sensitivity = Public | Secret
  deriving stock (Generic, Eq, Ord, Show)

data Setting a = Setting
  { key :: !Key
  , description :: !Text
  , sensitivity :: !Sensitivity
  , decoder :: !(RawValue -> Either DecodeFailure a)
  }
  deriving stock (Generic)

data Config a

required :: Setting a -> Config a
optional :: Setting a -> Config (Maybe a)
describe :: Config a -> Schema
```

Provide smart constructors for public and secret settings. Do not derive or hand-write a
`Show` instance for a value that can expose `decoder` input or future resolved
secrets. Record construction may use record syntax, but every record read or update uses
`(^.)`, `(.~)`, `(%~)`, `(?~)`, `at`, or `ix` as appropriate rather than generated record
selectors, record update syntax, or `Map.insert`/`Map.adjust` wrapped around a record
update. Avoid type-name field prefixes throughout; `DuplicateRecordFields` permits later
types to reuse `key`, `name`, `description`, `value`, and `annotations`.

### Milestone 3: prove the selective representation

Build two internal prototypes behind the same public combinators: a wrapper around the
free selective machinery in `Control.Selective.Free`, and the smallest explicit syntax
tree needed for `Pure`, typed setting requests, applicative application, and selective
branching. A prototype may live under `test/Settei/Prototype/`; it need not become public.

Evaluate the candidates against concrete properties rather than elegance alone:

- `describe` terminates without source data and enumerates every possible setting.
- It distinguishes effects necessary on all paths from effects that are conditional.
- A runtime interpreter can skip the unused side of a selective branch.
- Declaration order and stable identifiers survive interpretation so Plan 2 can attach
  explanations.
- The representation can attach Settei-specific metadata to a branch and named derived
  rule without pretending the `selective` package supplies provenance.
- Adding a new primitive interpreter does not require changing every adapter.

Choose one representation and remove the losing production prototype. If the free
selective API cannot preserve stable branch metadata cleanly, use an explicit Settei AST
while retaining the `Selective Config` public behavior. Do not expose the representation.

Add a `productionOnly` test declaration in which `runtime.environment` selects whether
`database.password` is required. Assert that the schema reports the environment as
necessary, the password as possible and conditional, and a development interpretation
does not request the password. Also prove that applicative composition of independent
settings marks both necessary.

### Milestone 4: document the contract

Create `docs/adr/0002-inspectable-configuration-algebra.md`. Record the alternatives,
evidence, chosen internal representation, public laws, schema terminology, and why no
Monad instance will be provided. Add Haddocks with a small declaration example and a
static-schema example. The milestone is complete when a reader can predict the schema of
the production-only declaration without reading implementation modules. Format every
module with Fourmolu and ensure examples use postpositive `qualified` imports. If a
Haddock or golden needs an embedded multi-line value, prefer GHC 9.12's `MultilineStrings`
with a local pragma or a narrowly scoped component extension rather than `unlines`; do not
enable it globally when no source file needs it.


## Concrete Steps

Run all commands from `/Users/shinzui/Keikaku/bokuno/settei`.

First refresh dependency knowledge and initialize project metadata:

```bash
mori registry search selective
mori registry search tasty
mori registry search lens
mori registry search generic-lens
mori registry show UnkindPartition/tasty --full
mori registry show ekmett/lens --full
mori registry show shinzui/haskell-jitsurei --full
mori registry docs shinzui/haskell-jitsurei
mori init --name settei
mori show --full
```

If `selective` remains absent, inspect the existing authorized checkout rather than
guessing its API:

```bash
git -C /tmp/selective-config-research status --short
rg "getEffects|getNecessaryEffects|data Select" /tmp/selective-config-research/src
```

After creating the Cabal files and modules, format and validate:

```bash
nix fmt
cabal build all
cabal test all --test-show-details=direct
cabal check
nix flake check
```

The meaningful portion of the test output should resemble:

```text
Settei.Config
  applicative settings are necessary: OK
  selective production secret is conditional: OK
  development skips production secret: OK
All tests passed
```


## Validation and Acceptance

The repository is accepted as bootstrapped when `cabal build all`, `cabal test all`, and
`nix flake check` succeed on a clean checkout and `mori show --full` identifies the
project. `nix flake show --no-write-lock-file` must no longer report a missing Cabal file.
`cabal check` must accept the package metadata. Inspect `settei.cabal` and confirm every
component imports `common`; inspect representative source and test modules and confirm
strict unprefixed fields, explicit deriving strategies, local label-instance imports, and
postpositive qualified imports.

Key tests must show that `parseKey "database.pool.size"` round-trips, while `""`,
`"database..size"`, and `".database"` fail. Decoder tests must show that invalid public
values yield useful type errors and invalid secret values do not appear in rendered error
text.

For the selective proof, construct one schema with a necessary
`runtime.environment` setting and a conditional `database.password`. `describe` must list
both without reading the process environment. Interpreting the development branch with a
test interpreter must succeed without requesting `database.password`; interpreting the
production branch without it must report the missing setting. No exported instance or
function may permit `Config a -> (a -> Config b) -> Config b`.


## Idempotence and Recovery

`mori registry` queries, builds, tests, and formatters are safe to repeat. Before running
`mori init`, check whether `mori.dhall` has appeared since this plan was written; if it has,
use `mori show --full` and edit the existing file rather than overwriting it. Cabal and Nix
artifacts are disposable and must not be committed.

Keep the representation prototypes isolated from the public modules. If one approach
fails, preserve the failing test as evidence, switch the private implementation, and
update the Decision Log and ADR. Do not rewrite the public API merely to make a prototype
convenient.


## Interfaces and Dependencies

The root component is package `settei`. Its intended public modules are `Settei`,
`Settei.Prelude`, `Settei.Key`, `Settei.Value`, `Settei.Setting`, `Settei.Schema`, and
`Settei.Config`. Internal interpreter and syntax modules use `Settei.Internal.*` and are
not exposed.

Use `selective` for the `Selective` class and its standard combinators. Use free-selective
analysis only if the prototype satisfies the metadata and interpreter criteria. Use
`text` for keys and descriptions and `containers` for deterministic schema collections.
If `Data.Aeson.Value` is chosen as `RawValue`, keep Aeson-specific construction out of the
public declaration algebra so a later major version can replace the representation.

Use `lens` for the operators exported by `Settei.Prelude` and `generic-lens` for local
`#label` access. Package-qualified imports are confined to `Settei.Prelude`; ordinary
modules use normal imports and postpositive `qualified` syntax. Never put the
`Data.Generics.Labels` orphan instance in the prelude.

Tests use `tasty` and `tasty-hunit`. Do not add YAML, KDL, Dhall, environment-process, CLI,
Kubernetes, or effect-system dependencies in this plan.


## Revision Note

2026-07-16: Embedded the applicable `shinzui/haskell-jitsurei` baseline into the bootstrap
work. The revision adds the shared GHC2024 Cabal stanza, `Settei.Prelude`, lens and
generic-lens boundaries, strict unprefixed records, explicit deriving, postpositive
qualified imports, and validation that future packages can inherit the same conventions.
The durable baseline is recorded in `docs/adr/0001-haskell-project-conventions.md`, so the
implementation-time algebra ADR moves to number 0002.
