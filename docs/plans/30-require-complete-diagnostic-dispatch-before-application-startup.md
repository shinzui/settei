---
id: 30
slug: require-complete-diagnostic-dispatch-before-application-startup
title: "Require complete diagnostic dispatch before application startup"
kind: exec-plan
created_at: 2026-10-21T18:40:22Z
intention: "intention_01m5fw5kpfe5s8d601wtxc4rmk"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-21T18:40:22Z
---


# Require complete diagnostic dispatch before application startup


This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision
Log, and Outcomes & Retrospective current during implementation. Distill durable
context into the relevant records in docs/adr/ before closing the plan.


## Purpose / Big Picture


An application requesting a configuration diagnostic must never accidentally start its
normal work. Static schema and deployment-contract requests must complete, or fail
explicitly, before reading runtime files, environment variables, or credentials. After
this change, applications will use one library-owned dispatch boundary and only a
successful `NoDiagnostic` run will receive permission to start.

This plan addresses [IR-5](../improvement-requests/prevent-diagnostic-modes-from-falling-through-to-startup.md).
It is a focused library improvement: the parser already recognizes contract flags, but
older helper composition silently treats them as normal startup. Acceptance includes a
consumer-shaped regression with contract support deliberately omitted, plus migration of
all three reference applications. This document plans the work; implementation, release,
and downstream deployment have not occurred under this plan.


## Progress


- [ ] Milestone 1: checked preparation and runtime dispatch reject incomplete composition, with exhaustive mode, laziness, failure, and API migration tests (AC-1 through AC-5).
- [ ] Milestone 2: CLI, service, and deployment runners use the boundary before effects; executable and omitted-contract consumer regressions prove diagnostics never start the application (AC-1 through AC-6).
- [ ] Milestone 3: adoption guidance, architecture records, and compatibility notes describe the checked API and preserve diagnostic formats and application-owned exit policy (AC-4 through AC-6).
- [ ] Milestone 4: workspace tests, public API checks, documentation validation, and executable acceptance pass; IR-5 closes with evidence (AC-1 through AC-6).


## Surprises & Discoveries


(None yet.)


## Decision Log


2026-10-21: Accept IR-5 as a separate follow-up to completed plans 26 and 29. Their
contract and validation mechanisms already exist; the remaining defect is dispatch
composition. Keep invariant semantics, contract interpretation, dependency upgrades,
preflight request formats, downstream migration, publishing, and deployment outside scope.

2026-10-21: Require a checked runtime-mode token from a complete preparation function,
and change both post-resolution helper signatures to require it. An optional convenience
wrapper would leave the currently unsafe composition supported. A source-level migration
is appropriate for the already planned shared major release; do not preserve an overload
that accepts arbitrary `DiagnosticMode` values. Retain the existing final decision type
and constructors to avoid unrelated API renaming.

2026-10-21: Keep stream routing, warnings, exit codes, input acquisition, and resource
startup in applications. Preparation is pure and distinguishes static output, static
failure, and permission to acquire runtime inputs. This provides the required ordering
without adding a general IO runner framework or forcing every application to use validators.


## Outcomes & Retrospective


(To be filled during implementation.)


## Context and Orientation


The repository contains the pure configuration library in settei/ and its CLI adapter in
settei-optparse-applicative/. The latter's public module,
settei-optparse-applicative/src/Settei/Optparse.hs, defines eight `DiagnosticMode`
constructors: `NoDiagnostic`, `CheckConfig`, `ExplainText`, `ExplainJson`,
`DescribeConfigText`, `DescribeConfigJson`, `DeploymentContractText`, and
`DeploymentContractJson`. A static diagnostic uses declarations and explicit built-in
defaults only; a runtime diagnostic needs acquired sources and resolution (decoding and
combining their values). Validation means the optional pure application rules applied
after resolution by settei/src/Settei/Validate.hs.

`schemaDiagnostic` and `contractDiagnostic` are partial selectors: `Nothing` means that
the particular helper did not handle the mode, not that startup is safe.
`resolutionDiagnostic` currently returns `Maybe Text` and yields `Nothing` for all static
modes. It also prints check success without itself checking the result's answer.
`validatedDiagnostic` returns `ValidatedDiagnostic a`, whose alternatives are
`DiagnosticFailure Text`, `DiagnosticOutput Text`, and `DiagnosticContinue a`. It checks
the validated answer, but returns `DiagnosticContinue` for all four static modes on
success. Its unit test named "nonempty warnings and static-mode success fallbacks survive
validation" explicitly preserves this unsafe behavior in
settei-optparse-applicative/test/Settei/OptparseTest.hs; replace that expectation rather
than treating it as a compatibility requirement.

The actual process environment readers are injected through `runCliWithEnvironment` in
examples/settei-cli/src/Settei/Example/Cli.hs, `runServiceWithEnvironment` in
examples/settei-service/src/Settei/Example/Service.hs, and `runDeploymentWithStartup` in
examples/settei-deployment/src/Settei/Example/Deployment.hs. CLI and service duplicate
static classification before calling their snapshot runners. Those runners then use
`schemaDiagnostic`, `contractDiagnostic`, and `resolutionDiagnostic`. Deployment composes
the first two selectors with `validatedDiagnostic` and separately guards startup with
`mode == NoDiagnostic`. The new API should replace that duplicated knowledge while
preserving source ordering, validators, safe output, and warnings.

The originating consumer is `mori://tan/notification-hub/packages/notification-hub-server`;
its adoption request is `mori://tan/notification-hub/okf/improvement-requests/concepts/IR-4`.
IR-5 records its reproduction: schema dispatch, loading, then resolution dispatch returns
an application-start outcome for a parsed contract flag. Reproduce that shape inside
this repository; do not require a production checkout or change its files.

[Plan 26](26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md)
implemented source-free contract export and the deployment example.
[Plan 29](29-integrate-application-validation-into-structured-configuration-diagnostics.md)
implemented validation and its diagnostic decision. Both are complete in the inspected
working tree; this is not a child plan and does not reopen their acceptance.

Relevant architecture context comes from
[ADR-1](../adr/0001-haskell-project-conventions.md),
[ADR-7](../adr/0007-reference-applications-are-the-public-api-conformance-boundary.md),
[ADR-12](../adr/0012-deployment-contract-export-semantics.md), and
[ADR-14](../adr/0014-application-invariant-validation.md). ADR-1 establishes GHC2024,
package-local conventions, and Cabal as the complete test authority. ADR-7 makes internal
reference applications the public API composition proof, with usage/source/resolution
exit codes 2/3/4 and advisory warnings on successful runs. ADR-12 requires schema and
contract dispatch before input reads, preserving existing version-1 JSON documents.
ADR-14 requires validator failures to block check success and normal startup, preserves
resolution provenance, and emits two JSON documents on stderr for validated JSON explain
failures. It also warns that `Generic` can bypass private constructors; use that lesson
for the checked token. No new core error constructor or JSON schema is needed here.

mori.dhall registers docs/adr/ as the `adrs` OKF bundle with docs/adr/profile.dhall and
registers the improvement-request bundle with docs/improvement-requests/profile.dhall.
Preserve stable ADR handles and existing metadata when amending records. The current
README.md and docs/compatibility.md target the unreleased shared 0.3.0.0 release while
Cabal versions and exact family pins remain 0.2.0.0 pending coordinated release work.


## Plan of Work


### Milestone 1: make complete dispatch a prerequisite for runtime helpers


Implement the interfaces specified below in
settei-optparse-applicative/src/Settei/Optparse.hs. `prepareDiagnostic` must inspect the
mode first. Schema modes render only their schema. Contract modes inspect optional
contract support and either render the supplied contract, render its existing safe
construction errors, or return a fixed unsupported diagnostic failure. Only the four
runtime modes produce a token. Neither unused schema nor unused contract arguments may
be forced. Do not add strict wrappers that evaluate both before selecting a mode.

Make the token an abstract data type with four private alternatives, corresponding to
normal execution, check, text explain, and JSON explain. Export the type name only, with
no constructor, `Generic`, `Read`, writable optics, or public conversion from an arbitrary
`DiagnosticMode`. The only supported way to obtain it is `DiagnosticNeedsRuntime` from
preparation. It carries no configuration or source values.

Change `resolutionDiagnostic` to consume the token and return `ValidatedDiagnostic a`
rather than `Maybe Text`; change `validatedDiagnostic` to consume the same token. The
shared final decision type retains its existing name and three constructors. Document
that its unvalidated use checks resolution only; applications with invariants must call
`validate` and use `validatedDiagnostic`. Preserve the existing absence of `Show` and
`Eq` on decisions that can carry typed secrets.

Both helpers check their respective answer before success. Only the normal-execution
token and a successful answer produce `DiagnosticContinue`. Preserve validated rendering
exactly. For bare resolution failures, preserve the CLI/service convention: text errors
alone for normal/check, text errors plus text report for text explain, and text errors
plus a newline-terminated resolution JSON document for JSON explain. Preserve raw
resolution success rendering without adding an invariants array. This is deliberately
different from the established validated JSON failure convention; do not silently
normalize the two during a control-flow fix. Warnings remain available on the original
result for application routing.

Keep `schemaDiagnostic` and `contractDiagnostic` as explicitly documented partial
rendering selectors for custom composition. Their `Nothing` is never a continuation
permission. They cannot replace preparation because post-resolution helpers now require
the checked token. Do not add a compatibility path that restores the old unchecked
signature. Use exhaustive cases with no catch-all in the complete mode classifier and
runtime dispatchers, and enable `-Werror=incomplete-patterns` locally for their module so
adding a mode cannot silently inherit a fallback.

Extend settei-optparse-applicative/test/Settei/OptparseTest.hs using the existing fixtures.
Exercise all eight modes, failures, warnings, and secret sentinels. A small consumer-shaped
runner should accept an injected runtime action and a startup action. First test parsed
contract flags with support set to `Nothing` and a runtime action that fails if invoked;
then provide contract support and prove output with the same failing action. This is the
early public producer/consumer proof, before migrating all examples. Include failing
unused schema/contract expressions to verify laziness and an explicit constructor-by-
constructor mode expectation without a default branch.

Add standalone compile fixtures under
settei-optparse-applicative/test/compile-fail/OldResolutionDispatch.hs and
settei-optparse-applicative/test/compile-fail/OldValidatedDispatch.hs. Each imports only
public modules and calls the relevant helper with a static `DiagnosticMode`; they must
fail on `DiagnosticMode` versus `RuntimeDiagnosticMode`, not a missing package or syntax
error. Add a compiling sibling fixture at
settei-optparse-applicative/test/compile-pass/CheckedDispatch.hs that
prepares a mode and consumes the returned token. Include these files in the adapter's
`extra-source-files`; they are not test-suite modules. Add
scripts/check-diagnostic-dispatch-api.sh to run the positive and negative compiler checks
against the Cabal package environment and inspect expected error categories. This makes
the migration requirement executable instead of relying on prose alone.

Milestone acceptance is passing adapter tests and the public compile checks. Older
example callers may temporarily fail compilation until milestone 2; keep this as a local
integration checkpoint and commit the cohesive API plus caller migration together.


### Milestone 2: use the boundary at the executable entry points


Migrate the CLI, service, and deployment modules named above. Each environment wrapper
calls preparation before reading the environment, validating supplied names, opening
files or mounted directories, resolving values, or running application validators. On
`DiagnosticRendered`, return success with output; on `DiagnosticRejected`, return a
configuration failure (exit 4) with stderr and no stdout. On `DiagnosticNeedsRuntime`,
execute the existing runtime pipeline once and pass that exact token to the appropriate
post-resolution helper. Only its `DiagnosticContinue` branch performs normal work.

Share the internal runtime path between each snapshot entry point and environment entry
point so static preparation is neither duplicated nor bypassed. The snapshot entry point
can supply `pure snapshot` to the environment wrapper; do not create mutual recursion.
The CLI and service keep using bare resolution; deployment keeps its role-specific
`validate (roleValidators role)`. Keep source-load failure exit 3, successful warning
routing, and error-path warning suppression. Move the deployment startup action directly
inside the successful `DiagnosticContinue` branch; no separate boolean reconstruction of
startup permission should be necessary.

Update examples/settei-cli/test/Settei/Example/CliTest.hs,
examples/settei-service/test/Settei/Example/ServiceTest.hs, and
examples/settei-deployment/test/Settei/Example/DeploymentTest.hs. Use the same environment
wrappers as their app/Main.hs executables, and the server/worker wrappers in
examples/settei-deployment/app/server/Main.hs and app/worker/Main.hs. Keep
examples/settei-deployment/test/Settei/Example/Deployment/PreflightTest.hs and
examples/settei-conformance/test/Settei/Example/ConformanceTest.hs passing.

Prove static requests work with nonexistent runtime paths and absent credentials, with
failing environment, validator, and startup actions where injection is available. Keep
separate counters for input acquisition and startup in the consumer-shaped fixture;
exercise all eight modes there. Contract `Nothing` must cause failure before the input
counter increments. Valid normal execution must increment the runtime and startup
counters once; check/explain may execute runtime work once but must never start. Use
both deployment roles to retain invariant rejection evidence. Static contract construction
may inspect explicit built-in defaults; it must not perform runtime resolution or run
application validators.

Acceptance is passing affected application/conformance suites and the executable probes
below. Preserve parser flag exclusivity and current help text. Do not add a public CLI
flag solely for disabling contract support in tests; that scenario belongs in the
injected public-API consumer fixture.


### Milestone 3: publish an actionable migration contract


Update the diagnostic sections and examples in docs/guides/cli-application.md and
docs/guides/environment-and-cli.md, and the README.md
files beneath examples/settei-cli/, examples/settei-service/, and
examples/settei-deployment/. Show an exhaustive preparation match, input loading solely
in `DiagnosticNeedsRuntime`, and an exhaustive final decision match. Explain that
`DiagnosticNeedsRuntime` authorizes resolution, not application startup. The prepared
token belongs to that invocation: do not cache a `NoDiagnostic` token and reuse it for
other requested modes. This is an ordinary checked API, not protection against callers
that deliberately ignore its decisions or use unsafe Haskell operations.

Document migration from both older patterns: schema/load/`resolutionDiagnostic` and
schema/contract/load/validate/`validatedDiagnostic`. Show how `Nothing` declares missing
contract support, while `Just (deploymentContract inputs config)` supplies a lazy static
contract. The compiler now forces callers to handle preparation; a dependency update
alone does not migrate an executable. Compile the guide's main dispatch example against
public modules using the positive fixture; avoid `Settei.Prelude` in adopter snippets.

Record the signature changes, unchanged final constructors, and fixed unsupported text
failure in docs/compatibility.md and settei-optparse-applicative/CHANGELOG.md. Target the
already planned next shared major release; leave numeric version bumps and release pins
to release tooling. If implementation occurs after 0.3.0.0 is released, re-evaluate the
next major version before assigning one. Update README.md and docs/release-checklist.md
to describe the implemented safety change without treating old validation evidence as
new acceptance. Successful schema/contract/resolution JSON schemas and exit conventions
remain unchanged. Unsupported contract requests, including JSON mode, produce fixed
plain-text stderr and exit 4 in reference applications; the library itself exits nowhere.

Amend docs/adr/0014-application-invariant-validation.md and
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md to record
the checked preparation requirement and startup-only-on-continue rule. Preserve ADR-12's
source-free contract interpretation. Update
docs/capabilities/configuration-diagnostic-options.md and
docs/capabilities/structured-application-validation.md only after behavior is implemented.
Preserve handles, advance changed document timestamps as applicable, maintain bundle logs
with `okf log add`, and validate all changed bundles. Do not claim this plan is already a
shipped capability while only planning it.


### Milestone 4: verify and close the request


Run the commands below on the integrated candidate. Record concise acceptance evidence,
including tests for the omitted-contract case, compile failures for the old API, valid
normal startup, and retained dynamic diagnostic behavior. Run the full workspace because
all reference applications and the preflight subprocesses depend on the adapter. Resolve
relevant failures without changing the requested semantics. Complete the ADR distillation
pass, fill Outcomes & Retrospective, and set IR-5 to completed with its targetPlan retained
only when AC-1 through AC-6 are demonstrated. No release, tag, push, or downstream
deployment is part of this plan.


## Concrete Steps


Run commands from the repository root, /Users/shinzui/Keikaku/bokuno/settei. Use the Nix
development shell for GHC 9.12 or newer; the unrelated host GHC may not satisfy the
packages' `base >=4.21` requirement. Nix may execute its configured tools; do not search
or read /nix/store for source code. Use Mori for dependency discovery. No new dependency
or bound change is planned.

After milestone 1 edits, run:

```bash
git status --short
nix develop -c cabal test settei-optparse-applicative-tests --test-show-details=direct
nix develop -c bash scripts/check-diagnostic-dispatch-api.sh
```

The script must build the adapter, then use `cabal exec -- ghc -fno-code -package settei
-package settei-optparse-applicative` on each fixture, capturing compiler output in a
fresh temporary directory. The positive fixture must compile; each negative fixture
must fail for the expected type mismatch. Print a concise success summary and return
nonzero on an unexpected result. Clean up only the script-owned temporary directory.

After migrating the examples, run:

```bash
nix develop -c cabal test settei-example-cli-tests settei-example-service-tests settei-example-deployment-tests settei-example-conformance-tests --test-show-details=direct
nix develop -c cabal build exe:settei-example-cli exe:settei-example-service exe:settei-example-deployment-server exe:settei-example-deployment-worker
```

Each suite must report all tests passed. Test counts may increase; the pre-plan recorded
baseline was 561 tests across 14 suites, not a replacement for a fresh run.

Obtain executable paths, then invoke the deployment worker without inherited runtime
credentials and with a path inside a fresh empty directory:

```bash
worker_bin=$(nix develop -c cabal list-bin exe:settei-example-deployment-worker)
probe_dir=$(mktemp -d)
env -i "$worker_bin" --config "$probe_dir/missing.yaml" --describe-config-json
printf 'exit %s\n' "$?"
env -i "$worker_bin" --config "$probe_dir/missing.yaml" --deployment-contract-json
printf 'exit %s\n' "$?"
env -i "$worker_bin" --config "$probe_dir/missing.yaml" --check-config
printf 'exit %s\n' "$?"
rmdir "$probe_dir"
```

The first two commands produce their existing version-1 `settei.schema` and
`settei.contract` JSON documents with exit 0, no stderr, and no startup summary. The
third must report a source-load error with exit 3 and never print `configuration valid`.
Repeat the static probes with text flags and the server executable, plus equivalent CLI
and service flags using their existing parser options. Tests must cover the same property
at their injected reader boundaries; executable success alone cannot prove no read
occurred.

For integrated validation run:

```bash
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c bash scripts/check-diagnostic-dispatch-api.sh
nix develop -c cabal haddock settei-optparse-applicative
nix fmt
okf validate docs/adr --strict --profile docs/adr/profile.dhall --profile-enforce --log-enforce
okf validate docs/guides --strict --profile mori/user-documentation-profile.dhall --profile-enforce --log-enforce
okf validate docs/capabilities --profile docs/capabilities/profile.dhall --profile-enforce --log-enforce
okf validate docs/improvement-requests --strict --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
nix flake check
git diff --check
```

Bundle validators must print `OK` with no errors. Inspect any formatter diff and rerun
only checks invalidated by subsequent changes. Packaging and publishing remain separate
release gates. Implementation commits use Conventional Commits with these trailers:

```text
fix(optparse): require checked diagnostic dispatch before runtime work

ExecPlan: docs/plans/30-require-complete-diagnostic-dispatch-before-application-startup.md
Intention: intention_01m5fw5kpfe5s8d601wtxc4rmk
```


## Validation and Acceptance


For AC-1, the complete consumer-shaped runner covers all eight constructors and parsed
flags, and startup occurs exactly once only for successful `NoDiagnostic`. Normal
resolution or invariant rejection never starts. Exhaustive classifier/dispatcher cases
under `-Werror=incomplete-patterns` ensure a future constructor requires a decision;
there must be no catch-all mapping unknown modes to normal execution.

For AC-2, both text and JSON schema/contract output succeed before any runtime reader,
resolver, validator, or startup action. Use failing actions and unforced expressions to
prove each relevant boundary, and nonexistent file paths plus absent credentials in the
real executable wrappers. Unrelated schema and contract arguments remain unevaluated.

For AC-3, both contract modes with `Nothing` support return precisely the fixed
unsupported failure specified below, with no runtime calls and no success text. Reference
routing yields exit 4 and empty stdout. A supplied contract construction error also
rejects before runtime work; use an existing safe error fixture and preserve its renderer.

For AC-4, old static calls to either post-resolution helper fail to compile for the
intended token type mismatch; the positive prepared consumer compiles. The old
schema/load/resolution shape cannot remain source-compatible by treating `Nothing` as
permission to start. Partial selectors remain documented solely as rendering utilities.

For AC-5, test check and both explanation modes with successful values, missing settings,
invalid scalar values, and failing invariants. Check success appears only after the
relevant answer succeeds. Keep resolution provenance and successful warnings unchanged,
keep failure-path warning suppression, and preserve both bare and validated JSON/stream
conventions described above. Scan output for both an adversarial secret and a unique
ASCII marker to catch escaped leaks. Existing core renderer goldens must remain unchanged.

For AC-6, all examples and guide snippets compile against the public API, the omitted
contract consumer case runs automatically, migration and next-major-release notes are
explicit, and the required workspace and documentation checks pass. Library decisions
have no process-exit effects; reference applications demonstrate the routing policy.


## Idempotence and Recovery


Builds and tests are repeatable and use existing local fixtures. The new compiler-check
script uses an isolated temporary directory and returns meaningful failure output; retry
a failed build after repairing the actual cause, never accept a missing package as an
expected negative test. Inspect git status before edits and stage only this plan's files.
Keep the current branch and preserve unrelated changes. No migration of persisted data,
remote consumer, or dependency pin is required.

An interrupted implementation resumes at the next unchecked milestone. Keep IR-5 accepted
or in progress until all required behavior passes; a changed API alone is not completion.
If token design needs adjustment, preserve the requirement that arbitrary static modes
cannot reach post-resolution continuation and update the interfaces, migration examples,
and acceptance together. Do not restore the unsafe helper signature as a temporary
compatibility shim. Record a revision through the skill's provenance script when making
later substantive plan edits.


## Interfaces and Dependencies


The planned public boundary in `Settei.Optparse` is:

```haskell
-- Export the type name only. Constructors are private runtime-only alternatives.
data RuntimeDiagnosticMode

data DiagnosticPreparation
  = DiagnosticRejected !Text
  | DiagnosticRendered !Text
  | DiagnosticNeedsRuntime !RuntimeDiagnosticMode

prepareDiagnostic
  :: DiagnosticMode
  -> Schema
  -> Maybe (Either (NonEmpty ConfigError) DeploymentContract)
  -> DiagnosticPreparation

resolutionDiagnostic
  :: RuntimeDiagnosticMode
  -> ResolveResult a
  -> ValidatedDiagnostic a

validatedDiagnostic
  :: RuntimeDiagnosticMode
  -> ValidatedResult a
  -> ValidatedDiagnostic a

-- Existing type and constructors are retained.
data ValidatedDiagnostic a
  = DiagnosticFailure !Text
  | DiagnosticOutput !Text
  | DiagnosticContinue a
```

The abstract declaration above describes the export surface, not an empty runtime data
type. Implement its four private constructors in the adapter module. `DiagnosticPreparation`
needs no `Generic` instance. `prepareDiagnostic` accepts a lazy optional contract result,
not an already executed IO action. `Nothing` explicitly means this application has not
supplied deployment-contract support. Both contract modes then return
`DiagnosticRejected "deployment contract diagnostic is unavailable\n"`. Use the existing
safe text error renderer for a supplied `Left` contract result. Fixed unsupported text
contains no source names, configuration values, or credentials.

Only the private normal-execution token can produce `DiagnosticContinue` from either
runtime helper, and only after success. No new `ConfigError`, `DiagnosticMode`
constructor, JSON document, source adapter, or dependency is necessary. Existing helpers
retain their module; family layering stays unchanged. Applications retain original
results to route warnings and choose exit codes.

The parser dependency was located through Mori at
`mori://pcapriotti/optparse-applicative/packages/optparse-applicative`; its public
`execParserPure` supports the existing parser tests without process execution. Preserve
the current parser API and bounds. If implementation proposes a dependency change,
first discover its source/docs with Mori and verify current registry releases and upstream
tags before choosing bounds or pins; this plan does not authorize a speculative upgrade.
