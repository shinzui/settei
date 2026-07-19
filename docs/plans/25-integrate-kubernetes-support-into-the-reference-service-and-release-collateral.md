---
id: 25
slug: integrate-kubernetes-support-into-the-reference-service-and-release-collateral
title: "Integrate Kubernetes support into the reference service and release collateral"
kind: exec-plan
created_at: 2026-07-19T15:20:08Z
intention: "intention_01kxxfcw4ke5fbb2kas9ghvv9a"
master_plan: "docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md"
---

# Integrate Kubernetes support into the reference service and release collateral

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Settei is a Haskell configuration library whose examples — not its unit tests — are the
proof that its public API works. That rule is written down in
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md: every
maintained package must be exercised in an application composition before release, and an
unexercised public API is an unproven API. The Kubernetes initiative
(docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md)
delivers three things before this plan starts: a new `settei-kubernetes` package that
reads a mounted ConfigMap/Secret volume directory as an ordinary Settei source (EP-22,
docs/plans/22-create-the-settei-kubernetes-mounted-directory-source-adapter.md), derived
environment bindings and freshness/identity annotations (EP-23,
docs/plans/23-derive-environment-bindings-and-freshness-provenance-from-kubernetes-references.md),
and the namespace cookbook with runnable deployment manifests under
examples/settei-service/deploy/ (EP-24,
docs/plans/24-write-the-namespace-driven-configuration-cookbook-and-deployment-manifests.md).
None of those plans, by design, makes the reference service actually *use* the new
adapter end to end. Until that happens, `settei-kubernetes` is the only maintained
package outside the conformance boundary, and the initiative's release collateral
(compatibility matrix, README package map, security model, release checklist,
changelogs) still describes a six-package family.

After this plan is complete, four things are true that are not true today. First, the
Kubernetes-shaped reference service in examples/settei-service accepts a
`--secrets-dir PATH` option, reads that directory through the public
`Settei.Kubernetes` mounted-directory source with explicit file bindings (at minimum the
database password file), places it at a documented position in the precedence stack, and
its `--explain-config` output shows the mounted-directory origin with the Kubernetes
object identity, the mount path, and the EP-23 freshness annotations — with the secret
value redacted. Anyone can see this by running the service against a temporary directory
containing a `password` file and reading the report. Second, the conformance and service
test suites lock the new surface: cross-source precedence laws include the mounted
directory, the secret-sentinel scan covers a secret delivered through a mounted file,
exit-code behavior for a missing or invalid mounted directory is asserted, and every
command-line flag referenced by the deploy/ manifests is proven to exist in the actual
service parser. Third, the release collateral tells the truth about the enlarged package
family: `settei-kubernetes` appears in docs/compatibility.md, README.md's package map
and release-status wording, docs/security.md's trust model, docs/release-checklist.md's
gates, and a consolidated changelog. Fourth, the parent MasterPlan is closed: registry
rows Complete, Outcomes & Retrospective written, and the ADR distillation pass performed
— including promoting the restart-to-reload posture and the reaffirmed no-cluster-client
boundary that the MasterPlan's Decision Log flags for promotion.

This is a final-pass plan in the same shape as
docs/plans/14-revalidate-correctness-and-update-release-collateral.md (correctness
initiative) and
docs/plans/21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md
(ergonomics initiative): integrate, validate everything, reconcile collateral, close the
MasterPlan. Nothing here is accepted on the author's word; every claim is re-verifiable
by the commands in Validation and Acceptance.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented
here, even if it requires splitting a partially completed task into two ("done" vs.
"remaining"). This section must always reflect the actual current state of the work.

Preflight (reconciliation — mandatory before Milestone 1):

- [ ] Confirm EP-22, EP-23, and EP-24 are marked Complete in the MasterPlan registry and
      their own Progress sections agree; abort and report if not.
- [ ] Read the landed `settei-kubernetes` source and record the real spellings in this
      plan's Context section: the mounted-directory reader (provisionally
      `readMountedDirectorySource`), the per-file bindings type (provisionally
      `FileBindings`), the source-options/annotation entry points, the error type and
      its renderer, and the EP-23 derived-bindings constructor (provisionally
      `bindingsFromKubernetesObject`) plus the exact freshness annotation names
      (provisionally `kubernetes.mount-path`, `kubernetes.file-modified`).
- [ ] Read the post-EP-21 examples/settei-service sources and record the actual CLI
      surface (shared `DiagnosticMode`, settei-formats tagged input, validated
      `Bindings`, warning rendering) so the new option composes with the shipped
      ergonomics shape rather than the pre-ergonomics shape described as fallback here.
- [ ] Read EP-24's landed deploy/ tree (base plus overlays) and cookbook; record the
      manifest spelling for the secrets mount (mount path, file names, container args)
      and reconcile this plan's `--secrets-dir` spelling and default mount path with it;
      note whether the old examples/settei-service/kubernetes/ directory was replaced.
- [ ] Reconcile with sibling MasterPlans' closures: confirm EP-14 and EP-21 left the
      release collateral in the state this plan's Milestone 3 edits assume (current test
      count in README, publishable-package count, compatibility matrix structure);
      record the current totals here.
- [ ] Commit the preflight recording.

Milestone 1 — reference service integration:

- [ ] Add the `--secrets-dir PATH` option to the service parser (Configuration group)
      and thread it through `ServiceOptions`.
- [ ] Load the mounted directory via the `Settei.Kubernetes` reader with explicit file
      bindings (`password` file -> `database.password`), keeping the env-var delivery
      binding so both modes are demonstrated.
- [ ] Place the mounted-directory source between the mounted config file and the
      environment source in `resolveServiceSources`; document the order in the module.
- [ ] Replace the hand-assembled `fromKubernetesObject` env-binding entry with the
      EP-23 derived-bindings construction.
- [ ] Update examples/settei-service/test/Settei/Example/ServiceTest.hs: temp-dir
      mounted-secret fixture resolves to the typed config; report shows the
      mounted-directory origin with object identity, mount path, and freshness
      annotations; secret redacted; missing/invalid directory exits with source exit
      code 3.
- [ ] Update the service cabal file (add `settei-kubernetes` dependency; extend
      data-files if a checked-in fixture directory is added).
- [ ] `nix develop -c cabal test settei-example-service --test-show-details=direct`
      green; commit.

Milestone 2 — conformance and smoke coverage:

- [ ] Conformance: mounted-directory source participates in cross-source precedence
      laws (env shadows mounted value; CLI shadows env where the CLI example applies;
      shadow trace retained).
- [ ] Conformance: secret-sentinel scan covers a sentinel delivered via a mounted file
      (never appears in any rendered output).
- [ ] Service tests: `--check-config` and `--explain-config` transcripts including
      `--secrets-dir` (expected transcripts recorded in this plan, replaced with real
      output when run).
- [ ] Service tests: manifest-flag validation — every long option named in the deploy/
      manifests' container args parses against `serviceParserInfo`.
- [ ] `nix develop -c cabal test all --test-show-details=direct` green; commit.

Milestone 3 — release collateral:

- [ ] docs/compatibility.md: settei-kubernetes toolchain/bounds/input-contract/public-
      module rows added in the file's existing structure.
- [ ] README.md: package map row with a one-line role; release-status wording updated
      (package count, test count, initiative summary sentence).
- [ ] docs/security.md: mounted-file trust model (kubelet-managed filesystem trusted;
      asserted KubernetesRef is caller-trusted, unverified metadata) plus the EP-23
      freshness-annotation clock caveat.
- [ ] docs/release-checklist.md: manifest render check and mounted-fixture smoke added
      to Automated validation.
- [ ] Changelogs: settei-kubernetes/CHANGELOG.md consolidated 0.1.0.0 entry;
      settei-env/CHANGELOG.md line if EP-23 touched it; no changelogs invented for
      examples (they have none).
- [ ] Registration verification: mori.dhall row for settei-kubernetes, nix/haskell.nix
      derivation, cabal.project entry all present (EP-22 wired them; re-verify).
- [ ] Commit.

Milestone 4 — full validation and MasterPlan closure:

- [ ] `nix develop -c cabal build all` green.
- [ ] `nix develop -c cabal test all --test-show-details=direct` green; new total test
      count recorded here and in README.
- [ ] `nix flake check` green (new files `git add`-ed first).
- [ ] sdist round-trip for settei-kubernetes via the isolated-unpack procedure.
- [ ] kustomize render checks from EP-24 re-run against the final service flags.
- [ ] MasterPlan: registry rows Complete, Progress boxes checked, Outcomes &
      Retrospective written.
- [ ] ADR distillation: settei-kubernetes semantics ADR (from EP-22/EP-23) verified
      coherent; restart-to-reload posture and no-cluster-client boundary promoted;
      dated note appended to docs/adr/0007 pointing at the adapter ADR.
- [ ] This plan's Outcomes & Retrospective written; final commit.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: The mounted secrets directory gets its own dedicated option, spelled
  `--secrets-dir PATH`, rather than a new `mounted:` tag inside the existing
  `FORMAT:PATH` tagged-input reader.
  Rationale: The `FORMAT:PATH` spelling dispatches *document parsers* (yaml/kdl/dhall
  over one file); a projected ConfigMap/Secret volume is not a document format — it is a
  directory where each object key is one file, read through explicit per-file bindings.
  Overloading the format tag would misrepresent the adapter's semantics and complicate
  the settei-formats loader EP-21 standardized on. A separate flag also mirrors how the
  EP-24 manifests deliver it (a distinct `volumeMount` for the Secret, distinct from the
  ConfigMap document mount). Preflight reconciles the exact spelling against EP-24's
  landed manifests and cookbook; if they shipped a different spelling, the manifests win
  and this plan is revised with a note.
  Date: 2026-07-19

- Decision: The mounted secrets directory sits *above* the mounted configuration file
  and *below* the environment source: ordered lowest to highest, config file <
  mounted secrets directory < environment (and, in the CLI example's cross-source law
  tests, environment < command line, unchanged). Both password delivery modes are kept:
  the env-var binding for `DATABASE_PASSWORD` remains, and the mounted `password` file
  is added, so the service demonstrates file delivery and env delivery of the same
  secret with an honest shadow trace when both are present.
  Rationale: The mounted directory is a file-class source, so it belongs in the file
  band; within that band it is narrower and more specifically provisioned than the
  general application document, so it wins over the config file. The environment stays
  highest among non-CLI sources because that is the family-wide documented order (README
  "Assemble ordered sources": files < env < CLI) and because an operator's last-resort
  incident override in Kubernetes is an env edit (or downward-API value) on the pod
  spec, which must beat anything baked into a volume. Keeping both delivery modes is
  required by the MasterPlan's conformance goal: precedence between them must be
  observable, not hypothetical.
  Date: 2026-07-19

- Decision: Cross-source precedence-law tests and the mounted-file sentinel scan live in
  examples/settei-conformance/test/Settei/Example/ConformanceTest.hs; the
  service-specific behaviors (option parsing, origin/annotation assertions, exit codes,
  manifest-flag validation, transcripts) live in
  examples/settei-service/test/Settei/Example/ServiceTest.hs.
  Rationale: This follows the suites' existing division of labor: the conformance
  package owns format-independent laws across public adapter modules (its existing
  "source ordering", CLI-shadows-env, and "Security" sentinel groups), while the service
  suite owns the service's own contract (its existing origin, redaction, and exit-code
  cases). Putting a mounted-directory precedence law in conformance also exercises
  `Settei.Kubernetes` from a second, independent consumer, which is exactly what ADR
  0007 wants.
  Date: 2026-07-19

- Decision: Manifest-flag validation is an automated Haskell test in the service suite,
  not a grep script and not a manual check: extract every `--`-prefixed token from the
  `args:` blocks of each YAML file under examples/settei-service/deploy/ by plain text
  scanning, and assert each token is accepted by `serviceParserInfo` (via
  `Options.execParserPure` over a synthesized minimal argument list, or by checking the
  token against the parser's rendered `--help`). Additionally keep EP-24's kustomize
  render check as a release-checklist item, with a documented fallback to a manual
  render if the `kustomize` binary is absent from the dev shell.
  Rationale: The manifests reference command-line options as strings; nothing else
  fails when the service renames a flag. A test in the service suite recompiles and
  re-runs on every flag change, which a checklist bullet cannot do. Text-scanning the
  `args:` block avoids adding a YAML dependency to the test suite for what is a token
  extraction; the extraction only needs to over-approximate (collect all `--tokens`),
  because a false extra token would fail loudly at parse-assert time and be corrected.
  The kustomize render is environment-dependent (external binary), so it stays a
  checklist gate rather than a cabal test.
  Date: 2026-07-19

- Decision: ADR distillation recommendation — do not write a second Kubernetes ADR from
  this plan. Verify the adapter-semantics ADR that EP-22/EP-23 created (number assigned
  at their implementation time, expected 0008 or later after the ergonomics ADRs),
  promote into *that* ADR the restart-to-reload posture and the reaffirmed
  no-cluster-client boundary if EP-22..24 have not already recorded them there, and
  append a short dated amendment note to
  docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md
  pointing at the adapter ADR and stating that the mounted-directory source is now part
  of the exercised conformance boundary while cluster access remains out of scope.
  Rationale: ADR 0007 already owns the "no cluster client, examples never contact a
  cluster" boundary; the adapter ADR owns mounted-file semantics. Splitting the
  restart-to-reload posture into a third document would scatter one decision across
  three files. A dated pointer note keeps 0007 the discoverable entry point without
  rewriting an accepted ADR.
  Date: 2026-07-19

- Decision: This plan is written while EP-22, EP-23, and EP-24 (and the ergonomics
  EP-15..EP-21 it also builds on) are unfilled skeletons; every identifier this plan
  uses for their deliverables — `readMountedDirectorySource`, `FileBindings`,
  `bindingsFromKubernetesObject`, `kubernetes.mount-path`, `kubernetes.file-modified`,
  the shared `DiagnosticMode`, the settei-formats input types, the validated `Bindings`
  — is provisional, taken from the MasterPlan's Integration Points and this plan's
  recommendations. The mandatory preflight in Progress reconciles all of them against
  landed code before any Milestone 1 edit, updating this plan with a revision note.
  Rationale: Same reasoning EP-14 and EP-21 recorded: freezing guessed spellings as
  requirements would make the plan wrong; freezing the reconciliation procedure makes
  it robust and restartable. The concepts are fixed by the MasterPlan even where the
  spellings are not.
  Date: 2026-07-19

- Decision: Failures found during Milestone 4 validation are triaged the same way EP-14
  triaged them: collateral drift (stale doc claim, missing sdist file, stale fixture) is
  fixed forward here; a behavior defect in settei-kubernetes, the derived bindings, or
  the manifests reopens the responsible child plan (registry row back to In Progress,
  defect recorded in both plans, this plan pauses at a clean commit).
  Rationale: EP-25 is the initiative's release gate, not a fourth feature plan; letting
  it silently patch adapter behavior would erase the per-plan history the MasterPlan
  decomposition exists for.
  Date: 2026-07-19

- Decision: The settei-kubernetes changelog for this release is one consolidated
  `0.1.0.0` entry covering EP-22's source adapter, EP-23's derived bindings and
  freshness annotations, and any adjustment this plan makes — not per-plan entries.
  Rationale: The package has never been published (the whole family's 0.1.0.0 is still
  untagged and not uploaded, per README "Release status" and the unchecked "Manual
  publication" section of docs/release-checklist.md); its first public entry should
  present one coherent story, matching the convention EP-14 recorded for the family.
  settei-env gains a line only if EP-23 actually changed it — verify at preflight; do
  not invent one. The examples/ packages have no CHANGELOG.md files (verified
  2026-07-19) and remain unpublished, so none is created.
  Date: 2026-07-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

### What Settei is and how this repository is laid out

Settei is a Haskell configuration library. An application writes one typed declaration
of its settings (a `Config a` value), passes an ordered list of *sources* — files,
environment variables, command-line flags, each a bundle of raw values with provenance
metadata — and calls `resolve` to get back a typed value plus a *resolution report* that
explains where every value came from, with values of `Secret` settings redacted. The
repository is a Cabal multi-package workspace pinned by a Nix flake; every build and
test command in this plan runs from the repository root
`/Users/shinzui/Keikaku/bokuno/settei` through the dev shell (`nix develop -c ...`),
because the host GHC cannot build this workspace (docs/compatibility.md).

Publishable packages live in top-level sibling directories (per
docs/adr/0001-haskell-project-conventions.md): `settei` (core), `settei-env`,
`settei-optparse-applicative`, `settei-yaml`, `settei-kdl`, `settei-dhall`, plus — after
the ergonomics initiative — `settei-formats` (tagged multi-format loading, EP-16) and —
after EP-22 — `settei-kubernetes` (the mounted-directory adapter this plan integrates).
Three internal, unpublished packages live under `examples/`: `examples/settei-cli` (a
layered CLI), `examples/settei-service` (the Kubernetes-shaped service this plan
extends; executable `settei-example-service`), and `examples/settei-conformance` (a
test-only package asserting cross-format laws). Every package repeats the canonical
`common common` cabal stanza (GHC2024; DeriveAnyClass, DuplicateRecordFields,
OverloadedLabels, OverloadedStrings), uses strict fields, explicit deriving strategies,
lens/generic-lens label access via `Settei.Prelude`, and postpositive `qualified`
imports — all governed by docs/adr/0001.

### What the settei-kubernetes surface is (from the MasterPlan; reconcile at preflight)

A "projected ConfigMap or Secret volume" is the standard Kubernetes mount shape: the
kubelet materializes each key of a ConfigMap or Secret object as one file in a mounted
directory, using an atomic-writer symlink layout (the visible file names are symlinks
through a `..data` indirection so updates swap atomically). EP-22's adapter reads such a
directory as an ordinary Settei `Source`: the caller supplies explicit per-file key
bindings (mirroring settei-env's explicit-bindings philosophy — no name guessing,
because object keys legally contain dots that collide with Settei's dotted key syntax),
the adapter handles the symlink layout, and its errors are secret-safe. EP-23 adds
derived environment bindings — one construction that produces both the env binding and
its Kubernetes provenance annotation so they cannot drift apart — and freshness/identity
annotations carried in the existing ordered annotation vocabulary: provisionally
`kubernetes.mount-path` and `kubernetes.file-modified` alongside the existing
`kubernetes.object-kind`, `kubernetes.object-name`, `kubernetes.namespace`, and
`kubernetes.object-key` names rendered by the kubernetes suffix in
settei/src/Settei/Render.hs (docs/adr/0003). The provisional reader spelling this plan
uses is `readMountedDirectorySource` with a `FileBindings` argument; the provisional
derived-bindings spelling is `bindingsFromKubernetesObject`. The preflight replaces all
of these with the landed spellings and records the adapter's error type, renderer name
(EP-17 contract: `render<Adapter>ErrorText` style), and options record here.

### The reference service as it stands (fallback description; reconcile at preflight)

This plan was authored against the pre-ergonomics tree; EP-21 rewrites the service
before this plan starts. Both states are described so the implementer can navigate
either. In the authored tree, examples/settei-service/src/Settei/Example/Service.hs
declares `ServiceConfig` (environment, http, database records; `database.password` is a
`Secret` setting decoded into a Show-less `SecretText`, required only when
`runtime.environment` resolves to `production`), parses `ServiceOptions` (an optional
`--config FORMAT:PATH` tagged input and a diagnostic mode with `--check-config`,
`--explain-config`, `--explain-config-json`), builds `environmentBindings` including a
`fromKubernetesObject (kubernetesRef SecretObject Nothing
"settei-example-service-database" (Just "password")) (binding (EnvName
"DATABASE_PASSWORD") databasePasswordKey)` entry, and resolves file sources followed by
the environment source in `resolveServiceSources :: [Source] -> EnvSnapshot -> Either
(NonEmpty ConfigError) (ResolveResult ServiceConfig)`. Exit codes are a contract: 0
success, 2 usage (`usageExitCode`), 3 source IO/parse failure (`sourceExitCode`), 4
typed resolution failure (`resolutionExitCode`). After EP-21, the tagged input comes
from settei-formats, the diagnostic mode is the shared six-mode
`Settei.Optparse.DiagnosticMode` (adding describe modes), environment bindings are the
validated EP-18 `Bindings`, warnings render to stderr, and the conditional password uses
EP-19 sugar — but the exports the conformance package depends on
(`serviceConformanceConfig`, `resolveServiceSources`, the exit codes) keep their shapes.
The executable (examples/settei-service/app/Main.hs) prints a captured `ServiceRun`'s
stdout/stderr and exits with its code; tests live in
examples/settei-service/test/Settei/Example/ServiceTest.hs (driver test/Main.hs, fixture
test/fixtures/application.yaml), and the cabal file is
examples/settei-service/settei-example-service.cabal.

The conformance suite is one module,
examples/settei-conformance/test/Settei/Example/ConformanceTest.hs (driver
test/Main.hs), with a "Conformance" group (equal typed values across YAML/KDL/Dhall,
normalized report structure, honest per-format origin precision, source ordering and
malformed-higher-value policy, CLI-shadows-env-shadows-file with
`assertShadowCount`-style helpers, password branch selection) and a "Security" group
(sentinel `never-render-this-conformance-secret` injected through both reference
executables; asserts the sentinel never appears and `<redacted>` does). Its fixtures
live in examples/settei-conformance/test/fixtures/ and its cabal data-files globs cover
`*.yaml`, `*.kdl`, `*.dhall`.

Deployment manifests: the authored tree has a hand-written
examples/settei-service/kubernetes/ directory (configmap.yaml, deployment.yaml,
secret.yaml.example) whose deployment passes container args `--config
yaml:/etc/settei/application.yaml --explain-config` and delivers the password via
`secretKeyRef` env. EP-24 creates the authoritative runnable tree under
examples/settei-service/deploy/ (a kustomize *base* — plain YAML manifests — plus
per-namespace *overlays*; kustomize is the Kubernetes-native tool that patches a base
manifest set per environment, invoked as `kubectl kustomize <dir>` or `kustomize build
<dir>`), mounting the Secret as a directory so the mounted-file delivery mode exists in
manifests. Preflight records what EP-24 landed, including whether kubernetes/ was
removed or narrowed, the secrets mount path (this plan's placeholder:
`/etc/settei/secrets`), and which flags the manifests pass.

### Release collateral this plan owns

docs/compatibility.md (tables: Toolchain; Libraries and adapters; Input contracts;
Public modules — settei-kubernetes rows are added to the last three in the existing
style), README.md (the "Package map" table and "Release status" section — note the
release-status test count and package count will already have been rewritten by EP-14
and EP-21; take the then-current numbers at preflight), docs/security.md (sections
including "Kubernetes Secrets and mounted files", which this plan extends),
docs/release-checklist.md ("Automated validation" gains the manifest render check and
mounted-fixture smoke), settei-kubernetes/CHANGELOG.md, settei-env/CHANGELOG.md (only
if EP-23 touched the package), and — for closure — the parent MasterPlan file and the
living sections of EP-22/EP-23/EP-24. Registration artifacts re-verified rather than
created: mori.dhall (package rows follow the pattern of the existing `settei-env` row:
name, path, dependencies), nix/haskell.nix (a `callCabal2nix` derivation per package),
cabal.project (packages list plus a `package settei-kubernetes` stanza).

### Relevant ADRs consulted

- docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md — this
  plan's authority. Examples are the conformance boundary; the service's Kubernetes
  references are *trusted origin annotations* attached to ordinary files and env
  bindings; the application never contacts a cluster and never renders a
  password-bearing record; static description loads no sources; usage/source/resolution
  exit codes are distinct. This plan appends the dated amendment note described in the
  Decision Log during Milestone 4.
- docs/adr/0001-haskell-project-conventions.md — package layout, canonical cabal stanza,
  record and lens conventions, dependency-research process (Mori first, registry
  freshness checked separately) that all Milestone 1 code follows.
- docs/adr/0003-resolution-provenance-and-default-semantics.md — the annotation
  vocabulary and renderer rules the mounted-directory origin assertions rely on;
  EP-23 extended the `kubernetes.*` names additively.
- The settei-kubernetes adapter ADR created by EP-22/EP-23 (number known after they
  land; read it at preflight) — mounted-directory mapping semantics, symlink handling,
  freshness vocabulary. Milestone 4 verifies its coherence and promotes into it.
- docs/adr/0002, 0004, 0005, 0006 — background input semantics; no amendment expected
  from this plan.


## Plan of Work

The work is a preflight plus four milestones, strictly ordered. Preflight reconciles
this plan's provisional names with the landed EP-15..EP-24 deliverables. Milestone 1
makes the reference service exercise the new adapter end to end. Milestone 2 locks the
new surface at the conformance boundary and validates the manifests against the real
flags. Milestone 3 reconciles the release collateral. Milestone 4 proves the whole
workspace green and closes the MasterPlan. Each milestone ends with the workspace
compiling and its tests green, so the plan can pause at any boundary.

### Preflight — reconcile against the landed dependency plans

Scope: this plan file only (plus reading). Do not skip. Read, in order: the completed
EP-22/EP-23/EP-24 plan documents; the shipped settei-kubernetes source under
settei-kubernetes/src/ (module names, reader, bindings type, options, error type,
renderer, EP-23 modules and annotation names); the post-EP-21
examples/settei-service/src/Settei/Example/Service.hs and its test module; EP-24's
examples/settei-service/deploy/ tree and docs/guides/kubernetes-cookbook.md; the
adapter ADR EP-22/EP-23 wrote; and README.md's then-current "Release status" numbers.
Rewrite the provisional spellings throughout this plan (Context, Plan of Work, Concrete
Steps, Interfaces) to the landed ones, resolve the `--secrets-dir` spelling and default
mount path against the manifests, record the current total test count and publishable
package count, and add a revision note at the bottom. If any of EP-22/23/24 is not
Complete, stop and report — this plan hard-depends on all three. Acceptance: the
preflight Progress boxes are checked and the plan contains no remaining "provisionally"
markers in normative instructions. Commit the updated plan.

### Milestone 1 — the reference service exercises the mounted-directory source

Scope: examples/settei-service only (source, app, tests, cabal). At the end, the
service demonstrates *both* Kubernetes secret-delivery modes — a Secret projected as an
env var and a Secret mounted as a directory of files — with honest provenance for each,
and its tests prove it. Acceptance: `nix develop -c cabal test settei-example-service
--test-show-details=direct` passes with the new cases named in the transcript, and the
manual transcript in Milestone 2's smoke section can be produced.

First, extend the options. In examples/settei-service/src/Settei/Example/Service.hs,
add a `secretsDir :: !(Maybe FilePath)` field to `ServiceOptions` and a
`--secrets-dir PATH` option to the "Configuration" parser group, help text "Read
mounted Kubernetes Secret files from this directory". The option is optional: without
it the service behaves exactly as before (env-var delivery only), which keeps every
existing test and manifest valid during rollout.

Second, load the directory through the public adapter. Add a
`loadMountedSecretsSource :: FilePath -> IO (Either Text Source)`-shaped helper (align
the error side with how the post-EP-21 service carries rendered source errors) that
calls the landed `Settei.Kubernetes` reader with: a `KubernetesRef` asserting
`SecretObject`, name `settei-example-service-database` (the same object the env-var
binding asserts, so the two delivery modes visibly describe one Kubernetes object), and
explicit file bindings mapping at minimum the file `password` to the key
`database.password`. Use the adapter's own options/annotation entry points so the
origin carries the object identity, the mount path, and the EP-23 freshness
annotations; do not hand-assemble annotations. Any reader failure — directory missing,
unreadable, a bound file absent or invalid — is a *source* failure: it must surface
through the existing `InputFailure`-class path and exit with `sourceExitCode` (3),
rendered with the adapter's EP-17-style renderer, never with `show`.

Third, place it in the precedence stack. In `resolveServiceSources` (and the loading
step in `resolveServiceOptions` that feeds it), order sources lowest to highest:
mounted config file (from `--config`), then the mounted secrets directory (from
`--secrets-dir`), then the environment source. Write a short haddock comment on
`resolveServiceSources` stating this order and the rationale recorded in the Decision
Log (file band lowest; the secrets directory is the narrower, more authoritative file
source; environment highest so a pod-spec env edit wins in an incident). Do not change
the CLI example's stack; its env < CLI ordering is unchanged and is reused by the
conformance laws.

Fourth, adopt the derived bindings. Replace the hand-assembled `fromKubernetesObject
... (binding (EnvName "DATABASE_PASSWORD") databasePasswordKey)` entry in
`environmentBindings` with the EP-23 derived construction
(provisionally `bindingsFromKubernetesObject`), which produces the binding and its
provenance annotation in one step so they cannot drift. The reconciled call must
compose with the post-EP-18 validated `Bindings` type that EP-21 made the service use;
the other (non-Kubernetes) bindings stay as they are.

Fifth, update the tests in
examples/settei-service/test/Settei/Example/ServiceTest.hs (the module named in the
cabal test-suite stanza alongside driver test/Main.hs — enumerate: those two files are
the entire suite today; add cases, do not fork a new module unless size demands it).
New cases, each phrased against observable behavior:

- "mounted secrets directory resolves the production password": create a temporary
  directory (System.IO.Temp or the tasty-provided equivalent already used in the
  workspace — check sibling adapter tests for the established helper; add the
  dependency to the test stanza if needed), write a `password` file containing the
  existing sentinel `never-render-this-service-secret`, load it with the same helper
  the application uses, resolve with `HASKELL_ENV=production` and *no*
  `DATABASE_PASSWORD` env var, and assert resolution succeeds with a present password —
  proving the mounted file alone satisfies the Production-only requirement.
- "mounted-directory origin carries identity, mount path, and freshness": from the same
  resolution, render `renderResolutionText` and assert it contains the Secret object
  name `settei-example-service-database`, the temp mount path, and the freshness
  annotation names recorded at preflight (assert on the annotation *names* plus the
  path value; do not assert an exact timestamp), and that the sentinel does not appear
  anywhere while `<redacted>` does.
- "environment shadows the mounted secret": provide both the mounted `password` file
  and a `DATABASE_PASSWORD` env value (a *different* sentinel), assert the env value
  wins and the report's `database.password` node retains a shadowed mounted-directory
  origin (shadow count at least 1) — both delivery modes demonstrated, precedence
  honest.
- "missing or invalid secrets directory is a source failure": run
  `runServiceWithSnapshot` (or the post-EP-21 equivalent) with `--secrets-dir` pointing
  at a nonexistent path and assert exit code 3 with a rendered (non-`show`) message on
  stderr; repeat with a directory missing the bound `password` file if the adapter
  treats that as an error (reconcile with EP-22's semantics at preflight — if an absent
  bound file is instead an absent key, assert *that* behavior and record it here).

Update examples/settei-service/settei-example-service.cabal: add `settei-kubernetes
==0.1.0.0` to the library (and test suite if the tests import it directly), plus any
temp-dir test dependency. Keep the canonical common stanza untouched. Commit.

### Milestone 2 — conformance and smoke coverage

Scope: examples/settei-conformance and examples/settei-service tests; no library edits.
At the end, reverting the adapter's precedence or redaction behavior fails the
conformance boundary, and a manifest referencing a nonexistent flag fails the service
suite. Acceptance: `nix develop -c cabal test all --test-show-details=direct` passes
with the new cases named.

In examples/settei-conformance/test/Settei/Example/ConformanceTest.hs, add to the
"Conformance" group a case "mounted directory participates in cross-source precedence":
build a temp-dir mounted source via public `Settei.Kubernetes` (binding a file to
`http.port` or another public key so the law is assertable without secrets), resolve it
under the existing minimal service sources with an env source above it, and assert env
shadows the mounted value with the shadow trace retained (reusing
`assertShadowCount`); then, using the CLI example's declaration exactly as the existing
"CLI overrides environment after the shared file" case does, assert CLI shadows env
with the mounted source present at the bottom of the file band. Add to the "Security"
group a case "mounted-file secrets never render": deliver the conformance sentinel
`never-render-this-conformance-secret` through a mounted `password` file into the
service declaration under `HASKELL_ENV=production`, render text and JSON reports plus
captured run output, and assert the sentinel appears nowhere while `<redacted>`
appears. The conformance cabal file gains a `settei-kubernetes ==0.1.0.0` test
dependency.

In the service suite, add the CLI smoke cases with expected transcripts. Using the
captured-run API (`runServiceWithSnapshot` and `Options.execParserPure` over
`serviceParserInfo`, as existing tests do), assert: `--check-config --config
yaml:<fixture> --secrets-dir <tempdir>` with a valid mounted password exits 0 printing
`configuration valid`; `--explain-config` under the same setup exits 0 and its stdout
contains the mounted path and object identity. Record the expected transcript shape in
this plan now and replace it with real output when run:

```text
$ settei-example-service --config yaml:/etc/settei/application.yaml \
    --secrets-dir /etc/settei/secrets --explain-config
...
database.password  <redacted>
  origin: kubernetes secret settei-example-service-database key password
          (mounted at /etc/settei/secrets, file password, modified <timestamp>)
  shadowed: (env DATABASE_PASSWORD, if also set)
...
```

(The exact renderer layout comes from settei/src/Settei/Render.hs and the adapter's
annotation suffix; the assertion in code checks substrings — object name, mount path,
annotation names, `<redacted>` — not the full layout.)

Add the manifest-flag validation case "deploy manifests reference only real service
flags": list every `*.yaml` file under examples/settei-service/deploy/ (walk the
directory at test time relative to the package root via `Paths_settei_example_service`
data-files or a relative path — reconcile with how EP-24 packaged the manifests;
if they are `extra-source-files` not `data-files`, read them via a path relative to the
package directory and note that this test runs from the repository checkout, which is
acceptable for an internal example package), text-scan each file's `args:` blocks for
tokens beginning with `--`, and assert each token is a flag `serviceParserInfo`
accepts. Implement acceptance-checking by rendering the parser's help
(`Options.parserHelp`/`execParserPure ["--help"]`) and asserting token membership, or
by `execParserPure` with a synthesized minimal argument vector per flag; choose
whichever the landed parser makes simpler and record it here. Commit.

### Milestone 3 — release collateral

Scope: documentation, changelogs, and registration verification only. Acceptance: a
reviewer reading each document finds no claim contradicted by the tree or by the
Milestone 4 transcripts; grep-checks in Validation and Acceptance pass.

docs/compatibility.md: following the file's existing structure — do not restructure it.
In "Libraries and adapters", add rows for any external dependency settei-kubernetes
introduced (likely `directory`/`filepath` bounds; mirror the landed cabal file exactly;
if it only uses existing family dependencies, add no false row). In "Input contracts",
add a settei-kubernetes row in the established one-line style, in substance: "Mounted
ConfigMap/Secret directories; explicit per-file key bindings; atomic-writer symlink
layout; no cluster access." In "Public modules", add the adapter's exposed modules
(`Settei.Kubernetes` plus EP-23's modules, exactly as the landed cabal exposes them) to
the adapters list. Update the header's validated date when Milestone 4's runs complete.

README.md: add a package-map row in the table's style —
`[settei-kubernetes](settei-kubernetes/) | Mounted ConfigMap/Secret directory source
with explicit file bindings, derived env bindings, and freshness provenance.` — and
update "Release status": the publishable package count, the new total test count (from
Milestone 4), and one honest sentence that the Kubernetes initiative added the
mounted-directory adapter, derived bindings, the namespace cookbook with runnable
manifests, and reference-service integration. Add the cookbook
(docs/guides/kubernetes-cookbook.md, from EP-24) to "Guides and examples" if EP-24 did
not already. Keep the unchanged claims (not tagged, not uploaded, experimental) intact.

docs/security.md: extend the "Kubernetes Secrets and mounted files" section (reusing
its existing honest-limitations tone) with the mounted-directory trust model, in
substance: the adapter trusts the kubelet-managed filesystem — whatever files exist at
the mount path are read as the asserted object's data, and the `KubernetesRef` identity
attached to them is caller-supplied, trusted metadata that Settei does not verify
against any cluster; a wrong assertion produces a wrong (but confidently rendered)
explanation, so treat the ref as documentation, not attestation. Add the EP-23
freshness caveat: `kubernetes.file-modified` reports the mounted file's modification
time from the node's clock through the atomic-writer symlink layout; clock skew,
timezone rendering, and the kubelet's sync interval make it an approximate freshness
hint for incident triage, not a rotation proof. State the restart-to-reload posture:
Settei reads mounted files at startup and does not watch them; a rotated ConfigMap or
Secret takes effect on process restart (the cookbook documents the deployment-side
rollout pattern).

docs/release-checklist.md: under "Automated validation", add two durable items —
"kustomize render check: every overlay under examples/settei-service/deploy/ renders
without error (`kubectl kustomize` or `kustomize build`; documented manual fallback if
the binary is unavailable in the shell)" and "mounted-fixture smoke: the service
`--check-config` run with a temp-dir mounted secret exits 0, and with a missing
directory exits 3". These join the existing gates; do not check them until Milestone 4
actually runs them.

Changelogs: create or complete settei-kubernetes/CHANGELOG.md with one consolidated
`## 0.1.0.0 — <date>` entry in the family's style ("Initial experimental release." plus
one line per capability: mounted-directory source with explicit file bindings and
atomic-writer handling; secret-safe errors and renderer; derived environment bindings
from Kubernetes references; freshness and identity annotations). If EP-22/EP-23 already
wrote lines, reconcile wording rather than duplicating. Add a settei-env line only if
preflight confirmed EP-23 changed that package. Do not create changelogs for examples/.

Registration verification (EP-22 owns the wiring; this plan re-verifies): mori.dhall
contains a `settei-kubernetes` package row with path and dependencies; cabal.project
lists the directory and a `package settei-kubernetes` stanza consistent with its
siblings; nix/haskell.nix has its derivation and the example-service derivation now
passes `settei-kubernetes` through. Fix any gap as collateral drift. Commit.

### Milestone 4 — full validation and MasterPlan closure

Scope: no intended source edits; run every gate, record evidence, then close the
initiative. This milestone may edit the MasterPlan, ADRs, and the child plans' living
sections — that is its scope. Acceptance: all gates green with evidence recorded; the
MasterPlan reads as finished; ADRs coherent.

Run the gates in Concrete Steps order: `nix develop -c cabal build all`; `nix develop
-c cabal test all --test-show-details=direct`, summing the per-suite totals and
recording the new count in Progress, README, and here; `nix flake check` (after
`git add` of new files — Nix evaluates the git tree); `cabal check` in
settei-kubernetes/; the sdist round-trip for settei-kubernetes using the
isolated-unpack procedure from docs/release-checklist.md and EP-14 (unpack all
publishable sdists together into one temp workspace because the family pins exact
`==0.1.0.0` inter-dependencies not on Hackage); the kustomize render check over every
overlay; and the mounted-fixture smoke transcript. Triage failures per the Decision
Log: drift fixed forward here, behavior defects reopen the owning child plan.

Then close the MasterPlan
(docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md):
set the EP-25 registry row (and any child row not yet updated) to Complete, check the
three EP-25 Progress lines, and write the MasterPlan's Outcomes & Retrospective — this
is the final child plan, so compare each Vision & Scope bullet against reality, one by
one, including the deliberate out-of-scope list (no cluster client, no watch/reload, no
Helm) remaining true.

Finally the ADR distillation pass: read the adapter ADR from EP-22/EP-23 and verify it
coherently records the mounted-directory mapping semantics, symlink handling, and
freshness vocabulary after this plan's integration; promote into it the
restart-to-reload posture and the reaffirmed no-cluster-client boundary if EP-24's
cookbook decision was not already promoted; append a dated amendment note to
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md stating
that the mounted-directory source is now exercised by the reference service and
conformance suite and pointing at the adapter ADR, while cluster access remains out of
scope. Sweep the Decision Logs and Surprises sections of EP-22/EP-23/EP-24 and this
plan for anything durable not yet in an ADR; promote or record "nothing left to
promote". Fill this plan's Outcomes & Retrospective, check every Progress box, add
revision notes to every plan file whose living sections were edited, and commit.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/settei` unless
a `cd` is shown; cabal commands run through the pinned dev shell (`nix develop -c`).
Every commit in this plan uses the Conventional Commits format (`feat:`, `fix:`,
`test:`, `docs:`, `chore:`, with an optional scope and `!` for breaking changes) and
carries these three trailers, exactly:

```text
MasterPlan: docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md
ExecPlan: docs/plans/25-integrate-kubernetes-support-into-the-reference-service-and-release-collateral.md
Intention: intention_01kxxfcw4ke5fbb2kas9ghvv9a
```

Commit directly to the current branch (no feature branch unless the user asks).

Step 0 — preflight. Confirm the dependency gate:

```bash
grep -n "^| 22 \|^| 23 \|^| 24 " docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md
```

Every row for EP-22, EP-23, EP-24 must read Complete; stop and report otherwise. Then
read the sources and documents listed in Plan of Work's Preflight, rewrite this plan's
provisional spellings, and commit:

```text
docs(plan-25): reconcile against landed EP-22..EP-24 and ergonomics interfaces
```

Step 1 — Milestone 1. Edit examples/settei-service/src/Settei/Example/Service.hs,
examples/settei-service/test/Settei/Example/ServiceTest.hs, and
examples/settei-service/settei-example-service.cabal as specified. Then:

```bash
nix develop -c cabal build settei-example-service
nix develop -c cabal test settei-example-service --test-show-details=direct
```

Expected transcript shape (names indicative; counts higher than before):

```text
Test suite settei-example-service-tests: RUNNING...
Settei.Example.Service
  ...existing cases... : OK
  mounted secrets directory resolves the production password: OK
  mounted-directory origin carries identity, mount path, and freshness: OK
  environment shadows the mounted secret:                     OK
  missing or invalid secrets directory is a source failure:   OK
All N tests passed (...)
Test suite settei-example-service-tests: PASS
```

Commit:

```text
feat(examples/service): read mounted Kubernetes secrets via settei-kubernetes with derived bindings
```

Step 2 — Milestone 2. Edit
examples/settei-conformance/test/Settei/Example/ConformanceTest.hs, its cabal file, and
the service test module for the smoke and manifest cases. Then:

```bash
nix develop -c cabal test settei-example-conformance-tests --test-show-details=direct
nix develop -c cabal test settei-example-service --test-show-details=direct
nix develop -c cabal test all --test-show-details=direct
```

(If a cabal target name differs, list targets with `nix develop -c cabal build all
--dry-run` and use the real name.) Expected: all suites PASS; the conformance
transcript names "mounted directory participates in cross-source precedence" and
"mounted-file secrets never render"; the service transcript names the smoke and
"deploy manifests reference only real service flags" cases. Commit:

```text
test(conformance): lock mounted-directory precedence, sentinel scan, and manifest flags
```

Step 3 — Milestone 3. Edit docs/compatibility.md, README.md, docs/security.md,
docs/release-checklist.md, settei-kubernetes/CHANGELOG.md (and settei-env/CHANGELOG.md
only if applicable) as specified; verify registration:

```bash
grep -n "settei-kubernetes" mori.dhall cabal.project nix/haskell.nix
grep -n "settei-kubernetes" docs/compatibility.md README.md docs/release-checklist.md
```

Expected: the first grep shows the package row in all three files (wired by EP-22);
the second shows the new collateral references. Then the cheap structural gates:

```bash
nix fmt && git status --porcelain
```

Expected: `nix fmt` exits 0 and the status output is empty (docs edits need no
reformatting). Commit:

```text
docs(release): register settei-kubernetes across compatibility, README, security, checklist, changelog
```

Step 4 — Milestone 4 gates, in order; tick Progress boxes as each passes and paste
evidence into Surprises & Discoveries only if something unexpected appears.

```bash
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
```

Sum the `All N tests passed` lines across every suite and record the total here and in
README's release status (replace this sentence with the number when run). Then:

```bash
cd settei-kubernetes && nix develop ../ -c cabal check; cd ..
git add -A
nix flake check
```

Expected: `cabal check` reports no errors or warnings; `nix flake check` exits 0
(treefmt and package builds included). Then the sdist round-trip. Produce the sdists
and unpack all publishable packages together (they pin `==0.1.0.0` on each other, which
is not on Hackage, so they must solve as one workspace — same procedure EP-14
established; extend the list with settei-formats and settei-kubernetes as landed):

```bash
nix develop -c cabal sdist all
SDIST_TMP="$(mktemp -d)"
for t in dist-newstyle/sdist/settei-*.tar.gz; do tar -xzf "$t" -C "$SDIST_TMP"; done
ls "$SDIST_TMP"   # write a cabal.project listing exactly the publishable package dirs
```

Create `$SDIST_TMP/cabal.project` naming each unpacked publishable directory, copy any
solver-critical stanzas from the root cabal.project (the documented pins and
allowances), then:

```bash
cd "$SDIST_TMP" && nix develop /Users/shinzui/Keikaku/bokuno/settei -c cabal test settei-kubernetes --test-show-details=direct
```

Expected: settei-kubernetes builds and tests from its own sdist contents. A failure
here is almost always a fixture missing from `extra-source-files`/`data-files` —
collateral drift: fix the cabal stanza, rerun sdist, repeat. Then the manifest render
and mounted smoke, back in the repository root:

```bash
for d in examples/settei-service/deploy/overlays/*/; do
  kubectl kustomize "$d" > /dev/null && echo "RENDER OK: $d" || echo "RENDER FAILED: $d"
done
SECRETS_TMP="$(mktemp -d)"; printf 'placeholder-not-a-real-secret' > "$SECRETS_TMP/password"
HASKELL_ENV=production nix develop -c cabal run settei-example-service -- \
  --config yaml:examples/settei-service/test/fixtures/application.yaml \
  --secrets-dir "$SECRETS_TMP" --check-config; echo "exit=$?"
HASKELL_ENV=production nix develop -c cabal run settei-example-service -- \
  --config yaml:examples/settei-service/test/fixtures/application.yaml \
  --secrets-dir /nonexistent-secrets --check-config; echo "exit=$?"
```

(Adjust the overlay glob to EP-24's landed layout; if `kubectl`/`kustomize` is not in
the dev shell, perform the render on a machine that has it and record the transcript
here — the checklist documents this fallback.) Expected: every overlay prints
`RENDER OK`; the first service run prints `configuration valid` and `exit=0`; the
second prints a rendered mounted-directory source error on stderr and `exit=3`. Paste
the real transcripts into Validation and Acceptance when run. Commit any fix-forward
changes:

```text
fix(release): repair collateral drift found by full Kubernetes-initiative validation
```

Step 5 — closure. Edit the MasterPlan (registry, Progress, Outcomes & Retrospective),
perform the ADR distillation pass (adapter ADR verified and extended; dated note
appended to docs/adr/0007), sweep the child plans' living sections, fill this plan's
Outcomes & Retrospective and Progress, add revision notes. Commit:

```text
docs(masterplan-4): close the Kubernetes initiative; distill ADRs and mark EP-25 complete
```


## Validation and Acceptance

Acceptance is observable behavior, verified by re-running commands, not by reading
diffs.

Service integration (Milestone 1). From the repository root,
`nix develop -c cabal test settei-example-service --test-show-details=direct` passes
and its transcript names the four new mounted-directory cases as `OK`. Behavioral
spot-checks a human can run: create a temp directory with a `password` file, run the
service with `HASKELL_ENV=production`, no `DATABASE_PASSWORD`, `--secrets-dir` pointing
at it, and `--explain-config`; the output must show `database.password` as `<redacted>`
with an origin naming the Secret object `settei-example-service-database`, the temp
mount path, and the freshness annotations — and must exit 0. Unset scenario: the same
run without `--secrets-dir` and without `DATABASE_PASSWORD` must fail resolution (exit
4) exactly as before this plan, proving the option is genuinely optional. Negative
check: temporarily pointing the file binding at a wrong file name must make the
"mounted secrets directory resolves the production password" test fail — demonstrating
the test constrains behavior. Do not commit the temporary change.

Conformance and manifests (Milestone 2). `nix develop -c cabal test
settei-example-conformance-tests --test-show-details=direct` passes naming the mounted
precedence and mounted-sentinel cases; grepping any captured output for
`never-render-this-conformance-secret` and `never-render-this-service-secret` finds
nothing. The manifest test fails if any deploy/ manifest names a flag the parser does
not accept — verify by temporarily misspelling a flag in a manifest copy and observing
the failure (do not commit). The expected `--explain-config` transcript sketch in
Milestone 2 is replaced by the real captured transcript when run.

Collateral truthfulness (Milestone 3). Cross-reads: `grep -n settei-kubernetes
docs/compatibility.md` shows input-contract and public-module rows matching the landed
cabal file's exposed modules; README's package map has the settei-kubernetes row and
the release-status test count equals the Milestone 4 recorded total; docs/security.md
contains the kubelet-trust wording, the unverified-KubernetesRef wording, the
file-modified clock caveat, and the restart-to-reload posture; docs/release-checklist.md
contains the render and mounted-smoke gates; settei-kubernetes/CHANGELOG.md has exactly
one consolidated 0.1.0.0 entry.

Full validation and closure (Milestone 4). Each of the following exits 0 from the
repository root: `nix develop -c cabal build all`; `nix develop -c cabal test all
--test-show-details=direct` with every suite PASS and the recorded total strictly
greater than the preflight-recorded total; `nix flake check`; `cabal check` in
settei-kubernetes/; the isolated sdist workspace test for settei-kubernetes; every
overlay render printing `RENDER OK`; the mounted smoke printing `configuration valid` /
`exit=0` and the missing-directory smoke printing `exit=3` with a rendered error.
`grep -n "Complete" docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md`
shows all four registry rows Complete; the MasterPlan's Progress boxes are all checked
and its Outcomes & Retrospective is non-empty; docs/adr/0007 ends with a dated
amendment note pointing at the adapter ADR; this plan's Progress is fully checked and
its Outcomes & Retrospective compares the result against the Purpose section. Real
transcripts replace the expected sketches in this plan wherever "replace when run" is
noted.


## Idempotence and Recovery

Every step is an ordinary edit-build-test cycle on a git working tree, safe to repeat.
All validation commands (build, test, check, flake check, sdist, render, smoke runs)
are side-effect free with respect to the repository; `cabal sdist` overwrites its
tarballs deterministically; the sdist and mounted-smoke procedures create fresh
`mktemp -d` directories on every run and never write into the repository — abandoned
temp directories can be deleted freely. Re-applying an edit that is already present is
a no-op.

Each milestone ends with the workspace green and committed, so the plan resumes from
any boundary: on restart, read Progress, find the first unchecked box, and re-verify
the boxes above it by re-running their commands (cheap by design). Documentation edits
are plain text: `git checkout -- <file>` before committing, or `git revert <sha>`
after, restores state without touching code. The new `--secrets-dir` option is
strictly additive — omitting it reproduces pre-plan behavior — so Milestone 1 cannot
strand the manifests or guides mid-rollout; if Milestone 1 must pause with the option
added but tests unfinished, the workspace still builds and existing tests still pass.

If `nix flake check` fails only because new files are untracked, `git add` them and
rerun — Nix evaluates the git tree, not the working directory. If the isolated sdist
build fails on solver grounds, compare the temp `cabal.project` against the root
cabal.project and copy the missing pin or allowance; that adjustment lives only in the
temp directory and in this plan's instructions. If the kustomize binary is unavailable,
the render check degrades to the documented manual fallback (run it where the binary
exists and record the transcript); do not silently skip it.

The one stateful hazard is the reopen path: a behavior defect found in Milestone 4
pauses this plan at a clean commit and sets the owning child plan's registry row back
to In Progress, with the defect recorded in both plans' living sections. Never fix
adapter or manifest behavior inside this plan; when the child plan is Complete again,
restart Milestone 4 from the top, because the tree changed. Make the MasterPlan and ADR
closure edits only after every gate passes, so a revert never orphans a "Complete"
status.


## Interfaces and Dependencies

This plan introduces no new public API and no new external library in publishable
packages. Its code changes are confined to examples/settei-service and
examples/settei-conformance; its documentation changes are enumerated in Milestone 3.
All dependency spellings below are provisional until Step 0's reconciliation (see
Decision Log) and this section must be updated with the shipped ones.

From `settei-kubernetes` (EP-22/EP-23; module `Settei.Kubernetes` plus whatever EP-23
exposed): the mounted-directory reader (provisionally `readMountedDirectorySource`,
taking source options with a `KubernetesRef` and explicit per-file bindings —
provisionally `FileBindings` mapping file names to Settei `Key`s — and returning
`IO (Either <adapter error> Source)` in the family's adapter shape); the adapter error
type and its EP-17-contract text renderer; the EP-23 derived-bindings constructor
(provisionally `bindingsFromKubernetesObject`) returning the validated EP-18 `Bindings`
material; and the annotation names (provisionally `kubernetes.mount-path`,
`kubernetes.file-modified`, joining `kubernetes.object-kind`, `kubernetes.object-name`,
`kubernetes.namespace`, `kubernetes.object-key`).

From `settei` (core): `Config`, `resolve`, `defaultResolveOptions`, the post-EP-12
resolve result carrying `value`, `report`, `warnings` on success and report-bearing
failure; `renderResolutionText`, `renderResolutionJson`, `renderErrorsText`,
`renderWarningsText`; `KubernetesRef`/`kubernetesRef`, `SecretObject`,
`ConfigMapObject`; report node access (`#nodes`, `#origin`, `#shadowed`,
`#annotations`) used by the origin and shadow assertions. From `settei-env`: the
validated `Bindings` construction, `EnvSnapshot`/`envSnapshot`, `EnvName`. From
`settei-optparse-applicative` post-EP-21: the shared `DiagnosticMode`,
`diagnosticModeOptions`, and the diagnostic helpers the service already uses. From
`settei-formats` post-EP-21: the tagged single-input parser the service's `--config`
uses (untouched by this plan beyond composing beside it). From optparse-applicative
`>=0.19 && <0.20`: `Options.option`/`Options.strOption`, `Options.parserOptionGroup`,
`Options.execParserPure`, and help rendering for the manifest-flag test. Test
libraries: tasty/tasty-hunit (already dependencies) plus, if needed for temp
directories, the same temp-dir helper the settei-kubernetes tests use (mirror that
package's test stanza rather than introducing a different library).

At the end of Milestone 1, `Settei.Example.Service` must still export everything the
conformance package and executable rely on — `serviceConfig`,
`serviceConformanceConfig :: Config (ServiceConfig, [Text])`, `resolveServiceSources`
(now three-band ordering), `runServiceWithSnapshot`, `safeStartupSummary`,
`environmentBindings` (derived-bindings form), `serviceParserInfo`, and the exit codes
`usageExitCode` (2), `sourceExitCode` (3), `resolutionExitCode` (4) — plus the extended
`ServiceOptions` carrying `secretsDir :: Maybe FilePath` and whatever small helper
(`loadMountedSecretsSource`) the tests exercise. At the end of Milestone 2, the
conformance module needs no new exports (its only consumer is its own driver).

Documents this plan owns during implementation: docs/compatibility.md, README.md,
docs/security.md, docs/release-checklist.md, settei-kubernetes/CHANGELOG.md,
settei-env/CHANGELOG.md (conditionally), the parent MasterPlan file, docs/adr/0007 (the
dated amendment note), the adapter ADR (verification and promotion), and the living
sections of EP-22/EP-23/EP-24. Registration artifacts (mori.dhall, cabal.project,
nix/haskell.nix) are verified, not redesigned. External tools: the Nix dev shell (GHC
9.12.4, Cabal 3.16.1.0 per docs/compatibility.md), `git` with the mandatory trailers,
and `kubectl kustomize` (or `kustomize`) for the render gate with its documented
fallback. The manual publication steps at the bottom of docs/release-checklist.md
(tagging, signing, Hackage upload) remain out of scope and unauthorized.
