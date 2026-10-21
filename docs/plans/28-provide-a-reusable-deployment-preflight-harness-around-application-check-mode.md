---
id: 28
slug: provide-a-reusable-deployment-preflight-harness-around-application-check-mode
title: "Provide a reusable deployment preflight harness around application check mode"
kind: exec-plan
created_at: 2026-10-21T13:30:07Z
intention: "intention_01m5faf5apez5s3g1d4hyxj2r0"
provenance:
  created_by:
    model: "claude-fable-5-1"
    harness: "claude-code"
    at: 2026-10-21T13:30:07Z
---

# Provide a reusable deployment preflight harness around application check mode

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan implements improvement request IR-3,
docs/improvement-requests/provide-a-reusable-deployment-preflight-workflow.md. Its five
acceptance criteria (AC-1 through AC-5) are the acceptance obligations of this plan; each
milestone below names the criteria it discharges.


## Purpose / Big Picture

Settei is a Haskell configuration library. An application declares its settings once,
resolves them from ordered sources (files, environment variables, command-line flags),
and, through the `settei-optparse-applicative` adapter, exposes a **check mode**: the
flag `--check-config` makes the program load and validate its configuration exactly as it
would at startup, print `configuration valid`, and exit without opening a database, a
network listener, or any other resource. The originating consumer, the notification-hub
service (`mori://tan/notification-hub`), already runs application-specific checks inside
that mode: its server validates event-webhook public keys and its workers validate
capacity, lease bounds, replica relationships, and email-account wiring, all before any
resource is acquired.

The person writing that service's first deployment in `mori://tan/tan-app-infrastructure`
(a Pulumi program in TypeScript) has no good way to use those checks before provisioning.
The container will receive literal environment entries, Secret references, generated values
that only exist after resources are created, and mounted files. Validating the Pulumi
input YAML or reading a schema does not exercise the TypeScript wiring that assembles
those inputs, and reimplementing the application's decoders and invariants in
infrastructure code would create a second, drifting copy of the rules.

After this plan, Settei ships a small **preflight harness**: the `settei-preflight`
package, with a library (`Settei.Preflight`), a JSON request document
(`Settei.Preflight.Request`), and an executable (`settei-preflight`). A caller describes
the role being checked, the application executable and its check command, every proposed
environment variable and file, and which of those values are real, synthetic stand-ins,
not yet resolved, or unavailable secrets. The harness writes the files into a private
temporary directory, builds the child's environment from nothing but the proposed entries
plus an explicit inherited allowlist, runs the application's own check command with a
timeout, redacts every secret it was given from the captured output, removes the
temporary directory, and reports one of three verdicts: `pass` (the application accepted
fully known inputs), `inconclusive` (the application accepted inputs that included
stand-ins or omissions, so this is not a deployment validation), or `fail` (the
application rejected the inputs, or the harness could not run the check). Only `pass`
passes a gate. Secrets reach the application only through environment variables or files,
never through command arguments, the request document, the report, or logs.

The reference workflow runs against the notification-hub-shaped example application
added by docs/plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md
(package `examples/settei-deployment`, executables `settei-example-deployment-server` and
`settei-example-deployment-worker`). A reference extractor in that example turns a
rendered Kubernetes manifest list, which is the shape both kustomize and a Pulumi program
produce, into a preflight request while stating exactly which input kinds it handles. From
the repository root, once this plan and plan 26 are implemented:

```bash
nix develop -c cabal build settei-example-deployment settei-preflight
nix develop -c cabal run settei-example-deployment-preflight -- \
  --manifest examples/settei-deployment/test/fixtures/rendered-production.json \
  --deployment settei-example-deployment-server --role server \
  --executable "$(nix develop -c cabal list-bin settei-example-deployment-server)" \
  --synthetic POD_NAMESPACE=production \
  > /tmp/server-request.json
SETTEI_PREFLIGHT_SECRET_SETTEI_EXAMPLE_DEPLOYMENT_SECRETS_DATABASE_URL='postgres://preflight.invalid/notification' \
SETTEI_PREFLIGHT_SECRET_SETTEI_EXAMPLE_DEPLOYMENT_SECRETS_WEBHOOK_SECRET='preflight-stand-in-webhook-secret' \
  nix develop -c cabal run settei-preflight -- --request /tmp/server-request.json; echo "exit $?"
```

The first command prints a request whose secrets are references to harness environment
variables, not values. The second prints a text report that names every input and its
classification, shows the application's redacted output, and ends with the verdict. With
`EMAIL_CREDENTIALS_JSON` left unprovisioned the application rejects the configuration
(`email.credentials: required value is missing`) and the exit code is `4`; with every
secret provisioned and `POD_NAMESPACE` still synthetic, the application accepts the inputs
and the verdict is `inconclusive` with exit code `1`, because a synthetic value was
checked for shape only. The real values are validated after provisioning by the
init-container `--check-config` gate that
docs/guides/kubernetes-cookbook.md already documents; the preflight harness is the
pre-provisioning half of that pair.


## Progress

- [ ] Milestone 1 — Harness library (AC-1, AC-3, AC-4, AC-5 at the library boundary):
      the new `settei-preflight` package with `Settei.Preflight` builds, validates,
      materializes, executes, redacts, classifies, and renders; the package is registered
      in `cabal.project`, `flake.module.nix`, and `mori.dhall`;
      `nix develop -c cabal test settei-preflight-tests --test-show-details=direct`
      passes with the fixture-application tests covering every classification, every
      execution-failure path, output redaction, environment isolation, cleanup, and the
      startup-marker instrumentation.
- [ ] Milestone 2 — Request document and executable (AC-2 interface, AC-4 channels):
      `Settei.Preflight.Request` parses and renders the strict `settei.preflight-request`
      document, resolves secret references through an injectable environment, and the
      `settei-preflight` executable maps verdicts to exit codes 0/1/2/3/4; the suite
      passes with the document goldens, the inline-secret and unknown-key rejections, and
      the executable transcripts.
- [ ] Milestone 3 — Reference workflow on the notification-hub-shaped example (AC-1,
      AC-2, AC-5 at the application boundary; requires plan 26 through Milestone 4):
      `examples/settei-deployment` gains the rendered-manifest fixture, the
      `Settei.Example.Deployment.Preflight` extractor, the
      `settei-example-deployment-preflight` executable, and tests proving server and
      worker precedence against in-process runs, extraction with deliberate mutations,
      visible unsupported inputs, and configuration-only execution;
      `nix develop -c cabal test settei-example-deployment-tests --test-show-details=direct`
      passes.
- [ ] Milestone 4 — Documentation and collateral (AC-2 assumptions, AC-3 reporting
      contract, AC-5 separation from readiness evidence): guide DOC-12, capability
      CAP-15, ADR-13 plus an ADR-7 amendment, cookbook cross-link, README,
      compatibility, security, changelog, and IR-3 moved to `completed`; every OKF
      bundle validates strictly.
- [ ] Milestone 5 — Full validation and closure: `cabal build all`, `cabal test all`,
      `treefmt`, `cabal check` for the new package, and `nix flake check` pass; evidence
      recorded here; Outcomes & Retrospective written; ADR distillation done.


## Surprises & Discoveries

- Planning evidence (2026-10-21): the solver plan in dist-newstyle/cache/plan.json
  already contains `process-1.6.26.1`, `temporary-1.3`, `directory-1.3.10.1`,
  `filepath-1.5.5.0`, `aeson-2.2.5.1`, and `bytestring-0.12.2.0`, so no new dependency
  enters the workspace closure. In the registered `process` source
  (`mori registry show haskell/process --full`), `withCreateProcess` is
  `bracket (createProcess c) cleanupProcess …` and `cleanupProcess` sends `SIGTERM`,
  closes the pipe handles, and waits asynchronously; an asynchronous `timeout`
  exception therefore terminates the child and releases its handles without extra
  code, but a child that ignores `SIGTERM` is not force-killed. The executable lookup
  follows `execvp(3)`: a name without a slash is searched on the *harness* process's
  `PATH`, not the child's, which is why the harness resolves names with
  `findExecutable` itself and reports the resolved path.
- Planning evidence (2026-10-21): GHC programs decode and encode handle text with the
  process locale. A child started with an empty environment runs under the `C` locale
  and can fail to print non-ASCII diagnostics, and a harness that reads the child's
  output as `String` would fail on non-ASCII bytes for the same reason. The design below
  inherits `LANG`, `LC_ALL`, and `LC_CTYPE` by default and reads the child's output as
  bytes decoded leniently as UTF-8.


## Decision Log

- Decision: The harness is a new publishable package `settei-preflight` rooted at
  `settei-preflight/`, with public modules `Settei.Preflight` and
  `Settei.Preflight.Request` and an executable `settei-preflight`. It depends on
  `settei` (for `Sensitivity`) and `settei-env` (for `EnvName`) but on no other family
  package, and no family package depends on it.
  Rationale: IR-3 assigns the generic interface, execution safeguards, and examples to
  Settei. Spawning processes and writing temporary files do not belong in a source
  adapter or in the core, which stays effect-free
  (docs/adr/0003-resolution-provenance-and-default-semantics.md), and
  `settei-optparse-applicative` does not depend on `settei-env`. A sibling package keeps
  the dependency graph acyclic and matches the package-layout rule in
  docs/adr/0001-haskell-project-conventions.md.
  Date: 2026-10-21

- Decision: Deployment tooling communicates through a strict JSON document of type
  `settei.preflight-request` (`schemaVersion` 1), parsed and emitted with `aeson`
  inside `settei-preflight` only. The document can carry public values and synthetic
  stand-ins inline, but a real secret may only be referenced, as `secretFromEnvironment`
  (a variable of the harness process) or `secretFromFile` (a path the harness reads);
  an inline value marked secret is a parse error. Unknown keys, missing keys, and entries
  with zero or several value forms are parse errors, never silently dropped.
  Rationale: AC-4 forbids secret values in generated public artifacts; the request file
  is such an artifact, so the format must make embedding a secret impossible rather than
  discouraged. `aeson` is already in the workspace closure through `settei-dhall`;
  docs/adr/0003-resolution-provenance-and-default-semantics.md rejects Aeson only for
  the core's own documents and explicitly allows parser libraries at input boundaries.
  Hand-writing a third private JSON encoder for a package that must parse JSON anyway
  would add code without adding a guarantee; determinism is obtained by building
  encodings with `pairs` in fixed order and is pinned by byte-identical goldens.
  Date: 2026-10-21

- Decision: Every proposed value is one of `SuppliedValue sensitivity value`,
  `SyntheticValue sensitivity value reason`, `UnresolvedValue reason`, or
  `UnavailableSecret reason`. Supplied and synthetic values are passed to the
  application; unresolved and unavailable inputs are omitted from the run and listed as
  limitations. The verdict is `pass` only when the application accepted and every input
  was supplied; `inconclusive` when it accepted but at least one input was synthetic,
  unresolved, or unavailable; and `fail` whenever it rejected or the harness could not
  run it, regardless of coverage. Only `pass` passes a gate; the text and JSON reports
  say so in words.
  Rationale: AC-3 requires that incomplete checking is never reported as full validation
  and that the outcomes blocking a gate are defined. Omitting an unresolved value lets
  the application's own missing-required error speak, while a synthetic stand-in lets a
  decoder run before provisioning; neither can prove the deployed value, so neither can
  produce `pass`.
  Date: 2026-10-21

- Decision: The child's environment is constructed from nothing: the proposed entries
  that are present, plus the variables named in an explicit `inherited` allowlist copied
  from the harness process. The default allowlist is `PATH`, `LANG`, `LC_ALL`, and
  `LC_CTYPE`; a request that sets `inherit` replaces the default entirely. Nothing else,
  in particular not `GHCRTS` or `HOME`, reaches the child unless named. The child's
  working directory is the materialized input directory.
  Rationale: IR-3 asks that ambient shell settings never fill missing application
  inputs and that any inherited environment be documented. Locale variables cannot fill
  a Settei binding but are needed for non-ASCII diagnostics (see Surprises &
  Discoveries); `PATH` is harmless to the application and useful if it spawns helpers.
  Date: 2026-10-21

- Decision: Secret safety is layered. `ProposedValue` and `ProposedInputs` have no
  `Show` instance. A literal argument that contains the value of any supplied or
  synthetic secret makes the request invalid (`secret-in-argument`, naming the input,
  never the value). Files are written beneath a directory created by `mkdtemp`
  semantics (`temporary`'s `withSystemTempDirectory`, mode `0700`) and removed when
  the run ends, including on exceptions. Every secret value the harness was given is
  replaced in the captured stdout and stderr by `[redacted:NAME]` before the output is
  retained, longest values first. Reports and request documents carry names,
  classifications, reasons, and redacted output only.
  Rationale: AC-4 names command arguments, public artifacts, logs, and failure
  summaries as places a secret must never appear. The harness cannot stop an application
  from printing a value it was given, so redaction of captured output is the only way
  to keep the report safe against a leaky application; the fixture tests deliberately
  echo secrets to prove it.
  Date: 2026-10-21

- Decision: Execution uses `process` (`withCreateProcess` with three `CreatePipe`
  handles in binary mode, output decoded leniently as UTF-8) under
  `System.Timeout.timeout`; a timeout terminates the child through the library's
  `cleanupProcess` and reports `not-run` with reason `timed-out`, retaining whatever
  output was captured. A bare executable name is resolved with `findExecutable` in the
  harness process before spawning; a missing executable or a spawn failure is reported
  as `not-run` with its own reason. Exit codes are classified by a configurable mapping
  whose default is the family convention: `0` accepted, `2` usage, `3` source loading
  failure, `4` configuration rejected, anything else unknown.
  Rationale: AC-4 requires executable-not-found, source-loading failure, application
  validation failure, and timeout paths with cleanup, and attribution to the checked
  role. The reference applications and notification-hub share the 2/3/4 convention
  (docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md), but
  a mapping keeps the harness usable for an application with other codes.
  Date: 2026-10-21

- Decision: The `settei-preflight` executable reads one request (`--request PATH`),
  prints the report as text or JSON (`--json`), and exits `0` for `pass`, `1` for
  `inconclusive`, `2` for a usage error, `3` when the harness could not run the check
  (unreadable or invalid document, invalid request, executable not found, spawn failure,
  timeout), and `4` when the application rejected the inputs.
  Rationale: Tooling needs a gate decision from the exit code alone, and operators need
  to tell "my request is wrong" from "the application said no". The split mirrors the
  family's input-versus-outcome discipline (`3` versus `4`).
  Date: 2026-10-21

- Decision: The `settei-preflight` test suite doubles as the fixture application: when
  the proposed variable `SETTEI_PREFLIGHT_FIXTURE` is present, `test/Main.hs` behaves as
  a small checked program selected by `FIXTURE_BEHAVIOUR` instead of running tasty, and
  tests point the harness at `getExecutablePath`. No extra executable component exists.
  Rationale: The harness never inherits environment, so the trigger cannot leak into an
  ordinary test run, and the package ships no fixture binary to Hackage. The fixture
  can deliberately echo secrets, sleep, crash, or write a startup marker, which the real
  reference applications never do, so the harness's own guarantees are testable in
  isolation.
  Date: 2026-10-21

- Decision: The reference workflow lives in plan 26's `examples/settei-deployment`
  package: a rendered Kubernetes manifest fixture with a server and a worker Deployment,
  a `Settei.Example.Deployment.Preflight` extractor, and a
  `settei-example-deployment-preflight` executable that writes a request document. The
  extractor reads env entries with `value`, `configMapKeyRef`, `secretKeyRef`, and
  `fieldRef`, `envFrom` ConfigMap and Secret references, and ConfigMap and Secret volume
  items mounted by the checked container, rewrites arguments that mention a mount path
  to the materialized file or directory, never reads Secret manifest values, references
  secrets as `secretFromEnvironment` under a documented naming rule, and reports every
  input kind it does not handle as a note that travels into the report. The host
  executable is an explicit `--executable` argument because the image is not run.
  Rationale: AC-2 requires a deployment-shaped example whose extraction assumptions are
  explicit and whose unsupported inputs stay visible; IR-3 keeps Pulumi-specific
  extraction in `mori://tan/tan-app-infrastructure`. A rendered manifest list is the
  shape both kustomize and the Pulumi Kubernetes provider emit, so the reference is
  generic without a Pulumi or Kubernetes client dependency, and IR-3 excludes deployed
  image identity from what configuration acceptance can establish.
  Date: 2026-10-21

- Decision: Milestone 3 is a hard dependency on plan 26 through its Milestone 4; this
  plan does not create a second notification-hub-shaped example. Milestones 1 and 2
  are independent of plans 26 and 27 and may be implemented first.
  Rationale: AC-1 and AC-5 need distinct server and worker fixtures with role-specific
  checks and conflicting file, environment, and command-line values; plan 26's example
  provides exactly that, and duplicating it would create two drifting copies of the
  consumer's shape.
  Date: 2026-10-21

- Decision: Out of scope, needing a scope decision before becoming acceptance:
  Pulumi-side extraction (owned by `mori://tan/tan-app-infrastructure`); emitting
  `--supplied-env` arguments from plan 27 automatically (a caller may add them as
  literal arguments today); parsing the application's output as structured diagnostics
  (IR-4's future result; the harness treats output as opaque redacted text); force-killing
  a child that ignores `SIGTERM`; and running the harness inside a cluster.
  Rationale: IR-3 names IR-1, IR-2, and IR-4 as complementary rather than prerequisite,
  and each of these items would widen the public contract.
  Date: 2026-10-21


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### Validation of the request

IR-3 was checked against the working tree and the registered consumer before this plan
was written. The check paths it relies on exist. In `mori://tan/notification-hub`, the
server's `NotificationHub.Server.Config.resolveServerOptions` dispatches the source-free
`schemaDiagnostic`, loads YAML files, reads the environment through
`readEnvironmentSource`, resolves with command-line overrides, validates event-webhook
public keys with `runtimeSendGridEventKeys`, and only then answers `--check-config`
through `resolutionDiagnostic`; the database, migrations, and listener are opened by
`server/app/Main.hs` only in the `ConfigStart` branch, which check mode never returns.
The workers' `NotificationHub.Workers.Config.resolveWorkerOptions` follows the same
order with `validateWorkerCapacity` (lease bounds, paced bounds, replica, job pool, and
email-account rules) before the diagnostic. Both use exit `3` for file loading failures
and `4` for resolution or invariant failures, and both print `configuration valid` on
success. On the infrastructure side, `mori://tan/tan-app-infrastructure`'s
`TanDeployment` component (project-relative path `pulumi/lib/tan-deployment.ts`;
artifact-level URI pending) turns an `env: Record<string, Input<string>>` into literal
`env[].value` entries, some of which are unresolved Pulumi outputs at preview time, and
turns `envFromSecrets` into `envFrom[].secretRef` entries whose variable names are the
keys of a Secret whose values come from Pulumi config. Those are exactly the literal,
secret-reference, generated-value, and mounted-file input kinds IR-3 lists. Nothing in
this plan modifies either consumer repository.

### What exists today in this repository

- settei-optparse-applicative/src/Settei/Optparse.hs defines `DiagnosticMode` and the
  `--check-config`, `--describe-config*`, and `--explain-config*` flags, plus
  `schemaDiagnostic` (source-free) and `resolutionDiagnostic`, which returns
  `configuration valid\n` for `CheckConfig`. Plan 26 adds `--deployment-contract*`
  modes here; this plan does not touch the module.
- examples/settei-service/src/Settei/Example/Service.hs and
  examples/settei-cli/src/Settei/Example/Cli.hs are the existing reference applications
  with the exit-code convention `usageExitCode = 2`, `sourceExitCode = 3`, and
  `resolutionExitCode = 4`. examples/settei-service/deploy/ holds kustomize manifests
  whose `check-config` init container runs the same image with `--check-config`, and
  examples/settei-service/deploy/validate.sh renders and checks them client-side.
  docs/guides/kubernetes-cookbook.md section 6 ("Gate rollouts with `--check-config`")
  documents that post-provisioning gate; this plan's harness is its pre-provisioning
  complement and must be cross-linked from there.
- settei-env/src/Settei/Env.hs defines `EnvName` (a newtype over `Text` with a public
  constructor) and `EnvSnapshot`. Its private `validEnvName` accepts an ASCII letter or
  underscore followed by ASCII letters, digits, or underscores
  (docs/adr/0010-validate-environment-bindings-at-construction.md). The harness mirrors
  that rule privately rather than widening the adapter's exports while plan 27 edits it.
- settei/src/Settei/Setting.hs exports `Sensitivity` (`Public` or `Secret`), which this
  plan reuses to classify proposed values.
- settei/src/Settei/Render.hs holds the core's private deterministic JSON encoder and
  the string-escaping rule the family's documents use; this plan's documents are encoded
  with `aeson` and must be documented as a tooling format rather than a core document.
- examples/settei-service/test/Settei/Example/ServiceTest.hs shows the test style every
  suite follows: tasty with HUnit, `withSystemTempDirectory` from `temporary`, fixtures
  located through the package's `Paths_` module, and a `secretSentinel` scanned for in
  every rendered output.
- flake.module.nix registers each package with `callCabal2nix`; packages whose tests
  need the pinned optparse-applicative 0.19 are wrapped in `dontCheck` because Cabal,
  not Nix, is the test authority (docs/adr/0001-haskell-project-conventions.md). Its
  pre-commit hook runs the four `okf validate` commands repeated under Concrete Steps.
- cabal.project lists every package and enables tests per package; mori.dhall lists
  packages and the OKF bundles (`docs/adr` with handles `ADR-N`, `docs/guides` with
  `DOC-N`, `docs/capabilities` with `CAP-N`, `docs/improvement-requests` with `IR-N`).
- docs/plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md
  (unimplemented when this plan was written) defines the package this plan's Milestone 3
  extends: `examples/settei-deployment` (`settei-example-deployment`, version 0.2.0.0)
  with library module `Settei.Example.Deployment`, `data Role = Server | Worker`,
  `runDeploymentWithSnapshot :: Role -> EnvSnapshot -> DeploymentOptions -> IO
  DeploymentRun`, `deploymentParserInfo :: Role -> ParserInfo DeploymentOptions`,
  options `--config PATH` (YAML, repeatable) and `--set KEY=VALUE` plus the Diagnostics
  group, exit codes 2/3/4, executables `settei-example-deployment-server` and
  `settei-example-deployment-worker`, bindings `ENVIRONMENT`, `DATABASE_URL`,
  `DATABASE_POOL_SIZE`, `HTTP_HOST`, `PORT`, `WEBHOOK_SECRET`, `DELIVERY_ENDPOINT`,
  `WORKER_CONCURRENCY`, `WORKER_VISIBILITY_TIMEOUT_SECONDS`, `OTEL_SERVICE_NAME`, and
  `EMAIL_CREDENTIALS_JSON` (required only in production), a server check that rejects a
  webhook secret shorter than 16 characters, and a worker check that rejects a visibility
  timeout below twice the concurrency and rejects the development webhook default in
  production. If any of those names differ when plan 26 lands, follow the landed code
  and record the difference in Surprises & Discoveries.
- docs/plans/27-validate-supplied-environment-variable-names-against-declared-bindings.md
  (unimplemented) adds `--supplied-env NAME` to the CLI example only. A preflight caller
  may include such flags as literal arguments; this plan does not generate them.

### Terms used in this plan

A **check command** is the application executable plus the arguments that put it in
check mode, for example `--config PATH --check-config`. A **proposed input** is one
environment variable or one file the deployment intends to give the container. A
**supplied** value is the real value the container will receive; a **synthetic** value is
a stand-in of the right shape used only to exercise a decoder; an **unresolved** value is
one that does not exist yet (a Pulumi output, a downward-API field); an **unavailable
secret** is secret material the caller could not obtain. **Coverage** is complete when
every proposed input was supplied and partial otherwise; each non-supplied input is a
**limitation**. The **outcome** is what happened to the application process: accepted,
rejected (by exit-code category), or not run (by harness reason). The **verdict** combines
outcome and coverage into `pass`, `inconclusive`, or `fail`. A **role** is the label of
the process being checked, such as `server` or `worker`; it names the report. The
**inherited allowlist** is the set of variable names copied from the harness's own
environment into the child's. **Materializing** means writing proposed files beneath a
fresh private temporary directory and rewriting file references in arguments to those
paths. A **rendered manifest list** is a JSON document of Kubernetes `kind: List` whose
items are the Deployment, ConfigMap, and Secret objects a tool such as `kubectl
kustomize -o json` or the Pulumi Kubernetes provider would produce.

### Relevant architecture decisions

- docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md:
  reference applications prove public capabilities; `--check-config` resolves normally,
  prints `configuration valid`, and keeps the usage (2), source (3), and resolution (4)
  exit-code discipline; no example contacts a cluster. The harness's default exit-code
  mapping is this convention, and Milestone 3 exercises the harness through the
  deployment example, which requires an amendment to this ADR.
- docs/adr/0003-resolution-provenance-and-default-semantics.md: the core emits
  deterministic versioned JSON without Aeson, and adapters may use parser libraries at
  input boundaries. The harness's two documents are tooling documents outside the core;
  ADR-13 records that boundary and the determinism rule they still follow.
- docs/adr/0009-adapter-error-rendering-contract.md: one operator-readable line per
  problem, plural renderers are the singular mapped over `NonEmpty` and joined with
  `Text.unlines`, renderers concatenate only retained fields. The harness's problem and
  report text renderers follow that shape; plan 27 amends this ADR to admit adapter JSON
  for tooling consumers, which this plan cites rather than repeats.
- docs/adr/0010-validate-environment-bindings-at-construction.md: the variable-name
  validity rule the harness mirrors for proposed and inherited names.
- docs/adr/0011-kubernetes-mounted-directory-input-semantics.md: the process boundary
  (mounted files and environment variables, never cluster access) that the reference
  extractor preserves by reading only a rendered manifest document.
- docs/adr/0001-haskell-project-conventions.md: package layout as a top-level sibling,
  the shared `common common` stanza, strict record fields, explicit deriving strategies,
  and optparse-applicative 0.19 option groups for command-line components.

No existing ADR covers running an application executable, temporary secret files,
output redaction, or preflight verdict semantics; Milestone 4 creates ADR-13. On
2026-10-21 `okf id next` reported `DOC-11`, `CAP-14`, and `ADR-12` as the next free
handles; plan 26 allocates those three, so this plan expects `DOC-12`, `CAP-15`, and
`ADR-13` and must re-run `okf id next` when allocating.


## Plan of Work

### Milestone 1 — Harness library

Scope: the `settei-preflight` package with its library module, registered in the
workspace, with a test suite that proves every guarantee against a fixture application.
At the end, a Haskell caller can describe a check and obtain a report, and the suite
demonstrates isolation, redaction, cleanup, classification, and every failure path.

Create settei-preflight/ with LICENSE (copy settei-env/LICENSE), README.md,
CHANGELOG.md (`## Unreleased` describing the new package), settei-preflight.cabal
(version `0.2.0.0`, `tested-with: GHC ==9.12.4`, the family's `common common` stanza,
`extra-source-files` for `test/golden/*.json` and `test/golden/*.txt`), the library
module settei-preflight/src/Settei/Preflight.hs, and the test suite
settei-preflight/test/Main.hs with settei-preflight/test/Settei/PreflightTest.hs and
settei-preflight/test/Settei/Preflight/Fixture.hs. Library dependencies: `base`,
`bytestring`, `containers`, `directory`, `filepath`, `generic-lens`, `process`,
`settei ==0.2.0.0`, `settei-env ==0.2.0.0`, `temporary`, and `text`. The executable and
`aeson` arrive in Milestone 2. Register the package: add `settei-preflight` to the
`packages:` list and a `package settei-preflight` stanza with `tests: True` in
cabal.project; add `setteiPreflightPackage` in flake.module.nix as a `callCabal2nix`
call passing `settei = setteiPackage; settei-env = setteiEnvPackage;` (wrap it in
`dontCheck` only once Milestone 2 adds the optparse-applicative dependency, with the same
comment the siblings carry) and a `packages.settei-preflight` output; add a
`Schema.Package` entry to mori.dhall (type Library, dependencies `settei` and
`settei-env`).

Implement the types and functions listed under Interfaces and Dependencies. The runner
`runPreflight` proceeds in these steps, each of which is a separately testable function:

1. Validate the request purely with `validatePreflight`. Problems are collected in
   encounter order: an invalid or duplicated proposed variable name; a proposed value
   containing a NUL character; a file name that is empty, absolute, contains a `..`
   segment or a NUL, or duplicates another after normalization with `splitDirectories`;
   a file part naming no declared file, or a directory part that is not a parent, at any
   depth, of at least one declared file (both `unknown-file-reference`); a literal
   argument part whose text contains the value of a supplied or synthetic secret
   (`secret-in-argument`, carrying the argument index and the input name only); an
   inherited name that is invalid or that duplicates a proposed name; and an empty role
   label. Any problem yields a report with outcome `NotRun (RequestInvalid problems)`,
   coverage computed as usual, and no execution record.
2. Partition the inputs: supplied and synthetic values are present; unresolved and
   unavailable inputs are absent and become limitations. A synthetic value is present
   and also a limitation. Build the input summaries (channel, name, classification,
   whether passed).
3. Resolve the executable: a path containing a directory separator must exist as a
   file; a bare name is looked up with `findExecutable` in the harness process. Failure
   yields `NotRun (ExecutableNotFound path)`.
4. Materialize under `withSystemTempDirectory "settei-preflight"`: create each present
   file at `root </> name` (creating parents), render each argument by replacing file
   and directory parts with absolute materialized paths, and construct the child
   environment as the inherited names found in the harness environment followed by the
   present proposed entries. Record which inherited names were absent.
5. Execute with `withCreateProcess` (`proc executable arguments` with `cwd = Just
   root`, `env = Just childEnvironment`, `std_in = CreatePipe` closed immediately,
   `std_out = CreatePipe`, `std_err = CreatePipe`), reading both output handles in
   binary mode on separate threads, under `timeout (seconds * 1_000_000)`. A spawn
   `IOException` yields `NotRun (SpawnFailed category)` where the category is a fixed
   description such as `permission denied` or `other`, never the exception text. A
   timeout yields `NotRun (TimedOut seconds)` with an execution record whose exit code
   is `Nothing` and whose output is whatever was captured.
6. Redact: replace every occurrence of every supplied or synthetic secret value (longest
   first, skipping empty values) in the decoded stdout and stderr with
   `[redacted:NAME]`, where `NAME` is the variable name or `file NAME` for a file.
7. Classify the exit code with the mapping, compute coverage and verdict, and return
   the report.

`renderPreflightReportText` prints, in this order: a first line `preflight ROLE:
VERDICT (OUTCOME DETAIL)`, for example `preflight server: fail (configuration rejected,
exit 4)` or `preflight worker: inconclusive (accepted with partial coverage; not a
deployment validation)`; a `coverage:` line followed by one indented line per
limitation; an `inputs:` line followed by one indented line per proposed input with its
classification and `omitted` when not passed; an `inherited:` line listing each name with
`present` or `absent`; a `command:` line showing the resolved executable and the rendered
arguments with file parts shown as `{file:NAME}` and directory parts as `{dir:NAME}`
rather than temporary paths; a `notes:` line with one indented line per note when any
exist; then `stdout:` and `stderr:` blocks containing the redacted output indented by two
spaces or `(empty)`. `renderPreflightReportJson` emits the `settei.preflight` document
described under Interfaces and Dependencies, compact and without a trailing newline.
`renderPreflightProblemText` and `renderPreflightProblemsText` follow the adapter
renderer contract: one line per problem, names only.

Write the fixture in settei-preflight/test/Settei/Preflight/Fixture.hs as `fixtureMain
:: IO ()`, and make settei-preflight/test/Main.hs call it when `lookupEnv
"SETTEI_PREFLIGHT_FIXTURE"` returns `Just _`, otherwise run `defaultMain`. The fixture
reads `FIXTURE_BEHAVIOUR` and behaves as follows: `accept` prints `configuration
valid\n` and exits 0; `reject` prints `database.url: required value is missing\n` to
stderr and exits 4; `source-failure` prints `configuration file: could not be read\n` to
stderr and exits 3; `usage` prints a usage line to stderr and exits 2; `crash` prints
`unexpected failure\n` to stderr and exits 1; `echo` prints every environment variable as
`NAME=VALUE` lines to stdout in ascending name order, every argument on its own line to
stderr, then the content of every argument that names an existing file, and exits 0;
`sleep` sleeps 30 seconds and exits 0; `server-like` writes the file named by
`FIXTURE_STARTUP_MARKER` and prints `ready\n` unless `--check-config` is among its
arguments, in which case it prints `configuration valid\n` without touching the marker,
exiting 0 either way; `unicode` prints `runtime.environment: expected one of «dev»\n` to
stderr and exits 4.

Tests in settei-preflight/test/Settei/PreflightTest.hs obtain the fixture path with
`getExecutablePath` and always propose `SETTEI_PREFLIGHT_FIXTURE=1` and a
`FIXTURE_BEHAVIOUR`. Required cases: `accept` with only supplied values yields outcome
accepted, complete coverage, verdict `pass`, exit code `Just 0`, stdout `configuration
valid\n`; `reject` yields rejected with category configuration-rejected and verdict
`fail`; `source-failure` yields category source-failure; `usage` yields category usage;
`crash` yields category unknown-exit-code with the code; a nonexistent executable path
and a bare name not on `PATH` yield `ExecutableNotFound`; `sleep` with a one-second
timeout yields `TimedOut 1` and the test confirms the temporary directory no longer exists
afterwards (capture its path through the `echo` behaviour in a separate run, or by
listing the system temporary directory for `settei-preflight` entries before and after);
`echo` with inherited `[]` shows exactly the proposed variables and nothing from the
test process (assert `PATH`, `HOME`, and a variable the test sets with `setEnv` are
absent), and with inherited `[PATH, MISSING_NAME]` shows `PATH` and reports
`MISSING_NAME` absent; `echo` with a supplied secret sentinel in a variable and in a
file shows `[redacted:DATABASE_URL]` and `[redacted:file secrets/token]` in the report's
stdout and the sentinel nowhere in the text report, the JSON report, or `show` of the
outcome and coverage; `echo` with a two-part argument `yaml:{file:application.yaml}` and
a directory argument shows the materialized absolute paths in the fixture's stderr and
the file content in its stdout, while the report's command line shows `{file:…}`; one
`SyntheticValue Secret` stand-in with `accept` yields verdict `inconclusive` with one
`synthetic-stand-in` limitation and the stand-in redacted from output; one
`UnresolvedValue` and one `UnavailableSecret` with `accept` yield `inconclusive` with
both limitations and both inputs marked omitted, and with `reject` yield `fail` while
still listing both limitations; every validation problem kind from step 1 yields
`RequestInvalid` with the expected problem and no execution, including
`secret-in-argument` for a literal part equal to a secret value; `server-like` without
`--check-config` creates the marker and `server-like` with `--check-config` does not,
proving the instrumentation and the configuration-only path; `unicode` with the default
inherited allowlist renders the non-ASCII message intact in the report; rendering the
same report twice yields byte-identical text and JSON; and goldens
settei-preflight/test/golden/report-fail.txt, report-fail.json,
report-inconclusive.txt, and report-inconclusive.json pin the vocabulary (write the
goldens by hand from the documented format first, then correct them to real output only
after reviewing the diff for leaks).

### Milestone 2 — Request document and executable

Scope: the interface deployment tooling uses. At the end, a JSON request on disk can be
turned into a report by one command whose exit code is a gate decision.

Add settei-preflight/src/Settei/Preflight/Request.hs with the types and functions under
Interfaces and Dependencies, adding `aeson >=2.2 && <2.3` to the library. Parsing uses
`withObject` and an explicit allowed-key check at every object so unknown keys fail with
a path such as `environment[2]: unknown key "vlaue"`. The forms of an environment or file
entry are: `value` (supplied, public; `sensitivity` is not allowed with `value`),
`secretFromEnvironment`, `secretFromFile`, `synthetic` with required `reason` and
optional `sensitivity` (`public` by default, `secret` allowed), `unresolved` (a reason),
and `unavailableSecret` (a reason). Exactly one form key must be present. An argument
is `{"literal": T}`, `{"file": F}`, `{"directory": D}`, or `{"parts": [...]}` whose parts
are single-form objects. `schemaVersion` must be `1` and `type` must be
`settei.preflight-request`. `inherit`, `timeoutSeconds` (positive), `exitCodes`, `files`,
and `notes` are optional with the documented defaults. `renderPreflightRequestJson`
emits a document that parses back to an equal value, so the example extractor and tests
can round-trip.

`resolveRequest` takes a `RequestEnvironment` (two actions: look up a variable of the
harness process and read a secret file) and turns each `secretFromEnvironment` into
`SuppliedValue Secret value` or `UnavailableSecret "harness environment variable NAME is
not set"`, and each `secretFromFile` into `SuppliedValue Secret content` (read as bytes,
decoded as UTF-8, never trimmed) or `UnavailableSecret "secret file PATH could not be
read"`. `processRequestEnvironment` uses `lookupEnv` and `ByteString.readFile`.

Create settei-preflight/app/Main.hs for the executable `settei-preflight` using
optparse-applicative 0.19 with two option groups, "Preflight" (`--request PATH`,
required) and "Output" (`--json`), `failureCode 2`, and `hSetEncoding` of stdout and
stderr to UTF-8. It reads the file, parses, resolves with the process environment, runs
the harness, prints the report to stdout, and exits by the verdict mapping in the
Decision Log; an unreadable or unparseable document prints one problem line per error
to stderr and exits 3. Add `optparse-applicative >=0.19 && <0.20` to the executable and
wrap the Nix derivation in `dontCheck` with the siblings' comment.

Tests (same suite; add `build-tool-depends: settei-preflight:settei-preflight` to the
test-suite stanza so the executable is on `PATH`): parse the golden
settei-preflight/test/golden/request.json covering every entry form, both argument
shapes, `inherit`, `timeoutSeconds`, `exitCodes`, and `notes`, and assert the resolved
`ProposedInputs` classify as expected with an injected `RequestEnvironment` whose
variable lookup returns a sentinel for one reference and `Nothing` for another and whose
file reader succeeds for one path and fails for another; reject an inline
`{"value": …, "sensitivity": "secret"}` entry, an entry with two forms, an entry with no
form, an unknown top-level key, an unknown entry key, a wrong `type`, a wrong
`schemaVersion`, and a non-positive timeout, each with a message naming the path; prove
`renderPreflightRequestJson` round-trips and is byte-identical across two calls; and run
the executable with `readProcessWithExitCode` against request files that point at the
fixture application (write them into a temporary directory with the test executable's
path): exit `0` with `pass` for `accept`, `1` for `accept` with a synthetic entry, `4` for
`reject`, `3` for a missing request file, an unparseable document, a request whose
executable does not exist, and a `sleep` request with `timeoutSeconds: 1`; `--json`
output begins `{"schemaVersion":1,"type":"settei.preflight"`; and a secret reference
resolved from the test process environment (set with `setEnv` before spawning the
executable, which inherits the test's environment) is redacted in both text and JSON
output while the request file on disk never contained it.

Update settei-preflight/CHANGELOG.md and README.md to describe the document and the
executable.

### Milestone 3 — Reference workflow on the notification-hub-shaped example

Scope: prove the harness at the conformance boundary with real server and worker
processes, and provide the deployment-shaped extraction example. Prerequisite: plan 26
implemented through Milestone 4, so that `examples/settei-deployment` exists with the
two executables and `runDeploymentWithSnapshot`. Verify with `ls
examples/settei-deployment/app/server/Main.hs` before starting; if absent, implement plan
26 first.

Add to examples/settei-deployment/settei-example-deployment.cabal: library dependencies
`aeson`, `settei-preflight ==0.2.0.0`, `filepath`, and `containers`; a new library module
`Settei.Example.Deployment.Preflight`; an executable `settei-example-deployment-preflight`
(app/preflight/Main.hs); test dependencies `settei-preflight`, `aeson`, `directory`,
`process`, and `temporary`; and `build-tool-depends:
settei-example-deployment:settei-example-deployment-server,
settei-example-deployment:settei-example-deployment-worker` on the test suite. Add the
fixture examples/settei-deployment/test/fixtures/rendered-production.json to
`data-files`. Update flake.module.nix's `setteiExampleDeploymentPackage` call with
`settei-preflight = setteiPreflightPackage;` and mori.dhall's package entry with the
dependency.

The fixture is a Kubernetes `List` containing: a ConfigMap `settei-example-deployment`
with data `ENVIRONMENT: production`, `DELIVERY_ENDPOINT:
http://delivery.production.internal:8080`, and `application.yaml` holding `server.host:
0.0.0.0` and `database.poolSize: 20`; a Secret `settei-example-deployment-secrets` whose
`stringData` keys are `DATABASE_URL`, `WEBHOOK_SECRET`, and `EMAIL_CREDENTIALS_JSON` with
values that are unmistakable placeholders; a Deployment `settei-example-deployment-server`
whose init container `check-config` has args `--config /etc/settei/application.yaml
--check-config`, env entries `ENVIRONMENT` and `DELIVERY_ENDPOINT` via `configMapKeyRef`,
`DATABASE_URL`, `WEBHOOK_SECRET`, and `EMAIL_CREDENTIALS_JSON` via `secretKeyRef`,
`POD_NAMESPACE` via `fieldRef metadata.namespace`, and `HTTP_HOST` as a literal `value`,
with a `configMap` volume mounting item `application.yaml` at `/etc/settei`; and a
Deployment `settei-example-deployment-worker` identical except for literal
`WORKER_CONCURRENCY: "16"` and `WORKER_VISIBILITY_TIMEOUT_SECONDS: "180"`. Add a
`projected` volume mounted at `/var/run/example` on the worker's checked container so an
unsupported input exists in the fixture.

The extractor `extractPreflightRequest :: ExtractionOptions -> Aeson.Value -> Either
ExtractionError (PreflightRequest, [Text])` (options: deployment name, container name
defaulting to `check-config`, role label, host executable path, secret variable prefix
defaulting to `SETTEI_PREFLIGHT_SECRET_`, synthetic public and secret substitutions by
variable name) handles exactly these inputs and documents them in its Haddock and the
guide: `env[].value` becomes a supplied public value; `configMapKeyRef` is resolved from
a ConfigMap in the list (missing object or key becomes `unresolved` with a reason, or is
omitted with a note when `optional: true`); `secretKeyRef` becomes a
`secretFromEnvironment` reference named `PREFIX <> sanitize(secretName) <> "_" <>
sanitize(key)`, where `sanitize` upper-cases and replaces every character that is not an
ASCII letter or digit with `_`, and the Secret manifest's values are never read;
`fieldRef` becomes `unresolved` unless a synthetic substitution is given for that
variable; `envFrom.configMapRef` expands every key of a ConfigMap in the list;
`envFrom.secretRef` expands the keys of a Secret in the list into references, and
produces a note when the Secret is absent (its keys are unknown); `configMap` volume
items mounted by the container become files named by the mount path relative to a
virtual root (for example `etc/settei/application.yaml`) with the ConfigMap data as
content; `secret` volume items become `secretFromEnvironment` file references with the
same naming rule; and every argument of the checked container is scanned for mount paths
of those files and directories and rewritten into parts, so `/etc/settei/application.yaml`
becomes `{"file": "etc/settei/application.yaml"}` and `--secrets-dir /etc/settei/secrets`
would become a directory part. Everything else, specifically `resourceFieldRef`,
`subPathExpr`, `projected`, `downwardAPI`, `csi`, `emptyDir`, and `persistentVolumeClaim`
volumes that are mounted, an env entry whose `valueFrom` has an unknown key, and an
argument containing an absolute path that matches no mount, becomes a note; an env entry
with an unknown `valueFrom` is additionally emitted as `unresolved` so its name stays
visible. Notes are copied into the request's `notes`, so the report shows them. The
executable `settei-example-deployment-preflight` parses `--manifest PATH`,
`--deployment NAME`, `--container NAME`, `--role LABEL`, `--executable PATH`,
`--secret-prefix TEXT`, repeated `--synthetic NAME=VALUE`, and repeated
`--synthetic-secret NAME=VALUE`, prints the request JSON to stdout and the notes to
stderr, and exits 2 on usage errors or 3 on extraction errors.

Tests in examples/settei-deployment/test/Settei/Example/DeploymentTest.hs (new
`testGroup "preflight"`), locating the executables with `findExecutable`:

- Precedence and role (AC-1): write an `application.yaml` setting `server.port: 9000`,
  propose `PORT=9100` with a complete production environment (built from plan 26's
  complete snapshot, with the secrets as `SuppliedValue Secret`), and run the server
  with `--config {file} --set server.port=9200 --explain-config-json`; assert exit 0 and
  that the stdout names `server.port` with value `9200` from a command-line origin and
  retains shadowed environment and file origins. Run the same inputs with
  `--check-config` through the harness and in-process through
  `runDeploymentWithSnapshot Server` with an equivalent snapshot and options and assert
  equal exit codes and equal stderr. Then propose `WORKER_VISIBILITY_TIMEOUT_SECONDS=1`
  and run both roles: the worker report is `fail` with the capacity message and the
  server report is `pass`, each naming its role.
- Extraction and mutation (AC-2): extract server and worker requests from the fixture,
  assert the notes list the `projected` volume for the worker and nothing for the server,
  assert `POD_NAMESPACE` is `unresolved` without a substitution and synthetic with one,
  assert the three secret references use the documented names, and assert the request
  renders to JSON that parses back equal. Resolve with an injected `RequestEnvironment`
  supplying `DATABASE_URL` and `WEBHOOK_SECRET` (a 24-character stand-in) and leaving
  `EMAIL_CREDENTIALS_JSON` unset: the server report is `fail` listing the unavailable
  secret as a limitation and `email.credentials: required value is missing` in stderr.
  Supplying all three with `POD_NAMESPACE` synthetic yields `inconclusive` for both
  roles with exactly one limitation. Then mutate the parsed manifest before extraction
  and assert each yields `fail` with the expected stderr: ConfigMap `ENVIRONMENT: prod`
  (decoder rejection, exit 4); `application.yaml` content `server: [` (source failure,
  exit 3); the server's `DATABASE_URL` entry pointing at a nonexistent Secret key, so
  that no provisioning variable matches (unavailable, exit 4 with the missing-required
  line); and the worker's `WORKER_VISIBILITY_TIMEOUT_SECONDS` literal set to `"1"`
  (worker `fail`, server unaffected). Also assert, as documented honesty, that renaming
  the ConfigMap key and variable from `ENVIRONMENT` to `HASKELL_ENV` still yields
  `inconclusive` or `pass`, because check mode cannot see an unbound name; the guide
  points at plan 27's supplied-name validation for that gap.
- Configuration-only execution (AC-5): with `DATABASE_URL` set to
  `postgres://preflight.invalid:5432/notification` and no network or database available,
  both roles accept; the captured stdout is exactly `configuration valid\n`, never the
  startup summary; and the harness's own fixture marker test from Milestone 1 is cited
  as the instrumentation evidence that check mode exits before a startup path.
- Sentinels (AC-4): with secret sentinels in `DATABASE_URL`, `WEBHOOK_SECRET`, and
  `EMAIL_CREDENTIALS_JSON`, no sentinel appears in the request JSON, the text report,
  the JSON report, or the executable's stdout and stderr when run through
  `settei-example-deployment-preflight` and `settei-preflight`.

Update examples/settei-deployment/README.md with a "Preflight" section describing the
fixture, the extractor's handled and unhandled inputs, and the two commands.

### Milestone 4 — Documentation and collateral

Scope: make the workflow discoverable, bounded, and recorded, and close the request.

Write docs/guides/deployment-preflight.md ("Preflight-checking proposed deployment
inputs", `docId: DOC-12` after re-running `okf id next`, `type: Guide`, tags `[settei,
deployment, preflight]`, `generated.by` per the bundle's existing records). It walks the
Purpose transcript end to end: what check mode is and why the application's own checks
are the only acceptable validator; the request document with one entry of every form
and the rule that secrets are references; building a request by hand for a container
specification, then with the reference extractor, listing its handled inputs and its
notes verbatim; running `settei-preflight`, reading the text report, and the verdict and
exit-code table; the pre-provisioning pattern (synthetic stand-ins give at most
`inconclusive`; unresolved values are omitted so the application's missing-required
errors appear; unavailable secrets block); and the post-provisioning complement, the
init-container gate in docs/guides/kubernetes-cookbook.md. State the limits in words:
the harness executes a caller-chosen command and cannot prove an arbitrary executable has
no effects; the documented contract and the tested reference paths establish that Settei
check modes exit before resource acquisition; configuration acceptance does not
establish database connectivity, provider authentication, deployed image identity, or
readiness, which remain live checks; a renamed variable is invisible to check mode and
needs plan 27's supplied-name validation; the harness inherits only the documented
allowlist; a child ignoring `SIGTERM` is not force-killed; secrets written to disk live
only in a `0700` directory for the duration of the run. Register the guide: add a row to
docs/guides/README.md, regenerate docs/guides/index.md with `okf index docs/guides
--write --okf-version 0.2`, and append a log entry. Add a paragraph at the end of
section 6 of docs/guides/kubernetes-cookbook.md linking the preflight guide as the
pre-provisioning half of the gate, and a row to the diagnostics table in
docs/guides/cli-application.md pointing at the harness as the way to run check mode on
proposed inputs.

Write docs/capabilities/deployment-preflight-harness.md (`capabilityId: CAP-15`,
packages `settei-preflight`, interface `Settei.Preflight` and
`Settei.Preflight.Request`, `requires` CAP-7, `since` the next release version the
changelog bump implies, evidence rows for settei-preflight/test/Settei/PreflightTest.hs,
the deployment example's preflight group, and the guide; a Limits list repeating the
non-claims). Add the table row by hand to docs/capabilities/index.md and append a log
entry.

Write docs/adr/0013-deployment-preflight-harness-semantics.md with the profile
frontmatter (`docId: ADR-13` after re-running `okf id next`). It records: the harness
runs the application's own check command and owns no configuration rules; the request
document admits secrets only by reference; the child's environment is built from the
request plus a documented allowlist; secrets reach the child only through environment
or files beneath a private temporary directory removed after the run; captured output is
redacted using the secrets the harness was given; the verdict rule and the gate rule;
the exit-code mapping and its default; the `settei.preflight-request` and
`settei.preflight` documents are tooling documents encoded with Aeson in fixed pair order
with byte-identical goldens, outside the core's encoder rule; and the rejected
alternatives (a Haskell-only API without a document, inline secrets with a warning,
inheriting the whole process environment, parsing application output into structure
before IR-4, force-killing children, and a Pulumi or Kubernetes client dependency).
Append a dated amendment to
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md stating
that the deployment example also exercises the preflight harness through its executables
and a rendered-manifest extractor, still without cluster access. Record both with `okf
log add docs/adr …`.

Update README.md (package map row for `settei-preflight`; guides list; release-status
sentence), docs/compatibility.md (public modules: `Settei.Preflight` and
`Settei.Preflight.Request`; library rows for `process`, `temporary`, and the preflight
use of `aeson`; an input-contracts row for the request document), docs/security.md (a
"Preflight harness" section: secrets only by reference in documents, only through
environment or `0700` temporary files toward the child, redaction of captured output,
reports are operational metadata that reveal names and topology, and the harness cannot
vouch for an arbitrary executable), and settei-preflight/CHANGELOG.md. Finally edit
docs/improvement-requests/provide-a-reusable-deployment-preflight-workflow.md. The record
already carries `status: accepted` and `targetPlan` naming this plan (set when the plan
was created); the first implementation session moves it to `status: in-progress`, and
this milestone sets `status: completed`, adds `completedAt` (RFC 3339 UTC) and a
`resolution` line naming this plan and the test evidence, following the field names in
docs/improvement-requests/profile.dhall (okf-profiles v0.22.0). Run the strict
validation after each lifecycle edit and append a log entry.

### Milestone 5 — Full validation and closure

Run the complete gates listed in Validation and Acceptance, record the test totals and
the Purpose transcript in this plan, write Outcomes & Retrospective, and confirm ADR-13
and the ADR-7 amendment capture everything durable from the Decision Log and Surprises &
Discoveries.


## Concrete Steps

All commands run from the repository root /Users/shinzui/Keikaku/bokuno/settei unless
stated otherwise. `nix develop -c` supplies GHC 9.12.4, Cabal 3.16, fourmolu, treefmt,
and hlint; `okf`, `bun`, and `mori` are on the user's PATH.

Baseline before any change:

```bash
git status --short            # expect no output
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
```

Milestone 1:

```bash
mkdir -p settei-preflight/{src/Settei,test/Settei/Preflight,test/golden}
cp settei-env/LICENSE settei-preflight/LICENSE
# create settei-preflight.cabal, README.md, CHANGELOG.md, src/Settei/Preflight.hs,
# test/Main.hs, test/Settei/PreflightTest.hs, test/Settei/Preflight/Fixture.hs, goldens;
# edit cabal.project, flake.module.nix, mori.dhall
nix develop -c cabal build settei-preflight
nix develop -c cabal test settei-preflight-tests --test-show-details=direct
```

Expected tail of the test run:

```text
    Settei.Preflight
      accept with supplied inputs passes:                     OK
      reject maps exit 4 to configuration-rejected:           OK
      timeout terminates the child and removes the directory: OK
      echoed secrets are redacted in the report:              OK
      server-like fixture never touches the marker in check mode: OK
      ...
All N tests passed (1.xxs)
Test suite settei-preflight-tests: PASS
```

Milestone 2:

```bash
mkdir -p settei-preflight/app
# create src/Settei/Preflight/Request.hs, app/Main.hs, test/golden/request.json;
# edit settei-preflight.cabal (aeson, executable, build-tool-depends), flake.module.nix (dontCheck)
nix develop -c cabal build settei-preflight
nix develop -c cabal test settei-preflight-tests --test-show-details=direct
printf '%s\n' '{"schemaVersion":1,"type":"settei.preflight-request","role":"smoke","command":{"executable":"/definitely/missing","arguments":[]},"environment":[]}' > /tmp/smoke-request.json
nix develop -c cabal run settei-preflight -- --request /tmp/smoke-request.json; echo "exit $?"
```

Expected output of the smoke run:

```text
preflight smoke: fail (not run: executable not found: /definitely/missing)
coverage: complete
inputs: (none)
inherited: PATH (present), LANG (present), LC_ALL (absent), LC_CTYPE (absent)
command: /definitely/missing
stdout:
  (empty)
stderr:
  (empty)
exit 3
```

(Presence of the inherited names depends on your shell.)

Milestone 3 (after plan 26 Milestone 4):

```bash
ls examples/settei-deployment/app/server/Main.hs      # must exist
mkdir -p examples/settei-deployment/app/preflight
# create src/Settei/Example/Deployment/Preflight.hs, app/preflight/Main.hs,
# test/fixtures/rendered-production.json; edit the cabal file, the test module, README.md,
# flake.module.nix, mori.dhall
nix develop -c cabal build settei-example-deployment
nix develop -c cabal test settei-example-deployment-tests --test-show-details=direct
nix develop -c cabal run settei-example-deployment-preflight -- \
  --manifest examples/settei-deployment/test/fixtures/rendered-production.json \
  --deployment settei-example-deployment-server --role server \
  --executable "$(nix develop -c cabal list-bin settei-example-deployment-server)" \
  --synthetic POD_NAMESPACE=production > /tmp/server-request.json
SETTEI_PREFLIGHT_SECRET_SETTEI_EXAMPLE_DEPLOYMENT_SECRETS_DATABASE_URL='postgres://preflight.invalid/notification' \
SETTEI_PREFLIGHT_SECRET_SETTEI_EXAMPLE_DEPLOYMENT_SECRETS_WEBHOOK_SECRET='preflight-stand-in-webhook-secret' \
  nix develop -c cabal run settei-preflight -- --request /tmp/server-request.json; echo "exit $?"
grep -c preflight-stand-in-webhook-secret /tmp/server-request.json   # expect 0
```

The preflight run must exit `4`, show `EMAIL_CREDENTIALS_JSON` as an unavailable secret
limitation, and show `email.credentials: required value is missing` in the stderr block.
Re-run with `SETTEI_PREFLIGHT_SECRET_SETTEI_EXAMPLE_DEPLOYMENT_SECRETS_EMAIL_CREDENTIALS_JSON='{}'`
added: exit `1` and verdict `inconclusive` with the single `POD_NAMESPACE` limitation.

Milestone 4:

```bash
okf id next docs/guides --profile mori/user-documentation-profile.dhall DOC        # expect DOC-12 after plan 26
okf id next docs/capabilities --profile docs/capabilities/profile.dhall CAP        # expect CAP-15 after plan 26
okf id next docs/adr --profile docs/adr/profile.dhall ADR                          # expect ADR-13 after plan 26
# write the guide, capability, ADR, amendment, cookbook/CLI-guide cross-links,
# README/compat/security/changelog edits, IR-3 lifecycle fields
okf index docs/guides --write --okf-version 0.2
okf index docs/adr --write --okf-version 0.2
okf index docs/improvement-requests --write --okf-version 0.2
okf log add docs/guides --kind Add -m "DOC-12 preflight-checks proposed deployment inputs with application check mode; DOC-8 links the pre-provisioning half of the rollout gate."
okf log add docs/capabilities --kind Add -m "CAP-15 deployment preflight harness."
okf log add docs/adr --kind Add -m "ADR-13 fixes deployment preflight harness semantics; ADR-7 amended for the preflight reference workflow."
okf log add docs/improvement-requests --kind Update -m "IR-3 completed by docs/plans/28-provide-a-reusable-deployment-preflight-harness-around-application-check-mode.md."
okf validate docs/adr --strict --profile docs/adr/profile.dhall --profile-enforce --log-enforce
okf validate docs/guides --strict --profile mori/user-documentation-profile.dhall --profile-enforce --log-enforce
okf validate docs/capabilities --profile docs/capabilities/profile.dhall --profile-enforce --log-enforce
okf validate docs/improvement-requests --strict --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
```

docs/capabilities/index.md carries hand-written prose, so add the CAP-15 row by hand
rather than regenerating that index.

Milestone 5:

```bash
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
(cd settei-preflight && nix develop -c cabal check)
nix develop -c treefmt --fail-on-change --no-cache
nix flake check
mori registry show shinzui/settei --full | grep settei-preflight
```

Commits: one per milestone at minimum, each with the trailers

```text
ExecPlan: docs/plans/28-provide-a-reusable-deployment-preflight-harness-around-application-check-mode.md
Intention: intention_01m5faf5apez5s3g1d4hyxj2r0
```

and a Conventional Commits subject such as `feat(settei-preflight): run application
check mode on proposed deployment inputs`. Record a provenance revision entry the first
time this plan is edited in an implementation session:

```bash
bun .claude/skills/exec-plan/record-provenance.ts revision \
  --plan docs/plans/28-provide-a-reusable-deployment-preflight-harness-around-application-check-mode.md \
  --model <your-model-id> --harness <harness> --mode implement --note "<one line>"
```


## Validation and Acceptance

Each acceptance criterion of IR-3 maps to observable checks:

- AC-1 (reusable harness preserving precedence and role). The fixture tests prove that
  exactly the proposed environment, the materialized files, and the rendered arguments
  reach the child (`echo` behaviour) and nothing else. The deployment example's
  precedence test shows a command-line override beating an environment value beating a
  file value in the application's own `--explain-config-json` output run through the
  harness, equal exit codes and stderr between the harness and
  `runDeploymentWithSnapshot` for `--check-config`, and a worker-only capacity failure
  with the server passing on the same inputs, each report naming its role. No run opens
  a database or listener.
- AC-2 (documented interface without reimplementing rules). The `settei.preflight-request`
  document is parsed strictly with path-bearing errors; the executable turns a document
  into a verdict; the extractor converts the rendered manifest fixture into requests for
  both roles and the mutation tests fail for a changed ConfigMap value, a malformed file
  input, a broken secret mapping, and a worker-specific value. The handled input kinds
  and the notes mechanism are asserted in tests and stated in the extractor's Haddock,
  the example README, and the guide. The harness contains no decoder, default, or
  invariant; every rejection in the tests is produced by the application process.
- AC-3 (honest coverage). Fixture tests cover a supplied public value, a supplied
  secret, a synthetic secret stand-in, an unresolved value, and an unavailable secret,
  asserting the classification of each input, the limitation list, the `omitted`
  marking, and the verdicts `pass`, `inconclusive`, and `fail`. The deployment example
  reproduces the five classifications from an extracted request. The text and JSON
  reports state in words that `inconclusive` is not a deployment validation, and the
  executable's exit code is `0` only for `pass`.
- AC-4 (secret channels and attributable errors). Sentinels injected through variables
  and files never appear in request documents, reports, `show` output, or the
  executable's stdout and stderr, even when the fixture application echoes them; a
  literal argument containing a secret invalidates the request before anything runs; the
  executable-not-found, source-loading (exit 3), configuration-rejected (exit 4), crash,
  and timeout paths each produce the documented outcome; the temporary directory is
  gone after a timeout; and every report carries the role label.
- AC-5 (configuration-only checks separated from readiness). The `server-like` fixture
  proves that check mode never reaches the startup marker while a non-check run does.
  Both deployment roles accept with an unreachable database URL and no network, and
  their stdout is exactly `configuration valid`. The guide separates these results from
  connectivity, credentials, image identity, and readiness, and names the init-container
  gate and live probes as the later checks.

Required gates before the plan is complete: all Milestone 5 commands pass; the four
`okf validate` commands pass; `cabal check` in settei-preflight reports no errors; the
Purpose transcript is reproduced and pasted into this section; `git status --short` is
empty after the final commit.

Expected text report excerpt for the server request with all secrets provisioned and
`POD_NAMESPACE` synthetic (vocabulary, ordering, redaction, and the verdict sentence are
requirements; exact spacing is not):

```text
preflight server: inconclusive (accepted with partial coverage; not a deployment validation)
coverage: partial
  POD_NAMESPACE: synthetic stand-in (downward API fieldPath metadata.namespace)
inputs:
  DATABASE_URL: supplied secret
  DELIVERY_ENDPOINT: supplied public
  EMAIL_CREDENTIALS_JSON: supplied secret
  ENVIRONMENT: supplied public
  HTTP_HOST: supplied public
  POD_NAMESPACE: synthetic public
  WEBHOOK_SECRET: supplied secret
  file etc/settei/application.yaml: supplied public
inherited: PATH (present), LANG (present), LC_ALL (absent), LC_CTYPE (absent)
command: /…/settei-example-deployment-server --config {file:etc/settei/application.yaml} --check-config
stdout:
  configuration valid
stderr:
  (empty)
```

Proposed, not required: emitting plan 27's `--supplied-env` arguments from the proposed
names; a comparison of the request's variable names against plan 26's deployment
contract; parsing the application's JSON output once IR-4 lands; a TypeScript request
builder in `mori://tan/tan-app-infrastructure`. Each needs a scope decision before
becoming acceptance.


## Idempotence and Recovery

Every build and test command is safe to repeat. The harness itself is idempotent by
construction: each run uses a fresh temporary directory removed by `bracket`, and
re-running a request changes nothing outside that directory. `okf id next` only reports
the next free handle; `okf log add` appends, so run each once and remove a duplicated
entry by hand if repeated; `okf index --write` is deterministic. If a golden test fails
after an intentional renderer change, inspect the diff for secret leaks before updating
the golden. If a fixture-mode test hangs, the `sleep` behaviour is the likely cause and
the one-second timeout in that test is the first thing to check. If the Nix derivation
for the new package fails to evaluate, the Cabal build and tests remain authoritative;
fix the flake.module.nix entry by comparing it line by line with `setteiEnvPackage` and
the `dontCheck` siblings. If Milestone 3 begins before plan 26 Milestone 4 has landed,
stop and implement that first; Milestones 1 and 2 can be committed independently. If the
strict validation of docs/improvement-requests fails after a lifecycle edit, restore the
record's frontmatter from git, fix the field the validator names, and retry. If a
milestone must be abandoned midway, commit only green states; the previous milestone's
commit is always a clean restart point.


## Interfaces and Dependencies

New public module `Settei.Preflight` in the `settei-preflight` package:

```haskell
-- Identity and command
newtype RoleLabel = RoleLabel Text                     -- deriving stock (Generic, Eq, Show)
newtype FileName = FileName Text                       -- relative path with '/' separators
data ArgumentPart = LiteralPart !Text | FilePart !FileName | DirectoryPart !FileName
newtype Argument = Argument [ArgumentPart]
literalArgument :: Text -> Argument
fileArgument :: FileName -> Argument
data CheckCommand = CheckCommand { executable :: !FilePath, arguments :: ![Argument] }

-- Proposed inputs (no Show instances for ProposedValue, ProposedFile, ProposedInputs)
data ProposedValue
  = SuppliedValue !Sensitivity !Text
  | SyntheticValue !Sensitivity !Text !Text            -- stand-in value, reason
  | UnresolvedValue !Text                              -- reason
  | UnavailableSecret !Text                            -- reason
data ProposedFile = ProposedFile { name :: !FileName, content :: !ProposedValue }
data ProposedInputs = ProposedInputs
  { environment :: ![(EnvName, ProposedValue)],
    files :: ![ProposedFile],
    inherited :: ![EnvName],
    notes :: ![Text] }                                  -- caller notes carried into the report
defaultInherited :: [EnvName]                          -- PATH, LANG, LC_ALL, LC_CTYPE
emptyProposedInputs :: ProposedInputs                  -- no inputs, defaultInherited, no notes

-- Options
data ExitCodeMapping = ExitCodeMapping
  { accepted :: !Int, usage :: ![Int], sourceFailure :: ![Int], rejected :: ![Int] }
defaultExitCodes :: ExitCodeMapping                    -- 0, [2], [3], [4]
data PreflightOptions = PreflightOptions { timeoutSeconds :: !Int, exitCodes :: !ExitCodeMapping }
defaultPreflightOptions :: PreflightOptions            -- 60 seconds, defaultExitCodes

-- Validation (pure)
data PreflightProblem
  = InvalidEnvironmentName !EnvName | DuplicateEnvironmentName !EnvName
  | InvalidEnvironmentValue !EnvName
  | InvalidFileName !FileName | DuplicateFileName !FileName
  | UnknownFileReference !Int !FileName                -- argument index, name
  | SecretInArgument !Int !InputRef                    -- argument index, which secret
  | InvalidInheritedName !EnvName | InheritedNameProposed !EnvName
  | EmptyRoleLabel
data InputRef = EnvironmentInput !EnvName | FileInput !FileName
validatePreflight :: RoleLabel -> CheckCommand -> ProposedInputs -> Either (NonEmpty PreflightProblem) ()
renderPreflightProblemText :: PreflightProblem -> Text
renderPreflightProblemsText :: NonEmpty PreflightProblem -> Text

-- Running
runPreflight :: PreflightOptions -> RoleLabel -> CheckCommand -> ProposedInputs -> IO PreflightReport

-- Report (all types derive Generic, Eq, Show; they never hold a value)
data PreflightReport = PreflightReport
  { role :: !RoleLabel, command :: !CommandSummary, inputs :: ![InputSummary],
    inherited :: ![(EnvName, Bool)], notes :: ![Text],
    outcome :: !Outcome, coverage :: !Coverage, verdict :: !Verdict,
    execution :: !(Maybe Execution) }
data CommandSummary = CommandSummary { executable :: !FilePath, arguments :: ![Text] }
data InputSummary = InputSummary { input :: !InputRef, classification :: !Classification, passed :: !Bool }
data Classification
  = SuppliedPublic | SuppliedSecret | SyntheticPublic | SyntheticSecret | Unresolved | UnavailableSecretInput
data Outcome = Accepted | Rejected !RejectionCategory !Int | NotRun !NotRunReason
data RejectionCategory = UsageError | SourceFailure | ConfigurationRejected | UnknownExitCode
data NotRunReason
  = RequestInvalid !(NonEmpty PreflightProblem) | ExecutableNotFound !FilePath
  | SpawnFailed !Text | TimedOut !Int
data Coverage = CompleteCoverage | PartialCoverage !(NonEmpty Limitation)
data Limitation = Limitation { input :: !InputRef, kind :: !LimitationKind, reason :: !Text }
data LimitationKind = SyntheticStandIn | NotYetResolved | SecretUnavailable
data Verdict = Pass | Inconclusive | Fail
data Execution = Execution
  { exitCode :: !(Maybe Int), timedOut :: !Bool, standardOutput :: !Text, standardError :: !Text }
renderPreflightReportText :: PreflightReport -> Text
renderPreflightReportJson :: PreflightReport -> Text       -- settei.preflight, no trailing newline
```

`ProposedValue`, `ProposedFile`, and `ProposedInputs` derive `Generic` and `Eq` only.
No record field is named `bindings`, because the reference applications import
`Settei.Env` unqualified and `Settei.Env.bindings` would become ambiguous;
`DuplicateRecordFields` and generic-lens labels resolve the remaining shared field names
as elsewhere in the family. No lens type appears in a public signature (the
compatibility policy's audit rule).

JSON layout of `settei.preflight` (`schemaVersion` 1), keys in this order:
`schemaVersion`, `type`, `role`, `verdict` (`pass`/`inconclusive`/`fail`), `outcome`
(object: `kind` = `accepted`/`rejected`/`not-run`; for `rejected` also `category` =
`usage`/`source-failure`/`configuration-rejected`/`unknown-exit-code` and `exitCode`;
for `not-run` also `reason` = `request-invalid`/`executable-not-found`/`spawn-failed`/
`timed-out`, `detail` string or null, and `problems` array of `{kind, name, argument}`
with `kind` spelled `invalid-environment-name`, `duplicate-environment-name`,
`invalid-environment-value`, `invalid-file-name`, `duplicate-file-name`,
`unknown-file-reference`, `secret-in-argument`, `invalid-inherited-name`,
`inherited-name-proposed`, or `empty-role-label`), `coverage` (object: `kind` =
`complete`/`partial`, `limitations` array of `{channel, name, limitation, reason}` with
`channel` = `environment`/`file` and `limitation` = `synthetic-stand-in`/
`not-yet-resolved`/`secret-unavailable`), `inputs` (array of `{channel, name,
classification, passed}` with `classification` = `supplied-public`/`supplied-secret`/
`synthetic-public`/`synthetic-secret`/`unresolved`/`unavailable-secret`), `inherited`
(array of `{name, present}`), `notes` (array of strings), `command` (`{executable,
arguments}` with arguments rendered as in the text report), and `execution` (null or
`{exitCode (int or null), timedOut, stdout, stderr}`).

New public module `Settei.Preflight.Request`:

```haskell
-- The parsed document. It derives Generic, Eq, and Show because it can never hold a
-- secret value: secrets appear only as references.
data PreflightRequest = PreflightRequest
  { role :: !RoleLabel,
    command :: !CheckCommand,
    environment :: ![RequestEntry],
    files :: ![RequestEntry],                           -- entry names are relative paths
    inherit :: !(Maybe [EnvName]),                      -- Nothing means defaultInherited
    timeoutSeconds :: !Int,
    exitCodes :: !ExitCodeMapping,
    notes :: ![Text] }
data RequestEntry = RequestEntry { name :: !Text, form :: !EntryForm }
data EntryForm
  = InlineValue !Text
  | SecretFromEnvironment !EnvName
  | SecretFromFile !FilePath
  | SyntheticEntry !Sensitivity !Text !Text             -- sensitivity, stand-in, reason
  | UnresolvedEntry !Text
  | UnavailableSecretEntry !Text
preflightRequest :: RoleLabel -> CheckCommand -> [RequestEntry] -> [RequestEntry] -> PreflightRequest
                                                       -- environment entries, file entries;
                                                       -- inherit Nothing, 60 seconds, defaultExitCodes, no notes
parsePreflightRequest :: ByteString -> Either (NonEmpty RequestError) PreflightRequest
renderPreflightRequestJson :: PreflightRequest -> Text   -- settei.preflight-request, round-trips
newtype RequestError = RequestError Text                  -- "path: message"
renderRequestErrorText :: RequestError -> Text
renderRequestErrorsText :: NonEmpty RequestError -> Text

data RequestEnvironment = RequestEnvironment
  { lookupVariable :: EnvName -> IO (Maybe Text),
    readSecretFile :: FilePath -> IO (Either Text Text) }
processRequestEnvironment :: RequestEnvironment
data ResolvedRequest = ResolvedRequest
  { role :: !RoleLabel, command :: !CheckCommand, inputs :: !ProposedInputs,
    options :: !PreflightOptions, notes :: ![Text] }
resolveRequest :: RequestEnvironment -> PreflightRequest -> IO ResolvedRequest
```

JSON layout of `settei.preflight-request` (`schemaVersion` 1): `schemaVersion`, `type`,
`role` (non-empty string), `command` (`{executable, arguments}`; an argument is
`{"literal": T}`, `{"file": F}`, `{"directory": D}`, or `{"parts": [single-form objects]}`),
`environment` (array of entries), optional `files` (array of entries whose `name` is a
relative path), optional `inherit` (array of names; replaces the default), optional
`timeoutSeconds` (positive integer, default 60), optional `exitCodes`
(`{accepted, usage, sourceFailure, rejected}`, default 0/[2]/[3]/[4]), and optional
`notes` (array of strings). An entry is `{"name": N}` plus exactly one of `value`,
`secretFromEnvironment`, `secretFromFile`, `synthetic` (with required `reason` and
optional `sensitivity` = `public`/`secret`), `unresolved`, or `unavailableSecret`.
Adding an entry form or a note field is a minor change for consumers that reject
unknown kinds explicitly; renaming a key or the document type requires a new
`schemaVersion`.

Executable `settei-preflight`: `--request PATH` (group "Preflight"), `--json` (group
"Output"); exit codes 0 pass, 1 inconclusive, 2 usage, 3 harness could not run the check,
4 application rejected.

Reference example additions in `examples/settei-deployment` (plan 26's package; not
public API): module `Settei.Example.Deployment.Preflight` exporting `ExtractionOptions`,
`extractionOptions :: Text -> RoleLabel -> FilePath -> ExtractionOptions` (deployment
name, role, host executable) with record fields `containerName`, `secretPrefix`,
`syntheticPublic :: Map EnvName Text`, and `syntheticSecret :: Map EnvName Text`;
`ExtractionError`; `extractPreflightRequest :: ExtractionOptions -> Aeson.Value -> Either
ExtractionError (PreflightRequest, [Text])`; executable
`settei-example-deployment-preflight`; fixture
`test/fixtures/rendered-production.json`.

Dependencies whose choice matters: `process >=1.6.19 && <1.7` (GHC 9.12 ships 1.6.26.1;
`cleanupProcess` exists since 1.6.4), `temporary >=1.3 && <1.4` (already a test
dependency of the service example), `directory >=1.3.8 && <1.4` and `filepath >=1.5.4 &&
<1.6` (the Kubernetes adapter's bounds), `aeson >=2.2 && <2.3` (the Dhall adapter's
bound), `bytestring >=0.12 && <0.13`, and `optparse-applicative >=0.19 && <0.20` for the
executable. Before pinning any bound, verify the current release on Hackage and consult
the registered sources with `mori registry show haskell/process --full` and `mori
registry show haskell/aeson --full`; `temporary` is not registered in Mori, so read its
Hackage documentation for `withSystemTempDirectory`. No Pulumi SDK, Kubernetes client,
or network library is added anywhere.
