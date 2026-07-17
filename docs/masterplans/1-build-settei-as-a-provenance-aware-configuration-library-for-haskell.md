---
id: 1
slug: build-settei-as-a-provenance-aware-configuration-library-for-haskell
title: "Build Settei as a provenance-aware configuration library for Haskell"
kind: master-plan
created_at: 2026-07-16T23:49:52Z
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
unrelated release cycles. There is no `docs/adr/` directory or existing ADR relevant to
this work; Plans 1 and 2 must record the durable algebra and resolution decisions there
once the prototypes have supplied evidence.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|---|---|---|---|---|
| EP-1 | Bootstrap Settei and prove the inspectable configuration algebra | `docs/plans/1-bootstrap-settei-and-prove-the-inspectable-configuration-algebra.md` | None | None | Not Started |
| EP-2 | Implement hierarchical resolution, provenance, and derived defaults | `docs/plans/2-implement-hierarchical-resolution-provenance-and-derived-defaults.md` | EP-1 | None | Not Started |
| EP-3 | Add environment and optparse-applicative configuration sources | `docs/plans/3-add-environment-and-optparse-applicative-configuration-sources.md` | EP-2 | None | Not Started |
| EP-4 | Add YAML configuration support | `docs/plans/4-add-yaml-configuration-support.md` | EP-2 | None | Not Started |
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

Format-specific provenance is owned by the corresponding adapter. YAML reports a file,
logical key, and parse location when available; KDL additionally retains node spans;
Dhall reports the root expression and substantiated import closure while explicitly
stating that normalization prevents reliable per-leaf import attribution. Environment and
CLI origins record exact variable and option names. Kubernetes ConfigMap and Secret names
are annotations supplied by the application or deployment, not discovered by the core.


## Progress

- [ ] EP-1: make the repository build and test as a Cabal/Nix Haskell project.
- [ ] EP-1: prove and document the inspectable selective configuration algebra.
- [ ] EP-2: implement deterministic hierarchical resolution and structured provenance.
- [ ] EP-2: implement constant and dependency-aware defaults with safe explanations.
- [ ] EP-3: load explicit environment bindings and command-line overrides.
- [ ] EP-4: translate YAML documents into provenance-aware sources.
- [ ] EP-5: translate canonical KDL documents while preserving node locations.
- [ ] EP-6: translate normalized Dhall values and report honest import provenance.
- [ ] EP-7: demonstrate CLI and Kubernetes service use cases end to end.
- [ ] EP-7: publish package-family documentation and complete the release checklist.


## Surprises & Discoveries

(None yet.)


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


## Outcomes & Retrospective

To be filled during and after implementation. Before this MasterPlan is complete, distill
the durable algebra, resolution semantics, adapter boundary, and Dhall provenance
limitation into `docs/adr/`, and compare the shipped package family and demonstrations with
the vision above.
