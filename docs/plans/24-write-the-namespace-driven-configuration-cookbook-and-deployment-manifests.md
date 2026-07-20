---
id: 24
slug: write-the-namespace-driven-configuration-cookbook-and-deployment-manifests
title: "Write the namespace-driven configuration cookbook and deployment manifests"
kind: exec-plan
created_at: 2026-07-19T15:20:08Z
intention: "intention_01kxxfcw4ke5fbb2kas9ghvv9a"
master_plan: "docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md"
---

# Write the namespace-driven configuration cookbook and deployment manifests

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Settei is being rolled out to roughly 50 microservices and 20 applications, and the
owner's stated dominant pattern is: one container image, promoted unchanged through
several Kubernetes namespaces (dev, staging/test, production), with configuration
differing per namespace. The library deliberately needs no special mechanism for this —
the parent MasterPlan (docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md)
records that decision — but nothing today shows an adopter how to actually do it. The
existing guide docs/guides/kubernetes-service.md mixes application code with a single
hand-written Deployment fragment; there are no per-namespace manifests, no promotion
story, no deploy-time validation gate, and no incident runbook.

After this plan is complete, two things exist that do not exist today. First, a runnable,
mechanically validated manifest set under `examples/settei-service/deploy/` — a
namespace-agnostic base Deployment plus `dev`, `test`, and `production` kustomize
overlays whose only differences are namespace and configuration data — deploying the
existing reference service `settei-example-service`. Second, a new cookbook guide
`docs/guides/kubernetes-cookbook.md`, the centerpiece of this initiative, that walks a
novice operator end to end: how namespace identity reaches the process, how to switch
behavior per namespace with an explicit `HASKELL_ENV` value, how ConfigMaps and Secrets
deliver values, how `--check-config` in an init container fails a bad rollout before
traffic, how `--explain-config` inside a pod answers "what configuration is this pod
actually running with", and why restart-to-reload is the documented posture. The
existing docs/guides/kubernetes-service.md narrows to application code only and links to
the cookbook for everything deployment-shaped.

You can see it working, from the repository root `/Users/shinzui/Keikaku/bokuno/settei`:

```bash
nix develop -c kubectl kustomize examples/settei-service/deploy/overlays/production
nix develop -c bash examples/settei-service/deploy/validate.sh
```

The first command renders the production overlay (Deployment plus a ConfigMap carrying
`HASKELL_ENV: production` and a placeholder Secret, all in namespace `production`)
without contacting any cluster. The second renders every overlay and asserts the
expected per-namespace values are present and no real-looking credential is. A full
read-through of the finished cookbook lets a novice deploy the reference service to a
local kind or minikube cluster — an explicitly optional, manual acceptance step that
stays outside CI, because per docs/adr/0007 the examples never contact a cluster.

This is documentation-and-manifests work only. No Haskell source file changes in this
plan; service code changes (for example binding the downward-API namespace variable) are
EP-25's job (docs/plans/25-integrate-kubernetes-support-into-the-reference-service-and-release-collateral.md).


## Progress

Milestone 1 — validation tooling and the manifest set:

- [x] (2026-07-20T02:39:03Z) Create `flake.module.nix` from
      `flake.module.nix.example`, adding `pkgs.kubectl` and `pkgs.kubeconform` to
      `haskellProject.extraDevPackages`; track it; verify `nix develop -c kubectl
      version --client` and `nix develop -c kubeconform -v` work.
- [x] (2026-07-20T02:45:13Z) Create
      `examples/settei-service/deploy/base/deployment.yaml` with downward-API namespace,
      ConfigMap-keyed `HASKELL_ENV`, Secret-backed `DATABASE_PASSWORD`, projected
      ConfigMap file, `--check-config` init container, and commented probe template.
- [x] (2026-07-20T02:45:13Z) Create
      `examples/settei-service/deploy/base/kustomization.yaml`.
- [x] (2026-07-20T02:45:13Z) Create the dev overlay with its kustomization, ConfigMap,
      and loud placeholder Secret.
- [x] (2026-07-20T02:45:13Z) Create the test overlay with its test-specific values.
- [x] (2026-07-20T02:45:13Z) Create the production overlay with its
      production-specific values.
- [x] (2026-07-20T02:45:13Z) Create `examples/settei-service/deploy/README.md` with the
      cookbook pointer, secret-hygiene warning, offline gate, and opt-in schema gate.
- [x] (2026-07-20T02:45:13Z) Create executable
      `examples/settei-service/deploy/validate.sh`; all render and value expectations
      pass, and opt-in kubeconform reports three valid resources for each overlay.
- [x] (2026-07-20T02:45:13Z) Delete the superseded
      `examples/settei-service/kubernetes/` tree and update its two immediate referrers
      to `deploy/`.
- [x] (2026-07-20T02:45:13Z) Manifest render, offline validation, opt-in schema
      validation, and the full `cabal test all --test-show-details=direct` suite pass;
      commit the manifest milestone.

Milestone 2 — the cookbook guide:

- [x] (2026-07-20T02:52:42Z) Reconcile every API name used by the cookbook against the
      current tree: all five diagnostic flags, exit codes 2/3/4, exact renderer text,
      `RejectUnknownKeys`, the EP-22 mounted-directory API, and the EP-23 binding
      derivation API.
- [x] (2026-07-20T02:52:42Z) Write `docs/guides/kubernetes-cookbook.md` sections 1–5:
      topology, namespace identity, explicit environment choice and its alternative,
      per-namespace delivery paths, and the checked-in manifest walkthrough.
- [x] (2026-07-20T02:52:42Z) Write sections 6–10: rollout gate, incident runbook,
      restart-to-reload posture, strict unknown-key recommendation, and FAQ.
- [x] (2026-07-20T02:52:42Z) Capture real `--check-config` and successful/failing
      `--explain-config` output from the built service using the overlay's public data;
      the production password is `<redacted>`, its sentinel is absent, and the missing
      Production password exits 4 with a provenance report.
- [x] (2026-07-20T02:52:42Z) Resolve the EP-22/EP-23 contingency by documenting the
      shipped `Settei.Kubernetes` mounted-directory API and exact
      `Settei.Kubernetes.Bindings.bindingsFromSecret` construction.
- [x] (2026-07-20T02:52:42Z) Commit the complete cookbook milestone.

Milestone 3 — rescope the service guide and update indexes:

- [x] (2026-07-20T02:56:55Z) Rescope `docs/guides/kubernetes-service.md` to application
      code only; remove Deployment/ConfigMap manifest YAML and deployment checklist
      items; cross-link the cookbook's rollout, rotation, and manifest sections.
- [x] (2026-07-20T02:56:55Z) Update `docs/guides/README.md` with a new namespace
      deployment row and narrow the service-guide description to application code.
- [x] (2026-07-20T02:56:55Z) Add the cookbook to the top-level `README.md` guide list.
- [x] (2026-07-20T02:56:55Z) Verify live documentation and example paths contain no
      `settei-service/kubernetes` reference, local links resolve, and the service guide
      contains no deployment manifest YAML; commit the rescope milestone.

Milestone 4 — validation, bookkeeping, closure:

- [x] (2026-07-20T03:00:20Z) Run the full validation pass from a clean tree: all three
      overlays render and pass invariant checks; opt-in kubeconform validates three
      resources per overlay; clean `cabal test all --test-show-details=direct` passes all
      322 tests; `nix flake check` passes; concise evidence added below.
- [x] (2026-07-20T03:00:20Z) Read the finished cookbook start to finish as a novice;
      verify every local link and language-tagged fence; clarify namespace declaration,
      validated binding composition, mounted-source error handling, missing-Secret pod
      events, and commands that contact a cluster.
- [x] (2026-07-20T03:00:20Z) Skip the optional kind/minikube walkthrough: the repository
      intentionally supplies an unpullable image and placeholder Secret, no disposable
      cluster was placed in scope, and ADR 0007 keeps live-cluster acceptance outside
      required CI.
- [x] (2026-07-20T03:00:20Z) Mark MasterPlan registry row EP-24 Complete and check its
      cookbook and runnable-manifest Progress items; add cross-plan findings for EP-25.
- [x] (2026-07-20T03:00:20Z) Fill Outcomes & Retrospective and perform the ADR
      distillation review. No new ADR is needed here; restart-to-reload and the
      no-cluster-client boundary remain explicitly queued for EP-25's initiative-wide
      distillation. Commit EP-24 closure.


## Surprises & Discoveries

- Mori has no registered project matching either `kubectl` or `kubeconform`, so there
  was no local source corpus to inspect for these deployment tools. The repository's
  locked Nix package set is the executable authority for this plan: the new dev shell
  evaluates and provides kubectl v1.36.1 with kustomize v5.8.1 and kubeconform v0.7.0.
  Evidence: both version commands exited 0 on 2026-07-20.

- Kubeconform's default schema location is a remote GitHub registry rather than an
  embedded offline schema set. The mandatory `validate.sh` path therefore keeps
  client-side kustomize rendering and invariant greps offline and makes schema checking
  explicit through `SETTEI_VALIDATE_SCHEMAS=1`. Evidence: the opt-in run validated all
  three resources in each of dev, test, and production with zero invalid resources or
  errors.

- The service fixture used by its tests intentionally contains `undeclared.setting`, so
  a direct guide capture against that fixture prints the default unknown-key warning.
  To keep the cookbook transcript specific to the checked-in overlays, the real binary
  was instead fed the overlay's `application.yaml` value through `/dev/stdin`. This
  produced the exact production host and no unrelated warning while exercising the same
  YAML loader and ConfigMap annotations.

- The illustrative renderer transcript in the authored plan did not match the landed
  renderer byte-for-byte. The shipped text says `from file source PATH (YAML) from
  Kubernetes ...`, renders default dependencies on nested `because` lines, and appends a
  final selected/not-selected branch trace. The cookbook uses captured text rather than
  preserving the sketch.

- A non-optional `secretKeyRef` changes where an absent Production Secret fails: kubelet
  prevents every pod container from starting until the Secret and named key exist, so
  the `--check-config` init container cannot itself report exit 4 for that cluster-side
  absence. Exit 4 still covers typed failures after the process starts, and the locally
  captured no-password run proves its diagnostic. The cookbook now directs operators to
  pod events for missing Kubernetes objects and to init-container logs for application
  failures instead of conflating the two gates.

- The authored dangling-link command searched all of `docs/`, which necessarily matched
  historical ExecPlans that describe the old directory and even matched EP-24's own
  migration instructions. The meaningful integrity gate is scoped to live guides,
  top-level README, and examples: `rg -n "settei-service/kubernetes" docs/guides
  README.md examples`. That command produced no matches after the rescope.


## Decision Log

- Decision: The cookbook's central recommendation is an explicit per-namespace
  environment switch — a `HASKELL_ENV` value of `development`, `test`, or `production`
  stored in each namespace's ConfigMap — and NOT deriving the runtime environment from
  the namespace name delivered by the downward API. Deriving from the namespace name is
  presented as a documented alternative with explicit caveats.
  Rationale: Namespace names are cluster topology, not application semantics. In real
  fleets they are team-prefixed (`payments-prod`), ephemeral (preview namespaces like
  `pr-4711`), or renamed during cluster migrations; deriving behavior from them couples
  every application to a naming convention nobody owns end to end. An explicit value in
  the namespace's ConfigMap survives migrations, works in preview namespaces (a preview
  namespace can simply declare `HASKELL_ENV: test`), and makes the environment choice
  reviewable in the overlay diff. The alternative works when naming is centrally
  governed, so the cookbook shows the `enumDecoder`/`parsedDecoder` binding for it
  rather than pretending it does not exist.
  Date: 2026-07-19

- Decision: Manifest layout — `deploy/base/` contains only the namespace-agnostic
  Deployment; each overlay (`deploy/overlays/{dev,test,production}/`) contains its own
  same-named ConfigMap and Secret plus a `namespace:` line in its kustomization. The
  Deployment reads `HASKELL_ENV` via `configMapKeyRef` rather than an inline `value:`.
  Rationale: This makes the promotion topology structurally true in the files: the
  Deployment never mentions a namespace or an environment name, so promoting the image
  means applying an unchanged base to the next overlay; only object *data* varies. An
  inline `env: value: production` in the base (as today's hand-written example has)
  would force every overlay to patch the Deployment, which is exactly the drift the
  cookbook warns against.
  Date: 2026-07-19

- Decision: Secret hygiene — each overlay ships a plain `Secret` manifest whose
  `stringData.password` is the literal `PLACEHOLDER-REPLACE-VIA-YOUR-SECRET-PIPELINE`
  under a loud comment saying never to commit a real value. `secretGenerator` was
  considered and rejected. The cookbook never shows a real or realistic secret value
  anywhere, including transcripts, where the value always appears as `<redacted>`;
  `validate.sh` asserts the placeholder marker is present in every rendered overlay.
  Rationale: kustomize's `secretGenerator` appends a content hash to the object name,
  which breaks the fixed name `settei-example-service-database` that the service's
  provenance annotation asserts (examples/settei-service/src/Settei/Example/Service.hs,
  `environmentBindings`); disabling the hash (`disableNameSuffixHash`) forfeits the
  generator's only benefit while adding indirection. A plain manifest with an
  unmistakable placeholder is easier to grep-validate, easier to explain, and matches
  the existing repository stance ("Do not commit a usable Secret manifest, encoded
  credential, or stable placeholder that could be mistaken for a credential" —
  docs/guides/kubernetes-service.md).
  Date: 2026-07-19

- Decision: Validation tooling — `kubectl` (whose `kubectl kustomize` subcommand
  renders overlays client-side with no cluster) and `kubeconform` (the optional
  network-backed schema validator described by the following decision) are added to
  the Nix dev shell via a new tracked `flake.module.nix`
  setting `haskellProject.extraDevPackages`, the extension point `nix/haskell.nix`
  declares for exactly this purpose. The mandatory mechanical gate is
  `examples/settei-service/deploy/validate.sh`: it renders every overlay with
  `kubectl kustomize` and greps for expected per-namespace values; kubeconform runs
  inside it only when `SETTEI_VALIDATE_SCHEMAS=1`. The script is NOT wired into
  `cabal test all`.
  Rationale: Honest inventory: the dev shell today contains only zlib, just, and
  pkg-config (nix/haskell.nix `baseDevPackages`); kubectl and kustomize exist in the
  plan author's user profile but a novice or CI runner cannot rely on that.
  `flake.module.nix` is the documented conflict-free extension file (see
  flake.module.nix.example; nix/haskell.nix and flake.nix are seihou-managed and must
  not be edited). Keeping the script out of the cabal test suite keeps
  `cabal test all` hermetic — a Haskell test suite shelling out to kubectl would fail
  on machines without the tool and would couple Haskell CI to deployment tooling. The
  repository currently has no CI workflow directory at all, so "a repo test or CI
  step" resolves to: the checked-in script is the repo test, run via
  `nix develop -c bash examples/settei-service/deploy/validate.sh`, and when a CI
  pipeline is introduced it should invoke that exact command (recorded here for
  whoever adds CI).
  Date: 2026-07-19

- Decision: Kubeconform validation is opt-in through `SETTEI_VALIDATE_SCHEMAS=1`; the
  default `validate.sh` gate is the offline kustomize render plus invariant checks.
  Rationale: Kubeconform's authoritative documentation confirms that its default schema
  location downloads schemas from a remote registry. Vendoring the Kubernetes schema
  corpus solely for three standard resources is disproportionate, while silently
  introducing network access would contradict the plan's offline default. The opt-in
  path remains reproducible through the pinned dev shell and passed for all overlays.
  Date: 2026-07-20

- Decision: The pre-existing hand-written manifest directory
  `examples/settei-service/kubernetes/` (configmap.yaml, deployment.yaml,
  secret.yaml.example, README.md) is deleted in Milestone 1 and replaced by
  `examples/settei-service/deploy/`; its two referrers (the closing paragraph of
  docs/guides/kubernetes-service.md and examples/settei-service/README.md) are updated
  in the same commit.
  Rationale: The MasterPlan fixes the manifest home as `examples/settei-service/deploy/`
  (base plus overlays). Keeping both directories would give adopters two divergent
  manifest sets, one of them unvalidated and single-namespace — worse than none. The
  old files' content survives, upgraded, inside the new base and overlays (the old
  deployment.yaml even carries a bug worth fixing: its long-running container runs
  `--explain-config`, a render-and-exit diagnostic mode, as its main args).
  Date: 2026-07-19

- Decision: This plan changes no Haskell code. The base Deployment injects
  `POD_NAMESPACE` via the downward API even though the current service binds no such
  variable; binding it to a Settei key (`kubernetes.namespace`) in
  `environmentBindings` is service-code work that belongs to EP-25, which owns all
  reference-service code changes and conformance impact for this initiative. The
  cookbook teaches the binding as the pattern adopters should implement.
  Rationale: The MasterPlan draws the boundary explicitly ("manifests and docs here,
  service code there"), and Settei's explicit-bindings model makes an unbound
  environment variable inert — the manifest can ship the variable ahead of the binding
  with zero behavior change, so the two plans compose without ordering pressure.
  Date: 2026-07-19

- Decision: The cookbook is written against the post-MasterPlan-2-and-3 tree (the
  hardened resolver from docs/plans/12-…md, the shared `DiagnosticMode` flags and
  warning rendering from docs/plans/21-…md, the adapter error renderers from
  docs/plans/17-…md). Reconciliation rule: every cookbook section that names an API,
  flag, exit code, or rendered output includes a verify-against-source step at
  implementation time — read the shipped module or run the built binary and paste real
  output — because several of those sibling plans were skeletons or unimplemented when
  this plan was authored. The flag spellings used throughout this plan
  (`--check-config`, `--explain-config`, `--explain-config-json`, exit codes 2/3/4)
  exist in today's tree already and are stable across EP-21 by its own Decision Log;
  `--describe-config` is EP-21's addition and is mentioned by the cookbook only if
  shipped.
  Date: 2026-07-19

- Decision: EP-22/EP-23 soft-dependency contingencies. The cookbook's "Secrets as
  mounted files" alternative (a Secret volume read as a directory via the
  settei-kubernetes adapter) and any use of ref-derived binding constructors are
  written only against shipped APIs. If EP-22 (docs/plans/22-…md) has not landed when
  the cookbook is written, the mounted-directory alternative is reduced to a two-
  sentence forward pointer ("Kubernetes can also project a Secret as a directory of
  files; the settei-kubernetes adapter, when released, reads that layout — see its
  package documentation") and the full subsection is added by EP-25. If EP-23
  (docs/plans/23-…md) has not landed, the DATABASE_PASSWORD flow is shown with today's
  shipped `fromKubernetesObject` + `binding` composition (which works and stays
  correct); the single-construction derived-bindings spelling replaces it during
  EP-25's pass.
  Rationale: The MasterPlan makes the cookbook deliberately independent ("must not be
  hostage to adapter implementation"); both sibling plans are placeholder skeletons at
  authoring time, so no API name from them can be trusted yet.
  Date: 2026-07-19

- Decision: Both soft dependencies landed before cookbook implementation, so the guide
  includes the full mounted-Secret alternative using `Settei.Kubernetes.fileBindings`,
  `mountedDirectoryOptions`, and `readMountedDirectorySource`, and the environment
  example uses `Settei.Kubernetes.Bindings.bindingsFromSecret` with
  `objectKeyBinding`. Nothing remains deferred to EP-25 for API spelling.
  Rationale: The implementations and their test suites are present, their exported names
  match the provisional plan, and using those names now prevents the centerpiece guide
  from shipping an obsolete manual-construction path.
  Date: 2026-07-20

- Decision: The base Deployment includes a readinessProbe only as a commented-out
  template with an explanatory comment, and the main container runs with no diagnostic
  flag.
  Rationale: Honesty about the reference binary: `settei-example-service` resolves
  configuration, prints a safe startup summary, and exits — it is a startup model, not
  a long-running server (per its README and ADR 0007). A live readinessProbe against a
  process that exits would make every pod permanently unready and teach nothing; a
  commented template (comments survive in the checked-in file for readers; kustomize
  strips them from renders, harmlessly) shows real services exactly where the probe
  goes. The cookbook states this explicitly so nobody files a bug about crash-looping
  example pods, and the optional kind walkthrough sets expectations (observe init
  container success and main-container logs, not a Ready condition).
  Date: 2026-07-19

- Decision: No ADR is created by this plan. The two durable positions it documents —
  the restart-to-reload posture and the reaffirmed no-cluster-client boundary — are
  recorded in the cookbook prose here and promoted into `docs/adr/` during EP-25's
  distillation pass, as the MasterPlan's Integration Points section directs.
  Rationale: EP-25 closes the initiative and performs one coherent distillation over
  all four child plans; creating a partial ADR now would either duplicate or conflict
  with that pass.
  Date: 2026-07-19

- Decision: Overlay namespace names are `dev`, `test`, and `production`, while the
  environment values are `development`, `test`, and `production`.
  Rationale: The deliberate mismatch between the namespace name `dev` and the
  environment value `development` is a teaching device: it makes the cookbook's central
  point — namespace name and runtime environment are different things — visible in the
  very first render, and it means a reader who wrongly assumes name-derivation will see
  their assumption fail immediately (`dev` is not a member of the `enumDecoder` table).
  Date: 2026-07-19


## Outcomes & Retrospective

EP-24 delivered the initiative's centerpiece: a ten-section namespace deployment
cookbook backed by a runnable client-side manifest set rather than copied inline YAML.
The namespace-agnostic base and dev/test/production overlays make the one-image promotion
model structural, inject namespace identity through the downward API, deliver explicit
`HASKELL_ENV` and Secret data, and run the same image and inputs through a
`--check-config` init container. The old single-namespace manifest directory is gone,
and the service guide now owns application code while the cookbook owns deployment and
operations.

The repository-specific validation path is reproducible from the pinned dev shell.
Offline rendering and invariant checks pass for all three overlays; the opt-in remote
schema pass validates all nine rendered resources; a clean rebuild passes all 322
Haskell tests; and `nix flake check` passes package evaluation, treefmt, and pre-commit.
Real successful and failing service output in the cookbook confirms exit behavior,
default-rule provenance, and password redaction.

Two implementation-time corrections improved the authored design. Kubeconform's default
schemas are remote, so schema validation is explicit rather than silently making the
mandatory gate network-dependent. Also, a missing non-optional Kubernetes Secret blocks
pod startup before the init container, while typed failures after the checker starts use
exit code 4; the incident runbook distinguishes pod events from application logs. The
optional live-cluster walkthrough remains deliberately outside acceptance.

The ADR review found no new project decision to promote in this child plan. The durable
restart-to-reload posture and process-only/no-cluster-client boundary were already
identified by the MasterPlan and remain queued for EP-25's final distillation pass.


## Context and Orientation

### The repository and the application being deployed

This repository at `/Users/shinzui/Keikaku/bokuno/settei` is a Cabal multi-package
Haskell workspace for the Settei configuration library, built inside a Nix dev shell
(prefix every cabal command with `nix develop -c`). The packages: `settei` (core),
`settei-env`, `settei-yaml`, `settei-kdl`, `settei-dhall`,
`settei-optparse-applicative` (adapters), and three internal packages under
`examples/`. This plan centers on `examples/settei-service`, the Kubernetes-shaped
reference service, defined by:

- `examples/settei-service/src/Settei/Example/Service.hs` — the whole application.
- `examples/settei-service/app/Main.hs` — a thin executable wrapper.
- `examples/settei-service/kubernetes/` — today's hand-written single-namespace
  manifests, replaced by this plan (see Decision Log).

What the service does, in enough detail to write manifests against it. It declares a
typed `ServiceConfig` with a `RuntimeEnvironment` enum whose accepted spellings are
exactly `development`, `test`, and `production` (an `enumDecoder` table on the key
`runtime.environment`). Configuration arrives from, lowest precedence first: one
optional mounted file passed as `--config FORMAT:PATH` (`yaml:`, `kdl:`, or `dhall:`
prefix — the manifests use `yaml:/etc/settei/application.yaml`), then explicitly bound
environment variables. The bindings (`environmentBindings` in Service.hs) map
`HASKELL_ENV` → `runtime.environment`, `HTTP_HOST`/`HTTP_PORT`, `DATABASE_HOST`/
`DATABASE_PORT`/`DATABASE_POOL_SIZE`, and `DATABASE_PASSWORD` → `database.password`,
the last wrapped in `fromKubernetesObject (kubernetesRef SecretObject Nothing
"settei-example-service-database" (Just "password"))` so reports can truthfully say
"this value was delivered from that Secret" without ever contacting a cluster. Only
bound variables are read — an environment variable with no binding is invisible to the
resolver, which is why the manifests can safely inject `POD_NAMESPACE` before EP-25
binds it. Two named default rules make environments behaviorally different even with
identical files: `http-port-by-environment` (Development 8080, Test 18080, Production
8080) and `database-pool-size-by-environment` (Development 2, Test 1, Production 20);
`database.password` is *required only when* `runtime.environment` is `production` (a
Selective branch). The mounted file is annotated as ConfigMap
`settei-example-service`, key `application.yaml`.

Diagnostics and exit codes, which the deploy-time gate and runbook are built on:
`--check-config` validates and prints `configuration valid`; `--explain-config` prints
a redacted text report of every setting with its winning origin, shadowed origins, and
fired default rules; `--explain-config-json` prints the same as JSON. Exit codes: 0
success, 2 usage error, 3 source failure (unreadable/unparseable mounted file), 4
resolution failure (missing required value, undecodable value). After the correctness
MasterPlan's EP-12 (docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md),
a *failing* resolution under an explain mode also prints the full provenance report
after the errors — the crash-loop debugging view the runbook teaches.

### Kubernetes knowledge this plan embeds

Define the terms once, because the cookbook's implementer and readers may be new to
Kubernetes. A *namespace* is a named partition of a cluster; object names are unique
per namespace, so every namespace can hold its own ConfigMap named
`settei-example-service`. A *ConfigMap* is a dictionary object of string keys to string
values; a *Secret* is the same shape for credentials (base64-wrapped at rest, delivered
to pods as plaintext). A *Deployment* declares a pod template and a replica count; a
*rollout* replaces old pods with new ones incrementally. *kustomize* is a template-free
YAML composition tool built into kubectl: a *base* directory holds common manifests, an
*overlay* directory references the base and layers differences (a `namespace:` field,
additional resources); `kubectl kustomize DIR` renders the composed YAML to stdout with
no cluster involved. The *downward API* lets a pod read its own metadata: an env var
with `valueFrom: fieldRef: fieldPath: metadata.namespace` receives the pod's namespace
name. An *init container* runs to completion before the main containers start; if it
exits non-zero the pod fails and a Deployment rollout halts with the previous replicas
still serving. A *readinessProbe* tells Kubernetes when a running container may receive
traffic.

The promotion topology the cookbook teaches: ONE container image is built once and
promoted unchanged dev → test → production. Each namespace holds same-named ConfigMap
and Secret objects with different values. Because the Deployment manifest references
those objects only by name and never states a namespace or environment, the overlays
vary only data — promoting a release is applying the identical base into the next
namespace, and configuration differences are exactly the visible diff between overlay
directories.

Config delivery mechanics the cookbook must state truthfully. A ConfigMap key mounted
as a file appears under the mount path via Kubernetes' atomic-writer layout: the mount
directory contains symlinks through a `..data` indirection, and an update atomically
swaps the `..data` symlink to a new timestamped directory. So mounted *files* do change
on disk after a ConfigMap update (with kubelet sync delay) — but Settei's documented
model is resolve-once-at-startup, so the running process's typed configuration does not
change; the documented posture is restart-to-reload (`kubectl rollout restart
deployment/NAME`). Environment-variable-delivered values are stricter: env vars are
fixed at container start and NEVER update without pod recreation, no matter how the
ConfigMap or Secret changes. Both facts are true Kubernetes behavior and the cookbook
states them as such.

### Sibling plans and the reconciliation rule

Hard dependencies: none. Soft dependencies: EP-22
(docs/plans/22-create-the-settei-kubernetes-mounted-directory-source-adapter.md) and
EP-23 (docs/plans/23-derive-environment-bindings-and-freshness-provenance-from-kubernetes-references.md).
Both were verified to be unfilled skeleton documents when this plan was authored, so the
contingencies in the Decision Log are live: write those cookbook passages only against
shipped code, otherwise defer to EP-25. Cross-initiative inputs, all under docs/plans/:
EP-21 (21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md) ships
the shared `DiagnosticMode` (`--check-config`, `--describe-config`,
`--describe-config-json` added; existing explain flags kept), renders resolver warnings
to stderr, and already commits the kubernetes-service guide to a `RejectUnknownKeys`
recommendation and an initContainer recipe — this plan's cookbook is where that content
actually gets its full treatment, and Milestone 3 must reconcile so the two guides do
not duplicate. EP-12 (12-report-resolution-provenance-and-warnings-on-failure.md) makes
failure reports available under explain modes. EP-17
(17-add-error-renderers-to-every-source-adapter.md) means source-failure stderr text is
renderer-formatted. The standing rule, restated: every cookbook section that names an
API or shows output carries an implementation-time verify-against-source step; all
transcripts in the published guide must be real captured output, with this plan's
sketches replaced.

### Relevant ADRs

- docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md —
  the examples prove the process boundary only: configuration is visible to the process
  as files and environment variables; the application never contacts a cluster; a live
  Kubernetes integration test was explicitly rejected. This plan's manifests are the
  OUTSIDE of that boundary: they are validated by client-side tooling
  (`kubectl kustomize`, kubeconform, greps), never by cluster tests, and the kind
  walkthrough is optional manual acceptance outside CI.
- docs/adr/0003-resolution-provenance-and-default-semantics.md — redaction rules the
  cookbook's transcripts must respect: secret values never appear in any report; the
  rendered form is `<redacted>`.
- docs/adr/0001-haskell-project-conventions.md — not directly relevant (no Haskell
  code changes); its dev-shell conventions motivate using flake.module.nix rather than
  editing seihou-managed nix files.

No ADR covers Kubernetes deployment topology; per the Decision Log, this plan creates
none, and EP-25 promotes the durable positions during distillation.

### Documentation surface touched

`docs/guides/kubernetes-cookbook.md` (new), `docs/guides/kubernetes-service.md`
(rescoped — today it contains a "Create the ConfigMap and Deployment" manifest section
and deployment items in its operational checklist, all of which move), `docs/guides/README.md`
(index table gains a row), top-level `README.md` (guide list at lines ~124–131 gains
the cookbook), `examples/settei-service/README.md` (points at `deploy/`), and the new
`examples/settei-service/deploy/README.md`.


## Plan of Work

Four milestones, each ending with the repository consistent and committed. Milestone 1
builds the manifests and their mechanical validation so the cookbook can reference
checked-in, tested files rather than inline YAML. Milestone 2 writes the cookbook
against those files. Milestone 3 rescopes the old guide and fixes every index.
Milestone 4 validates end to end and closes the bookkeeping.


### Milestone 1 — validation tooling and the manifest set

Scope: the Nix dev shell gains kubectl and kubeconform; `examples/settei-service/deploy/`
comes into existence with a base, three overlays, a README, and a validation script;
the old `examples/settei-service/kubernetes/` directory is deleted with referrers
updated. At the end, `nix develop -c bash examples/settei-service/deploy/validate.sh`
passes and `nix develop -c cabal test all` is untouched-green.

First the tooling. Copy `flake.module.nix.example` to `flake.module.nix` and set, in
its `perSystem` block:

```nix
haskellProject.extraDevPackages = [ pkgs.kubectl pkgs.kubeconform ];
```

Keep the rest of the example file's comments or trim them; do not edit `flake.nix` or
anything under `nix/` (seihou-managed). Flakes only see git-tracked files, so run
`git add flake.module.nix` before testing with
`nix develop -c kubectl version --client` — expect a client version string and no
server contact. If `pkgs.kubeconform` does not evaluate on this nixpkgs pin, drop it
from the list, make validate.sh's kubeconform step conditional (it already is, below),
and record the fact in Surprises & Discoveries — the mandatory gate is
`kubectl kustomize` plus greps either way.

Then the base. Create `examples/settei-service/deploy/base/deployment.yaml` with
exactly this content (novice implementer: this is the complete file, not an excerpt):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: settei-example-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: settei-example-service
  template:
    metadata:
      labels:
        app: settei-example-service
    spec:
      initContainers:
        # Deploy-time gate: the SAME image validates the SAME inputs the service
        # will see. Exit 3 (unreadable/unparseable file) or 4 (resolution failure)
        # fails the pod, halting the rollout before traffic shifts.
        - name: check-config
          image: example.invalid/settei-example-service:replace-me
          args:
            - --config
            - yaml:/etc/settei/application.yaml
            - --check-config
          env:
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: HASKELL_ENV
              valueFrom:
                configMapKeyRef:
                  name: settei-example-service
                  key: HASKELL_ENV
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: settei-example-service-database
                  key: password
          volumeMounts:
            - name: configuration
              mountPath: /etc/settei
              readOnly: true
      containers:
        - name: service
          image: example.invalid/settei-example-service:replace-me
          args:
            - --config
            - yaml:/etc/settei/application.yaml
          env:
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: HASKELL_ENV
              valueFrom:
                configMapKeyRef:
                  name: settei-example-service
                  key: HASKELL_ENV
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: settei-example-service-database
                  key: password
          volumeMounts:
            - name: configuration
              mountPath: /etc/settei
              readOnly: true
          # For a real long-running service, gate traffic on readiness, e.g.:
          #   readinessProbe:
          #     httpGet:
          #       path: /health
          #       port: 8080
          # The reference binary prints its startup summary and exits (it models
          # startup, not serving), so a live probe is deliberately not set here.
      volumes:
        - name: configuration
          configMap:
            name: settei-example-service
            items:
              - key: HASKELL_ENV
                path: HASKELL_ENV
              - key: application.yaml
                path: application.yaml
```

Design notes the implementer should preserve: the env list and volume mounts of the
init container are byte-identical to the service container's, so the check validates
what the service will actually see (a drifted init container is a false gate); the
`configMapKeyRef` for `HASKELL_ENV` is what keeps the Deployment namespace-agnostic;
`POD_NAMESPACE` is the downward API injection (inert until EP-25 binds it, see
Decision Log); the `items:` list is present so readers see how key-to-file projection
is controlled — mounting both keys is harmless (the service reads only the path it is
given) and shows the mechanism. The image reference stays `example.invalid/...:replace-me`
— a reserved-invalid registry name that can never be pulled accidentally, matching the
old manifests' convention.

Create `examples/settei-service/deploy/base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
```

Then the overlays. Each of `examples/settei-service/deploy/overlays/dev/`,
`.../overlays/test/`, `.../overlays/production/` contains three files. For dev,
`kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: dev
resources:
  - ../../base
  - configmap.yaml
  - secret.yaml
```

`configmap.yaml` for dev:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: settei-example-service
data:
  HASKELL_ENV: development
  application.yaml: |
    http:
      host: 0.0.0.0
    database:
      host: postgres.dev.internal
      port: 5432
```

`secret.yaml` for dev (identical file in every overlay):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: settei-example-service-database
type: Opaque
stringData:
  # PLACEHOLDER ONLY. NEVER commit a real credential, an encoded real
  # credential, or any value that could be mistaken for one. Real values are
  # injected by your secret-management pipeline (external-secrets, sealed
  # secrets, SOPS, vault, ...) — pick one and replace this object.
  password: PLACEHOLDER-REPLACE-VIA-YOUR-SECRET-PIPELINE
```

The test overlay differs from dev only in `namespace: test`, `HASKELL_ENV: test`, and
`host: postgres.test.internal`. The production overlay: `namespace: production`,
`HASKELL_ENV: production`, `host: postgres.production.internal`. Deliberately, no
overlay sets `http.port` or `database.poolSize` — those come from the named default
rules `http-port-by-environment` and `database-pool-size-by-environment` in the
declaration, so the rendered explanation differs per namespace (Test gets port 18080
and pool 1) purely from `HASKELL_ENV`, which is exactly the composition the cookbook
exists to show. Note the environment values are the enum's accepted spellings
(`development`, not `dev`) while the namespaces are `dev`/`test`/`production` — the
mismatch is intentional (Decision Log).

Create `examples/settei-service/deploy/README.md` — a short file (a few sentences)
stating: these manifests are the checked-in companion of
docs/guides/kubernetes-cookbook.md; they are validated by `validate.sh` client-side and
never against a cluster (docs/adr/0007); the Secret values are placeholders and real
credentials must never be committed.

Create `examples/settei-service/deploy/validate.sh` with this content:

```bash
#!/usr/bin/env bash
# Client-side validation of the deploy manifests. No cluster is contacted.
set -euo pipefail
cd "$(dirname "$0")"

fail=0
expect() { # expect <label> <needle> ; reads render from $render
  if grep -qF -- "$2" <<<"$render"; then
    echo "ok:   $1"
  else
    echo "FAIL: $1 (missing: $2)"
    fail=1
  fi
}

for overlay in dev test production; do
  echo "== overlay: ${overlay}"
  render="$(kubectl kustomize "overlays/${overlay}")"
  expect "namespace stamped"        "namespace: ${overlay}"
  expect "downward API namespace"   "fieldPath: metadata.namespace"
  expect "secret-backed password"   "name: settei-example-service-database"
  expect "check-config gate"        "--check-config"
  expect "no real secret committed" "PLACEHOLDER-REPLACE-VIA-YOUR-SECRET-PIPELINE"
  if command -v kubeconform >/dev/null 2>&1; then
    kubeconform -strict -summary <<<"$render" || fail=1
  else
    echo "note: kubeconform not on PATH; schema check skipped"
  fi
done

render="$(kubectl kustomize overlays/dev)"
expect "dev environment value"  "HASKELL_ENV: development"
expect "dev database host"      "postgres.dev.internal"
render="$(kubectl kustomize overlays/test)"
expect "test environment value" "HASKELL_ENV: test"
expect "test database host"     "postgres.test.internal"
render="$(kubectl kustomize overlays/production)"
expect "production environment value" "HASKELL_ENV: production"
expect "production database host"     "postgres.production.internal"

exit "$fail"
```

Make it executable (`chmod +x`). Implementation note: `kubeconform -strict` may need
`-schema-location` arguments for offline default schemas; if it tries to fetch schemas
over the network, either vendor the needed schemas or downgrade the kubeconform step to
opt-in via an environment variable — record whichever in the Decision Log. The grep
gate must never be weakened to accommodate tooling issues.

Finally, delete `examples/settei-service/kubernetes/` (all four files) and update the
referrers in the same commit: in docs/guides/kubernetes-service.md, the closing
paragraph's link `../../examples/settei-service/kubernetes/` becomes
`../../examples/settei-service/deploy/` (the full guide rescope happens in Milestone 3;
this edit only prevents a dangling link); in examples/settei-service/README.md, replace
the sentence about "The Kubernetes manifests are local examples..." to point at
`deploy/` and the cookbook.

Acceptance: `nix develop -c bash examples/settei-service/deploy/validate.sh` prints
`ok:` lines for every expectation and exits 0; `kubectl kustomize
examples/settei-service/deploy/overlays/production` renders three documents (ConfigMap,
Secret, Deployment) all carrying `namespace: production`; `nix develop -c cabal test
all` passes unchanged — no Haskell source, cabal file, or test fixture was touched, and
no cabal component references the `deploy/` directory, so the Haskell build cannot be
affected (flake.module.nix adds only dev-shell tools, not build inputs of the Haskell
derivations).


### Milestone 2 — write the cookbook guide

Scope: the new file docs/guides/kubernetes-cookbook.md, complete. At the end, a novice
reading only that guide understands the namespace pattern end to end and can operate
the checked-in manifests. Tone and format calibration: match docs/guides/
getting-started.md and the other guides — short declarative sections, second person
sparing, every code block language-tagged, links repository-relative.

Before writing, perform the reconciliation step (Decision Log): read
examples/settei-service/src/Settei/Example/Service.hs as it exists *then* (EP-21
rewrites it), confirm flag spellings and exit codes, build the binary and capture real
transcripts. Every transcript below is an illustrative sketch to be replaced by
captured output.

The guide's section structure, in order, with the content each must carry:

1. **One image, many namespaces** — motivation and topology in prose. State the
   pattern: build one image, promote it unchanged dev → test → production; each
   namespace holds same-named ConfigMap/Secret objects with different values; the
   Deployment is namespace-agnostic, so what varies between environments is data, and
   the diff between two overlay directories *is* the complete configuration difference
   between two environments. A diagram-in-prose walks one release: the same image
   digest lands in three namespaces, and only `HASKELL_ENV`, the database host, and
   the Secret differ. State up front that Settei has no Kubernetes-specific mechanism
   here and needs none — this whole guide is composition of ordinary sources — and
   that no code in this guide contacts the Kubernetes API (docs/adr/0007's boundary).
2. **The namespace identity chain** — the downward API, and binding the namespace for
   provenance. Exemplar passage, verbatim (this is the calibrated voice; the
   implementer transplants it into the guide):

   > ### Record the namespace identity
   >
   > The downward API is Kubernetes' mechanism for telling a pod about itself: a
   > `fieldRef` in the pod spec turns a field of the pod's own metadata into an
   > ordinary environment variable. The base Deployment injects the namespace:
   >
   > ```yaml
   > env:
   >   - name: POD_NAMESPACE
   >     valueFrom:
   >       fieldRef:
   >         fieldPath: metadata.namespace
   > ```
   >
   > Bind it explicitly, like every other environment variable the service reads:
   >
   > ```haskell
   > binding (EnvName "POD_NAMESPACE") (validKey "kubernetes.namespace")
   > ```
   >
   > This value does not select behavior. It exists for provenance: with the binding
   > in place, `--explain-config` states which namespace supplied the configuration
   > being explained — the first question in any incident. Selecting behavior belongs
   > to `HASKELL_ENV`, next.

3. **Choose the environment explicitly** — the central recommendation. Each
   namespace's ConfigMap carries `HASKELL_ENV: development|test|production`, delivered
   to the container via `configMapKeyRef`; the value feeds the existing
   `runtime.environment` enum setting; named defaults and the Production-only password
   requirement then differentiate behavior. Give the rationale from the Decision Log
   in guide voice: namespace names are cluster topology — team-prefixed, ephemeral in
   preview environments, renamed in migrations; deriving semantics from them couples
   application behavior to a naming convention; an explicit value survives migrations
   and is reviewable in the overlay diff. Then the documented alternative, honestly:
   **deriving from the namespace name** works when naming is centrally governed —
   show the binding of `POD_NAMESPACE` directly to `runtime.environment` with an
   `enumDecoder` table mapping governed namespace names to environments (or
   `parsedDecoder`/equivalent for prefix conventions like `*-prod`; verify the shipped
   combinator name at implementation time), and list the caveats: every new namespace
   spelling is a code change; preview namespaces break it; the checked-in overlays
   would fail under it (`dev` is not in the enum table) — which is the point.
4. **Per-namespace values** — the two delivery paths and where each belongs.
   Structured public configuration: a ConfigMap key mounted as a YAML file, loaded via
   the service's `--config yaml:/etc/settei/application.yaml`, annotated with
   `fromKubernetesMountedFile` so reports name the ConfigMap. Credentials: a Secret
   key delivered as an env var (`DATABASE_PASSWORD` via `secretKeyRef`), bound with
   the Kubernetes-object annotation so reports name the Secret while the value renders
   `<redacted>`; per-namespace Secrets are same-named objects with different values,
   exactly like ConfigMaps. Then the contingent subsection **Secrets as mounted
   files**: once the settei-kubernetes adapter (EP-22) ships, a Secret projected as a
   volume — one file per key, atomic-writer symlink layout — is read as an ordinary
   Settei source with explicit per-file bindings; write this against the shipped API
   or reduce it to the forward pointer per the Decision Log contingency.
5. **The manifests, walked through** — reference the CHECKED-IN files under
   `examples/settei-service/deploy/` by repository-relative link; quote only focused
   excerpts (the `configMapKeyRef` block, one overlay kustomization, one ConfigMap),
   never full files — the checked-in tree is the source of truth and inline
   duplication is how docs rot. Explain base vs overlay responsibilities, why the
   Deployment never names a namespace, how `kubectl kustomize` renders locally, and
   how `validate.sh` is the mechanical guard. Show applying one overlay
   (`kubectl apply -k examples/settei-service/deploy/overlays/dev`) as the manual
   step, marked as outside anything CI does.
6. **Gate rollouts with `--check-config`** — second exemplar passage, verbatim:

   > ### Fail bad configuration before traffic
   >
   > An init container runs to completion before the main containers start. Run the
   > same image, with the same mounts and environment, in check mode:
   >
   > ```yaml
   > initContainers:
   >   - name: check-config
   >     image: example.invalid/settei-example-service:replace-me
   >     args:
   >       - --config
   >       - yaml:/etc/settei/application.yaml
   >       - --check-config
   > ```
   >
   > If this namespace's ConfigMap is missing a required key, carries a value the
   > declaration rejects, or the Secret is absent in Production, the init container
   > exits with code 4 (resolution failure) or 3 (source failure). The pod fails, the
   > rollout stops, and the previous replicas keep serving. A configuration mistake
   > in one namespace becomes a failed rollout in that namespace — not an outage.
   > Keep the init container's `env` and `volumeMounts` identical to the service
   > container's; a gate that checks different inputs is a false gate.

   Follow with: the exit-code table (0/2/3/4) in prose; a note that a readinessProbe
   guards the *serving* process while the init container guards *startup
   configuration*, and both belong in a real service (the reference base shows the
   probe as a commented template because the example binary exits after its startup
   summary); and why `--check-config` also belongs in CI against each overlay — the
   same binary can validate every namespace's rendered configuration before anything
   is applied, catching a bad overlay at review time instead of rollout time (render
   the overlay, extract the ConfigMap data to a file and the env values to variables,
   run the binary with `--check-config`; sketch the shell recipe).
7. **The incident runbook** — third exemplar, the worked transcript (illustrative;
   replace with captured output at implementation time):

   > When a pod misbehaves, ask it to explain itself:
   >
   > ```console
   > $ kubectl -n production exec deploy/settei-example-service -- \
   >     settei-example-service --config yaml:/etc/settei/application.yaml --explain-config
   > runtime.environment = "production"
   >   from environment variable HASKELL_ENV
   > http.port = 8080
   >   by rule http-port-by-environment
   > database.host = "postgres.production.internal"
   >   from mounted application configuration (ConfigMap settei-example-service, key application.yaml)
   > database.poolSize = 20
   >   by rule database-pool-size-by-environment
   > database.password = <redacted>
   >   from environment variable DATABASE_PASSWORD (Secret settei-example-service-database, key password)
   > ```
   >
   > Winners, shadowed candidates, and fired default rules are all named; secret
   > values are always `<redacted>`. Use `--explain-config-json` for tooling.

   Add the failure case: when resolution fails (for example Production without a
   password), the process exits 4 and — with an explain flag — prints the errors
   followed by the full provenance report, so a crash-looping pod's logs already
   contain the explanation; show a second short transcript
   (`kubectl -n production logs` of a failing check-config init container, then the
   explain variant). This behavior is EP-12's deliverable; verify against the shipped
   tree.
8. **Rotation and reload** — state the true mechanics: a ConfigMap or Secret update
   atomically swaps the mount's `..data` symlink (after kubelet sync delay), so
   mounted files do change on disk; but the service resolves configuration once at
   startup, so the running process's typed values do not change — the documented
   posture is restart-to-reload: `kubectl rollout restart deployment/settei-example-service`.
   State the stricter env-var fact plainly: values delivered as environment variables
   (`HASKELL_ENV`, `DATABASE_PASSWORD` here) NEVER update in a running pod; pod
   recreation is the only path. Frame the posture as a feature for this pattern:
   configuration changes become rollouts, which means they pass the `--check-config`
   gate and are observable events, not silent drift.
9. **Reject unknown keys** — recommend services set `RejectUnknownKeys` (the
   `ResolveOptions` unknown-key policy) instead of the default warn policy: the
   namespace pattern multiplies copies of the same keys across overlays, and a typo in
   one namespace's ConfigMap (`database.poolsize`) is exactly the failure mode that
   otherwise degrades into a silently-ignored key and a default winning in one
   environment only. With rejection, the typo fails the `--check-config` gate in that
   namespace's rollout. Reconcile wording with what EP-21 already added to the
   service guide so the two do not drift.
10. **FAQ** — three entries minimum. *Deriving the environment from the namespace
    name?* — summary of section 3's alternative and caveats, with the pointer back.
    *Preview namespaces?* — ephemeral namespaces (one per pull request) work
    naturally under the explicit switch: the preview overlay sets `HASKELL_ENV: test`
    (or `development`) regardless of its generated namespace name; under
    name-derivation they would all fail. *Multi-container pods?* — each container
    gets its own env list; sidecars that need configuration bind their own variables;
    the ConfigMap volume can be mounted by several containers; the `--check-config`
    init container gates the whole pod regardless of container count.

Cross-cutting rules for the whole guide: never show a real or realistic secret value
anywhere, including transcripts — the rendered form is always `<redacted>` and manifest
values are always the loud placeholder; all manifest excerpts must be copied from the
checked-in files, not retyped; all transcripts captured from the real binary.

Acceptance: the guide exists with all ten sections; every fenced block has a language
tag; `grep -n "PLACEHOLDER-REPLACE" docs/guides/kubernetes-cookbook.md` finds the
placeholder only where a manifest excerpt legitimately shows it; a full read-through by
the implementer confirms no step requires knowledge outside the guide plus the
checked-in files.


### Milestone 3 — rescope the service guide and update the indexes

Scope: docs/guides/kubernetes-service.md, docs/guides/README.md, README.md. At the end,
the service guide covers application code only, the cookbook owns deployment, and every
index lists both.

Rescope docs/guides/kubernetes-service.md: keep (and leave to EP-21's rewrite where it
already touched them) the sections on modeling process-visible inputs, declaring typed
configuration, environment-dependent defaults and requirements, binding
Kubernetes-delivered environment variables, loading an annotated mounted file,
resolving once at startup, exposing safe diagnostics, and local testing. Remove the
"Create the ConfigMap and Deployment" section entirely — its content is superseded by
the checked-in manifests and the cookbook's walkthrough — replacing it with a short
paragraph linking to docs/guides/kubernetes-cookbook.md and
examples/settei-service/deploy/. Trim the operational checklist to application-code
items (secret marking, explicit bindings, resolve-before-listen, redaction testing),
moving deployment items (read-only mounts, Secret delivery, rollout-restart posture,
check-config gating) into the cookbook if not already covered. Add a scope sentence at
the top: this guide is the application-code half; the deployment half is the cookbook.
Update the closing pointer to name `deploy/` (already done minimally in Milestone 1)
and the cookbook.

Update docs/guides/README.md: add a table row for the cookbook — guide
"Deploying across Kubernetes namespaces" linking kubernetes-cookbook.md, "Use it when"
text along the lines of "You are promoting one image through dev/test/production
namespaces with per-namespace ConfigMaps and Secrets." — and narrow the
kubernetes-service.md row's description to the application-code scope. Update the
top-level README.md guide list (lines ~124–131) with a matching cookbook entry after
the Kubernetes-shaped service line.

Acceptance: `grep -rn "settei-service/kubernetes" docs README.md examples` returns
nothing; docs/guides/README.md and README.md both list the cookbook; the service guide
contains no Deployment/ConfigMap manifest YAML.


### Milestone 4 — validation pass and closure

Scope: no new artifacts; prove the work and close the bookkeeping. Run the full
validation battery (Concrete Steps step 5), paste real transcripts into Validation and
Acceptance, and perform the novice read-through. Optionally — explicitly outside CI and
outside required acceptance, per docs/adr/0007 — follow the cookbook on a local kind or
minikube cluster: build/load an image for the service, `kubectl apply -k` the dev
overlay, observe the init container pass, read the startup-summary logs, then break the
dev ConfigMap deliberately and observe the rollout halt with exit code 4 in the
check-config container; record the outcome in this plan either way (done, or skipped
and why). Then update the MasterPlan: in docs/masterplans/4-…md set the EP-24 registry
row to Complete and check the two EP-24 Progress items ("namespace cookbook written…",
"runnable base+overlay manifests…"). Fill this plan's Outcomes & Retrospective. Confirm
the no-ADR decision: this plan promotes nothing to docs/adr/ itself; the
restart-to-reload posture and the reaffirmed no-cluster-client boundary are flagged
here for EP-25's distillation pass (leave a one-line reminder in the Outcomes entry so
EP-25's implementer finds it).


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/settei`.
Every commit uses Conventional Commits (`feat:`, `docs:`, `chore:`, optional scope) and
carries these three trailers, exactly:

```text
MasterPlan: docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md
ExecPlan: docs/plans/24-write-the-namespace-driven-configuration-cookbook-and-deployment-manifests.md
Intention: intention_01kxxfcw4ke5fbb2kas9ghvv9a
```

Commit directly to the current branch. Update this plan's Progress section in the same
commit as the work it describes.

Step 1 (tooling). Create flake.module.nix as specified in Milestone 1, then:

```bash
git add flake.module.nix
nix develop -c kubectl version --client
```

Expected output shape:

```text
Client Version: v1.3x.y
Kustomize Version: v5.x.y
```

Commit: `chore(nix): add kubectl and kubeconform to the dev shell for manifest validation`.

Step 2 (manifests). Create the nine files under examples/settei-service/deploy/ and
delete examples/settei-service/kubernetes/, updating the two referrers. Then:

```bash
chmod +x examples/settei-service/deploy/validate.sh
nix develop -c kubectl kustomize examples/settei-service/deploy/overlays/production
nix develop -c bash examples/settei-service/deploy/validate.sh
nix develop -c cabal test all --test-show-details=direct
```

Expected: the render prints three YAML documents separated by `---`, each with
`namespace: production`; validate.sh ends with only `ok:` lines and exit 0; the cabal
suite result is identical to before this plan (docs and manifests are invisible to it).
Commit: `feat(examples/service): add base+overlay Kubernetes manifests with a check-config gate`.

Step 3 (cookbook). Reconcile API names against the current tree, capture real
transcripts:

```bash
nix develop -c cabal build settei-example-service
HASKELL_ENV=development nix develop -c cabal run settei-example-service -- \
  --config yaml:examples/settei-service/test/fixtures/application.yaml --check-config
HASKELL_ENV=development nix develop -c cabal run settei-example-service -- \
  --config yaml:examples/settei-service/test/fixtures/application.yaml --explain-config
HASKELL_ENV=production nix develop -c cabal run settei-example-service -- \
  --config yaml:examples/settei-service/test/fixtures/application.yaml --explain-config; echo "exit=$?"
```

Expected: `configuration valid`; a redacted text report; and (post-EP-12) errors
followed by a provenance report with `exit=4` for the production run without a
password — confirm no secret-like string appears anywhere. Write
docs/guides/kubernetes-cookbook.md per Milestone 2, pasting captured output over the
plan's sketches. Commit: `docs(guides): add the namespace-driven Kubernetes configuration cookbook`.

Step 4 (rescope and indexes). Edit docs/guides/kubernetes-service.md,
docs/guides/README.md, README.md per Milestone 3. Verify:

```bash
grep -rn "settei-service/kubernetes" docs README.md examples
```

Expected: no output. Commit: `docs(guides): rescope the Kubernetes service guide to application code`.

Step 5 (final validation and closure). Re-run from clean:

```bash
nix develop -c bash examples/settei-service/deploy/validate.sh
nix develop -c cabal clean && nix develop -c cabal test all --test-show-details=direct
```

Paste transcripts into Validation and Acceptance. Perform the novice read-through and
the optional kind walkthrough (record either way). Update the MasterPlan registry and
Progress, fill this plan's living sections. Commit:
`docs(plans): close EP-24 with validation transcripts and MasterPlan bookkeeping`.


## Validation and Acceptance

Acceptance is behavioral, verified from the repository root.

Implementation evidence captured on 2026-07-20 from a clean worktree:

```text
== overlay: dev
ok:   namespace stamped
ok:   downward API namespace
ok:   secret-backed password
ok:   check-config gate
ok:   no real secret committed
...
ok:   production environment value
ok:   production database host
```

The opt-in schema run ended once per overlay with:

```text
Summary: 3 resources found parsing stdin - Valid: 3, Invalid: 0, Errors: 0, Skipped: 0
```

After `nix develop -c cabal clean`, the full suite reported every component `PASS`: 105
core, 7 Dhall prototype, 45 YAML, 34 KDL, 9 optparse, 20 environment, 26 Dhall, 32
Kubernetes, 15 formats, 8 service, 10 CLI, and 11 conformance tests (322 total). The Nix
closure gate then reported:

```text
✅ checks.aarch64-darwin.pre-commit
✅ checks.aarch64-darwin.treefmt
```

1. Manifest rendering: `nix develop -c kubectl kustomize
   examples/settei-service/deploy/overlays/production` succeeds with no cluster access
   and its output contains, among the three documents, an excerpt shaped like:

   ```yaml
   apiVersion: v1
   data:
     HASKELL_ENV: production
     application.yaml: |
       http:
         host: 0.0.0.0
       database:
         host: postgres.production.internal
         port: 5432
   kind: ConfigMap
   metadata:
     name: settei-example-service
     namespace: production
   ```

   plus a Secret named `settei-example-service-database` containing only the
   placeholder value, and a Deployment whose init container args include
   `--check-config` and whose env includes `fieldPath: metadata.namespace`.
2. The value grep gate: `nix develop -c bash
   examples/settei-service/deploy/validate.sh` prints `ok:` for every expectation
   across all three overlays (namespace stamp, downward API, secret reference,
   check-config gate, placeholder present, per-namespace `HASKELL_ENV` and database
   host) and exits 0. Any `FAIL:` line is a failure.
3. Haskell suite unaffected: `nix develop -c cabal test all --test-show-details=direct`
   passes with results identical to before this plan. Why this must hold: this plan
   adds no Haskell source, edits no `.cabal` file and no test fixture, and no cabal
   component references `deploy/` or the guides; flake.module.nix only extends the dev
   shell's tool list, not the Haskell package derivations. Any test delta means an
   accidental edit — investigate, do not accept.
4. Documentation integrity: docs/guides/kubernetes-cookbook.md exists with the ten
   sections of Milestone 2; all fenced blocks carry language tags; all transcripts are
   captured, not invented; no secret-like value appears anywhere in the guide or
   manifests (`grep -rni "password" examples/settei-service/deploy docs/guides/kubernetes-cookbook.md`
   shows only key names, the placeholder, `<redacted>`, and prose);
   `grep -rn "settei-service/kubernetes" docs README.md examples` is empty; both guide
   indexes list the cookbook.
5. Novice read-through: an implementer-performed full read of the cookbook confirms
   every referenced file exists at the stated path and every command is runnable as
   written.
6. Optional manual acceptance — explicitly OUTSIDE CI and not required for completion,
   per docs/adr/0007 (examples never contact a cluster; a live integration test was
   rejected): following only the cookbook on a kind or minikube cluster, the dev
   overlay applies, the check-config init container succeeds, the service container
   logs its safe startup summary (and then exits — expected for the reference binary),
   and a deliberately broken ConfigMap halts the next rollout with exit code 4 visible
   in the init container's status. Record the outcome (or the decision to skip) in
   this plan.


## Idempotence and Recovery

Every step is an ordinary file creation or edit on a git working tree plus read-only
validation commands; all are safe to repeat. `kubectl kustomize` and validate.sh are
pure functions of the checked-in files — no cluster, no network (kubeconform's schema
fetching is the one exception; Milestone 1 says how to neutralize it). Re-running any
step after a partial failure is a no-op or a clean overwrite.

Recovery points are the five commits; `git log` plus this plan's Progress section
identify the last good state, and `git checkout -- <path>` or `git reset --hard
<commit>` return to it. The only deletion is `examples/settei-service/kubernetes/`,
performed in the same commit as its replacement and referrer updates, so a revert of
that single commit restores the old state whole — never delete the old directory in a
commit that does not also add `deploy/`. If Milestone 2 must pause mid-guide, commit
the partial guide only if every section it *does* contain is finished and true;
otherwise keep it uncommitted and record the split in Progress. The optional kind
walkthrough touches only a local disposable cluster and never this repository; nothing
in this plan can damage a real environment — the manifests point at an unpullable
`example.invalid` image and placeholder secrets by construction.


## Interfaces and Dependencies

No Haskell interfaces are created or changed; this plan's contract is files and
behavior. What must exist at the end:

- `flake.module.nix` (tracked) setting `haskellProject.extraDevPackages` to include
  `pkgs.kubectl` and (if it evaluates) `pkgs.kubeconform` — the option is declared in
  nix/haskell.nix; flake.nix auto-imports the module when present.
- `examples/settei-service/deploy/` containing exactly: `README.md`, `validate.sh`
  (executable), `base/deployment.yaml`, `base/kustomization.yaml`, and for each of
  `overlays/dev`, `overlays/test`, `overlays/production`: `kustomization.yaml`,
  `configmap.yaml`, `secret.yaml` — with the invariants: Deployment
  namespace-agnostic; init container env/mounts identical to the service container's;
  object names `settei-example-service` (ConfigMap) and
  `settei-example-service-database` (Secret) matching the annotations in
  examples/settei-service/src/Settei/Example/Service.hs; `HASKELL_ENV` values are the
  enum spellings `development`/`test`/`production`; Secret values are the loud
  placeholder only.
- `docs/guides/kubernetes-cookbook.md` with the Milestone 2 structure;
  docs/guides/kubernetes-service.md rescoped; docs/guides/README.md and README.md
  indexes updated; `examples/settei-service/kubernetes/` gone.

Tool dependencies: `kubectl` ≥ 1.27 for the bundled `kubectl kustomize` (any modern
version renders these manifests; no cluster and no kubeconfig required for rendering),
`kubeconform` optional, `bash` and `grep` from the shell. Application dependencies
consumed but not modified: the settei-example-service binary and its flags
(`--config FORMAT:PATH`, `--check-config`, `--explain-config`, `--explain-config-json`),
exit codes 0/2/3/4, the `enumDecoder` environment spellings, and the two named default
rules — all verified against the tree at implementation time per the reconciliation
rule. Downstream consumer: EP-25 (docs/plans/25-…md) wires the reference service to
any new adapter paths, adds the `POD_NAMESPACE` binding to `environmentBindings`,
validates the cookbook's manifests against the final service, and performs the ADR
distillation that promotes this plan's restart-to-reload and no-cluster-client
positions; nothing in this plan may pre-empt those code changes.
