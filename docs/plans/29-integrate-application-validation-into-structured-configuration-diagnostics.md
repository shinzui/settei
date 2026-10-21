---
id: 29
slug: integrate-application-validation-into-structured-configuration-diagnostics
title: "Integrate application validation into structured configuration diagnostics"
kind: exec-plan
created_at: 2026-10-21T14:11:22Z
intention: "intention_01m5fctnd8ezea1sejjpxss6bg"
provenance:
  created_by:
    model: "claude-fable-5-1"
    harness: "claude-code"
    at: 2026-10-21T14:11:22Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-21T14:33:14Z
      mode: "update"
      note: "Validate against current APIs and ADRs; fix opaque collection instances, diagnostic acceptance, sentinel coverage, migration details, and closure sequencing."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-21T14:37:38Z
      verdict: "approved"
      note: "Updated plan is implementable against current core, adapter, example, IR-4, and ADRs; three baseline test suites and all four bundle checks pass. Feature acceptance remains pending implementation."
---

# Integrate application validation into structured configuration diagnostics


This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan implements improvement request IR-4,
docs/improvement-requests/integrate-application-validation-into-structured-diagnostics.md.
Its five acceptance criteria (AC-1 through AC-5) are the acceptance obligations of this
plan; each milestone below names the criteria it discharges.


## Purpose / Big Picture


Settei is a Haskell configuration library. An application declares its settings once as
a `Config a` value, and `resolve` turns ordered sources (files, environment variables,
command-line flags) into a typed value plus a **resolution report**: a secret-safe trace
of which source won each setting, which candidates were shadowed, which defaults fired,
and which conditional branches ran. Every per-setting rule lives in a decoder, and every
decoder failure is a structured `ConfigError` that the library can render as operator
text or as versioned JSON with a stable `kind`.

Rules that relate several settings have no home today. The originating consumer, the
notification-hub service (`mori://tan/notification-hub`), checks after resolution that a
worker's visibility timeout covers its concurrency, that a job pool is large enough, that
a replica index is below the replica count, and that every email account has a
credential. Those checks are pure functions over the typed configuration that return
`Either Text ()`. Their failures are printed as free text, exit with the same code as a
resolution failure, bypass the explain report, and cannot be consumed as structured JSON.
A deployment tool that wants to know *which rule* failed and *which settings* it concerns
has to parse English.

After this plan, Settei ships a validation stage that applications declare next to their
configuration and run on the typed value. Each **validator** is a named, pure rule that
says up front which declared setting keys it inspects and what it expects. Running the
validators on a resolved configuration produces a **validated result** that carries the
unchanged resolution report, the warnings, a per-rule outcome trace, and either the typed
value or structured **invariant** failures. An invariant failure is an ordinary
`ConfigError`, so the existing text and JSON renderers, the explain modes, check mode,
and the exit-code discipline all treat it like a missing or malformed value. The failure
retains only the rule identifier, the declared keys, the declared expectation, and an
optional author-supplied detail; it never retains the configuration record, raw input, or
a derived `Show` of the typed value.

From the repository root, once this plan and plan 26's deployment example are
implemented, a worker whose visibility timeout cannot cover its concurrency is rejected
like this (environment variables stand in for the container's proposed inputs):

```bash
nix develop -c cabal build exe:settei-example-deployment-worker
deployment_worker=$(nix develop -c cabal list-bin exe:settei-example-deployment-worker)
env -i ENVIRONMENT=production DATABASE_URL=postgres://db.invalid/hub \
  WEBHOOK_SECRET=a-sufficiently-long-production-secret \
  DELIVERY_ENDPOINT=http://delivery.production.internal:8080 \
  EMAIL_CREDENTIALS_JSON='{"sendgrid":"placeholder"}' \
  WORKER_VISIBILITY_TIMEOUT_SECONDS=1 \
  "$deployment_worker" --explain-config-json
printf 'exit %s\n' "$?"
```

Build and locate the executable first so build-tool messages are separate from its
streams. `env -i` supplies only the fixture inputs, avoiding inherited overrides. The
executable prints nothing on stdout, exits `4`, and prints two JSON documents to stderr,
one per line (the following `printf` reports its exit code separately on stdout). The
first is the `settei.errors` document, whose only entry has
`"kind":"invariant"`, `"rule":"worker-visibility-covers-concurrency"`, and
`"keys":["workers.visibilityTimeoutSeconds","workers.concurrency"]`. The second is the
`settei.resolution` document with every setting's winning origin (the timeout's origin
has kind `environment` and annotation `environment.variable` equal to
`WORKER_VISIBILITY_TIMEOUT_SECONDS`) and a new `invariants` array
listing each rule the worker role declares with its status. With `--explain-config`
instead, the same run prints one error line, the text report, and one `invariant …` line
per rule. With `--check-config` it prints the error line only and still exits `4`; the
message `configuration valid` can no longer be printed before validation has run, because
check mode now consumes the validated result.


## Progress


- [ ] Milestone 1 — Core validation mechanism (AC-1, AC-3, AC-4 at the library
      boundary): the new public module `Settei.Validate`, the `InvariantError`
      constructor of `ConfigError`, the `ValidationReport` types in `Settei.Report`, and
      the `renderValidationText` and `renderValidatedResolutionJson` renderers exist, the
      umbrella `Settei` module re-exports the new module, and
      `nix develop -c cabal test settei-tests --test-show-details=direct` passes with the
      new `Settei.ValidateTest` group (notification-hub-shaped rules, construction
      rejections, accumulation, prerequisite skipping, not-run after failed resolution,
      role lists, sentinel scans, determinism, and goldens) while every existing golden
      stays byte-identical.
- [ ] Milestone 2 — Diagnostic integration (AC-2 at the adapter boundary):
      `Settei.Optparse.validatedDiagnostic` turns one validated result into a failure
      text, a diagnostic output, or a continue-with-value decision for every
      `DiagnosticMode`; the settei-optparse-applicative suite passes with the cases that
      prove check mode cannot succeed before validation and that text and JSON explain
      output carry the rule, keys, provenance, and outcome trace.
- [ ] Milestone 3 — Migration of the notification-hub-shaped example (AC-2 at the
      application boundary, AC-4 role lists, AC-5; requires plan 26 through its
      Milestone 4): `examples/settei-deployment` replaces its plain-text server and
      worker checks (`checkServer`, `checkWorker :: DeploymentConfig -> [Text]`) with
      role-specific `Validators` built from shared validator values,
      consumes `validatedDiagnostic` in every mode, and its suite proves unchanged typed
      values and unchanged accept/reject outcomes for the plan 26 fixture matrix, the
      structured failure in text and JSON explain modes, the retained provenance, and
      the absence of secret sentinels; `nix develop -c cabal test
      settei-example-deployment-tests --test-show-details=direct` passes.
- [ ] Milestone 4 — Documentation, collateral, and request lifecycle (AC-3 author
      contract, AC-5 versioning): a new ADR plus an ADR-3 amendment, a new capability
      record plus CAP-3 and CAP-7 updates, guide sections, security and compatibility
      updates, changelogs with the PVP consequences, and IR-4 still `in-progress`;
      every OKF bundle passes its prescribed profile-enforced validation.
- [ ] Milestone 5 — Full validation and closure: `cabal build all`, `cabal test all`,
      `treefmt`, the four `okf validate` commands, and `nix flake check` pass; evidence
      recorded here; Outcomes & Retrospective written; ADR distillation done; IR-4
      moved to `completed` only after those gates pass and its bundle revalidated.


## Surprises & Discoveries


- Validation evidence (2026-10-21): ADR-10 deliberately omits `Generic` from an
  opaque validated collection because generic conversion bypasses its smart constructor.
  Apply that same restriction to `Validators`; constructor privacy alone is insufficient.
  A raw sentinel containing quotes and newlines also cannot detect its JSON-escaped or
  `Show`-escaped form. The tests below scan a unique plain-ASCII marker within the
  adversarial sentinel as well as the complete raw sentinel.
- Validation evidence (2026-10-21): plan 26's core cycle helper and deployment example
  are now tracked, and its Milestones 1–5 are checked. Baseline core, optparse, and
  deployment suites pass; core reports 122 tests and deployment reports 15. All four
  prescribed OKF validations pass (12 ADRs, 11 guides, 14 capabilities, 4 requests).
  These are pre-implementation checks, not acceptance of this plan's new feature.
- Planning evidence (2026-10-21): plan 26 is being implemented in this working tree
  concurrently. At planning time `git status` showed uncommitted changes that add
  settei/src/Settei/Contract.hs and settei/src/Settei/Internal/DefaultValidation.hs and
  move `validateDefaultCycles` and `defaultRule` out of settei/src/Settei/Resolve.hs into
  that internal module. This plan therefore imports the shared module instead of moving
  the cycle walk itself; if the module is absent when Milestone 1 starts, create it with
  exactly the two exports plan 26 specifies and record that here.
- Planning evidence (2026-10-21): both reference applications and both notification-hub
  processes print resolution failures as *text* in every mode, including
  `--explain-config-json`, and append the JSON report after the text errors. The only
  structured failure document, `renderErrorsJson`, has no application consumer today.
  That gap is why Milestone 2 defines a mode-aware failure policy inside
  `validatedDiagnostic` rather than leaving each application to assemble it.
- Planning evidence (2026-10-21): while this plan was being written, plan 26's
  Milestone 4 landed in the working tree (uncommitted). The example's checks are
  `checkServer, checkWorker :: DeploymentConfig -> [Text]`, returning zero or more
  rejection lines, rather than the `Either Text ()` shape the consumer uses and plan 26's
  prose described; the dispatch selects one by role and maps a non-empty list to exit
  `4`. The migration in Milestone 3 therefore starts from a list-of-text check, which is
  still "a failure that currently returns plain Text after resolution" (AC-5).


## Decision Log


- Decision: Validation lives in the core `settei` package as a new public module
  `Settei.Validate`, re-exported by `Settei`, and an application invariant failure is a
  new constructor `InvariantError !InvariantProblem` of the existing `ConfigError` type.
  Rationale: IR-4 asks that startup, check mode, and both explain modes reject invariant
  failures exactly as they reject source and decode failures. Making the failure a
  `ConfigError` means `renderErrorsText`, `renderErrorsJson`, the exit-code discipline of
  docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md, and
  every consumer that already matches on `Left errors` handle it with no new code path.
  Adding a constructor breaks exhaustive matches on `ConfigError`; that is accepted under
  the experimental 0.x policy and recorded as a major PVP bump in settei/CHANGELOG.md,
  as plan 26 does for `DiagnosticMode`. The rejected alternative, a separate failure type
  and a parallel set of renderers, would give the fleet two failure vocabularies.
  Date: 2026-10-21

- Decision: `validate :: Validators a -> ResolveResult a -> ValidatedResult a` is pure
  and total. `ValidatedResult` carries `answer`, `report`, `warnings`, and a new
  `validation :: ValidationReport`. Totality assumes finite, total author-supplied
  validators; the pure API does not catch exceptions or terminate divergent code.
  Validators run only when `answer` is `Right`; when
  resolution failed, the errors, report, and warnings are returned unchanged and every
  rule is reported as not run, without forcing any validator function. `resolve`,
  `ResolveResult`, `describe`, and the `Config` algebra are not changed.
  Rationale: IR-4 requires that validators apply only when a typed configuration is
  available, that the resolution provenance report survives a validation failure, and
  that the inspectable declaration algebra keeps its source-free describe behaviour with
  no `Monad` instance. A separate record keeps `resolve` honest about what it did and
  lets applications without cross-setting rules keep using `ResolveResult` untouched.
  Date: 2026-10-21

- Decision: A validator is declared with `invariant rule keys expectation run`, where
  `rule :: InvariantRule` is a stable identifier, `keys :: [Key]` names the declared
  settings the rule inspects, `expectation :: Text` is fixed at declaration time, and
  `run :: a -> [Violation]` is a pure function returning zero or more violations. `check`
  is sugar for a boolean rule. `requires` attaches prerequisite rule names. `validators
  config list` validates the whole list against `describe config` and returns an opaque
  `Validators a` or structured `ValidatorError`s: an invalid or duplicated rule
  identifier, an empty key list, a key that no declaration in `config` can request, a
  prerequisite that is not an earlier rule in the same list, or a default cycle in the
  declaration (detected with the shared cycle walk before `describe` is called, since
  `describe` does not terminate on a cyclic declaration). Validators run in declaration
  order; every validator whose prerequisites all passed runs, and failures accumulate in
  declaration order with violations in the order the function returned them; a
  validator with a failed, skipped, or not-run prerequisite is skipped and the outcome
  names the unmet prerequisites. Role applicability needs no mechanism: an application
  builds one `Validators` value per process role from shared `Validator` values.
  Rationale: AC-1 requires stable identifiers, references to declared keys, and explicit
  handling of invalid references; checking the keys at construction makes an invalid
  reference a static programming error, mirrors the construction-time validation of
  docs/adr/0010-validate-environment-bindings-at-construction.md, and makes a runtime
  reference to an undeclared key impossible, because a failure always carries the
  validator's declared keys. AC-4 requires defined ordering, accumulation versus
  fail-fast, and role applicability; declaration order plus explicit prerequisites gives
  independent rules full accumulation and dependent rules an honest skip, and
  restricting prerequisites to earlier rules makes the dependency graph acyclic by
  construction with no second ordering rule to explain. The originating consumer's
  `validateWorkerCapacity` is a do-block that stops at the first failure; under this
  design its independent lease bounds become three accumulating rules while its
  registry-dependent pool check becomes a rule that `requires` the safe-mode rule.
  Date: 2026-10-21

- Decision: Secret safety is structural first and contractual second. `Validator`,
  `Validators`, and `ValidatedResult` have no `Show` or `Eq` instances. `Validator` and
  `Validators` also have no `Generic` instance or exported constructor; in particular,
  `Validators` must not expose a generic conversion or writable optic that bypasses
  `validators`, following ADR-10. A failure retains
  only `rule`, `keys`, `expectation`, and `detail :: Maybe Text`. The expectation is fixed
  at declaration time, so the common path does not need value interpolation. All
  author-supplied metadata (including rule names, keys, expectations, and details) must
  be safe to publish; a fixed `Text` is not proof of safety if an author constructed it
  from a secret. `detail` is the explicit per-run text channel; it exists for public
  labels such as an account or pool name and is produced by `violationWithDetail`, whose documentation states that the
  author must not embed the value of any setting declared `Secret` and that Settei does
  not and cannot sanitise it. The guide, docs/security.md, and the capability record
  repeat that contract and recommend referencing keys instead of interpolating values.
  Rationale: IR-4 says a custom validator can deliberately leak and that the library must
  not claim automatic sanitisation; the design minimises accidental leakage by making
  the leak-capable channel a separate, named, documented constructor rather than the
  default path, in keeping with the redaction-before-retention rule of
  docs/adr/0003-resolution-provenance-and-default-semantics.md.
  Date: 2026-10-21

- Decision: Rendering is additive to the version-1 documents. `renderErrorsText` renders
  an invariant failure as one line `KEYS: invariant RULE failed: EXPECTATION` with an
  optional ` (DETAIL)` suffix; `renderErrorsJson` emits `{"kind":"invariant","rule":…,
  "keys":[…],"expectation":…,"detail":…}` inside the unchanged `settei.errors` document.
  `renderValidationText` emits one block per rule (`invariant RULE [STATUS]: KEYS`, an
  indented `expects …` line, and an indented `after …` line when prerequisites exist).
  `renderValidatedResolutionJson report validation` emits the `settei.resolution`
  document with a trailing `invariants` array; `renderResolutionJson` stays byte-identical
  so the existing goldens and every consumer of a bare report are untouched, and a
  consumer treats `invariants` as an optional field. Check mode keeps printing exactly
  `configuration valid\n`.
  Rationale: docs/adr/0003-resolution-provenance-and-default-semantics.md allows version
  1 documents to gain additive fields and requires a new version only for a breaking
  representation change. One JSON document per explanation lets a tooling consumer parse
  once and join rule keys to the report's nodes for winning-source provenance (AC-2).
  Keeping the check-mode message byte-identical preserves plan 28's harness
  expectations and the cookbook's init-container gate.
  Date: 2026-10-21

- Decision: `Settei.Optparse` gains `validatedDiagnostic :: DiagnosticMode ->
  ValidatedResult a -> ValidatedDiagnostic a` with constructors `DiagnosticFailure Text`
  (render to stderr and exit with the resolution code), `DiagnosticOutput Text` (print to
  stdout and exit 0), and `DiagnosticContinue a` (no diagnostic requested; start the
  application with the typed value). On failure it renders, for `ExplainText`, the error
  lines followed by the text report and the validation lines; for `ExplainJson`, the
  `settei.errors` document and the validated `settei.resolution` document, one per line;
  and for every other mode, the error lines only. `resolutionDiagnostic` is retained
  unchanged for applications that declare no validators.
  Rationale: IR-4 asks that one validated result feed every mode and that a successful
  check-mode message never precede application validation; a helper that takes the
  validated result and decides failure, output, or continue in one place makes the
  ordering structural. A JSON mode that prints text errors is useless to the deployment
  tooling IR-4 serves, and the reference applications never used `renderErrorsJson`;
  defining the policy once in the adapter keeps the fleet consistent, while
  applications still own stdout/stderr routing, warnings, and exit codes as CAP-7
  documents.
  Date: 2026-10-21

- Decision: The migration example is plan 26's notification-hub-shaped application,
  examples/settei-deployment, and Milestone 3 requires plan 26 to have landed through
  its Milestone 4 with the plain-text server and worker checks it specifies (landed as
  `checkServer, checkWorker :: DeploymentConfig -> [Text]`). The
  role assignment is kept exactly as plan 26 designed it (server: webhook secret length;
  worker: visibility timeout versus concurrency, and the development webhook default in
  production), so no fixture changes its accept or reject outcome. The CLI and
  Kubernetes service examples are not migrated because they declare no cross-setting
  rule. The wording of invariant rejection lines and the JSON explain failure stream both
  change; document those changes in the example's README and changelog as the
  compatibility path.
  Rationale: AC-5 requires moving an existing post-resolution check that returns plain
  text, without duplicating rules, changing successful typed values, or weakening
  rejection. Plan 26's example reproduces the consumer's shape in miniature and is the
  reference application that docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md
  (as amended by plan 26) admits to the conformance boundary. If plan 26 has not reached
  Milestone 4, record that prerequisite before migration; do not build plan 26's checks
  directly on
  `Settei.Validate`, because the migration itself is this plan's deliverable.
  Date: 2026-10-21

- Decision: Out of scope, needing a scope decision before becoming acceptance: listing
  validators inside the describe modes or the `settei.schema` and `settei.contract`
  documents; a standalone `settei.validation` document; a conformance-suite case (the
  deployment example is the conformance-boundary host); a contravariant or focusing
  combinator for validators; running validators from IR-1's contract export; and
  teaching plan 28's preflight harness to parse the JSON this plan emits (IR-3 treats
  application output as opaque).
  Rationale: each item widens the public contract beyond IR-4's five criteria.
  Date: 2026-10-21


## Outcomes & Retrospective


(To be filled during and after implementation.)


## Context and Orientation


### Validation of the request


IR-4 was checked against the working tree and the registered consumer before this plan
was written, and it fits. The seams it needs already exist: `resolve` in
settei/src/Settei/Resolve.hs returns a total `ResolveResult` whose `answer` is `Either
(NonEmpty ConfigError) a` and whose `report` and `warnings` survive failure (plan 12);
`ConfigError` in settei/src/Settei/Error.hs is the single closed failure type that
`renderErrorsText` and `renderErrorsJson` in settei/src/Settei/Render.hs render and that
every application maps to exit code `4`; and `describe` in settei/src/Settei/Config.hs
yields the schema whose possible keys a validator can be checked against without loading
a source. The consumer's checks are exactly the shape IR-4 describes. In
`mori://tan/notification-hub`, the workers' `NotificationHub.Workers.Config` runs
`validateWorkerCapacity :: RuntimeConfig -> Either Text ()` after `resolveRuntimeConfig`
and before `resolutionDiagnostic`; it checks three lease bounds (visibility timeout
against concurrency, inbox size, and HTTP timeout), two paced bounds against the governor
floor rate, a production-only fan-out hook, the replica index against the count, the job
pool size through the registry settings, and the email accounts against their credentials
and pools, stopping at the first failure and returning a message that interpolates
public numbers. The server's `NotificationHub.Server.Config` runs
`runtimeSendGridEventKeys` the same way for event-webhook public keys. Both map a failure
to exit `4` with the text and a trailing newline, and both print the explain report only
for resolution failures, never for these. Nothing in this plan modifies the consumer.

### What exists today in this repository


- settei/src/Settei/Resolve.hs: `ResolveResult a` (`answer`, `report`, `warnings`),
  `ResolveOptions`, `resolve`. At planning time the uncommitted plan 26 work imports
  `validateDefaultCycles` and `defaultRule` from
  settei/src/Settei/Internal/DefaultValidation.hs, a private module whose only job is the
  cycle walk that must run before `describe` can be called safely.
- settei/src/Settei/Error.hs: the problem records and `ConfigError` with seven
  constructors (`MissingRequired`, `DecodeError`, `StructuralConflict`,
  `UnknownKeyError`, `DefaultError`, `DefaultCycle`, `SensitivityConflict`), all safe to
  show, plus `ConfigWarning`.
- settei/src/Settei/Report.hs: `ResolutionReport`, `ResolutionNode`, `ResolutionOutcome`,
  `BranchTrace`, `Derivation`, and the accessors `reportNodes` and `reportBranches`.
- settei/src/Settei/Render.hs: the text renderers, the private deterministic JSON
  encoder (`versionedJson`, `jsonObject`, `jsonArray`, `jsonString`, `jsonKeyArray`), and
  the `errorJson` cases whose `kind` spellings are the vocabulary tooling consumes.
- settei/src/Settei/Schema.hs: `schemaPossible :: Schema -> [SchemaSetting]` and
  `schemaSettingKey`, which this plan uses to validate declared keys.
- settei/src/Settei.hs: the umbrella module; at planning time it already re-exports
  plan 26's `Settei.Contract`.
- settei/test/Settei/RenderTest.hs and settei/test/Settei/ResolveTest.hs: the test style
  (tasty with HUnit, `expectAnswer`, `expectFailure`, `assertGolden`, the family's
  `secretSentinel` containing quotes, backslashes, a newline, and non-ASCII text, and
  `validKey`). settei/test/Main.hs lists the groups.
- settei-optparse-applicative/src/Settei/Optparse.hs: `DiagnosticMode`,
  `diagnosticModeOptions`, `schemaDiagnostic`, and `resolutionDiagnostic ::
  DiagnosticMode -> ResolveResult a -> Maybe Text`, which returns `configuration
  valid\n` for `CheckConfig` without looking at `answer`. Plan 26 adds the
  `DeploymentContractText` and `DeploymentContractJson` constructors and
  `contractDiagnostic` to the same module.
- examples/settei-cli/src/Settei/Example/Cli.hs and
  examples/settei-service/src/Settei/Example/Service.hs: the reference applications and
  the dispatch pattern every application follows: `schemaDiagnostic`, load, `resolve`,
  match `answer`, render errors plus a `failureReport` in explain modes, or
  `resolutionDiagnostic` on success. Both keep `usageExitCode = 2`, `sourceExitCode = 3`,
  and `resolutionExitCode = 4`.
- docs/plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md
  (in progress) defines examples/settei-deployment: library module
  `Settei.Example.Deployment` with `data Role = Server | Worker`, `deploymentConfig ::
  Config DeploymentConfig`, keys `runtime.environment`, `database.url`,
  `database.poolSize`, `server.host`, `server.port`, `server.webhookSecret`,
  `workers.deliveryEndpoint`, `workers.concurrency`, `workers.visibilityTimeoutSeconds`,
  `telemetry.serviceName`, and `email.credentials`, exported pure checks `checkServer,
  checkWorker :: DeploymentConfig -> [Text]` (each returned line is one rejection, for
  example `server.webhookSecret: must be at least 16 characters`),
  `runDeploymentWithSnapshot :: Role -> EnvSnapshot -> DeploymentOptions -> IO
  DeploymentRun`, `runDeploymentWithEnvironment`, the dispatch order
  `schemaDiagnostic`, `contractDiagnostic`, load, resolve, the role's check,
  `resolutionDiagnostic`, and a test suite whose fixture matrix includes a complete
  production snapshot, a five-character `WEBHOOK_SECRET`, and
  `WORKER_VISIBILITY_TIMEOUT_SECONDS=1`. At planning time the package existed
  uncommitted in the working tree at examples/settei-deployment/src/Settei/Example/Deployment.hs.
  Follow the landed code if names differ when Milestone 3 starts and record the
  difference in Surprises & Discoveries.
- docs/plans/27-validate-supplied-environment-variable-names-against-declared-bindings.md
  and docs/plans/28-provide-a-reusable-deployment-preflight-harness-around-application-check-mode.md
  (unimplemented) do not touch the files this plan edits, except that plan 27 amends
  docs/adr/0009-adapter-error-rendering-contract.md and plan 28 allocates documentation
  handles; see "Relationship to concurrent work".
- docs/guides/cli-application.md (DOC-2) documents the diagnostic modes and exit codes;
  docs/guides/getting-started.md ends with "Use the typed result and diagnostics";
  docs/capabilities/secret-safe-diagnostics.md (CAP-3) and
  docs/capabilities/configuration-diagnostic-options.md (CAP-7) describe the renderers
  and the diagnostic helpers; docs/security.md and docs/compatibility.md list the
  guarantees and the public modules.
- mori.dhall registers the OKF bundles: docs/adr (handles `ADR-N`, profile
  docs/adr/profile.dhall), docs/guides (`DOC-N`, profile
  mori/user-documentation-profile.dhall), docs/capabilities (`CAP-N`), and
  docs/improvement-requests (`IR-N`). flake.module.nix's pre-commit hook runs the four
  `okf validate` commands repeated under Concrete Steps.

### Terms used in this plan


An **invariant** is a rule that relates one or more resolved settings and that no single
decoder can express, such as "the visibility timeout must be at least twice the
concurrency". A **validator** is one declared invariant: a stable identifier, the
declared keys it inspects, a fixed expectation sentence, optional prerequisites, and a
pure function from the typed configuration to a list of violations. A **violation** is
one failing instance of a rule, optionally carrying a detail label. A **validators
collection** (`Validators a`) is an ordered list of validators that has been checked
against a declaration. A **validated result** is a resolution result after the
validators ran, or after they were skipped because resolution failed. An **outcome** is
what happened to one validator in one run: passed, failed with a violation count,
skipped because of unmet prerequisites, or not run. A **process role** is the label of
the process being configured, such as `server` or `worker`; roles differ in which
validators they declare. The **author contract** is the documented responsibility of
whoever writes a validator: never put the value of a secret setting into a detail.

### Relationship to concurrent work


Plans 26, 27, and 28 were authored on the same day and are in various states of
implementation. Files that more than one plan edits, and how to merge: settei/src/Settei.hs
(each plan adds one re-export line); settei/settei.cabal (each adds its own modules);
settei/src/Settei/Render.hs (plan 26 adds contract renderers, this plan adds validation
renderers and one new case in each error renderer; preserve both plans' changes to
shared JSON helpers); settei/src/Settei/Error.hs
(only this plan adds a constructor); settei-optparse-applicative/src/Settei/Optparse.hs
(plan 26 adds two `DiagnosticMode` constructors and `contractDiagnostic`; this plan adds
`validatedDiagnostic`, whose `case` must treat plan 26's constructors like the describe
modes); settei/CHANGELOG.md and settei-optparse-applicative/CHANGELOG.md (append bullets
under one `## Unreleased` heading); the OKF indexes and logs (append). Documentation
handles are allocated with `okf id next` at the moment of creation. On 2026-10-21 the
next free handles were `ADR-12`, `DOC-11`, and `CAP-14`; plan 26 expects to take
`ADR-12`, `DOC-11`, and `CAP-14`, and plan 28 expects `ADR-13`, `DOC-12`, and `CAP-15`,
so this plan most likely allocates `ADR-14` and `CAP-16`. Never derive a handle by
counting; re-run the command.

### Relevant architecture decisions


- [docs/adr/0002-inspectable-configuration-algebra.md](../adr/0002-inspectable-configuration-algebra.md): `Config` is a private GADT with no
  `Monad` instance so that complete static inspection is possible. Validators run over
  the typed value *after* interpretation and add no syntax node; `describe` and the
  schema documents are unchanged.
- [docs/adr/0003-resolution-provenance-and-default-semantics.md](../adr/0003-resolution-provenance-and-default-semantics.md): redaction happens
  before data enters a report or structured error; reports never contain application
  values; JSON documents are compact, deterministic, version 1, emitted without Aeson,
  and may gain additive fields. This plan's failure record retains metadata only, its
  `invariant` kind and `invariants` array are additive, and Milestone 4 amends this ADR
  to record both and the rule that `ConfigError` may grow a constructor per failure
  family under a major bump.
- [docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md](../adr/0007-reference-applications-are-the-public-api-conformance-boundary.md):
  every public capability is exercised by an internal reference application;
  `--check-config` prints `configuration valid` and keeps the 2/3/4 exit discipline.
  Plan 26's amendment admits the deployment example, which hosts this plan's migration.
- [docs/adr/0009-adapter-error-rendering-contract.md](../adr/0009-adapter-error-rendering-contract.md): one operator-readable line per
  problem; plural renderers are the singular mapped over `NonEmpty` and joined with
  `Text.unlines`; renderers concatenate only retained fields. The `ValidatorError`
  renderers and the invariant error line follow that shape.
- [docs/adr/0010-validate-environment-bindings-at-construction.md](../adr/0010-validate-environment-bindings-at-construction.md): validate once at
  construction into an opaque collection and report every problem. `validators` follows
  the same pattern for rule identifiers, keys, and prerequisites.
- [docs/adr/0001-haskell-project-conventions.md](../adr/0001-haskell-project-conventions.md): `GHC2024`, the shared `common common`
  stanza, strict record fields, explicit deriving strategies, generic-lens labels, and
  no lens type in a public signature.

No existing ADR covers post-resolution application validation, invariant failures, or
validator sequencing; Milestone 4 creates one.


## Plan of Work


### Milestone 1 — Core validation mechanism


Scope: the library boundary. At the end, a Haskell caller can declare validators next to
a `Config`, check them against the declaration, run them on a resolved result, and
render the outcome as text and JSON, with every guarantee proven by the core suite.

Add `InvariantRule`, `renderInvariantRule`, `InvariantProblem`, and the `InvariantError`
constructor to settei/src/Settei/Error.hs. Add `InvariantStatus`, `InvariantOutcome`,
`ValidationReport`, and `validationOutcomes` to settei/src/Settei/Report.hs (it may
import `Settei.Error` for `InvariantRule`; `Settei.Error` must not import
`Settei.Report`). Create settei/src/Settei/Validate.hs with the types and functions
listed under Interfaces and Dependencies; it imports `Settei.Internal.DefaultValidation`
for the cycle walk, `Settei.Config` for `describe`, `Settei.Schema` for the possible
keys, `Settei.Resolve` for `ResolveResult`, and `Settei.Report`. Its module header is the
author contract: what a validator may compute, that `expectation` is fixed at
declaration, that `detail` is for public labels only and must never carry the value of a
`Secret` setting, that all metadata must be safe to publish, that functions must be
total and return finite lists, and that Settei cannot sanitise
author-supplied text. Extend settei/src/Settei/Render.hs with the `InvariantError`
cases of `renderErrorText` and `errorJson`, `renderValidationText`, and
`renderValidatedResolutionJson` (reuse `versionedJson` with the existing `nodes` and
`branches` fields followed by `invariants`). Re-export `Settei.Validate` from
settei/src/Settei.hs. In settei/settei.cabal add `Settei.Validate` to the library
`exposed-modules` and test-suite `other-modules`, and add `Settei.ValidateTest` to
the latter. The existing `test/golden/*.json` and `test/golden/*.txt`
`extra-source-files` globs already include the new goldens.

`validators config list` proceeds in this order and collects every problem rather than
stopping at the first: run `validateDefaultCycles config` and turn each `DefaultCycle`
problem into `CyclicDeclaration`; compute the possible keys from `describe config` only
when no cycle was found, and otherwise omit key-membership checks while still checking
rule names, empty key lists, and prerequisites. Cycle errors precede validator errors.
Then, for each validator in list order, check the rule spelling
(non-empty, no whitespace, no control characters), duplicate rule names (reported at the
second occurrence), an empty key list, every key against the possible keys, and every
prerequisite against the rules declared *earlier* in the list (a self-reference or a
later rule is `UnknownPrerequisite`). `runValidators` walks the list in order with a map
from rule to status: a validator whose prerequisites are all `InvariantPassed` runs and
yields `InvariantPassed` or `InvariantFailed n` plus `n` problems, each carrying the
validator's rule, keys, expectation, and the violation's detail; otherwise it is
`InvariantSkipped` with the unmet prerequisites in their attached list order and its
function is never applied. `requires` appends prerequisites, removes duplicates while preserving
first occurrence, and composes additively across repeated calls. Outcomes preserve that
order for `prerequisites` and `blockedBy`. `check` returns no violations when its predicate
is true and `[violation]` otherwise; `violation` has no detail. Empty validator collections
are valid and yield an empty report.

`validate` applies `runValidators` on `Right value`: no problems preserves `Right value`,
and a non-empty problem list becomes `Left (fmap InvariantError problems)` in the same
order. Both cases preserve the original resolution report and warnings exactly. On
`Left`, retain the input errors, report, and warnings and put `describeValidators` in
the `validation` field. `describeValidators` lists every validator with `InvariantNotRun`.
Use the collection with the same declaration that produced the resolution result; the
type parameter alone cannot prove two `Config a` values describe the same keys.
Conditional keys are valid references, and authors must handle optional fields in their
total functions; declaration membership does not imply a key ran on this path.

The validation text block for one outcome is `invariant RULE [STATUS]: KEY1, KEY2` on the
first line, then `  expects EXPECTATION`, then `  after RULE1, RULE2` only when the
validator has prerequisites, where STATUS is `passed`, `failed (N violation)` or `failed
(N violations)`, `skipped after RULE1, RULE2`, or `not run`. The JSON entry is
`{"rule":…,"keys":[…],"expectation":…,"prerequisites":[…],"status":"passed"|"failed"|
"skipped"|"not-run","violations":N,"blockedBy":[…]}` with `violations` `0` and
`blockedBy` `[]` unless applicable. The invariant error line is `KEY1, KEY2: invariant
RULE failed: EXPECTATION` with ` (DETAIL)` appended when a detail exists; its JSON object
is `{"kind":"invariant","rule":…,"keys":[…],"expectation":…,"detail":null|"…"}`.
`renderValidatorErrorText` emits one line per construction problem naming only the rule,
key, prerequisite, or cycle-rule path involved. Escape control characters in invalid
rule names so a rejected newline cannot create an extra diagnostic line. The author
contract requires expectations and details used in line-oriented text to be single-line.
`renderValidatorErrorsText` is the singular mapped
over `NonEmpty` and joined with `Text.unlines`.

Write settei/test/Settei/ValidateTest.hs and register it in settei/test/Main.hs. The
fixture is a notification-hub-shaped declaration `hubConfig :: Config HubConfig` with
public keys `runtime.environment` (enum `development`/`production`), `database.poolSize`,
`workers.jobPoolSize`, `workers.concurrency`, `workers.visibilityTimeoutSeconds`,
`workers.replica.index`, `workers.replica.count`, `email.accounts` (a list of account
names), and secret keys `database.url` and `email.credentials` (a list of
`NAME:TOKEN` entries wrapped in a type without `Show`). Declare, in this order:
`pool-capacity` over `workers.jobPoolSize` and `workers.concurrency` (pool at least the
concurrency); `visibility-timeout` over `workers.visibilityTimeoutSeconds` and
`workers.concurrency` (timeout at least twice the concurrency); `replica` over
`workers.replica.index` and `workers.replica.count` (index non-negative and below the
count); `replica-pool-share` over `workers.jobPoolSize` and `workers.replica.count`,
with `requires [replica]` (pool at least the replica count); and `provider-account` over
`email.accounts` and `email.credentials`, which extracts the name before the first colon
of each credential and emits `violationWithDetail ("account " <> quoted name)` for each
account without one, never touching the token. Build `workerValidators` from all five
and `serverValidators` from `provider-account` alone; sources are built with the
existing test helpers (`sourceFromPairs` or a `RawObject` tree) so every test is pure.

Required cases: empty validator collections pass without changing the typed answer;
repeated `requires` calls accumulate distinct prerequisites in first-occurrence order;
multiple blocked prerequisites are reported in that order, including one transitively
skipped prerequisite; every `ValidatorError` kind (an empty rule, a rule with a space or
control character, a duplicate rule, an empty key list, the key `nothing.here`, a prerequisite naming a later
rule, a self-prerequisite, and the mutually recursive declaration from
settei/test/Settei/DefaultTest.hs) with the rendered line naming the offender; a
complete valid configuration passes every rule, `answer` is `Right`, and every outcome is
`InvariantPassed`; a configuration that breaks `pool-capacity`, `visibility-timeout`, and
`provider-account` for two accounts yields four `InvariantError` problems in declaration
order, the correct `InvariantFailed` counts, and `detail` for the account rule only; a
configuration that breaks `replica` reports `replica-pool-share` as `InvariantSkipped
(replica :| [])` while its function is an `error` thunk that is never forced; resolving
with `workers.concurrency` absent then validating leaves `answer` equal to the
`MissingRequired` errors, `report` and `warnings` identical to the `ResolveResult`'s, and
every outcome `InvariantNotRun`, with every validator function an `error` thunk; the
same configuration passes `serverValidators` and fails `workerValidators`;
`describeValidators` lists five outcomes with the prerequisite of
`replica-pool-share`; `runValidators` on a typed value directly returns the same
outcomes and problems without any source; rendering twice is byte-identical and the
outcome order is declaration order regardless of key order; a `violationWithDetail`
label is retained verbatim in the problem, the text line, and the JSON; a sentinel
placed in `database.url` and in a credential token is absent from `show` of the problems,
the report, and the outcomes, from `renderErrorsText`, `renderErrorsJson`,
`renderValidationText`, `renderResolutionText`, and `renderValidatedResolutionJson`
(scan every output with `Text.isInfixOf`). Use a unique contiguous ASCII marker such as
`SETTEI_VALIDATION_SECRET_29` within the punctuation-rich sentinel and assert absence of
both the marker and full sentinel: JSON and Haskell `Show` escape quotes and newlines,
so checking only the raw sentinel gives false assurance. Verify the scan detects a
deliberate escaped leak in a test-local string. Apply this scan to adapter and application
tests too. The goldens
settei/test/golden/validation.txt, validation.json, invariant-errors.txt, and
invariant-errors.json pin the vocabulary for the multi-failure run (write them by hand
from the format above first, then correct them to real output only after reviewing the
diff for leaks). The existing golden tests must keep passing unchanged, which proves
`renderResolutionJson` is byte-identical.

### Milestone 2 — Diagnostic integration


Scope: the adapter boundary. At the end, an application consumes one validated result
through one helper in every mode.

Add `ValidatedDiagnostic a` and `validatedDiagnostic` to
settei-optparse-applicative/src/Settei/Optparse.hs. On `answer = Left errors` return
`DiagnosticFailure` with the mode's failure text from the Decision Log (`ExplainText`:
`renderErrorsText errors <> renderResolutionText report <> renderValidationText
validation`; `ExplainJson`: `renderErrorsJson errors <> "\n" <>
renderValidatedResolutionJson report validation <> "\n"`; all other modes:
`renderErrorsText errors`). On `answer = Right value` return `DiagnosticOutput` for
`ExplainText` (report text then validation text), `ExplainJson` (the validated
resolution document plus a newline), and `CheckConfig` (`configuration valid\n`), and
`DiagnosticContinue value` for `NoDiagnostic` and for every mode an application answers
before resolution (`DescribeConfigText`, `DescribeConfigJson`, and plan 26's
`DeploymentContractText` and `DeploymentContractJson` when present). Update the
module's Haddock to say that an application with validators must consume
`validatedDiagnostic` and never call `resolutionDiagnostic` on the pre-validation result.

Extend settei-optparse-applicative/test/Settei/OptparseTest.hs with a small declaration
(`service.workers` and `service.poolSize`, both public integers, plus a secret
`service.token`) and one validator `pool-covers-workers`. Required cases: `CheckConfig`
on a passing result yields `DiagnosticOutput "configuration valid\n"`; `CheckConfig` on a
validation failure yields `DiagnosticFailure` whose text contains `invariant
pool-covers-workers failed` and does not contain `configuration valid`; `ExplainText`
success contains the report line for `service.workers` and `invariant pool-covers-workers
[passed]`; `ExplainJson` success is exactly one line beginning
`{"schemaVersion":1,"type":"settei.resolution"` and containing `"invariants":[{"rule":
"pool-covers-workers"`; `ExplainJson` failure is two lines, the first beginning
`{"schemaVersion":1,"type":"settei.errors"` and containing `"kind":"invariant"`, the
second the resolution document whose node for `service.poolSize` names the winning
source; `NoDiagnostic` success yields `DiagnosticContinue` with the typed value; a
resolution failure (missing `service.workers`) through `ExplainText` yields
`DiagnosticFailure` containing `required value is missing` and `[not run]`; and a
sentinel in `service.token` is absent from every text produced above. Exercise a failing
validated result through all eight constructors, including the four static-mode fallbacks
of the helper, and assert `DiagnosticFailure` for each. Add a decode failure and a result
with a non-empty warnings list to check unchanged errors, report, and warnings. Static
application dispatch still happens before calling this helper; passing a result directly
to a static-mode fallback is only an adapter test.

### Milestone 3 — Migration of the notification-hub-shaped example


Scope: the application boundary and AC-5. Prerequisite: plan 26 implemented through
its Milestone 4, so that examples/settei-deployment exists with `checkServer` and
`checkWorker`. Verify with `ls examples/settei-deployment/src/Settei/Example/Deployment.hs`
and `rg -n 'checkServer|checkWorker' examples/settei-deployment/src/Settei/Example/Deployment.hs`
before starting. The prerequisite is present at this validation; if it is absent in a
later checkout, record the blocked migration and continue independent work. Implementing
an unfinished part of plan 26 requires authorization for that separate plan.

In `Settei.Example.Deployment`, declare three validators next to `deploymentConfig`:
`server-webhook-secret-length` over `server.webhookSecret` expecting "must be at least
16 characters" (a `check` on the `Text` secret's length; no detail, so the value is
never echoed); `worker-visibility-covers-concurrency` over
`workers.visibilityTimeoutSeconds` and `workers.concurrency` expecting
"workers.visibilityTimeoutSeconds must be at least twice workers.concurrency"; and
`production-webhook-secret` over `server.webhookSecret` and `runtime.environment`
expecting "the development webhook secret must never reach production". Build
`serverValidators` from the first and `workerValidators` from the second and third, both
with `validators deploymentConfig …` in top-level definitions like `environmentBindings`,
and explicitly force them in tests so an invalid declaration fails. Preserve the current
`toInteger` conversions in the timeout comparison before multiplying by two; unchecked
`Int` multiplication changes rejection at large values. Export
`roleValidators :: Role -> Validators DeploymentConfig`, `serverValidators`, and `workerValidators`; remove `checkServer` and
`checkWorker` (the `DeploymentConfig -> [Text]` functions) and the `case role of` that
selects between them. Change the dispatch to `schemaDiagnostic`, `contractDiagnostic`, load,
`resolve`, `validate (roleValidators role)`, then `validatedDiagnostic`: route
`DiagnosticFailure` to stderr with `resolutionExitCode`, `DiagnosticOutput` to stdout with
the rendered warnings on stderr and exit 0, and `DiagnosticContinue config` to the safe
startup summary with rendered warnings on stderr, as today. Failures continue omitting
warning output. Delete the application-local `explanation` helper.

Update the example's test suite so that the plan 26 fixture matrix keeps its outcomes:
the complete production snapshot passes both roles with `configuration valid\n` and
exit 0; the five-character `WEBHOOK_SECRET` is rejected by the server with exit 4 and a
stderr line `server.webhookSecret: invariant server-webhook-secret-length failed: must
be at least 16 characters` and no value; `WORKER_VISIBILITY_TIMEOUT_SECONDS=1` is
rejected by the worker with the `worker-visibility-covers-concurrency` line; the
development webhook default in production is rejected by the worker only; the typed
values of the valid fixtures are unchanged (the existing suite checks process outcomes,
so add assertions comparing the pre-validation and post-validation `Right` values using
`DeploymentConfig`'s `Eq` instance without requiring or printing `Show`);
`--explain-config` on a failing worker prints the error line, the
full report including `workers.visibilityTimeoutSeconds = "1"` with its winning
environment origin, and exactly two `invariant …` outcome lines in declaration order: the
timeout rule failed and the production-secret rule passed; `--explain-config-json` prints
exactly two lines, the
`settei.errors` document with `"kind":"invariant"` and the `settei.resolution` document
containing both the node and the `invariants` entry; `--check-config` with the same
inputs prints only the error line and never `configuration valid`; startup with the
same invalid inputs exits 4 without printing a ready message. Include large `Int` values
whose doubled concurrency exceeds `maxBound :: Int` to prove the original rejection is
preserved, and a worker fixture failing both rules to prove ordered accumulation. A missing
`DATABASE_URL` yields the resolution error, `[not run]` for every rule in text explain,
and no invariant line in the errors; a malformed numeric setting produces a decode error
with not-run outcomes; an unreadable source still exits 3 through its existing adapter
text renderer before validation. The static modes still pass with a failing
environment reader (unchanged plan 26 tests, which now also prove validators are not
reached); and the secret sentinel in `DATABASE_URL`, `WEBHOOK_SECRET`, and
`EMAIL_CREDENTIALS_JSON` is absent from stdout and stderr in every mode. Add a
"Rejection lines changed" note to examples/settei-deployment/README.md and its changelog
showing one old and one new line, and the change from mixed text/JSON to two JSON
documents on JSON explain failure (including base resolution failure).

### Milestone 4 — Documentation, collateral, and request lifecycle


Scope: make the capability discoverable, bounded, versioned, and recorded.

Write the new ADR under docs/adr/ (filename `00NN-application-invariant-validation.md`
where `NN` is the handle number `okf id next docs/adr --profile docs/adr/profile.dhall
ADR` returns at creation; frontmatter `type: Architecture Decision Record`, `title`,
`description`, `docId`, `status: Accepted`, `date`, `timestamp`, `generated`). Record:
validators are pure rules over the typed value, declared with stable identifiers and
declared keys checked at construction, with no public constructor or `Generic` instance
for the checked collection; invariant failures are `ConfigError`s so every
renderer and exit path is shared; validators run only after successful resolution and
never in describe modes; declaration order, accumulation, explicit prerequisites and
skipping, and per-role collections; the metadata-only failure record, the fixed
expectation, and the detail channel's author contract; the additive `invariant` kind and
`invariants` array; and the rejected alternatives (a separate failure type, a `Monad`
instance for `Config`, runtime key references, automatic sanitisation, a standalone
validation document, listing rules in the schema). Append `## Amendment <date>:
invariant failures and additive diagnostics` to
docs/adr/0003-resolution-provenance-and-default-semantics.md stating that `ConfigError`
may gain a constructor per failure family under a major bump, that `settei.errors` gained
the `invariant` kind, and that `settei.resolution` gained the optional `invariants` array
emitted only by the validated renderer; advance its `timestamp`. Regenerate
docs/adr/index.md with `okf index docs/adr --write --okf-version 0.2` only if validation
reports a mismatch, and append log entries with `okf log add docs/adr`.

Write docs/capabilities/structured-application-validation.md (`capabilityId` from `okf
id next docs/capabilities --profile docs/capabilities/profile.dhall CAP`, packages
`settei` and `settei-optparse-applicative`, interface `Settei.Validate`,
`Settei.Report`, `Settei.Render`, `Settei.Optparse`, `requires` CAP-1, CAP-2, CAP-3,
CAP-7, `since` the version the changelog bump implies, evidence rows pointing at
settei/test/Settei/ValidateTest.hs, the optparse suite, the deployment example suite,
and the guide section). Its Limits list must state the author contract and that
validators are configuration acceptance checks, not connectivity or credential checks.
Update docs/capabilities/secret-safe-diagnostics.md (CAP-3) with the `invariant` kind
and the validation lines, and docs/capabilities/configuration-diagnostic-options.md
(CAP-7) with `validatedDiagnostic`; add the catalog row to docs/capabilities/index.md
and a log entry.

Add a section `## Validate cross-setting invariants after resolution` to
docs/guides/cli-application.md before "Distinguish exit behavior". It shows a validator
declaration with `check` and one with `invariant` and `violationWithDetail`, the
module-level `validators` construction, `validate` after `resolve`, the
`validatedDiagnostic` dispatch with its three constructors, the text and JSON transcripts
from Milestone 3, the author contract in a highlighted paragraph, and the role pattern.
Add "or a failed invariant" to the exit-code-4 row and one sentence under "Add
diagnostics that match user intent" saying check mode consumes the validated result.
Add one paragraph with a link to the new section at the end of "Use the typed result
and diagnostics" in docs/guides/getting-started.md. If plan 26's
docs/guides/deployment-contract.md exists, add a short subsection "Structured check
failures" with the JSON transcript. Append a log entry with `okf log add docs/guides`.

Add a section `## Application validators` to docs/security.md (the failure retains
metadata only; the expectation is fixed; the detail channel is author text that Settei
cannot sanitise; validators receive the typed record and must not log it). Add
`Settei.Validate` to the core module list in docs/compatibility.md and a sentence under
"Versioning policy" that `ConfigError` grew a constructor in this release. Add
`## Unreleased` bullets to settei/CHANGELOG.md (breaking: `InvariantError`; new:
`Settei.Validate`, report types, renderers, additive JSON fields) and
settei-optparse-applicative/CHANGELOG.md (`ValidatedDiagnostic`, `validatedDiagnostic`). Record these changes under the shared
next major release target already documented in docs/compatibility.md (currently
0.3.0.0), without incrementing only the core package or changing exact intra-family
pins during feature implementation; the release workflow owns the coordinated bump.
Mention application invariants in README.md's package-map line for `settei` only if that
line lists features; otherwise leave README.md alone.

Finally edit docs/improvement-requests/integrate-application-validation-into-structured-diagnostics.md.
The record carries `status: accepted` and `targetPlan` naming this plan (set when the
plan was created); the first implementation session moves it to `status: in-progress`.
Keep it in progress through this milestone. After Milestone 5 acceptance, set
`status: completed`, add `completedAt` (RFC 3339 UTC) and a `resolution` line naming this
plan and the test evidence. These field names come from the pinned
docs/improvement-requests/profile.dhall, which imports
`mori://shinzui/okf-profiles/profiles/improvement-requests` v0.22.0. After each lifecycle
edit, update the record's `generated.at`, append a log entry with
`okf log add docs/improvement-requests --kind Update -m "Update IR-4 lifecycle and evidence"`,
and run strict profile and log validation.

### Milestone 5 — Full validation and closure


Run the complete gates under Validation and Acceptance, record the test totals and the
Milestone 3 transcripts in this plan, write Outcomes & Retrospective, and confirm the new
ADR and the ADR-3 amendment capture everything durable from the Decision Log and
Surprises & Discoveries. Only then complete IR-4 using the fields above and revalidate
its bundle. No checkbox for this plan is complete merely because the baseline tests pass.


## Concrete Steps


All commands run from the repository root, /Users/shinzui/Keikaku/bokuno/settei, inside
the Nix development shell (`nix develop -c …`), which provides GHC 9.12.4, Cabal 3.16,
`treefmt`, and `okf`.

Before starting any milestone, look at the concurrent state of the tree:

```bash
git status --short
ls settei/src/Settei/Internal/DefaultValidation.hs examples/settei-deployment 2>&1
okf id next docs/adr --profile docs/adr/profile.dhall ADR
okf id next docs/capabilities --profile docs/capabilities/profile.dhall CAP
```

Milestone 1: create settei/src/Settei/Validate.hs, edit settei/src/Settei/Error.hs,
settei/src/Settei/Report.hs, settei/src/Settei/Render.hs, settei/src/Settei.hs, and
settei/settei.cabal, create settei/test/Settei/ValidateTest.hs and the four goldens, and
edit settei/test/Main.hs. Then:

```bash
nix develop -c cabal build settei
nix develop -c cabal test settei-tests --test-show-details=direct
```

The suite summary must end with `All N tests passed` where N is the previous total plus
the new cases; the golden tests for `resolution.json` and `failure-resolution.json` must
be among the passing cases.

Milestone 2: edit settei-optparse-applicative/src/Settei/Optparse.hs and
settei-optparse-applicative/test/Settei/OptparseTest.hs. Then:

```bash
nix develop -c cabal test settei-optparse-applicative-tests --test-show-details=direct
```

Milestone 3: after confirming the prerequisite, edit
examples/settei-deployment/src/Settei/Example/Deployment.hs, its test suite, README.md,
and changelog. Then:

```bash
nix develop -c cabal test settei-example-deployment-tests --test-show-details=direct
nix develop -c cabal build exe:settei-example-deployment-worker
deployment_worker=$(nix develop -c cabal list-bin exe:settei-example-deployment-worker)
env -i ENVIRONMENT=production DATABASE_URL=postgres://db.invalid/hub \
  WEBHOOK_SECRET=a-sufficiently-long-production-secret \
  DELIVERY_ENDPOINT=http://delivery.production.internal:8080 \
  EMAIL_CREDENTIALS_JSON='{"sendgrid":"placeholder"}' \
  WORKER_VISIBILITY_TIMEOUT_SECONDS=1 \
  "$deployment_worker" --explain-config
printf 'exit %s\n' "$?"
```

Expected application stderr (vocabulary and order are requirements; the report lines
between the error and the invariant block are the full report and are abbreviated here):

```text
workers.visibilityTimeoutSeconds, workers.concurrency: invariant worker-visibility-covers-concurrency failed: workers.visibilityTimeoutSeconds must be at least twice workers.concurrency
database.poolSize = 10
  from built-in source built-in defaults
…
workers.visibilityTimeoutSeconds = "1"
  from environment variable WORKER_VISIBILITY_TIMEOUT_SECONDS
…
invariant worker-visibility-covers-concurrency [failed (1 violation)]: workers.visibilityTimeoutSeconds, workers.concurrency
  expects workers.visibilityTimeoutSeconds must be at least twice workers.concurrency
invariant production-webhook-secret [passed]: server.webhookSecret, runtime.environment
  expects the development webhook secret must never reach production
```

The shell prints `exit 4` on stdout after the application exits; it is not part of
either diagnostic document.

Replace `--explain-config` with `--explain-config-json` and confirm two lines on stderr,
the first beginning `{"schemaVersion":1,"type":"settei.errors","errors":[{"kind":"invariant"`
and the second beginning `{"schemaVersion":1,"type":"settei.resolution"` and containing
`"invariants":[{"rule":"worker-visibility-covers-concurrency"`.

Milestone 4: write and edit the documents listed in Plan of Work, then validate every
bundle:

```bash
okf validate docs/adr --strict --profile docs/adr/profile.dhall --profile-enforce --log-enforce
okf validate docs/guides --strict --profile mori/user-documentation-profile.dhall --profile-enforce --log-enforce
okf validate docs/capabilities --profile docs/capabilities/profile.dhall --profile-enforce --log-enforce
okf validate docs/improvement-requests --strict --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
```

Each prints `OK: … concepts (okf_version 0.2)`. If a validator reports an index mismatch,
run `okf index <bundle> --write --okf-version 0.2` for that bundle and inspect the diff.

Milestone 5:

```bash
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c treefmt
nix flake check
git status --short
```

Commit at each milestone boundary with a Conventional Commits subject and both trailers:

```text
feat(settei): add structured post-resolution invariant validation

ExecPlan: docs/plans/29-integrate-application-validation-into-structured-configuration-diagnostics.md
Intention: intention_01m5fctnd8ezea1sejjpxss6bg
```

Because plan 26 is implemented in the same tree, stage this plan's files by path
(`git add settei/src/Settei/Validate.hs …`) rather than with `git add -A`, and never
commit another plan's uncommitted files.


## Validation and Acceptance


Each acceptance criterion of IR-4 maps to observable checks:

- AC-1 (public mechanism, stable identifiers, key references, invalid references).
  `Settei.ValidateTest` declares the notification-hub-shaped `pool-capacity`,
  `visibility-timeout`, `replica`, `replica-pool-share`, and `provider-account` rules,
  asserts that each failure's `rule` and `keys` equal the declaration, and asserts that
  `validators` returns `UndeclaredInvariantKey` for `nothing.here`,
  `UnknownPrerequisite` for a forward or self reference, `DuplicateInvariantRule`,
  `EmptyInvariantKeys`, `InvalidInvariantRule`, and `CyclicDeclaration` for the mutually
  recursive declaration, each rendered as one line naming the offender.
- AC-2 (one validated result across modes, consistent rejection, retained provenance,
  compatibility with existing failures). The optparse suite feeds one failing validated
  result through every `DiagnosticMode` and asserts non-success with the rule and keys in
  text and JSON; the error document identifies the rule and keys, and the second JSON
  document contains both the winning origin and the matching invariant outcome;
  the deployment example suite repeats that against server and worker run helpers.
  Resolution failures retain their original errors and provenance with every rule
  `not run`: text explain appends outcomes, and JSON explain deliberately changes the
  old mixed text/JSON stream to two valid JSON documents. Source-load failures retain
  their existing exit-3 text path;
  `configuration valid` never appears in any failing output.
- AC-3 (safe metadata, author contract). `Validator`, `Validators`, and
  `ValidatedResult` compile without `Show`; public API inspection confirms no constructor
  or `Generic` instance exposes unchecked `Validators`; the sentinel tests in the core,
  optparse,
  and example suites scan `show` of problems, reports, and outcomes plus every text and
  JSON renderer and both process streams; the Haddock of `Settei.Validate`, the guide
  section, docs/security.md, and the capability record document the detail channel's
  responsibility; the verbatim-detail test shows what the channel does.
- AC-4 (sequencing, accumulation, fail-fast, roles, failed resolution, static
  inspection). The core suite proves declaration-order accumulation of three independent
  failures, skipping of a dependent rule with an unforced `error` thunk, `not run` for
  every rule after a failed resolution with unforced thunks, and a configuration that
  passes `serverValidators` while failing `workerValidators`; the deployment example's
  unchanged static-mode tests with a failing environment reader prove describe and
  contract modes never reach validators; `describe` and the schema goldens are
  byte-identical.
- AC-5 (migration without duplication or behaviour change, documented versioning). The
  deployment example's fixture matrix from plan 26 keeps every accept and reject outcome
  and exit code and the same typed values (compared without rendering secrets); `checkServer` and `checkWorker` no longer
  exist and no rule is declared twice; the changelogs record the `ConfigError` major bump
  and the additive JSON fields, and the README note shows the old and new rejection
  line.

Required gates before the plan is complete: the build, test, and validation commands
under Concrete Steps exit 0, while the deliberately rejected worker commands exit 4;
the four `okf validate` commands pass; `git status --short` shows nothing from this plan
after the final commit. The expected number of core tests is the pre-plan total plus the
new `Settei.ValidateTest` cases; record the real totals here during Milestone 5.

Proposed, not required: a `settei.validation` standalone document for check-mode JSON
output, and a `focus :: (b -> a) -> Validator a -> Validator b` combinator for reusing
validators across record shapes. Both need a scope decision.


## Idempotence and Recovery


The migration removes application-local checks and changes their diagnostics; inspect
the diff before retrying an edit. Re-running tests is harmless. Goldens are created by hand from the documented format and only
then corrected to real output after the diff has been reviewed for leaked sentinels; if a
golden is accidentally overwritten with leaking output, restore only the affected lines
from the pre-edit snapshot or a reviewed Git diff. Do not restore the entire golden
directory: concurrent plan 26 work may own changes there. `okf log add` appends a dated
entry each time it runs, so
run it once per logical change and remove a duplicate entry by hand if a command is
repeated. The improvement-request status edits are plain frontmatter edits; re-running
the validation command after each one confirms the record. If plan 26 changes or is
reverted, reassess all three integration seams: the shared cycle module, contract-mode
constructors, and deployment example. Coordinate changes to shared files and preserve
the other work. Extracting the cycle helper, if needed, must retain both resolver
behaviour and Cabal module registration; do not create a duplicate cycle walk.
Milestone 3 can be deferred without blocking Milestones 1, 2, and the
non-example parts of 4; record a handoff note in Progress if it is.


## Interfaces and Dependencies


Additions to settei/src/Settei/Error.hs:

```haskell
newtype InvariantRule = InvariantRule Text            -- Generic, Eq, Ord, Show
renderInvariantRule :: InvariantRule -> Text

data InvariantProblem = InvariantProblem
  { rule :: !InvariantRule,
    keys :: ![Key],
    expectation :: !Text,
    detail :: !(Maybe Text)
  }                                                    -- Generic, Eq, Show

data ConfigError = … | InvariantError !InvariantProblem
```

Additions to settei/src/Settei/Report.hs:

```haskell
data InvariantStatus
  = InvariantPassed
  | InvariantFailed !Int
  | InvariantSkipped !(NonEmpty InvariantRule)
  | InvariantNotRun                                    -- Generic, Eq, Show

data InvariantOutcome = InvariantOutcome
  { rule :: !InvariantRule,
    keys :: ![Key],
    expectation :: !Text,
    prerequisites :: ![InvariantRule],
    status :: !InvariantStatus
  }                                                    -- Generic, Eq, Show

newtype ValidationReport = ValidationReport
  { invariants :: [InvariantOutcome]
  }                                                    -- Generic, Eq, Show
validationOutcomes :: ValidationReport -> [InvariantOutcome]
```

New public module settei/src/Settei/Validate.hs (re-exported by `Settei`):

```haskell
data Violation                                         -- private; Generic, Eq, Show
violation :: Violation
violationWithDetail :: Text -> Violation               -- author contract applies

data Validator a                                       -- private; no Generic, Eq, Show
invariant :: InvariantRule -> [Key] -> Text -> (a -> [Violation]) -> Validator a
check :: InvariantRule -> [Key] -> Text -> (a -> Bool) -> Validator a
requires :: [InvariantRule] -> Validator a -> Validator a

data ValidatorError
  = InvalidInvariantRule !InvariantRule
  | DuplicateInvariantRule !InvariantRule
  | EmptyInvariantKeys !InvariantRule
  | UndeclaredInvariantKey !InvariantRule !Key
  | UnknownPrerequisite !InvariantRule !InvariantRule  -- rule, prerequisite
  | CyclicDeclaration !DefaultCycleProblem             -- Generic, Eq, Show
renderValidatorErrorText :: ValidatorError -> Text
renderValidatorErrorsText :: NonEmpty ValidatorError -> Text

data Validators a                                      -- private; no Generic, Eq, Show
validators :: Config a -> [Validator a] -> Either (NonEmpty ValidatorError) (Validators a)
describeValidators :: Validators a -> ValidationReport
runValidators :: Validators a -> a -> (ValidationReport, [InvariantProblem])

data ValidatedResult a = ValidatedResult
  { answer :: !(Either (NonEmpty ConfigError) a),
    report :: !ResolutionReport,
    warnings :: ![ConfigWarning],
    validation :: !ValidationReport
  }                                                    -- Generic only
validate :: Validators a -> ResolveResult a -> ValidatedResult a
```

Additions to settei/src/Settei/Render.hs:

```haskell
renderValidationText :: ValidationReport -> Text
renderValidatedResolutionJson :: ResolutionReport -> ValidationReport -> Text
```

Additions to settei-optparse-applicative/src/Settei/Optparse.hs:

```haskell
data ValidatedDiagnostic a
  = DiagnosticFailure !Text
  | DiagnosticOutput !Text
  | DiagnosticContinue a                               -- Generic only
validatedDiagnostic :: DiagnosticMode -> ValidatedResult a -> ValidatedDiagnostic a
```

Changes to examples/settei-deployment (plan 26's package): `Settei.Example.Deployment`
exports `serverValidators`, `workerValidators`, and `roleValidators :: Role -> Validators
DeploymentConfig` and no longer exports `checkServer` or `checkWorker`.

No lens type appears in any public signature. `ValidatedResult` derives only `Generic`
because it holds the typed configuration; `Validator` and `Validators` expose neither
constructors nor `Generic`, `Eq`, or `Show` instances. Construction invariants must not
be bypassable through generic representation conversion. No new third-party dependency
is introduced; the
core keeps its own deterministic JSON encoder
(docs/adr/0003-resolution-provenance-and-default-semantics.md). The shared cycle walk is
`Settei.Internal.DefaultValidation.validateDefaultCycles :: Config a -> [ConfigError]`
from plan 26's in-progress work. Dependency source and documentation for `tasty`,
`optparse-applicative` 0.19, and `generic-lens` are registered in Mori (`mori registry
show UnkindPartition/tasty --full`, `mori registry show
pcapriotti/optparse-applicative --full`, `mori registry show ekmett/lens --full`); consult
them before guessing an API. Milestone 3 depends on plan 26 through its Milestone 4;
Milestones 1 and 2 depend on nothing unimplemented. Plan 28's harness classifies exit
`4` as "configuration rejected", which invariant failures already use, so no harness
change is needed; a future structured consumer would parse the two stderr lines this
plan defines for `--explain-config-json`.


Revision note (2026-10-21): validated this plan against the current core, CLI adapter,
deployment example, relevant ADRs, IR-4, and Mori-located consumer. Removed generic
construction bypasses, strengthened escaped-secret checks, specified result conversion
and prerequisite composition, corrected the worker outcome count and migration details,
made process transcripts independent of build output, and deferred request completion
until final acceptance. The three baseline suites and four bundle checks pass; all
implementation milestones remain open.
