---
id: 4
slug: deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook
title: "Deliver Kubernetes deployment support and the namespace configuration cookbook"
kind: master-plan
created_at: 2026-07-19T15:20:03Z
intention: "intention_01kxxfcw4ke5fbb2kas9ghvv9a"
---

# Deliver Kubernetes deployment support and the namespace configuration cookbook

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

The 2026-07-19 API review judged Kubernetes support the weakest part of Settei: what
ships today is provenance labeling (`KubernetesRef`, `kubernetesAnnotations`, and the
`fromKubernetes*` helpers), not integration. The owner is deploying roughly 50
microservices whose dominant configuration pattern is: one container image promoted
unchanged through several Kubernetes namespaces (for example dev, staging, production),
with configuration differing per namespace. That pattern needs no cluster client and no
special library mechanism — but it does need the mounted-file idioms Kubernetes actually
produces, structurally honest provenance, and above all a cookbook that shows the whole
flow end to end. After this initiative is complete, the following holds:

- A new `settei-kubernetes` adapter package reads a projected ConfigMap or Secret volume
  — the standard Kubernetes mount shape where each object key becomes one file in a
  directory — as an ordinary Settei `Source`, with explicit per-file key bindings
  (mirroring settei-env's explicit-bindings philosophy), per-key file locations, the
  Kubernetes atomic-writer symlink layout handled correctly, and secret-safe errors.
- Environment bindings can be derived from a `KubernetesRef` in one construction, so the
  binding and its provenance annotation cannot drift apart, and mounted-source origins
  carry freshness identity (mount path, file modification time) through the existing
  annotation vocabulary rather than core type changes.
- A namespace-driven configuration cookbook — the centerpiece of this initiative —
  documents how to configure and deploy a Settei microservice across namespaces:
  per-namespace ConfigMaps and Secrets with identical manifests, the downward API for
  namespace identity, `--check-config` as an init container gate, `--explain-config` as
  the incident runbook, and runnable manifests checked into the repository. The cookbook
  deliberately requires NO new library behavior for the namespace pattern itself; it
  teaches composition of what already exists.
- The Kubernetes-shaped reference service exercises the new adapter end to end and the
  release collateral (registration, compatibility matrix, changelogs, ADRs) is
  reconciled.

Out of scope, deliberately (consistent with docs/adr/0007): any Kubernetes API client,
cluster-state verification, watch/hot-reload of mounted volumes (restart-to-reload is
documented instead), Helm chart authoring (manifests are plain YAML plus kustomize
overlays), and operator/CRD tooling.


## Decomposition Strategy

Four work streams by functional concern:

1. The mounted-directory source is a self-contained new adapter package with its own
   parsing, validation, and provenance semantics — the same shape as the existing
   settei-yaml/settei-kdl/settei-dhall adapter plans.
2. Ref-derived bindings and freshness provenance extend the same package plus the shared
   annotation vocabulary; they are split from the source adapter because they touch the
   settei-env integration and the core renderer's Kubernetes suffix, and are
   independently verifiable.
3. The cookbook is documentation work with runnable manifests; it is the owner's primary
   ask and must not be hostage to adapter implementation, so it is a separate plan that
   can proceed in parallel (its adapter-referencing sections carry contingencies).
4. Reference-service integration and release collateral form the final conformance pass,
   per docs/adr/0007 (reference applications are the public-API conformance boundary).

Relevant ADRs consulted: docs/adr/0001-haskell-project-conventions.md (sibling package
layout, canonical stanza, dependency research process — governs the new package),
docs/adr/0003-resolution-provenance-and-default-semantics.md (source, origin, and
annotation semantics the adapter must respect; the Kubernetes annotation vocabulary it
extends), docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md
(the examples prove the process boundary only; no cluster access — this initiative keeps
that boundary and the cookbook documents the deployment side that lives outside the
process). docs/adr/0004/0005/0006 are not directly relevant beyond adapter-error styling
precedent. The ergonomics initiative's ADRs-to-be (docs/adr/0008 umbrella package,
docs/adr/0009 renderer contract) are consumed as constraints: settei-kubernetes follows
the renderer contract and may be added to settei-formats only as a follow-up decision.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 22 | Create the settei-kubernetes mounted-directory source adapter | docs/plans/22-create-the-settei-kubernetes-mounted-directory-source-adapter.md | None | None | Complete |
| 23 | Derive environment bindings and freshness provenance from Kubernetes references | docs/plans/23-derive-environment-bindings-and-freshness-provenance-from-kubernetes-references.md | EP-22 | None | Complete |
| 24 | Write the namespace-driven configuration cookbook and deployment manifests | docs/plans/24-write-the-namespace-driven-configuration-cookbook-and-deployment-manifests.md | None | EP-22, EP-23 | Complete |
| 25 | Integrate Kubernetes support into the reference service and release collateral | docs/plans/25-integrate-kubernetes-support-into-the-reference-service-and-release-collateral.md | EP-22, EP-23, EP-24 | None | Complete |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-22).


## Dependency Graph

EP-22 is implementable immediately; it creates the settei-kubernetes package and the
mounted-directory source. EP-23 hard-depends on EP-22 because it extends the same new
package (its code cannot compile without the package existing). EP-24 (the cookbook) has
no hard dependency — its core content, the namespace pattern, uses only shipped APIs —
but soft-depends on EP-22 and EP-23 for the sections that showcase the mounted-directory
source and derived bindings; those sections carry explicit contingencies if written
first. EP-25 hard-depends on all three: it wires the adapter into the reference service,
validates the cookbook's manifests against that service, and closes the release
collateral.

Cross-MasterPlan constraint: this initiative lands after
docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md and
docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md. It builds
directly on ergonomics deliverables: the validated `Bindings` type from
docs/plans/18-make-environment-bindings-total-and-validated.md (EP-23's derived bindings
return it), the adapter error renderer contract from
docs/plans/17-add-error-renderers-to-every-source-adapter.md (settei-kubernetes ships
renderers from day one), the `--check-config`/`DiagnosticMode` options from
docs/plans/21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md (the
cookbook's init-container gate), and the post-EP-12 resolver result shape from
docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md (the cookbook's
incident runbook shows failure reports). If this initiative is started earlier, each
child plan records which sections must be reconciled.


## Integration Points

New package settei-kubernetes (EP-22 owns; EP-23 extends; EP-25 registers in release
collateral): top-level sibling directory per docs/adr/0001 with the canonical common
stanza. EP-22 defines the package, its error type, its renderer (following the EP-17
contract), and the mounted-directory source API. EP-23 adds the bindings-derivation and
freshness behavior. The landed public derivation module is
`Settei.Kubernetes.Bindings`, with `objectKeyBinding`, `bindingsFromSecret`, and
`bindingsFromConfigMap`; validated collections compose through settei-env's
`mergeBindings`. Dependency direction: settei-kubernetes depends on settei, settei-env,
and time; nothing in the existing family depends on settei-kubernetes.

Kubernetes annotation vocabulary (EP-22, EP-23, core): docs/adr/0003 gives core the
shared `kubernetes.*` annotation names (kubernetes.object-kind, kubernetes.object-name,
kubernetes.namespace, kubernetes.object-key) rendered by the kubernetesSuffix in
settei/src/Settei/Render.hs. EP-23 owns the additive vocabulary extensions
(kubernetes.mount-path, kubernetes.file-modified, and any resource-identity names) and
decides whether the core renderer learns to display them; any core change is minimal and
additive. EP-23 landed `kubernetes.mount-path`, `kubernetes.file-modified`, and
`kubernetes.read-at`; text displays only the file modification time while JSON retains
all annotations. The durable semantics extend
docs/adr/0011-kubernetes-mounted-directory-input-semantics.md, with the core contract
amended in docs/adr/0003-resolution-provenance-and-default-semantics.md.

Deployment manifests (EP-24 owns; EP-25 validates): the landed manifests live under
examples/settei-service/deploy/ as a namespace-agnostic base plus dev, test, and
production kustomize overlays. `deploy/validate.sh` is the mandatory offline render and
invariant gate; `SETTEI_VALIDATE_SCHEMAS=1` adds the networked kubeconform pass. The
cookbook lives at docs/guides/kubernetes-cookbook.md, while
docs/guides/kubernetes-service.md is now the application-code half and links to the
cookbook for deployment.

Reference service (EP-25 owns the final pass; EP-22/EP-23 keep example edits minimal per
the established convention): examples/settei-service gains a mounted-directory
configuration path demonstrating the adapter; examples remain the conformance boundary
per docs/adr/0007 and never contact a cluster.

Cross-plan durable records: ADR 0011 owns the mounted-directory mapping semantics and
EP-23's freshness/identity vocabulary; ADR 0010 owns validated environment collection
composition and Kubernetes binding derivation; ADR 0003 owns the minimal core renderer
extension. The documented restart-to-reload posture and reaffirmed no-cluster-client
boundary remain for EP-24's cookbook and EP-25's final distillation.


## Progress

- [x] EP-22: settei-kubernetes package scaffolded and registered in cabal/nix/mori
- [x] EP-22: mounted-directory source with explicit file bindings, symlink handling, tests
- [x] EP-22: error type plus renderer per the adapter renderer contract
- [x] EP-23: bindingsFrom* derivation returning validated Bindings, tests
- [x] EP-23: freshness/identity annotations and renderer decision, ADRs amended
- [x] EP-24: namespace cookbook written with downward API, check-config gate, runbook
- [x] EP-24: runnable base+overlay manifests under examples/settei-service/deploy/
- [x] EP-25: reference service exercises the mounted-directory source end to end
- [x] EP-25: conformance/smoke coverage, compatibility matrix, changelogs, README
- [x] EP-25: ADR distillation and MasterPlan closure


## Surprises & Discoveries

- Plan authoring (2026-07-19) found that examples/settei-service already ships a small
  single-namespace manifest set under examples/settei-service/kubernetes/ (configmap,
  deployment, secret example). EP-24 replaces it with the base-plus-overlays layout
  under examples/settei-service/deploy/ and deletes the old directory.
- The child plans were authored in parallel, so each pins its cross-plan assumptions as
  a preflight reconciliation step (EP-23 verifies EP-22's final module surface and the
  ergonomics initiative's landed Bindings shape; EP-25 replaces every provisional
  spelling — including its placeholder name for EP-23's derivation constructors —
  against landed code before editing). Implementers must run those preflights rather
  than trust the provisional names.
- EP-24 research confirmed the nix dev shell currently ships no kubectl/kustomize/
  kubeconform; the manifest-validation tooling is added via the flake's extension
  point, and manifest rendering stays a checklist gate rather than a cabal test.
- EP-22's full Nix gate exposed stale wiring from the earlier formats work: the CLI and
  service Cabal packages depended on `settei-formats`, but their `callCabal2nix`
  overrides did not pass `setteiFormatsPackage`. EP-22 repaired those two overrides;
  later plans may rely on `nix flake check` evaluating both reference applications.
- EP-22 landed the provisional mounted-directory interface without renaming: the public
  collection is `FileBindings`, its smart constructor is `fileBindings`, options begin
  with `mountedDirectoryOptions`, and reads use `readMountedDirectorySource`. The durable
  semantics live in docs/adr/0011-kubernetes-mounted-directory-input-semantics.md. EP-23
  can extend this surface directly but must still reconcile its planned environment-
  binding constructor names against the live opaque `Bindings` API.
- EP-23 landed the provisional derivation names unchanged:
  `Settei.Kubernetes.Bindings.objectKeyBinding`, `bindingsFromSecret`, and
  `bindingsFromConfigMap`, returning settei-env's validated `Bindings`. EP-25 must use
  those exact names rather than its authoring-time placeholders; mixed manual and
  derived collections compose through `mergeBindings`.
- EP-23's Nix gate found that the CLI and service `callCabal2nix` overrides still passed
  direct format-adapter arguments removed when those applications adopted
  `settei-formats`. Cabal accepted the stale arguments because it does not consume Nix
  overrides, but `nix flake check` rejected them. EP-23 removed only arguments absent
  from each application's Cabal graph, retained the service test's direct settei-yaml
  argument, and added settei-env to the settei-kubernetes Nix and Mori dependency
  declarations; the flake gate then passed.
- EP-24 replaced the old `examples/settei-service/kubernetes/` directory with the exact
  downstream paths EP-25 must validate: `examples/settei-service/deploy/base/`,
  `deploy/overlays/{dev,test,production}/`, and `deploy/validate.sh`. The live guide is
  `docs/guides/kubernetes-cookbook.md`; EP-25 should not restore or reference the old
  manifest home.
- Kubeconform does not embed its default Kubernetes schema corpus; it downloads schemas
  from its default registry. EP-24 therefore made the offline kustomize render and grep
  gate mandatory and the schema pass opt-in through `SETTEI_VALIDATE_SCHEMAS=1`. EP-25
  can run both gates, but must not describe the schema pass as offline.
- A missing non-optional `secretKeyRef` blocks pod container startup at kubelet before
  the `--check-config` init container can run. EP-24's cookbook distinguishes this pod
  event from typed checker failures (exit 4). EP-25's final service/manifests validation
  must preserve that distinction in tests and release prose.
- EP-25 found that a `CustomSource` text origin renders its stable source name but not
  `SourceLocation.path`. The service therefore names mounted inputs `mounted service
  secrets at PATH`; JSON still retains the exact file location and
  `kubernetes.mount-path` annotation. This keeps the operator-visible mount path without
  changing the generic renderer contract.
- The installed Mori corpus entry for `shinzui/settei` lagged the live repository and
  omitted `settei-formats` and `settei-kubernetes`. Dependency discovery still began
  through Mori, then used the current registered project source for API verification.
  The checked-in `mori.dhall`, Cabal project, and Nix graph all contain the complete
  eleven-package workspace.


## Decision Log

- Decision: Scope this initiative to process-boundary integration only — mounted files,
  environment variables, and documentation; no Kubernetes API client, no watch/reload.
  Rationale: docs/adr/0007 already records that configuration delivery is visible to the
  process as files and environment variables; the review's gaps (projected-volume
  source, ref-derived bindings, freshness identity, cookbook) are all addressable at
  that boundary. Restart-to-reload is documented rather than engineered around.
  Date: 2026-07-19

- Decision: The namespace-driven configuration pattern gets NO special library
  mechanism; it is delivered as a cookbook (EP-24) composing existing features
  (per-namespace ConfigMaps, downward API env binding, named defaults, check/explain
  diagnostics).
  Rationale: Owner's explicit direction. The pattern is deployment topology, not
  library semantics: the same declaration resolves against whatever the namespace
  mounts. Any library affordance would couple Settei to cluster naming conventions.
  Date: 2026-07-19

- Decision: The mounted-directory source uses explicit per-file key bindings rather
  than deriving keys from file names automatically.
  Rationale: ConfigMap and Secret data keys legally contain dots (application.yaml,
  tls.crt), which collide with Settei's dotted key syntax; guessing a mapping would be
  the same trap ADR 0003 rejected for environment variables. Explicit bindings mirror
  settei-env and keep provenance honest. EP-22 records the detailed mapping semantics.
  Date: 2026-07-19

- Decision: Freshness and identity ride the existing annotation vocabulary
  (kubernetes.mount-path, kubernetes.file-modified, …) instead of extending the core
  KubernetesRef record.
  Rationale: Annotations are additive, adapter-owned, and already rendered through the
  ordered annotation map; changing the core record would ripple through every adapter
  for metadata only one adapter produces. EP-23 owns the exact names and the renderer
  decision.
  Date: 2026-07-19

- Decision: Run this initiative third, after the correctness and ergonomics
  MasterPlans.
  Rationale: The adapter should ship against the hardened core (post-EP-12 resolver
  shape) and the ergonomics contracts (validated Bindings, renderer convention,
  DiagnosticMode) rather than being written twice. The cookbook teaches the final API.
  Date: 2026-07-19

- Decision: The mounted adapter's final freshness vocabulary is
  `kubernetes.mount-path`, `kubernetes.file-modified`, and `kubernetes.read-at`, all
  captured eagerly during the read and descriptive only. Text renders only `(modified
  TIME)`; JSON retains the complete map.
  Rationale: Mount path, file modification time, and one source-wide read timestamp
  answer the incident questions without changing `KubernetesRef` or precedence. Showing
  all three on every text line would be noisy; the generic JSON representation already
  preserves them for detailed tooling. Durable semantics are in ADR 0011 and the core
  renderer contract amendment is in ADR 0003.
  Date: 2026-07-20

- Decision: Kubernetes deployment collateral has a mandatory offline validation path
  (`examples/settei-service/deploy/validate.sh`) that renders all overlays and checks
  their invariants. Kubeconform schema validation is an additional networked gate enabled
  with `SETTEI_VALIDATE_SCHEMAS=1`.
  Rationale: Kubeconform's default schemas are downloaded from a remote registry. Making
  that implicit would contradict the repository's client-side/offline default, while
  omitting schema validation entirely would discard a useful pinned tool. The split gives
  every contributor a deterministic baseline and CI an explicit stronger option.
  Date: 2026-07-20

- Decision: The reference Deployment demonstrates the same Secret through both a
  mounted `password` file and `DATABASE_PASSWORD`, ordered mounted file < environment,
  and binds `POD_NAMESPACE` to an optional public setting.
  Rationale: Keeping both delivery paths makes their precedence and shadow provenance
  observable in a real application. The optional namespace preserves the same binary's
  local usability while Kubernetes-only consumers may declare their namespace required.
  Date: 2026-07-20


## Outcomes & Retrospective

The initiative delivered every in-scope outcome.

- EP-22 created and registered `settei-kubernetes`. Its explicit `FileBindings` API
  reads projected ConfigMap/Secret directories through visible atomic-writer symlinks,
  keeps per-file locations, treats missing bound files as absent resolver inputs, and
  returns categorized value-free errors for invalid UTF-8 and I/O failures.
- EP-23 added `Settei.Kubernetes.Bindings`, so ConfigMap/Secret object-key rows derive
  validated environment bindings and provenance together. Mounted origins carry
  `kubernetes.mount-path`, `kubernetes.file-modified`, and `kubernetes.read-at`; text
  shows the concise modification suffix and JSON retains the full ordered annotations.
- EP-24 delivered the centerpiece namespace cookbook plus a namespace-agnostic base and
  dev/test/production Kustomize overlays. The manifests inject downward-API namespace,
  per-namespace public and secret data, and an init-container `--check-config` gate;
  the runbook covers redacted explanations, rollout failures, and restart-to-reload.
- EP-25 moved the adapter into the reference application's exercised boundary. Both
  containers mount `/etc/settei/secrets` and pass `--secrets-dir`; the service reads
  `password` as `database.password`, retains env-over-mounted precedence, explains the
  namespace, and proves its flags against the packaged manifests. Service and
  conformance coverage locks provenance, freshness, shadowing, exit codes, and secret
  redaction.

The release view is now coherent at eight publishable and eleven workspace packages.
The final pinned run built all packages and passed 333 tests across 12 suites, `cabal
check`, `nix flake check`, an isolated unpacked `settei-kubernetes` sdist test, offline
renders, the networked kubeconform pass, and mounted-directory exit-0/exit-3 smokes.
Compatibility, README, security, checklist, changelog, application guide, cookbook, and
deployment README all match that result.

The deliberate exclusions remained exclusions: there is no Kubernetes client or
cluster-state verification, no automatic discovery, watch, or hot reload, no Helm
chart, and no operator/CRD tooling. Settei consumes only process-visible files and
environment variables; asserted object identity is trusted metadata and deployments
restart to adopt new values. ADR 0011 owns those adapter and reload semantics, ADR 0010
owns derived validated bindings, ADR 0003 owns renderer behavior, and ADR 0007 now
records the mounted source as part of the exercised public-API conformance boundary.

The main implementation lesson was to preserve deployment and library boundaries while
making them test each other. Kustomize/schema checks prove Kubernetes topology;
parser-derived manifest tests prove that topology calls real binary flags; application
and conformance tests prove the same ordinary sources resolve safely without a cluster.
The only remaining inventory caveat is the separately installed Mori corpus lag; the
repository registration itself is complete.


## Revision Notes

2026-07-20: Closed EP-25 and the initiative after the reference-service integration,
333-test conformance run, release-collateral reconciliation, package/flake/sdist gates,
offline and networked manifest validation, mounted-directory smokes, and ADR
distillation. Recorded the final dual-delivery precedence, optional reference namespace,
renderer constraint, Mori corpus lag, validated outcomes, and deliberate exclusions.
