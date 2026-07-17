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

The work is divided into three waves. The first wave establishes a buildable package and
proves that the configuration language can be both selective at runtime and inspectable
before evaluation. The second wave defines the resolution and provenance contract. The
third wave implements independent source adapters against that contract, followed by an
integration plan that exercises the whole package family in CLI and Kubernetes-shaped
deployments.

Seven ExecPlans keep the risky algebra decision separate from runtime semantics, give each
serialization format an independently testable boundary, and let the four adapter plans
run in parallel once the core is stable. Environment and `optparse-applicative` share one
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
cross-plan implementation baseline adopted during this revision. Plans 1 and 2 must add
the algebra and resolution ADRs once their prototypes have supplied evidence.

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
| EP-5 | Add KDL configuration support | `docs/plans/5-add-kdl-configuration-support.md` | EP-2 | None | Not Started |
| EP-6 | Add Dhall configuration support | `docs/plans/6-add-dhall-configuration-support.md` | EP-2 | None | Not Started |
| EP-7 | Prove Settei in CLI and Kubernetes service reference applications | `docs/plans/7-prove-settei-in-cli-and-kubernetes-service-reference-applications.md` | EP-3, EP-4, EP-5, EP-6 | None | Not Started |

Status values are Not Started, In Progress, Complete, and Cancelled. Hard dependencies and
soft dependencies reference other rows by their EP prefix.


## Dependency Graph

EP-1 has no predecessor. It produces the repository layout, public declaration algebra,
static schema model, test harness, and an ADR-backed decision about the internal
free-selective representation. EP-2 depends on those types and adds the shared `Source`,
resolver, origin, explanation, and default-rule contracts. Those contracts must be stable
before any parser translates external data into a Settei source.

EP-3, EP-4, EP-5, and EP-6 all depend on EP-2 and can proceed in parallel. Each owns only
its input boundary and must consume the core source and provenance types rather than
reimplement merging. EP-7 depends on all four adapter plans because its acceptance cases
compare equivalent configurations across environment variables, CLI options, YAML, KDL,
and Dhall and demonstrate the complete Kubernetes delivery model.

The dependency shape is therefore:

```text
EP-1 -> EP-2 -> EP-3 --\
               EP-4 ---+
               EP-5 ---+-> EP-7
               EP-6 --/
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

The package workspace is established in EP-1. Adapter plans add packages beneath
`packages/`, register them in `cabal.project`, and extend the Nix and CI build without
changing the identity of the root `settei` package. EP-7 adds examples beneath `examples/`
and is responsible for testing package interoperability, documentation navigation, and
release readiness.

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
- [ ] EP-5: translate canonical KDL documents while preserving node locations.
- [ ] EP-6: translate normalized Dhall values and report honest import provenance.
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
dependency-ready and may implement adapters independently against this core contract.

EP-3 completed on 2026-07-17. It added pure explicit environment bindings, opt-in prefix
derivation, trusted Kubernetes annotations, ordered optparse-applicative overrides, named
options, grouped reusable parsers, and an audited migration guide. Per-key annotations and
descending shadow traces were added to core so every adapter can preserve exact origins.
The 62-test suite and Cabal build/check/Haddock, Nix format/check, and explicit adapter
builds pass; ADRs 0001 and 0003 retain the cross-plan packaging, provenance, rendering,
and redaction decisions. EP-4 through EP-6 remain dependency-ready.

EP-4 completed on 2026-07-17. It added a direct marked-event YAML translator, strict
single-mapping input semantics, duplicate and unsupported-feature rejection, exact
successful-node locations, structured secret-safe errors, file IO, mounted ConfigMap or
Secret metadata, and a complete format guide. ADR 0004 preserves the portable YAML
contract. The 82-test workspace suite, 100%-covered YAML Haddocks, package checks, Nix
formatting, dedicated YAML build, full flake check, and convention audit pass. EP-5 and
EP-6 remain dependency-ready.

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
