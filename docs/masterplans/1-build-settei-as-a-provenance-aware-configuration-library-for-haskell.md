---
id: 1
slug: build-settei-as-a-provenance-aware-configuration-library-for-haskell
title: "Build Settei as a provenance-aware configuration library for Haskell"
kind: master-plan
created_at: 2026-07-16T23:49:52Z
intention: intention_01kxr36cqgem8tmxjjtnq0t6ns
---

# Build Settei as a provenance-aware configuration library for Haskell

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Vision & Scope

Settei (設定) will be a family of Haskell packages for typed, layered, explainable
configuration. A program declares its settings once, loads values from ordered sources,
and receives both a typed result and a report that says which source supplied each value,
which candidates were shadowed, and how a derived default was computed. The same core
declaration will support long-running services, interactive command-line programs, and
applications deployed to Kubernetes.

The first release includes the `settei` core package and the adapter packages
`settei-env`, `settei-optparse-applicative`, `settei-yaml`, `settei-kdl`, and
`settei-dhall`. It defines deterministic hierarchical merging, static schema inspection,
environment-dependent requirements and defaults, secret-safe explanations, structured
errors, and text and JSON reports. Kubernetes support means reading environment variables
and mounted files and attaching operator-supplied ConfigMap or Secret metadata to their
origins; it does not mean talking to the Kubernetes API.

Every publishable package lives in a same-named directory directly beneath the repository
root: `settei/`, `settei-env/`, `settei-optparse-applicative/`, `settei-yaml/`,
`settei-kdl/`, and `settei-dhall/`. Each owns its `.cabal` file, `src/`, `test/`, fixtures,
and package documentation. The repository root owns workspace configuration and
package-family documentation, while non-published reference applications remain beneath
`examples/`. A generic `packages/` container and a special core package rooted at `.` are
both deliberately excluded.

All packages follow the registered `shinzui/haskell-jitsurei` core conventions. They use
GHC 9.12 or newer. Each `.cabal` file declares the same package-local `common common`
stanza with `default-language: GHC2024`, `DeriveAnyClass`, `DuplicateRecordFields`,
`OverloadedLabels`, and `OverloadedStrings`, and every component imports that stanza. The
core exposes `Settei.Prelude`; modules import it, use postpositive `qualified` imports,
define strict record fields without type-name prefixes, use explicit deriving strategies,
and use generic-lens `#label` access and updates. `Data.Generics.Labels ()` is imported only
by modules that use those labels, never re-exported from `Settei.Prelude`. Operators remain
unqualified; a collision is resolved by hiding the unwanted operator from the
`Settei.Prelude` import.

This initiative proves the package family with a CLI reference program and a service-like
reference program plus Kubernetes manifests. It deliberately excludes migrations of Rei,
Mori, Seihou, `tan-commons-config`, and `mls-service-v2`; those should be separate adoption
plans once the API is proven. Remote configuration services, live reload, file write-back,
secret storage or encryption, a Vault client, a Kubernetes client, and an `effectful`
adapter are also outside this first initiative. Exact per-leaf origin tracking through
arbitrary Dhall imports is not promised: the adapter must report the root expression and
the import information it can substantiate.


## Decomposition Strategy

The work is divided into four waves. The first wave establishes a buildable package and
proves that the configuration language can be both selective at runtime and inspectable
before evaluation. The second wave defines the resolution and provenance contract. The
third wave implements source adapters against that contract and includes a structural
gate: after the environment, CLI, and YAML packages, EP-8 moves every existing package to
the top-level sibling layout before KDL or Dhall adds another package. The fourth wave is
the integration plan that exercises the whole package family in CLI and
Kubernetes-shaped deployments.

Eight ExecPlans keep the risky algebra decision separate from runtime semantics, give each
serialization format an independently testable boundary, and isolate the repository move
from behavior changes. Environment and `optparse-applicative` share one
plan because they jointly define the normal CLI/service precedence story and both map
already-tokenized scalar input into the same source abstraction. YAML, KDL, and Dhall each
have separate plans because their syntax, error locations, duplicate-key behavior, and
provenance limitations differ materially.

A single package with format dependencies in the core was rejected because consumers
should not pay for parsers they do not use. A monadic public configuration language was
rejected because a key computed from an earlier runtime value prevents complete static
enumeration of possible settings. Treating each format as its own configuration engine was
rejected because merge and provenance behavior would drift. Migrating production
consumers in this initiative was rejected because it would couple API discovery to several
unrelated release cycles.
[ADR 0001](../adr/0001-haskell-project-conventions.md) records the
cross-plan implementation and repository-layout baseline. Plans 1 and 2 added the algebra
and resolution ADRs after their prototypes supplied implementation evidence.

The convention audit uses `mori registry show shinzui/haskell-jitsurei --full` and
`mori registry docs shinzui/haskell-jitsurei` as the source locator. The child plans embed
the applicable rules so implementation does not depend on remembering that external
corpus. Its CLI option-group pattern applies to Settei's reusable option parser and
reference CLI. Its hierarchical-config rule against merging independent concerns does not
replace Settei's deliberate precedence merge: Settei merges multiple sources for the same
declared settings, while genuinely independent configuration concerns should still use
separate declarations.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|---|---|---|---|---|
| EP-1 | Bootstrap Settei and prove the inspectable configuration algebra | `docs/plans/1-bootstrap-settei-and-prove-the-inspectable-configuration-algebra.md` | None | None | Complete |
| EP-2 | Implement hierarchical resolution, provenance, and derived defaults | `docs/plans/2-implement-hierarchical-resolution-provenance-and-derived-defaults.md` | EP-1 | None | Complete |
| EP-3 | Add environment and optparse-applicative configuration sources | `docs/plans/3-add-environment-and-optparse-applicative-configuration-sources.md` | EP-2 | None | Complete |
| EP-4 | Add YAML configuration support | `docs/plans/4-add-yaml-configuration-support.md` | EP-2 | None | Complete |
| EP-8 | Move Settei packages to top-level sibling directories | `docs/plans/8-move-settei-packages-to-top-level-sibling-directories.md` | EP-3, EP-4 | None | Complete |
| EP-5 | Add KDL configuration support | `docs/plans/5-add-kdl-configuration-support.md` | EP-2, EP-8 | None | Complete |
| EP-6 | Add Dhall configuration support | `docs/plans/6-add-dhall-configuration-support.md` | EP-2, EP-8 | None | Complete |
| EP-7 | Prove Settei in CLI and Kubernetes service reference applications | `docs/plans/7-prove-settei-in-cli-and-kubernetes-service-reference-applications.md` | EP-3, EP-4, EP-5, EP-6 | None | Not Started |

Status values are Not Started, In Progress, Complete, and Cancelled. Hard dependencies and
soft dependencies reference other rows by their EP prefix.


## Dependency Graph

EP-1 has no predecessor. It produces the initial workspace, public declaration algebra,
static schema model, test harness, and an ADR-backed decision about the internal
free-selective representation. EP-2 depends on those types and adds the shared `Source`,
resolver, origin, explanation, and default-rule contracts. Those contracts must be stable
before any parser translates external data into a Settei source.

EP-3 and EP-4 depend on EP-2 and own only their input boundaries. EP-8 depends on both
because it migrates the core and every implemented adapter together and proves the whole
current workspace still builds. EP-5 and EP-6 depend on EP-2's adapter contract and on
EP-8's completed sibling-package layout; after the structural gate they can proceed in
parallel without creating more paths that would immediately need migration. Every adapter
consumes the core source and provenance types rather than reimplementing merging. EP-7
depends on all four adapter feature plans because its acceptance cases compare equivalent
configurations across environment variables, CLI options, YAML, KDL, and Dhall and
demonstrate the complete Kubernetes delivery model.

The dependency shape is therefore:

```text
EP-1 -> EP-2
EP-2 -> EP-3
EP-2 -> EP-4
EP-3 + EP-4 -> EP-8
EP-2 + EP-8 -> EP-5
EP-2 + EP-8 -> EP-6
EP-3 + EP-4 + EP-5 + EP-6 -> EP-7
```


## Integration Points

The declaration algebra in `Settei.Config` and schema types in `Settei.Schema` are owned by
EP-1. Every later plan may add combinators but must preserve the laws and the deliberate
absence of a `Monad Config` instance. The choice of internal representation and the static
meaning of conditional branches must be captured in an ADR by EP-1.

`Settei.Prelude` re-exports `Control.Lens` except for the lens library's setter type alias
named `Setting`, which collides with Settei's public `Setting` domain type. Later packages
receive the lens operators normally and should use Settei's unqualified `Setting`; code
that specifically needs the lens alias can import it directly from `Control.Lens` under a
distinct local name.

The raw value tree, dotted-path `Key`, `Source`, resolver, and provenance graph are shared
by every adapter and are owned by EP-2. Sources are ordered from lowest to highest
precedence. Resolution is leaf-wise: the rightmost present value wins, arrays replace
wholesale, and a malformed higher-precedence value is an error rather than permission to
fall back. EP-2 must capture these durable semantics in an ADR. Adapter plans extend
origin details through core extension points; they do not add format cases to the core.

The explanation renderers are owned by EP-2 and consumed by EP-3 for `--explain-config`
and by EP-7 for service diagnostics. All renderers, errors, and debug representations must
honor the core sensitivity marker and redact secret values. A source may retain a real
secret long enough to build the typed application value, but reports must never contain
it.

The package workspace is established in EP-1 and normalized by EP-8. EP-8 moves the core
from the repository root to `settei/`, moves each implemented adapter out of `packages/`,
and updates Cabal, Nix, Mori metadata, documentation paths, package-local data files, and
source-distribution validation without changing any package or module identity. EP-5 and
EP-6 then add `settei-kdl/` and `settei-dhall/` as direct repository-root siblings. EP-7
adds non-published examples beneath `examples/` and is responsible for testing package
interoperability, documentation navigation, and release readiness. The durable layout
rationale is recorded in [ADR 0001](../adr/0001-haskell-project-conventions.md).

EP-1 also owns the Haskell convention baseline shared by every package. It defines the
canonical Cabal `common` stanza contents and `Settei.Prelude`, including `lens` re-exports
but excluding the generic-lens orphan `IsLabel` instance. Because Cabal common stanzas are
package-local, every later package repeats the canonical stanza in its own `.cabal` file
and imports it from each component. Every later plan otherwise consumes the baseline,
keeps record fields strict and unprefixed, derives instances with explicit `stock`,
`newtype`, or `anyclass` strategies, imports qualified modules with postpositive
`qualified`, and uses lenses instead of record selectors, record update syntax, or direct
`Map.insert`/`adjust` when manipulating records. Adapter packages declare `generic-lens`
directly whenever a module imports `Data.Generics.Labels ()`; package dependency visibility
must not be assumed to be transitive. The durable rationale and rejected alternatives are
recorded in [ADR 0001](../adr/0001-haskell-project-conventions.md).

Format-specific provenance is owned by the corresponding adapter. YAML reports a file,
logical key, and parse location when available; KDL additionally retains node spans;
Dhall reports the root expression and substantiated import closure while explicitly
stating that normalization prevents reliable per-leaf import attribution. Environment and
CLI origins record exact variable and option names. Kubernetes ConfigMap and Secret names
are annotations supplied by the application or deployment, not discovered by the core.


## Progress

- [x] EP-1: make the repository build and test as a convention-compliant Cabal/Nix
  Haskell project.
- [x] EP-1: prove and document the inspectable selective configuration algebra.
- [x] EP-2: implement deterministic hierarchical resolution and structured provenance.
- [x] EP-2: implement constant and dependency-aware defaults with safe explanations.
- [x] EP-3: load explicit environment bindings and command-line overrides.
- [x] EP-4: translate YAML documents into provenance-aware sources.
- [x] EP-8: move the core and implemented adapters to top-level sibling package roots
  while preserving all package identities and behavior.
- [x] EP-5: translate canonical KDL documents while preserving node locations.
- [x] EP-6: translate normalized Dhall values and report honest import provenance.
- [ ] EP-7: demonstrate CLI and Kubernetes service use cases end to end.
- [ ] EP-7: publish package-family documentation and complete the release checklist.


## Surprises & Discoveries

- Observation: the registered `shinzui/haskell-jitsurei` corpus makes GHC2024, a shared
  extension stanza, postpositive qualified imports, strict unprefixed records, explicit
  deriving strategies, and the custom-prelude/generic-lens split project-wide
  requirements rather than optional style preferences.
  Evidence: `mori registry docs shinzui/haskell-jitsurei` resolves the relevant
  `core-standards`, `core-custom-prelude`, and `core-record-patterns` guides.
  Impact: EP-1 must establish the baseline, and every child plan's illustrative API and
  dependency guidance must conform to it.

- Observation: nixpkgs' GHC 9.12.4 package set carries `generic-lens` 2.2.2.0 while the
  refreshed Mori source checkout carries 2.3.0.0.
  Evidence: the initial Nix build rejected an `>=2.3` bound, and the same build succeeded
  after widening the bound to `>=2.2 && <2.4`.
  Impact: every Settei package that uses the local `Data.Generics.Labels` instance must
  retain a bound compatible with both package environments until the Nix package set
  advances.

- Observation: `Control.Lens` exports a setter type alias named `Setting`, which collides
  with Settei's public declaration metadata type.
  Evidence: EP-1's first vocabulary build failed with ambiguous `Setting` occurrences;
  hiding that alias at the custom-prelude boundary made the public and test imports
  unambiguous.
  Impact: every later package inherits a `Settei.Prelude` that still provides lens
  operators but deliberately omits `Control.Lens.Setting`.

- Observation: recursive Haskell bindings can express mutually dependent default syntax
  even though the public declaration algebra has no monadic bind.
  Evidence: EP-2's cycle test constructs two named defaults that refer to one another and
  proves resolution rejects `cycle-a -> cycle-b -> cycle-a` before a poison source's
  location function is called.
  Impact: adapters can rely on cycle validation happening before source inspection, and
  default rule names are durable semantic identities rather than presentation labels.

- Observation: source-wide annotations cannot identify distinct environment variables or
  parsed locations for multiple keys in one source.
  Evidence: EP-3's first environment adapter could construct the raw tree but needed a
  core `annotateSourceAt` hook before origins could name the exact variable per candidate.
  Impact: EP-3 added composable per-key annotations to core; EP-4 through EP-6 should use
  that extension for key-specific format metadata instead of splitting one document into
  artificial sources.

- Observation: an exact command-line assignment is unsafe provenance because its value
  may belong to a secret setting whose sensitivity is not known at parse time.
  Evidence: EP-3's adversarial CLI test requires the winning key and occurrence in both
  report formats while proving the raw secret sentinel is absent.
  Impact: CLI origins retain `--set KEY` plus an occurrence number, never `KEY=VALUE`;
  future adapters must likewise keep raw candidate values out of annotations.

- Observation: nixpkgs' GHC 9.12.4 package set carries optparse-applicative 0.18, and its
  `tasty` package was built against that ABI, while EP-3 requires 0.19's option-group API.
  Evidence: pinning 0.19 made the adapter library build, but enabling the Nix test
  component mixed both ABIs; the coherent Cabal plan ran every test against 0.19.
  Impact: the flake pins 0.19.0.0, the Nix CLI adapter output is library-only for checks,
  and Cabal remains the executable test authority until nixpkgs advances.

- Observation: the common high-level YAML-to-Aeson decoder drops duplicate-key warnings
  and successful node marks even though its lower-level parser retains both.
  Evidence: EP-4's source audit found warning accumulation followed by map insertion in
  `yaml-0.11.11.2`, while `libyaml-0.1.4` exposes every pair and zero-based span through
  `decodeMarked`; block and flow duplicate tests now fail at the second key.
  Impact: format adapters must select parser layers by the provenance and ambiguity
  contract they need, rather than assuming a convenient value conversion preserves it.

- Observation: the owner's registered Mori and Shibuya Haskell workspaces place Cabal
  packages in package-named top-level sibling directories rather than under a generic
  `packages/` directory or in a special repository-root package.
  Evidence: `mori registry show shinzui/mori --full` and
  `mori registry show shinzui/shibuya --full` resolved the source trees, whose
  `cabal.project` files directly list siblings such as `mori-core`, `mori-cli`, and
  `shibuya-core`.
  Impact: EP-8 must migrate the exceptional Settei layout before unfinished adapters add
  more packages, and EP-5 and EP-6 now depend on that structural gate.

- Observation: moving the core involves more than changing `cabal.project` because its
  source distribution and Nix derivation currently assume that the package root is the
  repository root.
  Evidence: `settei.cabal` names root `README.md` and `test/golden/*`, while
  `nix/haskell.nix` builds `settei` from `inputs.self` and adapters from
  `../packages/<name>`.
  Impact: EP-8 explicitly owns package-local documentation and golden paths, explicit Nix
  source roots, source-distribution inspection, and Mori package-path validation.

- Observation: `kdl-hs` 1.0.1 preserves ordered duplicate properties in `Node.entries`,
  but its `getProps` helper passes them through `Map.fromList`; its public parse failure is
  rendered text containing both a location header and a source excerpt.
  Evidence: EP-5's Mori-backed source inspection and parser probes found both ordered
  duplicate entries and the rendered excerpt, while all mapping and syntax-redaction tests
  pass against the direct translator.
  Impact: `settei-kdl` traverses entries directly, reports both duplicate spans, and keeps
  only the safe line/column header from syntax failures. Cabal and Nix pin the inspected
  1.0.1 release rather than nixpkgs' unregistered 1.1.0 source.

- Observation: KDL positional-argument cardinality cannot distinguish a scalar from an
  array containing exactly one element under the canonical version-one mapping.
  Evidence: EP-5's precedence test needed two arguments for an array decoder, while one
  argument correctly remained a scalar.
  Impact: ADR 0005 and the KDL guide make the limitation explicit, and EP-7 now requires
  at least two elements in its cross-format list fixture.

- Observation: `dhall` 1.42.3 exposes import status and configurable remote fetches but no
  maintained hook for intercepting local-file or environment reads; disabling its semantic
  cache also leaves a separate semi-semantic cache active.
  Evidence: EP-6 traced `Dhall.Import.loadWith`, `fetchFresh`, and
  `Dhall.Import.Types.Status` in Mori's registered `dhall-lang/dhall-haskell` source.
  Impact: EP-6 narrows version one to `NoImports` and cache-independent,
  preflighted `LocalImportsWithin` graphs. EP-7 should use import-free or local-only Dhall
  fixtures and must not imply that unrestricted standard imports are supported.

- Observation: the Hackage revision of `dhall-json` 1.7.12 predates the dependency-bound
  widenings already present in the registered monorepo source for Aeson, bytestring, and
  text on GHC 9.12.
  Evidence: EP-6's Cabal solver rejected each stale ceiling, while Mori-backed inspection
  found `<2.3`, `<0.13`, and `<2.2` respectively in the registered source.
  Impact: the workspace relaxes only those three `dhall-json` bounds and the Nix package
  applies the equivalent local jailbreak; EP-7 inherits the pinned, tested adapter rather
  than adding another Dhall dependency workaround.


## Decision Log

- Decision: Name the project Settei (設定), use `settei` for the core package, and publish
  format or integration support as separate `settei-*` packages.
  Rationale: the name is directly about configuration, and package separation keeps the
  core dependency surface small.
  Date: 2026-07-16

- Decision: Give `Config` `Functor`, `Applicative`, and `Selective` behavior but no public
  `Monad` instance.
  Rationale: derived defaults need only declared dependencies, while conditional required
  settings benefit from Selective. Unrestricted monadic binding would allow runtime-built
  keys and make the promise to enumerate possible configuration effects false.
  Date: 2026-07-16

- Decision: Treat Selective as structure for static analysis, not as the provenance model.
  Rationale: useful explanations require named defaults, declared dependency edges,
  candidate origins, branch decisions, and redaction metadata that the `selective` package
  does not provide.
  Date: 2026-07-16

- Decision: Centralize leaf-wise precedence, errors, defaults, provenance, and rendering in
  `settei`; adapters only translate inputs into the shared source model.
  Rationale: CLI, service, and application consumers must observe identical semantics
  regardless of file format.
  Date: 2026-07-16

- Decision: Interpret Kubernetes support as environment and mounted-file ingestion with
  explicit deployment metadata, not cluster discovery.
  Rationale: this covers normal Kubernetes delivery paths without adding credentials,
  network behavior, or a Kubernetes client to a configuration library.
  Date: 2026-07-16

- Decision: Defer production consumer migrations until after the reference applications
  prove the API.
  Rationale: Settei can change rapidly during its first release without coupling design
  experiments to Rei, Mori, Seihou, or microservice rollout schedules.
  Date: 2026-07-16

- Decision: Adopt the applicable `shinzui/haskell-jitsurei` conventions across the entire
  package family, with EP-1 owning the shared Cabal stanza and `Settei.Prelude`.
  Rationale: one baseline prevents the core, adapters, examples, and tests from drifting in
  language edition, import style, record design, deriving, or field access. CLI-specific
  patterns remain limited to packages that expose a command-line interface.
  Date: 2026-07-16

- Decision: Record the convention baseline in
  `docs/adr/0001-haskell-project-conventions.md` and reserve the next two ADR numbers for
  the algebra and resolution decisions produced by EP-1 and EP-2.
  Rationale: prelude ownership and public record-label design are durable cross-plan
  context, while the algebra and resolver decisions still require implementation evidence.
  Date: 2026-07-16

- Decision: Use a private explicit GADT as the production configuration algebra and keep
  the `Control.Selective.Free` version as a test-only analysis oracle.
  Rationale: both classify the proof declaration correctly, but only explicit syntax
  nodes provide durable identities and metadata attachment points for EP-2 provenance.
  Date: 2026-07-17

- Decision: Exclude `Control.Lens.Setting` from `Settei.Prelude` while retaining the rest
  of the lens re-export.
  Rationale: Settei's domain `Setting` must remain unambiguous in every package and example.
  Date: 2026-07-17

- Decision: Adopt ADR 0003's low-to-high leaf precedence, malformed-winner failure,
  explicit default dependencies, pre-source named-cycle validation, core-level redaction,
  and versioned deterministic report formats as the adapter contract.
  Rationale: EP-3 through EP-6 must translate inputs into one shared source model rather
  than acquire format-specific merge, fallback, or explanation behavior.
  Date: 2026-07-17

- Decision: Let `Source` compose source-wide and per-key annotations, with per-key entries
  winning name collisions, and let the core text renderer describe Kubernetes references.
  Rationale: adapters need honest candidate-level provenance and consistent text/JSON
  explanations without format-specific rendering paths.
  Date: 2026-07-17

- Decision: Treat origin annotations as secret-safe metadata and order shadowed origins
  from highest to lowest losing precedence.
  Rationale: reports can explain the nearest overridden candidate first without risking
  values being copied around core redaction through adapter metadata.
  Date: 2026-07-17

- Decision: Pin optparse-applicative 0.19.0.0 as a flake input and disable checks only for
  the Nix CLI adapter derivation while nixpkgs' `tasty` retains the 0.18 ABI.
  Rationale: this preserves the source-inspected public API and reproducible library
  output without weakening Cabal's all-package, all-test acceptance gate.
  Date: 2026-07-17

- Decision: Adopt ADR 0004's single-mapping, marked-event YAML subset with strict
  duplicate detection, exact rational numbers, explicit null, one-based locations, and
  explicit rejection of graph, merge, custom-tag, and multi-document semantics.
  Rationale: direct marked events preserve the evidence Settei needs without moving YAML
  merge behavior or lossy Aeson conversion into the shared core.
  Date: 2026-07-17

- Decision: Standardize every publishable Settei package as a same-named top-level
  sibling, including relocating the core to `settei/`; retain non-published reference
  applications beneath `examples/`.
  Rationale: this matches the owner's established Haskell workspace convention, removes
  the root-package exception and generic `packages/` wrapper, and gives future adapters
  one predictable location without changing any package or module identity.
  Date: 2026-07-17

- Decision: Add EP-8 after the completed environment, CLI, and YAML work and make KDL and
  Dhall depend on it.
  Rationale: one behavior-neutral migration can move the complete current workspace and
  validate it before unfinished plans create more paths that would immediately need the
  same refactor.
  Date: 2026-07-17

- Decision: Adopt ADR 0005's canonical KDL v2 mapping, exact finite-number conversion,
  explicit ambiguity and annotation rejection, direct duplicate-preserving AST traversal,
  one-based span provenance, safe syntax-error truncation, and `kdl-hs` 1.0.1 pin.
  Rationale: KDL sources need one deterministic adapter-neutral tree meaning while
  retaining evidence and never allowing parser excerpts or convenience helpers to hide
  secrets or duplicate input.
  Date: 2026-07-17

- Decision: Limit the first Dhall adapter to `NoImports` and
  `LocalImportsWithin`, rejecting alternatives in the local-only policy and omitting an
  unrestricted standard-import constructor.
  Rationale: only a preflighted no-alternative local graph can enforce canonical-root
  containment before reads and produce a cache-independent transitive closure through the
  maintained `dhall` 1.42.3 API.
  Date: 2026-07-18

- Decision: Preserve the Dhall input, import, conversion, cache, and provenance contract
  in ADR 0006 and make EP-7 demonstrate only those enforceable policies.
  Rationale: reference applications must inherit the adapter's actual security and
  observability boundary instead of recreating the broader initial aspiration.
  Date: 2026-07-18


## Outcomes & Retrospective

EP-1 completed on 2026-07-17. It established the convention-compliant Cabal/Nix project,
Mori identity, public declaration vocabulary, explicit inspectable selective algebra,
source-free schema, and 16-test proof suite. ADR 0002 preserves the algebra choice and
laws; ADR 0001 now also records the narrow `Control.Lens.Setting` exclusion needed by the
public domain type.

EP-2 completed on 2026-07-17. It added hierarchical adapter-neutral sources and origins,
rightmost-per-leaf resolution, structured diagnostics, actual-run provenance, named
constant/derived/case defaults, static cycle rejection, Selective branch traces, and
redacted deterministic text and JSON reports. ADR 0003 fixes those semantics for every
adapter. The 45-test suite includes exhaustive source-ordering, golden rendering, and an
adversarial secret-leak audit; Cabal build/test/check/Haddock, Nix formatting/check/build,
JSON parsing, and Mori identity validation all pass. EP-3 through EP-6 are now
API-ready against this core contract; EP-3 and EP-4 completed, while EP-5 and EP-6 now
wait for EP-8's structural migration.

EP-3 completed on 2026-07-17. It added pure explicit environment bindings, opt-in prefix
derivation, trusted Kubernetes annotations, ordered optparse-applicative overrides, named
options, grouped reusable parsers, and an audited migration guide. Per-key annotations and
descending shadow traces were added to core so every adapter can preserve exact origins.
The 62-test suite and Cabal build/check/Haddock, Nix format/check, and explicit adapter
builds pass; ADRs 0001 and 0003 retain the cross-plan packaging, provenance, rendering,
and redaction decisions. EP-4 completed next; EP-5 and EP-6 remain API-ready but now wait
for EP-8's structural migration.

EP-4 completed on 2026-07-17. It added a direct marked-event YAML translator, strict
single-mapping input semantics, duplicate and unsupported-feature rejection, exact
successful-node locations, structured secret-safe errors, file IO, mounted ConfigMap or
Secret metadata, and a complete format guide. ADR 0004 preserves the portable YAML
contract. The 82-test workspace suite, 100%-covered YAML Haddocks, package checks, Nix
formatting, dedicated YAML build, full flake check, and convention audit pass. EP-5 and
EP-6 remain API-ready but now wait for EP-8 to normalize the package layout.

The first four completed plans produced a working root `settei` package plus adapters
beneath `packages/`. That structure was intentionally provisional and EP-8 replaced it
with top-level siblings while preserving the 82-test behavior and all public identities.
KDL and Dhall implementation can now begin against the normalized layout.

EP-8 completed on 2026-07-17. It moved the core and three implemented adapters into
same-named top-level package roots as content-identical Git renames, added a package-local
core README, and rewired Cabal, Nix, Mori, and family documentation without changing any
package, module, version, or public interface. The unchanged 82-test suite, Haddocks, four
package checks, inspected source distributions, four Nix package outputs, full flake check,
formatting, and Mori inventory all pass. ADR 0001 already preserves the durable layout
decision. EP-5 and EP-6 are now dependency-ready and may proceed independently.

EP-5 completed on 2026-07-17. It added the top-level `settei-kdl` package, a direct
canonical KDL v2 AST translator, exact finite-number conversion, explicit ambiguity and
unsupported-feature failures, one-based full-span origins, secret-safe syntax and mapping
errors, mounted-file metadata, and a complete guide. ADR 0005 preserves the mapping and
the source-inspected `kdl-hs` 1.0.1 Cabal/Nix pin. Its 18 focused tests bring the workspace
to 100 passing tests; all builds, five package checks, Haddocks, source distributions,
Mori inventory, dedicated/default Nix builds, formatting, and the full host-platform flake
check pass. EP-6 is now the first dependency-ready plan, and EP-7 remains blocked on it.

EP-6 completed on 2026-07-18. It added the top-level `settei-dhall` package, official
typed Dhall-to-JSON-to-raw-tree conversion, `NoImports` and canonical-root-confined
`LocalImportsWithin` policies, cache-independent structured import closure details,
stable secret-safe errors, honest root-plus-closure provenance, and explicit
post-normalization leaf-attribution limits. ADR 0006 and the Dhall guide preserve the
security, cache, conversion, schema-evolution, and provenance contract. Its 21 focused
tests bring the workspace to 121 passing tests; Cabal build/check/Haddock/source
distribution, the dedicated Nix package build, full flake check, formatting, convention
audit, and six-package Mori inventory all pass. EP-7 is now dependency-ready and is the
only remaining child plan.

Before this MasterPlan is complete, distill the durable resolution semantics, adapter
boundary, and Dhall provenance limitation into `docs/adr/`, and compare the shipped package
family and demonstrations with the vision above. The final retrospective must also confirm
that every Cabal component imports its package-local GHC2024 common stanza and that exposed
examples and implementation modules follow the record, prelude, deriving, lens, and
qualified-import conventions above.


## Revision Note

2026-07-16: Audited the initiative against the registered
`shinzui/haskell-jitsurei` corpus and cascaded the applicable core and CLI conventions into
the MasterPlan and all child ExecPlans. This revision makes the language edition, shared
extensions, custom prelude, record style, deriving strategies, lens usage, import syntax,
and option grouping explicit while preserving Settei's intentional source-merging model.
It also records the durable cross-plan policy in
`docs/adr/0001-haskell-project-conventions.md`.

2026-07-17: Recorded EP-1's reproducible-package milestone and propagated the Nix/Cabal
`generic-lens` compatibility constraint to later packages.

2026-07-17: Recorded EP-1's explicit configuration representation and propagated the
narrow `Control.Lens.Setting` prelude exclusion required by Settei's public type name.

2026-07-17: Marked EP-1 complete after the full Cabal, Haddock, Nix, Mori, formatting, and
16-test acceptance suite. EP-2 is now the first dependency-ready plan.

2026-07-17: Marked EP-2 complete after the full Cabal, Haddock, Nix, Mori, formatting,
45-test, JSON-golden, and adversarial-redaction acceptance suite. EP-3 through EP-6 are now
dependency-ready.

2026-07-17: Marked EP-3 complete after its 62-test Cabal suite, Haddock, formatting,
explicit adapter Nix builds, and flake checks. Recorded the exact-origin core extensions,
secret-safe CLI metadata, migration guide, and optparse-applicative 0.19 Nix constraint.

2026-07-17: Marked EP-4 complete after its strict marked-event implementation, format ADR
and guide, 82-test workspace suite, 100%-covered adapter Haddocks, package checks,
formatting, dedicated Nix build, full flake check, and convention audit.

2026-07-17: Replaced the exceptional root-plus-`packages/` layout with a planned
top-level sibling-package convention. Added EP-8 to relocate the core and implemented
adapters without API changes, made KDL and Dhall depend on that gate, cascaded future paths
through the affected child plans, and amended ADR 0001 with the durable layout decision.

2026-07-17: Marked EP-8 complete after content-identical package moves and the full Cabal,
Haddock, source-distribution, Mori, Nix, flake, formatting, and 82-test acceptance gate.
EP-5 and EP-6 are now dependency-ready.

2026-07-17: Marked EP-5 complete after its canonical KDL v2 translator, guide, ADR 0005,
100-test workspace suite, five package checks, Haddocks, source distributions, Mori
inventory, dedicated/default Nix builds, formatting, and full host-platform flake check.
Propagated the one-element positional-array limitation to EP-7; EP-6 is now the first
dependency-ready plan.

2026-07-18: Marked EP-6 complete after its typed Dhall adapter, enforceable no-import and
root-confined local policies, structured closure provenance, stable secret-safe errors,
guide, ADR 0006, 121-test workspace suite, and full Cabal, Nix, flake, formatting,
convention, source-distribution, Haddock, and Mori gates. Propagated the actual import
contract to EP-7, which is now dependency-ready and the only remaining child plan.
