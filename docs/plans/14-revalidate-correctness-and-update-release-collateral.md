---
id: 14
slug: revalidate-correctness-and-update-release-collateral
title: "Revalidate correctness and update release collateral"
kind: exec-plan
created_at: 2026-07-19T14:54:42Z
intention: "intention_01kxxdt2f0enp928nc1wbcsd2t"
master_plan: "docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md"
---

# Revalidate correctness and update release collateral

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Five behavior-changing remediation plans have landed (or will have landed before this plan
starts): the shared-key sensitivity redaction hole (EP-9), bounded numeric scalar
conversion in the YAML and KDL adapters (EP-10), YAML 1.2 core-schema booleans (EP-11),
resolution reports on failure (EP-12), and the source-construction and adapter-diagnostics
hardening sweep (EP-13). Each plan carried its own tests and documentation, but each was
verified in isolation. Nobody has yet proven that the whole nine-package workspace is
release-ready *again*, and nobody has reconciled the release collateral — README.md's
"Release status" section still claims "All 138 tests pass" and "all eight ExecPlans are
complete", claims that were true on 2026-07-18 and are false after five behavior changes
and a second MasterPlan.

After this plan is complete, three things are true that are not true today. First, the
cross-format conformance suite in examples/settei-conformance locks the new semantics at
the application boundary: a YAML document containing `no` or `on` observably resolves as
text in a full adapter round-trip, a `1e1000000000` scalar is observably rejected by both
the YAML and KDL adapters with their stable format-specific bound categories, and a failed resolution observably
yields the same normalized provenance report shape from YAML, KDL, and Dhall sources.
Second, every automated release gate from docs/release-checklist.md passes on the merged
tree, and the evidence (including the new total test count) is recorded here. Third, every
piece of release collateral — README.md, docs/compatibility.md, docs/security.md,
docs/release-checklist.md, and all six package changelogs — tells the truth about the
re-validated workspace, and the parent MasterPlan is closed out with its ADR amendments
verified, its Outcomes & Retrospective written, and its registry rows marked Complete.

The Progress checklist below is the release gate the project owner will read before
rolling Settei out to roughly 50 microservices and 20 applications. Anyone can verify the
outcome by running the commands in Validation and Acceptance and by reading the updated
documents; nothing in this plan is accepted on the author's word alone.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] (2026-07-19T18:26:22Z) Preflight: confirmed EP-9 through EP-13 are marked Complete in the MasterPlan registry
      and their plan files' own Progress sections agree; abort and report if not.
- [x] (2026-07-19T18:26:22Z) Preflight: read the landed code for the exact post-remediation API shapes this plan
      asserts (resolve's failure shape, the numeric-bound error category names in
      settei-yaml and settei-kdl, the sensitivity-conflict error constructor) and record
      them in this plan's Context section.
- [x] (2026-07-19T18:29:48Z) Milestone 1: add the Norway-regression YAML conformance fixture and test (untagged
      `no`/`on` are text through the public adapter).
- [x] (2026-07-19T18:29:48Z) Milestone 1: add the huge-exponent rejection fixtures and tests for YAML and KDL,
      asserting each adapter's stable EP-10 bound category.
- [x] (2026-07-19T18:29:48Z) Milestone 1: add the resolution-failure fixtures (YAML, KDL, Dhall) and the test
      asserting the EP-12 failure report shape is normalized-equal across all three.
- [x] (2026-07-19T18:29:48Z) Milestone 1: extend the existing conformance secret-sentinel scan so it also covers
      the new failure-path report renderings.
- [x] (2026-07-19T18:29:48Z) Milestone 1: conformance suite passes with 11 tests; commit.
- [x] (2026-07-19T18:30:58Z) Milestone 2: `nix develop -c cabal build all` green.
- [x] (2026-07-19T18:31:30Z) Milestone 2: `nix develop -c cabal test all --test-show-details=direct` green;
      192 tests passed across 10 suites.
- [x] (2026-07-19T18:31:56Z) Milestone 2: `cabal check` clean in all six publishable package directories.
- [x] (2026-07-19T18:32:47Z) Milestone 2: `nix develop -c cabal haddock all` green.
- [x] (2026-07-19T18:34:39Z) Milestone 2: `nix develop -c cabal sdist all` green and the isolated
      unpacked-sdist build-and-test procedure passes 169 tests across the six publishable
      packages.
- [x] (2026-07-19T18:35:14Z) Milestone 2: formatting gate green (`nix fmt` changed no files) and
      `nix flake check` green for the host system.
- [x] (2026-07-19T18:42:26Z) Milestone 2: example CLI and service smoke tests pass, including the
      failure-path report behavior from EP-12 and an explicit CLI secret-sentinel
      redaction probe.
- [x] (2026-07-19T18:42:26Z) Milestone 2: `git diff --check` clean; no collateral drift or behavior
      defect was found.
- [x] (2026-07-19T18:50:15Z) Milestone 3: README.md Release status section rewritten with the re-validation date,
      the new test count, and an honest statement of what changed since the first
      0.1.0.0 validation.
- [x] (2026-07-19T18:50:15Z) Milestone 3: docs/compatibility.md updated (validated date, dependency-bound changes
      from EP-10/EP-13 such as a `scientific` dependency, input-contract rows for the new
      scalar semantics).
- [x] (2026-07-19T18:50:15Z) Milestone 3: docs/security.md final sweep (sensitivity-conflict semantics, Dhall
      preflight TOCTOU note, redaction guarantees re-confirmed).
- [x] (2026-07-19T18:50:15Z) Milestone 3: docs/release-checklist.md extended with the new behavior smoke checks
      (Norway fixture, exponent bound, failure-path report) and re-checked end to end.
- [x] (2026-07-19T18:50:15Z) Milestone 3: all six CHANGELOG.md files reconciled under the unreleased
      0.1.0.0 entry; the four packages changed by EP-9..EP-13 carry dated behavior lines,
      while the untouched environment and optparse adapters retain their original entry.
- [x] (2026-07-19T18:50:42Z) Milestone 3: collateral changes committed.
- [x] (2026-07-19T18:53:36Z) Milestone 4: ADR amendments from EP-9..EP-13 (docs/adr/0003, 0004, 0005, 0006)
      verified present and mutually coherent; gaps filled.
- [x] (2026-07-19T18:53:36Z) Milestone 4: remaining durable context from the five child plans'
      Decision Logs, Surprises, and Outcomes reviewed; nothing remained outside ADRs
      0003-0006. EP-14's conformance-boundary decision was promoted to ADR 0007.
- [x] (2026-07-19T18:53:36Z) Milestone 4: MasterPlan Progress boxes checked, Outcomes & Retrospective filled,
      registry row for EP-14 marked Complete.
- [x] (2026-07-19T18:53:36Z) This plan's own Outcomes & Retrospective written and its ADR distillation pass done.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- The landed EP-10 adapters deliberately use format-specific stable categories for the
  same exponent-bound rejection: `YamlInvalidScalar` and `KdlUnsupportedValue`. The
  authored plan's phrase "same error category" was corrected to require the exact
  category from each public adapter rather than inventing a cross-package category.

- The authored CLI explanation smoke expected `<redacted>` without populating the
  optional `SERVICE_TOKEN`, so the observed node was correctly `missing` with a null
  value. An additional run with `SERVICE_TOKEN=never-render-this-conformance-secret`
  produced `<redacted>` and omitted the sentinel, directly exercising the intended gate.


## Decision Log

Record every decision made while working on the plan.

- Decision: Assert the new conformance behaviors at the adapter/source boundary
  (`readYamlSource`, `readKdlSource`, `loadDhallSource`, `lookupSource`, `resolve`) with
  standalone fixture files, rather than growing the shared `ServiceConfig` declaration in
  examples/settei-service with new settings.
  Rationale: The service declaration is consumed by the CLI guide, the service guide, the
  Kubernetes manifests, and the ergonomics MasterPlan that follows; adding
  Norway/exponent/failure-probe settings to it would pollute the reference application to
  serve a test. Standalone fixtures keep the conformance package's existing pattern (the
  cabal `data-files` globs `test/fixtures/*.yaml`, `*.kdl`, `*.dhall` already cover new
  files) and exercise exactly the public modules ADR 0007 designates as the conformance
  boundary.
  Date: 2026-07-19

- Decision: The formatting gate for this plan is `nix fmt` followed by a clean-worktree
  check, plus the treefmt check inside `nix flake check` — not a bare
  `fourmolu --mode check` invocation.
  Rationale: The project has no direct fourmolu invocation anywhere in its release
  collateral. Formatting is wired through treefmt-nix in nix/treefmt.nix (fourmolu,
  cabal-fmt, nixpkgs-fmt, configured by the root fourmolu.yaml); docs/release-checklist.md
  and agents/skills/release/SKILL.md both specify `nix fmt`, and `nix flake check` runs
  the treefmt verification. Using the project's own gate keeps this plan's claims
  identical to the release checklist's claims.
  Date: 2026-07-19

- Decision: Do not hard-code EP-9/EP-10/EP-12 constructor and category names in this
  plan's test code; instead, a mandatory preflight step reads the landed modules and
  records the exact names in Context before Milestone 1 begins.
  Rationale: This plan is written before its five hard dependencies have landed. Guessing
  identifiers (for example the exponent-bound error category or the failure-shape type
  returned by `resolve`) would bake likely-wrong names into a plan that must remain
  self-contained; a recorded preflight keeps the plan honest and restartable.
  Date: 2026-07-19

- Decision: Fold every behavior-change changelog line into the existing unreleased
  `0.1.0.0` changelog entries (updating that entry's date at re-validation) rather than
  opening a `0.1.0.1` or "Unreleased" section.
  Rationale: 0.1.0.0 has never been tagged or uploaded (README "Release status",
  docs/release-checklist.md "Manual publication" section is unchecked), so there is no
  published version to preserve; the first Hackage release should present one coherent
  0.1.0.0 story including the hardening.
  Date: 2026-07-19

- Decision: Failures found during Milestone 2 are triaged into exactly two routes: fix
  forward inside this plan when the failure is collateral drift (stale fixture, golden
  file, doc claim, missing sdist file), or reopen the responsible child plan (set its
  MasterPlan registry row back to In Progress and record why in both plans) when the
  failure is a behavior defect in code the child plan owns.
  Rationale: EP-14 is the release gate, not a fifth remediation plan. Letting it silently
  patch behavior would erase the per-plan revertibility the MasterPlan decomposition was
  designed for.
  Date: 2026-07-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

EP-14 is complete. Four new conformance cases lock the correctness initiative at the
public composition boundary: YAML 1.2 `no`/`on` text semantics, format-specific rejection
of huge YAML and KDL exponents, normalized-equal failure reports with file provenance
across YAML/KDL/Dhall, and failure-path secret redaction. The conformance suite now passes
11 tests.

The release gate passed without reopening a child plan: all nine workspace packages
build, 192 tests pass across 10 suites, all six publishable packages pass `cabal check`,
Haddocks and source distributions build, and 169 publishable-package tests pass from a
fresh unpacked-sdist workspace. Formatting changed no files, host-system flake checks
passed, and CLI/service success, failure-provenance, and explicit secret-sentinel smokes
matched their documented exit and output contracts.

Release collateral now records the 2026-07-19 re-validation, the direct `scientific` and
`megaparsec` dependencies, the hardened adapter contracts, the failure-report security
guarantee, and the correct workspace/sdist test counts. Manual tagging, signing, Hackage
upload, and public-registry installation remain deliberately unchecked and unauthorized.

The ADR promotion pass found EP-9 through EP-13's durable decisions complete and coherent
in ADRs 0003-0006. EP-14's durable testing decision — use standalone fixtures at the
public conformance boundary and compare shared failure semantics without erasing
format-specific categories or origins — is recorded in ADR 0007. The main execution
lesson was that a redaction smoke must populate a secret; an absent optional secret
correctly renders as missing rather than `<redacted>`. No EP-14 work was descoped and no
correctness defect remains open in this initiative.


## Context and Orientation

### What Settei is and how this repository is laid out

Settei is a Haskell configuration library: an application writes one typed declaration of
its settings (`Config a`), passes an ordered list of sources (files, environment
variables, command-line flags), and gets back a resolved value plus a provenance report
that explains where every value came from, with secret values redacted. The repository is
a Cabal multi-package workspace pinned by a Nix flake (flake.nix; the development shell is
entered with `nix develop` from the repository root, and every build/test command in this
plan is run from the repository root through that shell).

Six publishable packages live at the top level: settei/ (core: declaration algebra,
resolver, reports, errors), settei-env/ (environment variables), settei-optparse-applicative/
(command-line overrides), settei-yaml/, settei-kdl/, and settei-dhall/ (file-format
adapters). Three internal packages live under examples/: examples/settei-cli (a layered
reference CLI whose executable is `settei-example-cli`), examples/settei-service (a
Kubernetes-shaped reference service whose executable is `settei-example-service`), and
examples/settei-conformance (a test-only package, `settei-example-conformance`, that loads
equivalent YAML, KDL, and Dhall fixtures through the public adapter modules and asserts
equal typed values and a normalized report shape). Per
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md, these
example packages — not the unit tests — are the conformance boundary for the public API:
if a behavior change is real, it must be observable there.

Key file locations you will touch or read:

- examples/settei-conformance/test/Settei/Example/ConformanceTest.hs — the entire
  conformance suite (one module). It already defines fixture loading via
  `Paths_settei_example_conformance.getDataFileName`, a `NormalizedReport` type that
  compares reports across formats, helpers like `expectLoaded`, `expectResolution`,
  `assertShadowCount`, and a "Security" test group whose secret sentinel is the string
  `never-render-this-conformance-secret`.
- examples/settei-conformance/test/fixtures/ — currently `service.yaml`, `service.kdl`,
  `service.dhall`. The cabal file's `data-files` stanza globs `test/fixtures/*.yaml`,
  `*.kdl`, and `*.dhall`, so new fixture files are packaged automatically with no cabal
  edit.
- settei/src/Settei/Resolve.hs, settei/src/Settei/Error.hs, settei/src/Settei/Render.hs —
  core resolver, error vocabulary, and renderers, reshaped by EP-9 and EP-12.
- settei-yaml/src/Settei/Yaml.hs and the settei-kdl sources — adapters reshaped by EP-10,
  EP-11, and EP-13.
- README.md ("Release status" section), docs/compatibility.md, docs/security.md,
  docs/release-checklist.md, and the six CHANGELOG.md files (settei/, settei-env/,
  settei-optparse-applicative/, settei-yaml/, settei-kdl/, settei-dhall/) — the release
  collateral reconciled in Milestone 3.
- docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md — the parent
  MasterPlan whose registry, Progress, and Outcomes sections this plan closes out in
  Milestone 4.

### The five plans this one depends on

This plan is meaningless before its five hard dependencies are Complete. Do not start it
otherwise. The dependencies, by registry number and checked-in path:

- EP-9, docs/plans/9-close-the-shared-key-sensitivity-redaction-hole.md — when the same
  key is declared both `Public` and `Secret`, the most restrictive sensitivity wins in
  every report and a structured sensitivity-conflict error is raised, instead of a silent
  left-bias that could leak a secret.
- EP-10, docs/plans/10-bound-numeric-scalar-conversion-in-the-yaml-and-kdl-adapters.md —
  numeric scalars with astronomically large exponents (for example `1e1000000000`), which
  previously could hang or exhaust memory when converted to `Rational`, are rejected by
  the YAML and KDL adapters with a structured error.
- EP-11, docs/plans/11-adopt-yaml-1-2-core-schema-boolean-scalars.md — untagged YAML
  booleans are only `true`/`false` (case-insensitive); `y`, `yes`, `on`, `n`, `no`, `off`
  are plain text. This eliminates the "Norway problem", the classic YAML 1.1 bug where a
  country code `no` silently becomes the boolean false.
- EP-12, docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md — `resolve`
  returns the provenance report and warnings on failure as well as success, so an operator
  debugging a failed pod still sees which sources were consulted and what was missing.
- EP-13, docs/plans/13-harden-source-construction-and-adapter-diagnostics.md — annotation
  merge semantics, validated custom-source construction, YAML decode exception
  tightening, Dhall parse-failure source positions, decimal (not fraction) report
  rendering, and a documented Dhall preflight time-of-check/time-of-use note.

### Mandatory preflight: record the landed API shapes here

This plan is written before those plans landed, so three identifier families are
deliberately not hard-coded. The first implementation step is to read the landed code and
plans and fill in this subsection (replacing the "to be recorded" markers) so the plan
stays self-contained for anyone restarting it:

- The landed resolver is total: `resolve :: ResolveOptions -> [Source] -> Config a ->
  ResolveResult a`. `ResolveResult` contains `answer :: Either (NonEmpty ConfigError) a`,
  `report :: ResolutionReport`, and `warnings :: [ConfigWarning]`; errors are the `Left`
  inside `answer`, while report and warnings remain available beside it. The reference
  CLI and service first handle input-loading `Either` failures, then inspect
  `result ^. #answer`; their failure renderers append `failureReport options result` to
  the structured errors in explain modes.
- The landed numeric limit is an adapter-local absolute base-10 exponent of 4096 in both
  adapters. YAML reports an out-of-range scalar as `YamlInvalidScalar`; KDL reports it as
  `KdlUnsupportedValue`. Both fixed messages state that the numeric exponent is outside
  the supported range. These are distinct public error types, so conformance asserts the
  exact stable category from each adapter rather than a nonexistent shared constructor.
- The landed core constructor is
  `SensitivityConflict (SensitivityConflictProblem { key :: Key })`. It participates in
  the existing exhaustive `problemKey` helper in the conformance suite, and both text and
  JSON renderers are already covered by core secret-sentinel tests.

### Relevant ADRs consulted

- docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md — this
  plan's authority. The conformance package compares typed values and a normalized report
  shape across formats but deliberately does not force byte-identical origin payloads;
  new tests must follow the same philosophy (compare normalized structure, assert each
  format's honest precision separately).
- docs/adr/0003-resolution-provenance-and-default-semantics.md — report semantics and the
  `schemaVersion: 1` JSON stability rule; amended by EP-9 (most-restrictive sensitivity)
  and EP-12 (reports on failure). Milestone 4 verifies those amendments.
- docs/adr/0004-yaml-input-semantics.md — YAML scalar semantics; amended by EP-10
  (exponent bound), EP-11 (boolean set), and EP-13 (decode tightening), each as an
  appended dated note. Milestone 4 verifies all three notes are present and coherent.
- docs/adr/0005-canonical-kdl-v2-input-semantics.md — KDL semantics; amended by EP-10.
- docs/adr/0006-dhall-input-import-and-provenance-semantics.md — Dhall import policy and
  the documented preflight race; amended by EP-13.
- docs/adr/0001-haskell-project-conventions.md and
  docs/adr/0002-inspectable-configuration-algebra.md — background conventions; no
  amendment expected from this plan.

### What the conformance package already covers (investigated 2026-07-19)

So that Milestone 1 adds only what is missing: the suite in
examples/settei-conformance/test/Settei/Example/ConformanceTest.hs already asserts (a)
equal typed values across YAML/KDL/Dhall, (b) format-independent normalized report
structure, (c) per-format honest origin precision (YAML line, KDL span annotations, Dhall
import-policy annotations), (d) core precedence and malformed-higher-value failure, (e)
CLI-over-environment-over-file ordering, (f) Selective production-password branching, and
(g) — this answers the investigation question about a sentinel scan — a "Security" test
group that injects the sentinel `never-render-this-conformance-secret` through both
reference executables' captured stdout/stderr and asserts the sentinel never appears while
`<redacted>` does. A conformance-level secret-sentinel scan therefore already exists and
Milestone 1 extends it to the new failure-path renderings rather than creating one. A
sensitivity-conflict declaration test (same key Public and Secret in one declaration)
belongs to core and was delivered by EP-9; it is out of scope here except for the sentinel
extension just described.

### Release collateral drift known before starting

README.md's "Release status" section claims: validation on GHC 9.12.4 / Cabal 3.16.1.0 /
`aarch64-darwin`; "All 138 tests pass"; "The MasterPlan and all eight ExecPlans are
complete" (that refers to the *first* MasterPlan,
docs/masterplans/1-build-settei-as-a-provenance-aware-configuration-library-for-haskell.md);
and a validated-collateral list. docs/compatibility.md is dated 2026-07-18 and its
dependency table has no `scientific` row (EP-10 likely added a direct `scientific`
dependency to settei-kdl for the exponent guard — verify at preflight against the landed
cabal files). docs/security.md predates EP-9's conflict semantics and EP-13's Dhall
TOCTOU note. The six CHANGELOG.md files each have a single `0.1.0.0 — 2026-07-18` entry;
each child plan was responsible for adding its own behavior-change line, which Milestone 3
verifies and reconciles. All of these are collateral drift by definition and are fixed
forward here.


## Plan of Work

The work is four milestones, in order. Milestone 1 makes the conformance boundary assert
the new behaviors; Milestone 2 proves the whole workspace green with the release gates;
Milestone 3 makes the collateral tell the truth; Milestone 4 closes the MasterPlan.
Nothing in this plan intentionally changes library behavior — if a library change turns
out to be needed, that is a behavior defect and is routed back to the responsible child
plan per the Decision Log.

### Milestone 1 — Cross-format conformance coverage for the new behaviors

Scope: examples/settei-conformance only (new fixture files plus new test cases in
test/Settei/Example/ConformanceTest.hs). At the end of this milestone the conformance
suite fails if anyone reverts EP-10, EP-11, or EP-12's semantics, which is not true today.
Acceptance: `nix develop -c cabal test settei-example-conformance-tests
--test-show-details=direct` passes with the new test names visible in the transcript.

First, after the preflight recording described in Context, add a Norway-regression
fixture. Create examples/settei-conformance/test/fixtures/booleans.yaml:

```yaml
region:
  country: no
  telemetry: on
  enabled: true
  disabled: FALSE
```

Add a test case "YAML 1.2 booleans: no and on are text at the adapter boundary" to the
"Conformance" group in ConformanceTest.hs. Load the fixture with
`Yaml.readYamlSource (Yaml.yamlSourceOptions "norway YAML") path` (resolve `path` via
`Paths.getDataFileName "test/fixtures/booleans.yaml"`, following the existing
`loadFixtureSources` pattern), then use the existing `expectCandidate` helper with keys
`region.country`, `region.telemetry`, `region.enabled`, and `region.disabled` and assert
the candidate raw values are `RawText "no"`, `RawText "on"`, `RawBoolean True`, and
`RawBoolean False` respectively (match the exact raw-value constructor names used by the
landed settei core — the existing test file uses `RawText`/`RawNumber`; confirm the
boolean constructor name there or in settei/src/Settei/Value.hs). This locks EP-11 at the
public-adapter level: the unit tests in settei-yaml prove the scalar function, this test
proves an adopting application reading a real file sees text.

Second, add the huge-exponent rejection fixtures. Create
examples/settei-conformance/test/fixtures/huge-exponent.yaml:

```yaml
http:
  port: 1e1000000000
```

and examples/settei-conformance/test/fixtures/huge-exponent.kdl:

```kdl
http {
  port 1e1000000000
}
```

(Adjust the KDL numeric literal spelling if the landed EP-10 tests use a different one —
copy the exact rejected literal from settei-kdl's own tests so the conformance fixture and
the unit tests agree on what is rejected.) Add a test case "huge exponents are rejected by
YAML and KDL with stable categories". Call `Yaml.readYamlSource` and
`Kdl.readKdlSource` on the two fixtures and assert both return `Left`; then assert YAML
reports `YamlInvalidScalar` and KDL reports `KdlUnsupportedValue`, as recorded at
preflight. The
test must assert the *category*, not the rendered message text, so wording can evolve.
Dhall needs no such fixture: `1e1000000000` is a Dhall `Double`, which is bounded, and
EP-10 did not change settei-dhall — state this in a comment in the test so a future reader
does not think Dhall was forgotten.

Third, add the resolution-failure report fixtures. Create failure.yaml, failure.kdl, and
failure.dhall in the same fixtures directory, each an exact copy of the corresponding
service.* fixture with the entire `database.host` entry removed (in the Dhall record,
delete the `host = ...` field from `database`; the Dhall fixture is an untyped record so
removing a field simply removes the key from the loaded source). `database.host` is a
required setting with no default in the service declaration, so resolving each fixture
alone fails with a missing-required error. Add a test case "failure reports are
format-independent and carry provenance". For each of the three sources, call `resolve
defaultResolveOptions [src] Service.serviceConformanceConfig`, assert the failure side is
taken, destructure it using the EP-12 failure shape recorded at preflight, and assert:
(a) the errors identify exactly the key `database.host` (reuse the existing `problemKey`
helper, updating it if EP-9 added a constructor); (b) a report is present even though
resolution failed, and its node for `http.host` shows a resolved outcome with a `file`
source class (proving the report is a real provenance report, not an empty stub); and
(c) `normalizeReport` of the YAML failure report equals `normalizeReport` of the KDL and
Dhall failure reports — extending the existing `normalizeReport`/`NormalizedReport`
machinery to accept whatever container the failure side provides. This is the
conformance-level lock on EP-12: failure diagnostics are as format-independent as success
diagnostics.

Fourth, extend the existing "Security" sentinel scan. In the same failure test (or a
sibling test in the "Security" group), render the failure-path report with
`renderResolutionText` and `renderResolutionJson`, and render the errors with
`renderErrorsText`, over a variant resolution in which the environment supplies the secret
sentinel (follow the existing pattern that builds `expectEnvSource (Env.envSnapshot
[("DATABASE_PASSWORD", secretSentinel), ...])` and force a failure by also setting
`HASKELL_ENV=production` while omitting some other required key). Assert
`secretSentinel` appears in none of the rendered outputs. This closes the one redaction
surface the current scan cannot reach — reports that accompany *failures* did not exist
before EP-12.

Commit Milestone 1 (see Concrete Steps for the mandated message format).

### Milestone 2 — Full workspace validation

Scope: no source edits intended; this milestone runs every automated gate from
docs/release-checklist.md against the merged tree and records evidence in this plan.
Acceptance: every command below exits 0 with the expected transcript shape, and the new
total test count is recorded in this plan and carried into Milestone 3.

Run, from the repository root, in this order (each command's expected outcome is detailed
in Concrete Steps and Validation and Acceptance): `nix develop -c cabal build all`; `nix
develop -c cabal test all --test-show-details=direct` (sum the per-suite "N tests passed"
lines and write the total into Progress and the Milestone 3 README edit — the old total
was 138 and the new total must be strictly larger since EP-9..EP-13 and Milestone 1 all
added tests); `cabal check` inside each of the six publishable package directories
(settei, settei-env, settei-optparse-applicative, settei-yaml, settei-kdl, settei-dhall —
run through `nix develop -c` so the Cabal CLI version matches the matrix); `nix develop -c
cabal haddock all`; `nix develop -c cabal sdist all`; the isolated unpacked-sdist
procedure spelled out in Concrete Steps (docs/release-checklist.md states the requirement
as "Every publishable source distribution is unpacked in a new temporary directory and
builds from its own contents", and agents/skills/release/SKILL.md adds that this catches
missing `extra-source-files` and goldens — the exact runnable form is given below because
the checklist does not spell one out); the formatting gate (`nix fmt` then confirm the
worktree is unchanged — this project has no direct fourmolu invocation; see Decision Log);
`nix flake check` (remember: newly created files must be `git add`-ed first because Nix
evaluates the git tree); the example CLI and service smoke tests including a failure-path
smoke test (Concrete Steps); and finally `git diff --check`.

On any failure, triage per the Decision Log: collateral drift (a stale golden under
settei/test/golden/, a conformance fixture invalidated by a child plan, a missing sdist
file, a doc claim) is fixed forward here with its own commit; a behavior defect (wrong
redaction, wrong scalar semantics, wrong report shape) reopens the responsible child plan
— set its registry row in the MasterPlan back to In Progress, record the defect in that
plan's Progress and Surprises sections and in this plan's Surprises section, stop this
plan at a clean commit, and resume only when the child plan is Complete again.

### Milestone 3 — Release collateral reconciliation

Scope: documentation and changelogs only. Acceptance: a reviewer reading each document
finds no claim contradicted by the Milestone 2 transcripts.

README.md, "Release status" section: rewrite it to state that 0.1.0.0 was first validated
on 2026-07-18 and re-validated on the actual date Milestone 2 completes, after a
correctness-hardening pass; replace "All 138 tests pass" with the recorded new count;
replace "The MasterPlan and all eight ExecPlans are complete" with wording that names both
MasterPlans (the original build MasterPlan and
docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md); and add an
honest summary sentence per behavior change since the first validation: sensitivity
conflicts are now structured errors with most-restrictive redaction, huge-exponent
numerics are rejected by YAML/KDL, YAML booleans follow the 1.2 core schema, failed
resolutions still produce provenance reports, and source/adapter diagnostics were
hardened. Keep the unchanged claims (not tagged, not uploaded, experimental) intact.

docs/compatibility.md: update the header's validated date; verify the toolchain table
against the shell (`nix develop -c ghc --version`, `nix develop -c cabal --version`) in
case the pinned flake moved; add or amend dependency rows for any bound changes made by
EP-10/EP-13 — check the landed settei-yaml.cabal and settei-kdl.cabal for a direct
`scientific` dependency and mirror its bound; and update the "Input contracts" rows for
YAML ("only true/false are untagged booleans; numeric exponents beyond the EP-10 bound
fail") and KDL (exponent bound) so the contract table matches the new semantics.

docs/security.md: three edits. In "Redaction guarantees", document EP-9's semantics: when
one key is declared with conflicting sensitivities, resolution raises a structured
sensitivity-conflict error and every retained or rendered occurrence of that key's value
uses the most restrictive sensitivity, so a conflicting declaration can never widen
exposure. In "Source parsing and errors", note that adapter numeric bounds (EP-10) are a
denial-of-service protection: a hostile or corrupt file cannot hang startup via
`toRational`. In "Dhall import policy" (or a new short subsection), add EP-13's
time-of-check/time-of-use note: import-policy preflight checks and file reads are not
atomic, so a file substituted between check and read is a race the adapter documents
rather than prevents — mirror the wording EP-13 put in ADR 0006. Confirm the remaining
guarantees still read true against the landed code and leave them otherwise unchanged.

docs/release-checklist.md: under "Automated validation", add three durable items — the
conformance Norway fixture passes (`booleans.yaml` asserts `no`/`on` are text), the
huge-exponent fixtures are rejected by both adapters, and a forced resolution failure
still renders a redacted provenance report. Re-verify every existing checked item against
the Milestone 2 run and re-check them honestly (they were checked for the 2026-07-18 run;
this plan's run supersedes it — note the re-validation date in the document's
introduction).

The six CHANGELOG.md files: each child plan was to add one line for its behavior change
under the unreleased 0.1.0.0 entry. Verify: settei/CHANGELOG.md has lines for EP-9
(sensitivity conflicts), EP-12 (reports on failure), and EP-13's core-touching items
(decimal rendering, validated custom sources); settei-yaml/CHANGELOG.md for EP-10, EP-11,
and EP-13's decode tightening; settei-kdl/CHANGELOG.md for EP-10; settei-dhall/CHANGELOG.md
for EP-13's parse locations and TOCTOU documentation; settei-env/ and
settei-optparse-applicative/ for whatever EP-13's annotation-merge sweep touched in them
(if a package was genuinely untouched, its changelog gains no line — do not invent one).
Add any missing line, make wording parallel ("Reject ...", "Report ...", "Treat ..."),
order lines consistently (core semantics first, then diagnostics), and set each touched
entry's date to the re-validation date. Commit Milestone 3.

### Milestone 4 — MasterPlan closure and ADR distillation

Scope: docs/adr/, docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md,
and the five child plan files (only their living sections, if promotion notes are
needed). Acceptance: the MasterPlan reads as finished — registry all Complete, Progress
all checked, Outcomes written — and every durable decision from the initiative lives in an
ADR, not only in a plan file.

First verify the ADR amendments: docs/adr/0003 must contain EP-9's
most-restrictive-sensitivity rule and conflict error plus EP-12's always-available report
semantics; docs/adr/0004 must contain three dated notes (EP-10 exponent bound, EP-11
boolean set, EP-13 decode tightening) that do not contradict each other; docs/adr/0005
must contain EP-10's bound; docs/adr/0006 must contain EP-13's parse-location and TOCTOU
notes. If an amendment is missing or incoherent, write it now, sourcing content from the
child plan's Decision Log (this is collateral drift, not a reopen).

Then perform the promotion pass: read the Decision Log, Surprises & Discoveries, and
Outcomes sections of all five child plans and of this plan; anything durable (a chosen
constant like the exponent bound and why, a rejected alternative, a gotcha future
maintainers need) that is not yet in an ADR gets promoted — amend the topical ADR, or
create docs/adr/0008-... if a genuinely new topic emerged. Record in this plan's Decision
Log what was promoted and what was deliberately left as task-local detail.

Finally close the MasterPlan: check its remaining Progress boxes (the two EP-14 lines and
any child lines left unchecked), fill its Outcomes & Retrospective (what the initiative
achieved against its Vision & Scope, the final test count, anything descoped), set the
EP-14 registry row — and any child rows not yet updated — to Complete, and add a dated
revision note at the bottom of any plan file whose living sections were edited, per the
Revision Protocol in agents/skills/exec-plan/PLANS.md. Write this plan's own Outcomes &
Retrospective and perform its ADR distillation pass. Commit Milestone 4.


## Concrete Steps

All commands run from the repository root, /Users/shinzui/Keikaku/bokuno/settei, unless a
`cd` is shown. Every commit in this plan must use a Conventional Commits message
(`feat:`, `fix:`, `test:`, `docs:`, `chore:` with an optional scope) and must carry these
three trailers, exactly:

```text
MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
ExecPlan: docs/plans/14-revalidate-correctness-and-update-release-collateral.md
Intention: intention_01kxxdt2f0enp928nc1wbcsd2t
```

Step 0 — preflight. Confirm the dependency gate and record the landed shapes:

```bash
grep -n "| 9 \|| 10 \|| 11 \|| 12 \|| 13 " docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
```

Every row for EP-9..EP-13 must read Complete; if any does not, stop and report. Then read
settei/src/Settei/Resolve.hs (failure shape), settei/src/Settei/Error.hs
(sensitivity-conflict constructor), settei-yaml/src/Settei/Yaml.hs and the settei-kdl
error module (numeric-bound category and limit), and the tail sections of the five child
plan files. Fill in the "Mandatory preflight" subsection of Context in this file and
commit:

```text
docs(plan-14): record landed EP-9..EP-13 API shapes at preflight
```

Step 1 — Milestone 1 fixtures and tests. Create the four fixture files described in Plan
of Work (booleans.yaml, huge-exponent.yaml, huge-exponent.kdl, failure.yaml, failure.kdl,
failure.dhall) under examples/settei-conformance/test/fixtures/ and add the four test
cases to examples/settei-conformance/test/Settei/Example/ConformanceTest.hs. Then:

```bash
git add examples/settei-conformance
nix develop -c cabal test settei-example-conformance-tests --test-show-details=direct
```

Expected transcript shape (test count will be higher than the current 7; the exact
number depends on how tests are grouped):

```text
Test suite settei-example-conformance-tests: RUNNING...
Settei
  Conformance
    ...
    YAML 1.2 booleans: no and on are text at the adapter boundary: OK
    huge exponents are rejected by YAML and KDL with stable categories:       OK
    failure reports are format-independent and carry provenance:  OK
  Security
    no captured output contains secret sentinels:                 OK
All N tests passed (...)
Test suite settei-example-conformance-tests: PASS
```

Commit:

```text
test(conformance): lock Norway booleans, exponent bounds, and failure reports cross-format
```

Step 2 — Milestone 2 gates, in order. After each command, tick the matching Progress box
and paste a one-to-three-line evidence snippet into Surprises & Discoveries only if
something unexpected appeared.

```bash
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
```

The build must end without errors; the test run must end with every suite reporting
`PASS` and no suite reporting `FAIL`. Sum the `All N tests passed` lines across the nine
packages' suites and record the total (expected: strictly greater than 138) in Progress
and in this step, replacing this sentence. Then per-package checks:

```bash
for p in settei settei-env settei-optparse-applicative settei-yaml settei-kdl settei-dhall; do
  (cd "$p" && nix develop ../ -c cabal check) || echo "CHECK FAILED: $p"
done
```

Expected: each package prints `No errors or warnings could be found in the package.` (or
Cabal 3.16's equivalent success line) and no `CHECK FAILED` line appears. Then:

```bash
nix develop -c cabal haddock all
nix develop -c cabal sdist all
```

Haddock must finish without errors (warnings about missing links are tolerated only if
the 2026-07-18 run tolerated them — compare against the checklist's spirit: documentation
builds). sdist prints one `Wrote: .../dist-newstyle/sdist/<pkg>-0.1.0.0.tar.gz` line per
package. Then the isolated unpacked-sdist procedure. The release checklist requires that
every publishable sdist, unpacked into a fresh temporary directory, builds from its own
contents; because the six packages depend on each other at exact version `==0.1.0.0`
which is not on Hackage, unpack all six together and give them a workspace-local
cabal.project:

```bash
SDIST_TMP="$(mktemp -d)"
for t in dist-newstyle/sdist/settei-0.1.0.0.tar.gz \
         dist-newstyle/sdist/settei-env-0.1.0.0.tar.gz \
         dist-newstyle/sdist/settei-optparse-applicative-0.1.0.0.tar.gz \
         dist-newstyle/sdist/settei-yaml-0.1.0.0.tar.gz \
         dist-newstyle/sdist/settei-kdl-0.1.0.0.tar.gz \
         dist-newstyle/sdist/settei-dhall-0.1.0.0.tar.gz; do
  tar -xzf "$t" -C "$SDIST_TMP"
done
printf 'packages:\n  settei-0.1.0.0\n  settei-env-0.1.0.0\n  settei-optparse-applicative-0.1.0.0\n  settei-yaml-0.1.0.0\n  settei-kdl-0.1.0.0\n  settei-dhall-0.1.0.0\n' > "$SDIST_TMP/cabal.project"
```

Copy into `$SDIST_TMP/cabal.project` any solver-critical stanzas from the repository's
root cabal.project (the documented dhall-json revision allowances, and the
source-repository/tarball pins for optparse-applicative 0.19.0.0 and kdl-hs 1.1.1 that
flake.nix documents — open the root cabal.project and mirror what the unpacked build
needs; the unpacked tree has no flake, so Cabal must be able to solve on its own inside
the nix shell). Then:

```bash
cd "$SDIST_TMP" && nix develop /Users/shinzui/Keikaku/bokuno/settei -c cabal test all --test-show-details=direct
```

Expected: all publishable-package suites pass from the unpacked contents. A failure here
almost always means a fixture or golden file missing from `extra-source-files`/
`data-files` — that is collateral drift; add the file to the package's cabal stanza, rerun
sdist, and repeat this step. Then formatting and flake gates, back in the repository root:

```bash
nix fmt
git status --porcelain   # expected: empty output (no reformatting was needed)
git add -A               # only if new files were created earlier and not yet staged
nix flake check
```

`nix flake check` runs the treefmt verification and pre-commit hooks; expected outcome is
a quiet exit 0 (with build log lines). Then the example smoke tests:

```bash
nix develop -c cabal run settei-example-cli -- \
  --config yaml:examples/settei-cli/test/fixtures/application.yaml --check-config
nix develop -c cabal run settei-example-cli -- \
  --config yaml:examples/settei-cli/test/fixtures/application.yaml --explain-config-json
HASKELL_ENV=development nix develop -c cabal run settei-example-service -- \
  --config yaml:examples/settei-service/test/fixtures/application.yaml --check-config
```

Expected: the `--check-config` runs print a short success message and exit 0; the
`--explain-config-json` run prints a `schemaVersion: 1` JSON report with every secret
rendered as `<redacted>`. Add one failure-path smoke: run the service `--check-config`
with `HASKELL_ENV=production` and no `DATABASE_PASSWORD`, and confirm it exits nonzero
with the missing-key diagnostic *and* (per EP-12) that its explanation output still
identifies the sources it consulted — capture the exact observed transcript into
Validation and Acceptance when run. Finally:

```bash
git diff --check
```

Expected: no output. Commit any fix-forward changes made during this step:

```text
fix(release): repair collateral drift found by full workspace validation
```

Step 3 — Milestone 3 edits. Edit README.md, docs/compatibility.md, docs/security.md,
docs/release-checklist.md, and the six CHANGELOG.md files exactly as described in Plan of
Work, using the test count recorded in Step 2 and the actual completion date. Re-run the
two cheapest gates to prove docs edits broke nothing structural:

```bash
nix fmt && git status --porcelain
nix flake check
```

Commit:

```text
docs(release): reconcile README, compatibility, security, checklist, and changelogs
```

Step 4 — Milestone 4 closure. Verify and, where needed, write the ADR amendments in
docs/adr/0003, 0004, 0005, 0006; perform the promotion pass over the five child plans'
living sections; update the MasterPlan (Progress, Outcomes & Retrospective, registry
statuses); write this plan's Outcomes & Retrospective; add revision notes to every plan
file edited. Commit:

```text
docs(masterplan-2): close correctness initiative; distill ADRs and mark EP-14 complete
```

Every one of the four commits above carries the three mandatory trailers shown at the top
of this section.


## Validation and Acceptance

Acceptance is observable behavior, verified by re-running commands, not by reading diffs.

Conformance behaviors (Milestone 1). From the repository root:

```bash
nix develop -c cabal test settei-example-conformance-tests --test-show-details=direct
```

passes, and the transcript names the three new Conformance cases and the Security case as
`OK`. Negative check: temporarily reverting EP-11's boolean set (or hand-editing
booleans.yaml's `country: no` assertion to expect a boolean) makes the suite fail —
demonstrating the tests actually constrain behavior. Do not commit the temporary revert.

Workspace gates (Milestone 2). Each of the following exits 0 from the repository root:
`nix develop -c cabal build all`; `nix develop -c cabal test all
--test-show-details=direct` with every suite `PASS` and a recorded total strictly greater
than 138; `cabal check` clean in all six publishable directories; `nix develop -c cabal
haddock all`; `nix develop -c cabal sdist all` writing six `settei*-0.1.0.0.tar.gz`
files; the unpacked-sdist workspace test run passing 169 tests in a fresh `mktemp -d`
directory; `nix fmt` changing no files; `nix flake check`; `git diff --check` with no
output. Smoke tests: both `--check-config` invocations exited 0 and printed
`configuration valid`. The CLI JSON explanation emitted `"schemaVersion":1`; with
`SERVICE_TOKEN=never-render-this-conformance-secret`, its `credentials.token` node
rendered `"value":"<redacted>"` and did not contain the sentinel. The production service
without `DATABASE_PASSWORD` exited 4 and printed:

```text
database.password: required value is missing
database.host = "postgres.internal"
  from file source examples/settei-service/test/fixtures/application.yaml (YAML) from Kubernetes ConfigMap settei-example-service key application.yaml
database.password = <missing>
runtime.environment = "production"
  from environment variable HASKELL_ENV
branch 1 [selected]: runtime.environment -> database.password
```

The full observed explanation also retained the file origin for `http.host` and the
default derivations for `database.poolSize`, `database.port`, and `http.port`, confirming
EP-12 provenance remains available on failure.

Collateral truthfulness (Milestone 3). Verified by cross-reading: the test count printed
by the Milestone 2 test run equals the count claimed in README.md's Release status; the
date in docs/compatibility.md's first paragraph equals the re-validation date; `grep -n
scientific docs/compatibility.md` reflects exactly what `grep -n scientific
settei-kdl/settei-kdl.cabal settei-yaml/settei-yaml.cabal` shows (a row if and only if a
direct dependency exists); docs/security.md mentions the sensitivity-conflict error and
the Dhall preflight race; each behavior change from EP-9..EP-13 appears as exactly one
line in the changelog of each package it touched.

Closure (Milestone 4). `grep -n "Complete" docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md`
shows all six registry rows Complete; the MasterPlan's Progress boxes are all checked and
its Outcomes & Retrospective is non-empty; docs/adr/0003 and 0004 each contain the dated
amendment notes named in Plan of Work (verify with `grep -n "2026-" docs/adr/0003*.md
docs/adr/0004*.md docs/adr/0005*.md docs/adr/0006*.md`); this plan's Progress list is
fully checked and its Outcomes & Retrospective compares the result against the Purpose
section.


## Idempotence and Recovery

Every step in this plan is safe to repeat. All validation commands (build, test, check,
haddock, sdist, fmt, flake check, smoke runs) are read-only with respect to source and can
be rerun at any time; `cabal sdist` overwrites its previous tarballs deterministically.
The unpacked-sdist procedure creates a fresh temporary directory on every run (`mktemp
-d`) and never writes into the repository; abandoned temp directories can be deleted
freely. `nix fmt` is idempotent by construction — a second run after a clean first run
changes nothing, which is exactly the property the formatting gate checks.

Documentation edits are plain-text and versioned; if an edit goes wrong, `git checkout --
<file>` before committing, or `git revert <sha>` after, restores the previous state
without affecting code. Each milestone is its own commit, so the plan can be resumed from
any milestone boundary: on restart, read the Progress section, find the first unchecked
box, and confirm the boxes above it against the working tree (rerunning their commands is
the reliable way to re-verify — that is cheap by design).

The one genuinely stateful hazard is the reopen path: if Milestone 2 finds a behavior
defect, this plan stops at a clean commit and a child plan's registry row is set back to
In Progress. Recovery is procedural, not technical — when the child plan is Complete
again, restart this plan at Milestone 2 from the top (all gates rerun, because the tree
changed). Never fix a behavior defect inside this plan; that would leave the MasterPlan's
per-plan history dishonest even though the tree would compile.

If `nix flake check` fails only because newly created files are untracked, the recovery
is `git add` of those files and a rerun — Nix evaluates the git tree, not the working
directory. If the unpacked-sdist build fails on solver grounds rather than missing files,
compare `$SDIST_TMP/cabal.project` against the repository root cabal.project and copy the
missing pin or allowance stanza; that adjustment lives only in the temp directory and in
this plan's instructions, so repeating it is harmless.


## Interfaces and Dependencies

This plan intentionally introduces no new libraries, no new modules in publishable
packages, and no new public API. Its code changes are confined to the internal test
package settei-example-conformance.

Dependencies consumed (all already in examples/settei-conformance/settei-example-conformance.cabal;
no cabal edits are expected — the `data-files` globs `test/fixtures/*.yaml`, `*.kdl`,
`*.dhall` already package the new fixtures): `settei ==0.1.0.0` (module `Settei` and
`Settei.Prelude`: `resolve`, `defaultResolveOptions`, `lookupSource`, `renderErrorsText`,
`renderResolutionText`, `renderResolutionJson`, the `RawValue` constructors, `Key`
parsing, and — post EP-12 — the failure shape recorded at preflight); `settei-yaml
==0.1.0.0` (`Settei.Yaml.readYamlSource`, `Settei.Yaml.yamlSourceOptions`, and the
post-EP-10/EP-11 error type); `settei-kdl ==0.1.0.0` (`Settei.Kdl.readKdlSource`,
`Settei.Kdl.kdlSourceOptions`, post-EP-10 error type); `settei-dhall ==0.1.0.0`
(`Settei.Dhall.loadDhallSource`, `Settei.Dhall.dhallSourceOptions`,
`Settei.Dhall.NoImports`, `Settei.Dhall.DhallFile`); `settei-env ==0.1.0.0`
(`Settei.Env.envSnapshot`, `Settei.Env.envSource`); the example libraries
`settei-example-service` (`Settei.Example.Service.serviceConformanceConfig`,
`serviceConfig`, `environmentBindings`) and `settei-example-cli`; and `tasty`/`tasty-hunit`
for the test tree.

Interfaces that must exist at the end of Milestone 1, all in
examples/settei-conformance/test/Settei/Example/ConformanceTest.hs: three new `testCase`
entries in the "Conformance" group and one extended or new sentinel case in the
"Security" group, plus whatever small helpers they need (a
`loadFailureSources :: IO FixtureSources`-style loader reusing the `FixtureSources`
record, and a widening of `normalizeReport` usage to the EP-12 failure container). No
signatures are exported; the module's only consumer is test/Main.hs.

External tools relied on, and why: the Nix development shell from flake.nix (pins GHC
9.12.4 and Cabal 3.16.1.0 per docs/compatibility.md — every command runs through `nix
develop -c` so validation happens on the release toolchain, not the host's GHC 9.10);
treefmt via `nix fmt` (fourmolu + cabal-fmt + nixpkgs-fmt, configured in nix/treefmt.nix
and fourmolu.yaml); and `git` for the commit protocol with the mandatory MasterPlan /
ExecPlan / Intention trailers listed in Concrete Steps.

Documents this plan owns during implementation (writable then, though only this plan file
is written at authoring time): README.md, docs/compatibility.md, docs/security.md,
docs/release-checklist.md, the six package CHANGELOG.md files, docs/adr/0003 through
0006 (verification and gap-filling of the child plans' amendments, plus any new ADR from
the promotion pass), the parent MasterPlan file, and the living sections of the five
child plan files. The manual publication steps at the bottom of docs/release-checklist.md
(tagging, signing, Hackage upload) remain out of scope and unauthorized, exactly as the
checklist states.


## Revision Note

2026-07-19: Implemented the plan, recorded every release-gate transcript and collateral
decision in the living sections, distilled the conformance-boundary rule into ADR 0007,
and marked EP-14 complete after closing the parent MasterPlan.
