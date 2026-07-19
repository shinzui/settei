---
id: 16
slug: provide-shared-tagged-format-configuration-loading
title: "Provide shared tagged-format configuration loading"
kind: exec-plan
created_at: 2026-07-19T14:54:49Z
intention: "intention_01kxxdt2m8eysvxggq33jsmt2v"
master_plan: "docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md"
---

# Provide shared tagged-format configuration loading

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Settei is a Haskell configuration library that resolves typed application configuration
from ordered sources (built-in defaults, files, environment variables, command-line
overrides). Today, every multi-format Settei application must hand-write the same two
pieces of plumbing: a command-line reader that parses a tagged input such as
`--config yaml:app.yaml` into a format tag plus a file path, and a loader that dispatches
that tag to the right adapter (`Settei.Yaml`, `Settei.Kdl`, or `Settei.Dhall`). Both
reference applications in this repository —
`examples/settei-cli/src/Settei/Example/Cli.hs` and
`examples/settei-service/src/Settei/Example/Service.hs` — carry byte-for-byte duplicated
copies of this code, roughly forty lines each. Fifty microservices and twenty
applications are about to adopt Settei, and without this plan each of them would paste a
third, fourth, and fiftieth copy.

After this plan is complete, a new publishable package `settei-formats` exists in the
top-level directory `settei-formats/`. It exposes a pure module `Settei.Formats` (the
`FORMAT:PATH` grammar, a format-dispatching loader, and a combined error type) and a
command-line module `Settei.Formats.Optparse` (a ready-made `--config FORMAT:PATH`
option). An adopting application replaces its hand-rolled reader and dispatch with two
imports and two function calls. You can see it working by running the new package's test
suite, which parses all three tag spellings, loads tiny YAML, KDL, and Dhall fixture
files through one function, and proves that Kubernetes provenance annotations pass
through to the produced `Source`.

This plan builds and registers the package, its tests, its guide, and a new ADR. It does
**not** rewrite the two reference applications to use the package — the parent MasterPlan
(docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md) explicitly
defers example adoption to EP-21
(docs/plans/21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md) so
that one deliberate pass rewrites the conformance-boundary examples.


## Progress

- [x] (2026-07-19T20:05:00Z) Milestone 1: `settei-formats/` directory scaffolded (cabal file, LICENSE, CHANGELOG.md).
- [x] (2026-07-19T20:05:00Z) Milestone 1: `Settei.Formats` pure core implemented (`ConfigFormat`, `ConfigInput`,
      `parseConfigInput`, `LoadOptions`, `FormatLoadError`, `loadConfigInput`,
      `renderFormatLoadErrorText`).
- [x] (2026-07-19T20:05:00Z) Milestone 1: package registered in `cabal.project`, `nix/haskell.nix`, and `mori.dhall`;
      `nix develop -c cabal build settei-formats` succeeds.
- [x] (2026-07-19T20:08:00Z) Milestone 2: `Settei.Formats.Optparse` implemented (`configInputReader`,
      `configInputOption`, `configInputOptions`).
- [x] (2026-07-19T20:15:00Z) Milestone 3: test suite `settei-formats-tests` with fixtures written and green via
      `nix develop -c cabal test settei-formats-tests --test-show-details=direct`.
- [x] (2026-07-19T20:15:00Z) Milestone 3: full workspace validation green (`nix develop -c cabal test all`,
      `nix flake check`).
- [ ] Milestone 4: `docs/guides/formats.md` written; pointer edits in
      `docs/guides/README.md`, `docs/guides/cli-application.md`,
      `docs/guides/kubernetes-service.md`; `docs/compatibility.md` public-module list updated.
- [ ] Milestone 4: `docs/adr/0008-settei-formats-umbrella-package.md` written.
- [x] (2026-07-19T20:05:00Z) EP-17 renderers were unavailable, so the typed `Show` stub is active and a
      `TODO(EP-17)` is recorded in `Settei.Formats`; the function type is final so replacement
      will not churn callers.
- [ ] ADR distillation pass done; plan marked complete; MasterPlan registry row updated.


## Surprises & Discoveries

- Observation: EP-17 had not landed when Milestone 1 began, so
  `renderFormatLoadErrorText` currently uses the plan's `Show` fallback over each
  adapter's structured error list.
  Evidence: `rg -n "TODO\(EP-17\)" settei-formats/src/Settei/Formats.hs` finds the
  tracked replacement marker, while the `FormatLoadError` constructors preserve the
  full typed adapter errors for a source-compatible swap later.
  Date: 2026-07-19

- Observation: a Git-backed local flake cannot evaluate a new package directory until
  that path is in Git's index.
  Evidence: the first `nix build .#settei-formats` failed with `path .../settei-formats
  does not exist`; after `git add settei-formats`, the same command built
  `settei-formats-0.1.0.0` successfully.
  Date: 2026-07-19

- Observation: the plan's test sketch predated the correctness initiative's final
  resolver result shape.
  Evidence: `resolve` now returns `ResolveResult`, whose typed success or accumulated
  errors are in `result ^. #answer`; the new three-adapter tests use that accessor and
  all 14 package tests pass.
  Date: 2026-07-19


## Decision Log

- Decision: Deliver tagged-format loading as a new umbrella package `settei-formats`
  rather than extending `settei-optparse-applicative`.
  Rationale: Inherited from the MasterPlan's 2026-07-19 decision. The dispatch code needs
  `settei-yaml`, `settei-kdl`, and `settei-dhall` as dependencies; adding those to the
  optparse adapter would force every CLI consumer to build all three format stacks. An
  umbrella package keeps adapters independent while giving multi-format applications one
  import. The MasterPlan's Integration Points section names this plan the owner of the
  package (name, cabal file, registration in cabal.project, flake wiring under nix/, and
  mori.dhall).
  Date: 2026-07-19

- Decision: `Settei.Formats.Optparse` lives inside the `settei-formats` package, not in a
  fourth micro-package.
  Rationale: One package with module-level separation keeps the pure loader
  (`Settei.Formats`) importable without touching optparse-applicative symbols, at the only
  cost that optparse-applicative is in the package's dependency closure. Every realistic
  consumer of the loader is an application that already links optparse-applicative (that
  is the whole point of `FORMAT:PATH` command-line inputs), so the closure cost is
  theoretical. Rejected alternative: a `settei-formats-optparse` micro-package, which
  would double the registration surface (cabal.project, Nix, Mori, Hackage, changelogs)
  for a single ~30-line module and worsen fleet ergonomics with a second install step.
  Date: 2026-07-19

- Decision: `parseConfigInput` adopts the two examples' grammar and error strings
  verbatim; no behavioral unification is needed.
  Rationale: `configInputReader` (examples/settei-cli/src/Settei/Example/Cli.hs, ~line
  168) and `serviceInputReader` (examples/settei-service/src/Settei/Example/Service.hs,
  ~line 166) are textually identical apart from the constructor names: break the input at
  the first `:`; missing colon or empty path yields `"expected FORMAT:PATH"`; an
  unrecognized format name (including the empty name in an input like `:app.yaml`) yields
  `"FORMAT must be yaml, kdl, or dhall"`. Because the two hand-rolled parsers already
  agree exactly, the shared parser preserves observable behavior for both applications.
  The one deliberate confirmation to record: an empty format with a non-empty path
  (`:app.yaml`) falls through to the unknown-format message, not the missing-colon
  message; the test suite pins this.
  Date: 2026-07-19

- Decision: `LoadOptions` defaults its Dhall import policy to `NoImports`; there is no
  policy-free constructor.
  Rationale: Never default to filesystem imports. A loader that silently followed Dhall
  imports would let one `--config dhall:PATH` argument widen the process's file-read
  surface to arbitrary reachable paths, which contradicts the adapter's own
  security posture (ADR 0006 territory: imports are an explicit, bounded opt-in via
  `LocalImportsWithin`). Callers who need imports must call `withDhallImportPolicy
  (LocalImportsWithin dir)` and thereby name the allowed directory in their own code.
  Both reference applications already pass `Dhall.NoImports` explicitly, so the default
  changes nothing for them.
  Date: 2026-07-19

- Decision: `FormatLoadError` is a three-constructor sum whose constructors each hold the
  originating adapter's complete `NonEmpty` error list; `loadConfigInput` returns
  `Either (NonEmpty FormatLoadError) Source`.
  Rationale: The adapters already return `NonEmpty YamlSourceError` /
  `NonEmpty KdlSourceError` / `NonEmpty DhallSourceError`; wrapping the whole list keeps
  every adapter detail (categories, paths, lines, spans) intact for rendering instead of
  flattening to text as the examples do today (`Text.pack . show`). The outer `NonEmpty`
  makes a single load a singleton but gives callers that load many inputs a natural
  accumulation shape, mirroring the core's `NonEmpty ConfigError` convention, and lets
  EP-21 traverse a `[ConfigInput]` without inventing a second error shape.
  Date: 2026-07-19

- Decision: `renderFormatLoadErrorText` delegates to the per-adapter renderers that EP-17
  (docs/plans/17-add-error-renderers-to-every-source-adapter.md, a soft dependency)
  introduces; if EP-17 has not landed when this plan is implemented, the function is
  stubbed with `Show`-based rendering plus a tracked TODO.
  Rationale: EP-17 owns the fleet-wide rendering contract (`render<Adapter>ErrorText`
  naming, one line per problem, never a raw value). Duplicating that logic here would
  create a second owner. The stub contingency keeps this plan independently deliverable,
  matching the MasterPlan's dependency graph which marks EP-17 as soft. The contingency
  procedure is spelled out in Milestone 1.
  Date: 2026-07-19

- Decision: Teach the package in a new dedicated guide `docs/guides/formats.md`, not a
  section inside `docs/guides/cli-application.md`.
  Rationale: Every other package with its own input behavior has its own guide
  (`yaml.md`, `kdl.md`, `dhall.md`), and both application guides
  (`cli-application.md` and `kubernetes-service.md`) need to point at the same material —
  a shared page avoids duplicating it into two application guides. The application guides
  get short pointer paragraphs only; their full rewrite onto the new API belongs to EP-21.
  Date: 2026-07-19

- Decision: Update `docs/compatibility.md` minimally — its "Public modules" section does
  enumerate the supported module surface, so `Settei.Formats` and
  `Settei.Formats.Optparse` are added there — and leave all other compatibility wording
  to EP-20 and EP-21.
  Rationale: The file was checked (2026-07-19): it lists core modules and adapters as the
  "supported adoption surface", so omitting the new package would make the matrix wrong.
  EP-20 (docs/plans/20-tighten-the-public-surface-and-dependency-hygiene.md) is the final
  authority on the PVP statement and dependency-bound wording; this plan must not
  restructure that file.
  Date: 2026-07-19

- Decision: The Nix derivation for `settei-formats` uses
  `pkgs.haskell.lib.dontCheck`; Cabal remains the test authority.
  Rationale: The package's test suite depends on optparse-applicative 0.19 (for parser
  round-trip tests) plus tasty, and the locked nixpkgs `tasty` derivation still embeds
  optparse-applicative 0.18. This is the exact ABI conflict already documented for
  `settei-optparse-applicative` and the example packages in ADR 0001 and
  `nix/haskell.nix`; the same narrowly-scoped exception applies. `cabal test all` runs
  the suite with one coherent solver plan.
  Date: 2026-07-19

- Decision: This plan makes no edits under `examples/`.
  Rationale: The MasterPlan's Decision Log (2026-07-19) assigns the coherent example
  rewrite to EP-21 because the examples are the public-API conformance boundary
  (docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md) and
  five concurrent plans editing them would conflict constantly. The duplication evidence
  stays in place until EP-21 deletes it.
  Date: 2026-07-19

- Decision: Retain the sibling packages' existing dependency ranges in
  `settei-formats.cabal`, including `containers >=0.6.8 && <0.8`, rather than widening
  only the new package to the latest major release.
  Rationale: Mori inspection confirmed the local APIs used here, and a 2026-07-19
  freshness check against Hackage plus upstream release tags found
  optparse-applicative 0.19.0.0, generic-lens 2.3.0.0, tasty 1.5.4,
  tasty-hunit 0.10.2, containers 0.8, and text 2.1.4. All proposed ranges cover the
  workspace's audited versions except containers 0.8; widening containers for one
  package would create family inconsistency, while EP-20 is explicitly responsible for
  the fleet-wide bounds audit.
  Date: 2026-07-19

- Decision: Assert adapter dispatch through the current `ResolveResult.answer` field in
  the end-to-end tests.
  Rationale: The correctness MasterPlan deliberately made reports and warnings
  available on both success and failure. Matching the current public API keeps this
  plan's behavioral test meaningful without reverting or bypassing that result shape.
  Date: 2026-07-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This repository is a multi-package Haskell workspace rooted at the directory containing
`cabal.project`. All paths below are repository-relative. The publishable package family
lives in same-named top-level sibling directories per
docs/adr/0001-haskell-project-conventions.md: the core is `settei/`, and the adapters are
`settei-env/`, `settei-optparse-applicative/`, `settei-yaml/`, `settei-kdl/`, and
`settei-dhall/`. Non-published reference applications live under `examples/`
(`examples/settei-cli`, `examples/settei-service`, `examples/settei-conformance`); per
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md they are
the conformance boundary for the public API and are deliberately rewritten only by EP-21.

Terms used below. A *source* (`Source`, from `settei/src/Settei/Source.hs`) is one named,
provenance-carrying bundle of raw configuration values; the core resolver merges an
ordered list of sources against a typed declaration. An *adapter* is a package that turns
some external input (a YAML file, a KDL file, a Dhall expression, environment variables,
command-line flags) into a `Source`. An *annotation* is a `Map Text Text` of trusted,
secret-safe origin metadata attached to a source (readable back via
`sourceAnnotations :: Source -> Map Text Text`). A *KubernetesRef*
(`settei/src/Settei/Origin.hs`) is a cluster-independent description of a ConfigMap or
Secret; `kubernetesAnnotations :: KubernetesRef -> Map Text Text` renders it to stable
annotation keys (`kubernetes.object-kind`, `kubernetes.object-name`, optional
`kubernetes.namespace` and `kubernetes.object-key`). No cluster is ever contacted.

The duplication this plan eliminates. Both reference applications hand-roll the same
tagged-input machinery:

- `examples/settei-cli/src/Settei/Example/Cli.hs` defines `ConfigFormat` (~line 66, a sum
  `YamlFormat | KdlFormat | DhallFormat`), `ConfigInput` (~line 70, a record of `format`
  and `path`), `configInputReader` (~line 168, an optparse-applicative `ReadM` for
  `FORMAT:PATH`), and `loadConfigInput` (~line 242, a three-way dispatch calling
  `Yaml.readYamlSource`, `Kdl.readKdlSource`, or `Dhall.loadDhallSource` and collapsing
  each adapter's structured errors to `Text.pack . show`).
- `examples/settei-service/src/Settei/Example/Service.hs` defines `ServiceFileFormat`
  (~line 77), `ServiceInput` (~line 80), `serviceInputReader` (~line 166, textually
  identical grammar and error strings), and `loadServiceInput` (~line 289, the same
  dispatch, additionally threading a `KubernetesRef` into each adapter — via
  `Yaml.fromKubernetesMountedFile` / `Kdl.fromKubernetesMountedFile` for YAML and KDL,
  and via `Dhall.annotateDhallSourceOptions (kubernetesAnnotations ref)` for Dhall,
  which has no `fromKubernetesMountedFile` helper).

The adapter loading APIs the new package composes:

- `settei-yaml/src/Settei/Yaml.hs`: `yamlSourceOptions :: Text -> YamlSourceOptions`
  (start options named by a source label), `annotateYamlSourceOptions`,
  `fromKubernetesMountedFile :: KubernetesRef -> YamlSourceOptions -> YamlSourceOptions`,
  and `readYamlSource :: YamlSourceOptions -> FilePath -> IO (Either (NonEmpty
  YamlSourceError) Source)`.
- `settei-kdl/src/Settei/Kdl.hs`: the same shape — `kdlSourceOptions`,
  `annotateKdlSourceOptions`, `fromKubernetesMountedFile`, and
  `readKdlSource :: KdlSourceOptions -> FilePath -> IO (Either (NonEmpty KdlSourceError)
  Source)`.
- `settei-dhall/src/Settei/Dhall.hs`:
  `dhallSourceOptions :: Text -> DhallImportPolicy -> DhallSourceOptions`,
  `annotateDhallSourceOptions`, `DhallImportPolicy` with constructors `NoImports` and
  `LocalImportsWithin !FilePath`, the root type `DhallRoot` with constructor
  `DhallFile !FilePath`, and `loadDhallSource :: DhallSourceOptions -> DhallRoot ->
  IO (Either (NonEmpty DhallSourceError) Source)`.
- `settei-optparse-applicative/src/Settei/Optparse.hs` sets the option-building house
  style this plan follows: a default parser (`configPathOptions`, `overrideOptions`)
  delegating to a `...With` variant taking a caller-supplied
  `Mod OptionFields a` (`configPathOptionsWith`, `overrideOptionsWith`), built with
  `Options.Applicative.many`, `Options.option`, and `Options.eitherReader`.

Packaging surface to replicate. `cabal.project` lists nine package roots and a
`package NAME` / `tests: True` stanza per package. `flake.nix` is a thin shell that
imports `nix/haskell.nix`, `nix/treefmt.nix`, and `nix/pre-commit.nix`; all Haskell
package wiring lives in `nix/haskell.nix`, which builds each package with
`haskellPackages.callCabal2nix`, passes sibling packages as overrides, and exposes each
as `packages.<name>`. `mori.dhall` registers every package with name, path, description,
and dependency list for the Mori corpus. Each sibling package directory owns its `.cabal`
file, `LICENSE`, `CHANGELOG.md`, `src/`, and `test/`; a check on 2026-07-19 confirmed the
sibling packages have **no** per-package README (the root `README.md` is the family
navigation document), so `settei-formats` gets none either.
`settei-yaml/settei-yaml.cabal` is the template for the canonical `common common` stanza
(ADR 0001: stanzas do not cross package files, so the new cabal file repeats it) and for
metadata: `cabal-version: 3.8`, BSD-3-Clause, author/maintainer `shinzui`, category
`Configuration`, `tested-with: GHC ==9.12.4`, and `data-files` plus an autogenerated
`Paths_*` module for test fixtures.

Relevant ADRs consulted (repository-relative paths):

- docs/adr/0001-haskell-project-conventions.md — sibling-directory layout, the canonical
  common stanza (GHC2024 with `DeriveAnyClass`, `DuplicateRecordFields`,
  `OverloadedLabels`, `OverloadedStrings`; `-Wall -Wcompat`), lens/generic-lens record
  conventions (strict unprefixed fields, accessor functions using `^. #label`, explicit
  deriving strategies, postpositive `qualified`), the `Settei.Prelude` baseline, the
  Mori-first dependency research process with independent release-freshness checks, and
  the documented optparse-applicative-0.19/tasty ABI exception in Nix.
- docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md — the
  examples are adoption evidence and are rewritten deliberately; this plan therefore
  leaves them untouched.
- docs/adr/0006-dhall-input-import-and-provenance-semantics.md (headings scanned) —
  import policy is an explicit, bounded opt-in; supports the `NoImports` default.

The parent MasterPlan, docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md,
records the umbrella-package decision (Decision Log, 2026-07-19), names this plan the
package owner (Integration Points), marks EP-17 as this plan's only (soft) dependency,
and requires that if implementation settles on a different package name, this plan and
EP-21 and the MasterPlan are updated in the same change. No renaming is anticipated.

Dependency research reminder (ADR 0001): before finalizing any dependency bound in the
new cabal file, use `mori registry` commands to inspect sources locally, and verify
current released versions against Hackage independently; the bounds specified in this
plan mirror the already-audited sibling cabal files, so new research is only needed if a
sibling bound has changed by implementation time.


## Plan of Work

The work is four milestones. Milestone 1 creates and registers the package with the pure
`Settei.Formats` module and proves it builds. Milestone 2 adds the optparse module.
Milestone 3 adds the test suite with fixtures and gets the whole workspace green.
Milestone 4 writes the guide, the doc pointers, and the new ADR. Each milestone is
independently verifiable with the commands given in Concrete Steps.

### Milestone 1: package scaffold, pure core, registration

Scope: after this milestone, `settei-formats/` exists with a compiling library exposing
`Settei.Formats`, and the package is registered in `cabal.project`, `nix/haskell.nix`,
and `mori.dhall`. Acceptance: `nix develop -c cabal build settei-formats` succeeds from
the repository root, and `nix build .#settei-formats` produces the package.

Create the directory `settei-formats/` with `src/`, `test/`, and `test/fixtures/`
subdirectories. Copy the repository `LICENSE` file to `settei-formats/LICENSE` (every
sibling carries its own copy). Create `settei-formats/CHANGELOG.md`:

```markdown
# Changelog for settei-formats

## 0.1.0.0 — Unreleased

- Initial experimental release.
- Add tagged `FORMAT:PATH` configuration inputs, a shared loader dispatching to the
  YAML, KDL, and Dhall adapters, and a reusable `--config FORMAT:PATH` option.
```

Create `settei-formats/settei-formats.cabal`. The full file follows; the `common common`
stanza is copied from `settei-yaml/settei-yaml.cabal` because ADR 0001 requires each
package file to repeat the canonical stanza. The test-suite stanza is written now but the
test files arrive in Milestone 3; if you prefer strictly compiling commits, add the
test-suite stanza in the Milestone 3 commit instead — both orders are acceptable.

```cabal
cabal-version:      3.8
name:               settei-formats
version:            0.1.0.0
synopsis:           Tagged multi-format configuration loading for Settei
description:
  Parse tagged FORMAT:PATH configuration inputs and load them through the
  Settei YAML, KDL, and Dhall adapters with one shared dispatcher, so
  multi-format applications stop hand-rolling the same reader and loader.

homepage:           https://github.com/shinzui/settei
bug-reports:        https://github.com/shinzui/settei/issues
license:            BSD-3-Clause
license-file:       LICENSE
author:             shinzui
maintainer:         shinzui
category:           Configuration
build-type:         Simple
tested-with:        GHC ==9.12.4
extra-doc-files:    CHANGELOG.md
data-files:
  test/fixtures/*.dhall
  test/fixtures/*.kdl
  test/fixtures/*.yaml

source-repository head
  type:     git
  location: https://github.com/shinzui/settei.git

common common
  default-language:   GHC2024
  default-extensions:
    DeriveAnyClass
    DuplicateRecordFields
    OverloadedLabels
    OverloadedStrings

  ghc-options:        -Wall -Wcompat

library
  import:          common
  hs-source-dirs:  src
  exposed-modules:
    Settei.Formats
    Settei.Formats.Optparse

  build-depends:
    , base                         >=4.21    && <5
    , containers                   >=0.6.8   && <0.8
    , generic-lens                 >=2.2     && <2.4
    , optparse-applicative         >=0.19    && <0.20
    , settei                       ==0.1.0.0
    , settei-dhall                 ==0.1.0.0
    , settei-kdl                   ==0.1.0.0
    , settei-optparse-applicative  ==0.1.0.0
    , settei-yaml                  ==0.1.0.0
    , text                         >=2.1     && <2.2

test-suite settei-formats-tests
  import:          common
  type:            exitcode-stdio-1.0
  hs-source-dirs:  test
  main-is:         Main.hs
  other-modules:
    Paths_settei_formats
    Settei.FormatsOptparseTest
    Settei.FormatsTest

  autogen-modules: Paths_settei_formats
  build-depends:
    , base                  >=4.21    && <5
    , containers            >=0.6.8   && <0.8
    , generic-lens          >=2.2     && <2.4
    , optparse-applicative  >=0.19    && <0.20
    , settei                ==0.1.0.0
    , settei-dhall          ==0.1.0.0
    , settei-formats        ==0.1.0.0
    , tasty                 >=1.5     && <1.6
    , tasty-hunit           >=0.10.2  && <0.11
    , text                  >=2.1     && <2.2
```

Notes on the dependency list: `settei-optparse-applicative` is a library dependency
because the umbrella package is the one-stop import for multi-format CLI applications and
EP-21 composes `Settei.Formats.Optparse` with `Settei.Optparse` (`overrideOptions`,
`cliSources`); depending on it here also lets `Settei.Formats.Optparse` stay stylistically
and versionally coupled to the CLI adapter it complements. `generic-lens` is a direct
dependency because modules use `Data.Generics.Labels ()` locally (ADR 0001 forbids
relying on transitive visibility). The exact `==0.1.0.0` intra-family bounds mirror every
sibling cabal file.

Create `settei-formats/src/Settei/Formats.hs`. This is the pure core plus the one
IO-performing loader. Its design, in full, so a novice can implement it directly. The
module header and exports:

```haskell
-- |
-- Module: Settei.Formats
-- Description: Tagged multi-format configuration inputs and a shared adapter loader.
module Settei.Formats
  ( ConfigFormat (..),
    ConfigInput,
    FormatLoadError (..),
    LoadOptions,
    annotateLoadOptions,
    configInput,
    configInputFormat,
    configInputPath,
    defaultLoadOptions,
    fromKubernetesMountedFile,
    loadConfigInput,
    loadOptionsAnnotations,
    loadOptionsDhallImportPolicy,
    loadOptionsKubernetesRef,
    parseConfigInput,
    renderFormatLoadErrorText,
    withDhallImportPolicy,
  )
where
```

Imports follow house style (postpositive `qualified`, local
`Data.Generics.Labels ()`, `Settei.Prelude` for lens operators and common types):

```haskell
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Settei
import Settei.Dhall qualified as Dhall
import Settei.Kdl qualified as Kdl
import Settei.Prelude
import Settei.Yaml qualified as Yaml
```

The types. `ConfigFormat` is the open sum (constructors exported), matching the CLI
example's names exactly so EP-21's migration is a re-export-level change. `ConfigInput`
keeps its constructor private (only the smart constructor and accessors are exported),
matching the project convention that record constructors stay private when accessor
functions exist:

```haskell
-- | Explicit format tag required for each configuration input.
data ConfigFormat = YamlFormat | KdlFormat | DhallFormat
  deriving stock (Generic, Eq, Ord, Show)

-- | One ordered, explicitly tagged configuration file.
data ConfigInput = ConfigInput
  { format :: !ConfigFormat,
    path :: !FilePath
  }
  deriving stock (Generic, Eq, Show)

-- | Construct a tagged input programmatically.
configInput :: ConfigFormat -> FilePath -> ConfigInput
configInput format path = ConfigInput {format, path}

-- | Return an input's explicit adapter tag.
configInputFormat :: ConfigInput -> ConfigFormat
configInputFormat value = value ^. #format

-- | Return an input's filesystem path.
configInputPath :: ConfigInput -> FilePath
configInputPath value = value ^. #path
```

The grammar. `parseConfigInput` is extracted verbatim from the two example readers (they
are textually identical; see the Decision Log). The exact error strings are load-bearing:
tests in both example packages and this package assert them.

```haskell
-- | Parse the @FORMAT:PATH@ grammar: @yaml:PATH@, @kdl:PATH@, or @dhall:PATH@.
--
-- A missing colon or an empty path fails with @expected FORMAT:PATH@. Any other
-- format name, including an empty one as in @:app.yaml@, fails with
-- @FORMAT must be yaml, kdl, or dhall@.
parseConfigInput :: String -> Either String ConfigInput
parseConfigInput input =
  let (formatName, separatorAndPath) = break (== ':') input
      filePath = drop 1 separatorAndPath
   in if null separatorAndPath || null filePath
        then Left "expected FORMAT:PATH"
        else case formatName of
          "yaml" -> Right (configInput YamlFormat filePath)
          "kdl" -> Right (configInput KdlFormat filePath)
          "dhall" -> Right (configInput DhallFormat filePath)
          _ -> Left "FORMAT must be yaml, kdl, or dhall"
```

The load options. `LoadOptions` captures exactly what the two examples needed and nothing
more: an optional `KubernetesRef` for mounted-file provenance, extra caller annotations,
and the Dhall import policy. The constructor stays private; the default plus three
builders are the API. `defaultLoadOptions` must default the policy to
`Dhall.NoImports` — never default to filesystem imports (see the Decision Log for the
safety rationale; record it in the Haddock too):

```haskell
-- | How loaded sources should be annotated and how Dhall imports are policed.
data LoadOptions = LoadOptions
  { kubernetesReference :: !(Maybe KubernetesRef),
    annotations :: !(Map Text Text),
    dhallImportPolicy :: !Dhall.DhallImportPolicy
  }
  deriving stock (Generic)

-- | No Kubernetes reference, no extra annotations, and @NoImports@ for Dhall.
--
-- The Dhall default is deliberately the most restrictive policy: a loader must
-- never follow filesystem imports unless the caller explicitly names an allowed
-- directory with 'withDhallImportPolicy'.
defaultLoadOptions :: LoadOptions
defaultLoadOptions =
  LoadOptions
    { kubernetesReference = Nothing,
      annotations = Map.empty,
      dhallImportPolicy = Dhall.NoImports
    }

-- | Attach a trusted Kubernetes reference for a mounted file. No cluster lookup occurs.
fromKubernetesMountedFile :: KubernetesRef -> LoadOptions -> LoadOptions
fromKubernetesMountedFile reference options =
  options & #kubernetesReference ?~ reference

-- | Add trusted, secret-safe annotations to every loaded source.
annotateLoadOptions :: Map Text Text -> LoadOptions -> LoadOptions
annotateLoadOptions extra options = options & #annotations %~ (extra <>)

-- | Replace the Dhall import policy (default 'Dhall.NoImports').
withDhallImportPolicy :: Dhall.DhallImportPolicy -> LoadOptions -> LoadOptions
withDhallImportPolicy policy options = options & #dhallImportPolicy .~ policy
```

Also write the three accessors `loadOptionsKubernetesRef :: LoadOptions -> Maybe
KubernetesRef`, `loadOptionsAnnotations :: LoadOptions -> Map Text Text`, and
`loadOptionsDhallImportPolicy :: LoadOptions -> Dhall.DhallImportPolicy` in the same
`value ^. #label` style as the other accessors above. The builder name
`fromKubernetesMountedFile` intentionally matches the YAML and KDL adapters' helper of
the same name; it is unambiguous because this module is imported unqualified only
alongside qualified adapter imports.

The error sum. Each constructor holds the originating adapter's complete `NonEmpty`
error list, so no structure is lost:

```haskell
-- | One failed tagged load, wrapping the originating adapter's full error list.
data FormatLoadError
  = YamlLoadError !(NonEmpty Yaml.YamlSourceError)
  | KdlLoadError !(NonEmpty Kdl.KdlSourceError)
  | DhallLoadError !(NonEmpty Dhall.DhallSourceError)
  deriving stock (Generic, Eq, Show)
```

The loader. It builds each adapter's options from the shared `LoadOptions`: the source
label is the input path rendered as `Text` (both examples do exactly this); the
Kubernetes reference, when present, goes through `Yaml.fromKubernetesMountedFile` /
`Kdl.fromKubernetesMountedFile`, and for Dhall — which has no such helper — through
`Dhall.annotateDhallSourceOptions (kubernetesAnnotations reference)`, exactly as
`loadServiceInput` does today; extra annotations are applied with each adapter's
`annotate*SourceOptions`. A failed load is wrapped in a singleton outer `NonEmpty`:

```haskell
-- | Load one tagged input through the adapter its format names.
loadConfigInput ::
  LoadOptions ->
  ConfigInput ->
  IO (Either (NonEmpty FormatLoadError) Source)
loadConfigInput options input =
  let sourceLabel = Text.pack (input ^. #path)
      wrap wrapError = either (Left . NonEmpty.singleton . wrapError) Right
      kubernetesAnnotationsOf =
        maybe Map.empty kubernetesAnnotations (options ^. #kubernetesReference)
   in case input ^. #format of
        YamlFormat ->
          let yamlOptions =
                Yaml.annotateYamlSourceOptions
                  (options ^. #annotations)
                  ( maybe
                      id
                      Yaml.fromKubernetesMountedFile
                      (options ^. #kubernetesReference)
                      (Yaml.yamlSourceOptions sourceLabel)
                  )
           in wrap YamlLoadError <$> Yaml.readYamlSource yamlOptions (input ^. #path)
        KdlFormat ->
          let kdlOptions =
                Kdl.annotateKdlSourceOptions
                  (options ^. #annotations)
                  ( maybe
                      id
                      Kdl.fromKubernetesMountedFile
                      (options ^. #kubernetesReference)
                      (Kdl.kdlSourceOptions sourceLabel)
                  )
           in wrap KdlLoadError <$> Kdl.readKdlSource kdlOptions (input ^. #path)
        DhallFormat ->
          let dhallOptions =
                Dhall.annotateDhallSourceOptions
                  (kubernetesAnnotationsOf <> options ^. #annotations)
                  ( Dhall.dhallSourceOptions
                      sourceLabel
                      (options ^. #dhallImportPolicy)
                  )
           in wrap DhallLoadError
                <$> Dhall.loadDhallSource dhallOptions (Dhall.DhallFile (input ^. #path))
```

(The sketch above is the intended shape; adjust parenthesization to taste and to
compiler feedback, but preserve the observable behavior: label equals path, reference
and annotations reach the produced `Source`, and the Dhall policy comes from
`LoadOptions`.)

The renderer. `renderFormatLoadErrorText :: FormatLoadError -> Text` composes the
per-adapter renderers that EP-17 adds
(docs/plans/17-add-error-renderers-to-every-source-adapter.md; the MasterPlan fixes the
naming convention as `render<Adapter>ErrorText` style — expect functions shaped like
`Yaml.renderYamlErrorsText :: NonEmpty YamlSourceError -> Text` and its KDL and Dhall
counterparts; confirm the exact exported names in EP-17's plan or the adapter modules at
implementation time). The intended implementation is one case expression delegating each
constructor's payload to its adapter renderer.

Contingency if EP-17 has not landed when you implement this milestone: implement the
function as a `Show`-based stub —

```haskell
-- TODO(EP-17): replace Show-based rendering with the per-adapter
-- render<Adapter>ErrorText renderers once
-- docs/plans/17-add-error-renderers-to-every-source-adapter.md lands.
renderFormatLoadErrorText :: FormatLoadError -> Text
renderFormatLoadErrorText = \case
  YamlLoadError problems -> Text.pack (show (NonEmpty.toList problems))
  KdlLoadError problems -> Text.pack (show (NonEmpty.toList problems))
  DhallLoadError problems -> Text.pack (show (NonEmpty.toList problems))
```

— keep the `TODO(EP-17)` marker in the code, tick the corresponding Progress item in
this plan as "stubbed", and add a Surprises & Discoveries note stating that the stub is
live so that EP-17 (or a small follow-up commit under this plan) swaps it and deletes the
TODO. The function's type must not change when the stub is replaced, so no caller churn
occurs. This stub is no worse than today's examples, which print `show` output already.

Registration. Three files change:

1. `cabal.project`: add `  settei-formats` to the `packages:` list (alphabetically,
   between `settei-env` and `settei-kdl`) and add a stanza after `package settei-env`:

   ```text
   package settei-formats
     tests: True
   ```

2. `nix/haskell.nix`: in the `let` block, after `setteiOptparseApplicativePackage`, add
   the derivation below, and add `packages.settei-formats = setteiFormatsPackage;` next
   to the other `packages.*` attributes. `flake.nix` itself needs no edit — it only
   imports this module. The `dontCheck` is required for the reason recorded in the
   Decision Log (nixpkgs' tasty embeds optparse-applicative 0.18; Cabal is the test
   authority):

   ```nix
   setteiFormatsPackage =
     pkgs.haskell.lib.dontCheck (
       haskellPackages.callCabal2nix "settei-formats" ../settei-formats {
         optparse-applicative = optparseApplicativePackage;
         settei = setteiPackage;
         settei-dhall = setteiDhallPackage;
         settei-kdl = setteiKdlPackage;
         settei-optparse-applicative = setteiOptparseApplicativePackage;
         settei-yaml = setteiYamlPackage;
       }
     );
   ```

3. `mori.dhall`: add a package entry in the `packages` list (alphabetically, after the
   `settei-env` entry), mirroring the existing adapter entries:

   ```dhall
   , Schema.Package::{
     , name = "settei-formats"
     , type = Schema.PackageType.Library
     , language = Schema.Language.Haskell
     , path = Some "settei-formats"
     , description = Some "Tagged multi-format configuration inputs and a shared adapter loader for Settei"
     , dependencies =
       [ Schema.Dependency.ByName "settei"
       , Schema.Dependency.ByName "settei-dhall"
       , Schema.Dependency.ByName "settei-kdl"
       , Schema.Dependency.ByName "settei-optparse-applicative"
       , Schema.Dependency.ByName "settei-yaml"
       ]
     }
   ```

### Milestone 2: the optparse module

Scope: after this milestone, `settei-formats/src/Settei/Formats/Optparse.hs` exists and
the library still builds. Acceptance: `nix develop -c cabal build settei-formats`
succeeds and `ghci` can parse `["--config", "yaml:app.yaml"]` through
`configInputOptions`.

The module follows the `Settei.Optparse` house style (a default parser delegating to a
variant that takes caller-supplied option metadata, built from `many` + `option` +
`eitherReader`). Its default help text matches the examples' `--config FORMAT:PATH`
option so EP-21's migration is behavior-preserving. Full intended content:

```haskell
-- |
-- Module: Settei.Formats.Optparse
-- Description: Reusable @--config FORMAT:PATH@ options for tagged multi-format inputs.
module Settei.Formats.Optparse
  ( configInputOption,
    configInputOptions,
    configInputReader,
  )
where

import Control.Applicative qualified as Applicative
import Options.Applicative (Mod, OptionFields, Parser)
import Options.Applicative qualified as Options
import Settei.Formats

-- | 'Options.ReadM' for the @FORMAT:PATH@ grammar of 'parseConfigInput'.
configInputReader :: Options.ReadM ConfigInput
configInputReader = Options.eitherReader parseConfigInput

-- | Parse zero or more tagged inputs using caller-supplied option metadata.
configInputOption :: Mod OptionFields ConfigInput -> Parser [ConfigInput]
configInputOption modifiers =
  Applicative.many (Options.option configInputReader modifiers)

-- | Parse zero or more default @--config FORMAT:PATH@ occurrences.
configInputOptions :: Parser [ConfigInput]
configInputOptions =
  configInputOption
    ( Options.long "config"
        <> Options.metavar "FORMAT:PATH"
        <> Options.help "Load yaml:PATH, kdl:PATH, or dhall:PATH in occurrence order"
    )
```

The names `configInputOption` (caller metadata) and `configInputOptions` (default) are
fixed by this plan; the analogy to `configPathOptionsWith`/`configPathOptions` is the
pattern being followed even though the suffix differs. Applications group the parser
themselves (for example under `Options.parserOptionGroup "Configuration"`), exactly as
they do today with `configPathOptions`; grouping is deliberately not baked in here.

### Milestone 3: tests and fixtures

Scope: after this milestone, `settei-formats-tests` exists, is green, and the whole
workspace is green. Acceptance: the three commands in Validation and Acceptance behave as
described there.

Create four fixture files under `settei-formats/test/fixtures/` (already declared as
`data-files` in the cabal file, located at run time through the autogenerated
`Paths_settei_formats.getDataFileName`):

`settei-formats/test/fixtures/app.yaml`:

```yaml
service:
  endpoint: https://example.test
```

`settei-formats/test/fixtures/app.kdl`:

```text
service {
  endpoint "https://example.test"
}
```

(The `.kdl` fixture fence is tagged `text` because KDL has no dedicated tag; the file
contents are exactly the three lines shown.)

`settei-formats/test/fixtures/app.dhall`:

```dhall
{ service = { endpoint = "https://example.test" } }
```

`settei-formats/test/fixtures/imports.dhall` (its only content is a local import, so it
must be rejected under the default `NoImports` policy):

```dhall
./app.dhall
```

Create `settei-formats/test/Main.hs` gathering two tasty test groups:

```haskell
module Main (main) where

import Settei.FormatsOptparseTest qualified
import Settei.FormatsTest qualified
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain
    ( testGroup
        "settei-formats"
        [ Settei.FormatsTest.tests,
          Settei.FormatsOptparseTest.tests
        ]
    )
```

Create `settei-formats/test/Settei/FormatsTest.hs` with `tests :: TestTree` covering, as
tasty-hunit cases:

1. Grammar successes: `parseConfigInput "yaml:app.yaml"` is
   `Right` with format `YamlFormat` and path `"app.yaml"` (assert via
   `configInputFormat`/`configInputPath`); likewise `"kdl:app.kdl"` and
   `"dhall:app.dhall"`. Also a path containing a second colon,
   `"yaml:dir:with:colons.yaml"`, parses with path `"dir:with:colons.yaml"` (only the
   first colon separates).
2. Grammar failures: `parseConfigInput "app.yaml"` (missing colon) and
   `parseConfigInput "yaml:"` (empty path) are both
   `Left "expected FORMAT:PATH"`; `parseConfigInput "toml:app.toml"` and
   `parseConfigInput ":app.yaml"` (empty format) are both
   `Left "FORMAT must be yaml, kdl, or dhall"`. These pin the exact strings the examples
   use today.
3. Loader dispatch, one case per format: resolve the fixture path with
   `getDataFileName "test/fixtures/app.yaml"` (and `.kdl`, `.dhall`), call
   `loadConfigInput defaultLoadOptions (configInput YamlFormat fixturePath)` (matching
   format per case), assert `Right`, then prove the load is meaningful beyond
   compilation by resolving a one-setting declaration against the returned source and
   asserting the typed value. A minimal in-test declaration:

   ```haskell
   endpointConfig :: Config Text
   endpointConfig =
     required (publicSetting endpointKey "Service endpoint" textDecoder)

   endpointKey :: Key
   endpointKey = either (error . show) id (parseKey "service.endpoint")
   ```

   Then `resolve defaultResolveOptions [loadedSource] endpointConfig` must have
   `result ^. #answer == Right "https://example.test"` for all three formats. (These helpers —
   `Config`, `required`, `publicSetting`, `textDecoder`, `parseKey`, `resolve`,
   `defaultResolveOptions` — are all exported by the core `Settei` module; the
   `ResolveResult` value is read through `result ^. #answer`, as the examples do.)
4. Kubernetes annotation pass-through: load `app.yaml` with
   `fromKubernetesMountedFile (kubernetesRef ConfigMapObject Nothing "settei-formats-test" (Just "app.yaml")) defaultLoadOptions`,
   and assert that `sourceAnnotations` of the produced source contains
   `"kubernetes.object-kind" -> "ConfigMap"` and
   `"kubernetes.object-name" -> "settei-formats-test"` (these are the stable keys
   emitted by `kubernetesAnnotations` in `settei/src/Settei/Origin.hs`). Repeat the
   same assertion for the Dhall fixture, since Dhall takes the
   annotate-options path rather than a `fromKubernetesMountedFile` helper. Also assert
   `annotateLoadOptions (Map.singleton "team" "platform") ...` surfaces
   `"team" -> "platform"`.
5. Dhall policy default: `loadOptionsDhallImportPolicy defaultLoadOptions` equals
   `Dhall.NoImports`; loading `imports.dhall` with `defaultLoadOptions` returns `Left`
   whose single `FormatLoadError` is a `DhallLoadError` and whose underlying error has
   `Dhall.dhallErrorCategory` equal to `Dhall.DhallImportPolicyError` (the adapter
   rejects with message "imports are disabled"); loading `imports.dhall` again with
   `withDhallImportPolicy (Dhall.LocalImportsWithin fixturesDirectory) defaultLoadOptions`
   succeeds and resolves the same endpoint value, proving the policy is honored, not
   ignored.
6. Missing file: loading `configInput YamlFormat "does-not-exist.yaml"` returns `Left`
   wrapping a `YamlLoadError` (category `Yaml.YamlIoError`), demonstrating that IO
   failures arrive as structured errors, not exceptions.

Create `settei-formats/test/Settei/FormatsOptparseTest.hs` with `tests :: TestTree`
covering: `Options.execParserPure Options.defaultPrefs (Options.info configInputOptions mempty) ["--config", "yaml:a.yaml", "--config", "kdl:b.kdl"]`
yields a `Options.Success` with the two inputs in occurrence order;
no `--config` occurrence yields `Success []`; `["--config", "toml:x"]` yields a
`Options.Failure`; and `configInputOption` with custom metadata (for example
`Options.long "input"`) parses `["--input", "dhall:c.dhall"]`.

With tests in place, run the package suite, then the full workspace suite and flake check
(commands and expected transcripts in Validation and Acceptance).

### Milestone 4: guide, doc pointers, compatibility list, and ADR

Scope: after this milestone the package is documented and the umbrella boundary is an
ADR. Acceptance: the named files exist with the described content; `nix flake check`
still passes (it runs formatting hooks over the tree).

Write `docs/guides/formats.md`. Structure it like the sibling adapter guides
(`docs/guides/yaml.md` and friends): a title `# Tagged multi-format configuration`,
a short intro naming the problem (multi-format apps need `--config FORMAT:PATH` and a
dispatching loader) and the package; a "Add the dependency" section showing
`build-depends: settei-formats`; a "Accept tagged inputs" section showing
`Settei.Formats.Optparse.configInputOptions` inside a `parserOptionGroup
"Configuration"`; a "Load tagged inputs" section showing `defaultLoadOptions`,
`fromKubernetesMountedFile`, `annotateLoadOptions`, `withDhallImportPolicy`, a
`traverse (loadConfigInput options) inputs` loop, and `renderFormatLoadErrorText` for
operator-facing failures; an explicit paragraph on the `NoImports` default and why a
loader must never default to filesystem imports; and a closing pointer that the
reference applications adopt this package in a later plan (EP-21). All code fences in
the guide must carry language tags (`haskell`, `cabal`, `bash`, `text`). Add a row to
the guide table in `docs/guides/README.md`:

```markdown
| [Tagged multi-format configuration](formats.md) | You accept `--config FORMAT:PATH` inputs across YAML, KDL, and Dhall with one shared loader. |
```

Add pointer paragraphs (two or three sentences each, no code migration): in
`docs/guides/cli-application.md`, immediately after the "Add dependencies and split the
modules" section's dependency block, note that the `settei-formats` package provides the
`--config FORMAT:PATH` reader and format-dispatching loader shown by hand later in that
guide, linking to `formats.md`; in `docs/guides/kubernetes-service.md`, after the
dependency block, note that `settei-formats` bundles the mounted-file loading and
Kubernetes annotation attachment for all three formats, linking to `formats.md`. Do not
otherwise rewrite these guides — EP-21 owns the coherent rewrite when the examples
migrate.

Update `docs/compatibility.md`: the file was checked and its "Public modules" section
does enumerate the supported surface, so add one bullet after the "Adapters:" bullet:

```markdown
- Multi-format umbrella: `Settei.Formats` and `Settei.Formats.Optparse`.
```

Make no other change to that file; EP-20 owns the PVP statement and any restructuring,
and EP-20/EP-21 own final compatibility wording.

Write `docs/adr/0008-settei-formats-umbrella-package.md` recording the umbrella-package
boundary. Content outline (write it as full prose in the ADR house style — Status,
Date, Context, Decision, Consequences, Rejected Alternatives, matching ADR 0007's
shape):

- Status: Accepted. Date: the implementation date.
- Context: multi-format applications need `FORMAT:PATH` parsing and three-adapter
  dispatch; both reference applications duplicated it; the dispatch necessarily depends
  on `settei-yaml`, `settei-kdl`, and `settei-dhall` simultaneously, which no existing
  package may do without dragging all format stacks into unrelated consumers.
- Decision: a dedicated umbrella package `settei-formats` owns tagged inputs and the
  shared loader. The dependency direction is one-way and load-bearing:
  `settei-formats` may depend on the core and on all source adapters (and on
  `settei-optparse-applicative`); **no adapter may ever depend on `settei-formats`**;
  and `settei-optparse-applicative` stays adapter-free (it must never depend on
  `settei-yaml`, `settei-kdl`, or `settei-dhall`). Within the package, the pure loader
  (`Settei.Formats`) and the command-line surface (`Settei.Formats.Optparse`) are
  separate modules so the loader is importable without optparse symbols. The Dhall
  import policy defaults to `NoImports` at the umbrella boundary.
- Consequences: single-import ergonomics for multi-format apps; adding a future format
  adapter means extending `ConfigFormat`, the loader, and this package's dependencies —
  a major version bump of `settei-formats` but no change to any adapter; applications
  that use only one format should keep depending on that adapter directly rather than
  the umbrella.
- Rejected alternatives: extending `settei-optparse-applicative` (forces three format
  stacks on every CLI consumer — the MasterPlan's original rejection); a separate
  `settei-formats-optparse` micro-package (registration overhead for one module);
  putting the dispatch in the core `settei` package (the core must stay
  adapter-agnostic and dependency-light).

Finally, perform the plan-completion duties: update this plan's Progress, write the
Outcomes & Retrospective entry, do the ADR distillation pass (ADR 0008 is the expected
distillation product; add anything else the Decision Log or Surprises accumulated), and
update the MasterPlan's registry row for EP-16 to Complete and its Progress checklist.


## Concrete Steps

All commands run from the repository root (the directory containing `cabal.project`).
Every command that builds or tests Haskell runs inside the Nix development shell via
`nix develop -c`.

Every commit in this plan uses Conventional Commits (`feat:`, `test:`, `docs:`,
`chore:`, with an optional scope such as `feat(formats): ...`) and carries these three
trailers, exactly as written:

```text
MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/16-provide-shared-tagged-format-configuration-loading.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

Commit directly to the current branch (no feature branch unless the owner asks).

Step 1 — scaffold and pure core (Milestone 1). Create the files described in Milestone 1:
`settei-formats/settei-formats.cabal`, `settei-formats/LICENSE` (copy of the root
`LICENSE`), `settei-formats/CHANGELOG.md`, and
`settei-formats/src/Settei/Formats.hs`. Edit `cabal.project`, `nix/haskell.nix`, and
`mori.dhall` as specified. Then build:

```bash
nix develop -c cabal build settei-formats
```

Expected: the solver picks up the new package and the build ends with a line like

```text
[1 of 1] Compiling Settei.Formats
```

and exit code 0. (If the test-suite stanza is already in the cabal file but the test
files do not exist yet, `cabal build settei-formats` still succeeds because it builds
only the library target; do not run `cabal build all` until Milestone 3.) Also verify the
Nix wiring:

```bash
nix build .#settei-formats
```

Expected: a `result` symlink to a `settei-formats-0.1.0.0` store path. Commit:

```text
feat(formats): add settei-formats package with tagged-input core and loader

MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/16-provide-shared-tagged-format-configuration-loading.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

Update this plan's Progress section in the same commit (living-document rule).

Step 2 — optparse module (Milestone 2). Create
`settei-formats/src/Settei/Formats/Optparse.hs` as specified, rebuild with the same
`nix develop -c cabal build settei-formats` command, and spot-check in GHCi:

```bash
nix develop -c cabal repl settei-formats
```

```text
ghci> import Options.Applicative
ghci> import Settei.Formats.Optparse
ghci> getParseResult (execParserPure defaultPrefs (info configInputOptions mempty) ["--config","yaml:app.yaml"])
Just [ConfigInput {format = YamlFormat, path = "app.yaml"}]
```

Commit as `feat(formats): add reusable --config FORMAT:PATH option parsers` with the
trailers.

Step 3 — tests and fixtures (Milestone 3). Create the four fixture files,
`settei-formats/test/Main.hs`, `settei-formats/test/Settei/FormatsTest.hs`, and
`settei-formats/test/Settei/FormatsOptparseTest.hs` (and, if deferred from Step 1, the
test-suite stanza in the cabal file). Run:

```bash
nix develop -c cabal test settei-formats-tests --test-show-details=direct
```

Expected: a tasty tree named `settei-formats` with every grammar, loader, annotation,
policy, and optparse case listed as `OK`, ending in

```text
All N tests passed
Test suite settei-formats-tests: PASS
```

Then the full workspace and the flake:

```bash
nix develop -c cabal test all
nix flake check
```

Expected: every existing suite still passes (this plan changed no existing package's
code, so any failure here means a packaging edit broke wiring — see Idempotence and
Recovery), and `nix flake check` completes without error. Commit as
`test(formats): cover FORMAT:PATH grammar, adapter dispatch, annotations, and Dhall policy`
with the trailers.

Step 4 — docs and ADR (Milestone 4). Write `docs/guides/formats.md`; edit
`docs/guides/README.md`, `docs/guides/cli-application.md`,
`docs/guides/kubernetes-service.md`, and `docs/compatibility.md`; write
`docs/adr/0008-settei-formats-umbrella-package.md`. Re-run `nix flake check` (it runs
the formatting hooks over docs too). Commit as
`docs(formats): add formats guide, doc pointers, and umbrella-package ADR` with the
trailers.

Step 5 — close the plan. Update this plan's Progress, Surprises & Discoveries, and
Outcomes & Retrospective; perform the ADR distillation pass; update the MasterPlan
registry row (EP-16 → Complete) and its Progress checklist. Commit as
`docs(plans): complete EP-16 tagged-format loading plan` with the trailers.


## Validation and Acceptance

Acceptance is behavioral. After Milestone 3, all of the following hold, and each can be
checked by a person with no prior context:

1. Building the package succeeds from the repository root:

   ```bash
   nix develop -c cabal build settei-formats
   ```

   ends with exit code 0 and no warnings beyond the workspace's usual noise
   (`-Wall -Wcompat` are on; new warnings in the new modules should be fixed, not
   suppressed).

2. The package suite proves the behavior end-to-end:

   ```bash
   nix develop -c cabal test settei-formats-tests --test-show-details=direct
   ```

   prints an `OK` for each case and `Test suite settei-formats-tests: PASS`.
   Specifically, the suite demonstrates that: `parseConfigInput` accepts exactly
   `yaml:`, `kdl:`, and `dhall:`-tagged inputs and rejects everything else with the two
   exact error strings the reference applications use today (`expected FORMAT:PATH` and
   `FORMAT must be yaml, kdl, or dhall`); one `loadConfigInput` call loads a YAML, KDL,
   or Dhall fixture and a typed `resolve` over the returned `Source` yields
   `"https://example.test"` for `service.endpoint` in all three formats; a
   `KubernetesRef` supplied through `LoadOptions` is visible in
   `sourceAnnotations` as `kubernetes.object-kind`/`kubernetes.object-name` for both
   the mounted-file adapters and Dhall; the default Dhall policy is `NoImports` and a
   fixture whose body is `./app.dhall` fails with a `DhallLoadError` of category
   `DhallImportPolicyError` under the default while succeeding under an explicit
   `LocalImportsWithin`; and a missing file surfaces as a structured `YamlLoadError`
   rather than an exception.

3. The whole workspace remains green:

   ```bash
   nix develop -c cabal test all
   nix flake check
   ```

   Every pre-existing suite passes unchanged (this plan adds a package; it modifies no
   existing Haskell source), and the flake evaluates, builds `packages.settei-formats`,
   and passes its hooks.

4. After Milestone 4, `docs/guides/formats.md` exists and is reachable from the guide
   table in `docs/guides/README.md`; `docs/guides/cli-application.md` and
   `docs/guides/kubernetes-service.md` each contain a pointer to it; the "Public
   modules" list in `docs/compatibility.md` names `Settei.Formats` and
   `Settei.Formats.Optparse`; and `docs/adr/0008-settei-formats-umbrella-package.md`
   states the boundary rules (umbrella may depend on all adapters; adapters never depend
   on the umbrella; `settei-optparse-applicative` stays adapter-free).

Interpreting failures: a tasty assertion naming an error string means the grammar
drifted from the examples — restore the verbatim strings. A `DhallImportPolicyError` in
the *success* fixtures means the fixture accidentally contains an import or the policy
default was wired wrong. A Nix evaluation error mentioning `settei-formats` means the
`callCabal2nix` override list omits one of the six direct dependencies. A
`cabal test all` failure inside an *example* package means `cabal.project` or the shared
solver plan was perturbed — re-check the two `cabal.project` edits against the file
shown in Context and Orientation.


## Idempotence and Recovery

Every step is additive and repeatable. Creating files, re-running `cabal build`,
`cabal test`, `nix build`, and `nix flake check` are all safe to repeat; Cabal and Nix
are content-addressed and simply rebuild what changed. If a milestone is interrupted,
re-read the Progress checklist, `git status`, and `git log --oneline -5`, then resume at
the first unchecked item — the plan is written so that no step depends on unrecorded
state.

The three registration edits (`cabal.project`, `nix/haskell.nix`, `mori.dhall`) are the
only changes to shared files before Milestone 4, and each is a small, self-contained
insertion. If one breaks the workspace (for example, a `cabal.project` typo makes
`cabal test all` fail to plan), revert just that file with
`git checkout -- cabal.project` (or the corresponding path) and reapply the insertion
from this plan's Milestone 1 text. Nothing in this plan mutates existing Haskell source,
so reverting the new `settei-formats/` directory (`git rm -r settei-formats` on an
uncommitted tree, or `git revert` of the commit) restores the exact pre-plan build.

If EP-17 lands mid-implementation (after the `Show` stub was written), replacing the
stub is a one-commit change confined to `renderFormatLoadErrorText`; its type does not
change, so no other file is touched. If EP-17's final renderer names differ from the
`render<Adapter>ErrorText` expectation, only that one function body changes — record the
actual names in Surprises & Discoveries.

There are no migrations, no destructive operations, and no generated files outside
`dist-newstyle/` (which is never committed). The `result` symlink produced by
`nix build` is transient and already git-ignored at the repository root.


## Interfaces and Dependencies

Packages and why. The new package `settei-formats` (version 0.1.0.0, directory
`settei-formats/`) depends on: `settei ==0.1.0.0` (core types: `Source`,
`KubernetesRef`, `kubernetesAnnotations`, `sourceAnnotations`, `Settei.Prelude`);
`settei-yaml ==0.1.0.0`, `settei-kdl ==0.1.0.0`, and `settei-dhall ==0.1.0.0` (the three
dispatched loaders and their error types); `settei-optparse-applicative ==0.1.0.0`
(house-style CLI adapter this package's option parsers complement, and a companion
import for applications composing overrides with tagged inputs);
`optparse-applicative >=0.19 && <0.20` (the `ReadM`/`Parser`/`Mod` machinery — 0.19 is
the workspace-pinned, source-inspected release per ADR 0001); and `base >=4.21 && <5`,
`containers >=0.6.8 && <0.8`, `text >=2.1 && <2.2`, `generic-lens >=2.2 && <2.4`
(records, annotation maps, labels — `generic-lens` is a direct dependency because the
modules import `Data.Generics.Labels ()` locally, per ADR 0001). The test suite adds
`tasty >=1.5 && <1.6` and `tasty-hunit >=0.10.2 && <0.11`. The dependency direction is
one-way: adapters must never depend on `settei-formats`, and
`settei-optparse-applicative` must never depend on any format adapter (this becomes ADR
0008).

At the end of Milestone 1, the module `Settei.Formats` (file
`settei-formats/src/Settei/Formats.hs`) exists and exports exactly:

```haskell
data ConfigFormat = YamlFormat | KdlFormat | DhallFormat

data ConfigInput -- abstract; Generic, Eq, Show

configInput :: ConfigFormat -> FilePath -> ConfigInput
configInputFormat :: ConfigInput -> ConfigFormat
configInputPath :: ConfigInput -> FilePath

parseConfigInput :: String -> Either String ConfigInput

data LoadOptions -- abstract

defaultLoadOptions :: LoadOptions
fromKubernetesMountedFile :: KubernetesRef -> LoadOptions -> LoadOptions
annotateLoadOptions :: Map Text Text -> LoadOptions -> LoadOptions
withDhallImportPolicy :: Settei.Dhall.DhallImportPolicy -> LoadOptions -> LoadOptions
loadOptionsKubernetesRef :: LoadOptions -> Maybe KubernetesRef
loadOptionsAnnotations :: LoadOptions -> Map Text Text
loadOptionsDhallImportPolicy :: LoadOptions -> Settei.Dhall.DhallImportPolicy

data FormatLoadError
  = YamlLoadError (NonEmpty Settei.Yaml.YamlSourceError)
  | KdlLoadError (NonEmpty Settei.Kdl.KdlSourceError)
  | DhallLoadError (NonEmpty Settei.Dhall.DhallSourceError)

loadConfigInput ::
  LoadOptions -> ConfigInput -> IO (Either (NonEmpty FormatLoadError) Source)

renderFormatLoadErrorText :: FormatLoadError -> Text
```

At the end of Milestone 2, the module `Settei.Formats.Optparse` (file
`settei-formats/src/Settei/Formats/Optparse.hs`) exists and exports exactly:

```haskell
configInputReader :: Options.Applicative.ReadM Settei.Formats.ConfigInput
configInputOption ::
  Options.Applicative.Mod Options.Applicative.OptionFields Settei.Formats.ConfigInput ->
  Options.Applicative.Parser [Settei.Formats.ConfigInput]
configInputOptions :: Options.Applicative.Parser [Settei.Formats.ConfigInput]
```

At the end of Milestone 3, the test executable `settei-formats-tests`
(`settei-formats/test/Main.hs` with modules `Settei.FormatsTest` and
`Settei.FormatsOptparseTest`, each exporting `tests :: Test.Tasty.TestTree`) exists and
passes.

Soft dependency: EP-17, docs/plans/17-add-error-renderers-to-every-source-adapter.md,
supplies the per-adapter text renderers (naming contract per the MasterPlan:
`render<Adapter>ErrorText`, one line per problem, never a raw value) that
`renderFormatLoadErrorText` composes. This plan is implementable before EP-17 via the
`Show`-based stub described in Milestone 1; the stub carries a `TODO(EP-17)` marker and
a Progress/Surprises note until replaced. No other plan is a dependency. EP-21 is a
downstream consumer: it migrates both reference applications and the application guides
onto this package and deletes the duplicated code; EP-20 later audits this package's
exposed modules and bounds along with the rest of the family.
