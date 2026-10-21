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
  reviews:
    - model: "claude-fable-5-1"
      harness: "claude-code"
      at: 2026-10-21T19:02:11Z
      verdict: "changes-requested"
      note: "Verified helpers, examples, tests, ADRs, and the cabal exec compile-check spike against the working tree; Milestone 3 omits deployment-contract guide, contract capability, and example changelog updates, and executable probes should use the existing startup-failure switch."
  revisions:
    - model: "claude-fable-5-1"
      harness: "claude-code"
      at: 2026-10-21T19:03:55Z
      mode: "update"
      note: "Apply review findings: widen documentation scope, use the startup-failure switch in executable probes, record cabal exec and formatter facts, require exporting preparation constructors."
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
successful `NoDiagnostic` run will receive permission to start. Consumers cross the
resulting 0.3.0.0 break with one `seihou agent migrate settei-upgrade` run, because this
plan also publishes Settei's first Seihou upgrade blueprint.

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
- [ ] Milestone 4: the `settei-upgrade` Seihou blueprint, its registry entry, the 0.2.0.0 to 0.3.0.0 edge, the version probe, and the release-collateral gate validate and preview as one step (AC-6).
- [ ] Milestone 5: workspace tests, public API checks, blueprint validation, documentation validation, and executable acceptance pass; IR-5 closes with evidence (AC-1 through AC-6).


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

2026-10-21: Rename the shared decision type from `ValidatedDiagnostic` to
`DiagnosticDecision`, superseding the retention recorded above. Once
`resolutionDiagnostic` returns the same type, a continuation can arrive from a path that
ran no validators, so a name claiming validation would mislead adopters. The type exists
only in the unreleased working tree: the adapter changelog lists it under Unreleased,
Hackage 0.2.0.0 predates it, and the originating consumer still calls
`resolutionDiagnostic`. Renaming inside the same major release that changes both helper
signatures costs one export, one changelog line, and one ADR sentence; renaming after
0.3.0.0 ships would cost a further major bump. The three constructors and both helper
names stay, because each helper name already describes its input.

2026-10-21: Ship the 0.3.0.0 upgrade as a Seihou blueprint migration published from
this repository, `settei-upgrade` with one agent-guided edge from 0.2.0.0 to 0.3.0.0,
instead of leaving consumers to migrate by hand from the changelog and compatibility
notes. The sibling libraries keiro, kiroku, and kioku ship every breaking release this
way, and the consumer that raised IR-5 upgrades through `seihou agent migrate`. The edge
covers the whole 0.3.0.0 breaking surface, not only this plan's dispatch change, because
an edge describes one release window and no earlier plan created the blueprint. The
version probe reads the resolved `settei` version from the consumer's Cabal build plan.
No upstream edge is entailed, because Settei absorbs no other blueprint's break. The
release checklist and the release skill gain a gate so each later breaking release adds
its edge in the same change that cuts the release.


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

Seihou (`mori://shinzui/seihou`; the installed CLI reports v0.10.1.0) is the project
scaffolding tool that already manages this repository through .seihou/manifest.json. A
Seihou blueprint migration is upgrade knowledge a library ships beside its code: a
directory holding `blueprint.dhall`, a shared `prompt.md`, and one Markdown prompt per
released version edge, listed in a `seihou-registry.dhall` at the repository root. A
consumer installs it with `seihou install <git url> --module <name>` and runs
`seihou agent migrate <name>`; Seihou selects the edges inside the consumer's version
window, runs one agent session per edge inside the consumer's project, and records a
receipt in that project's manifest. The author guide is docs/user/blueprint-migrations.md
in the Seihou repository, and the decision that a blueprint declares its own read-only
version probe is that repository's
docs/adr/0009-seihou-reads-no-package-manager-format-artifacts-declare-the-command.md
(its artifact-level `mori://` URI is pending). Settei has neither a registry file nor a
blueprint today. The exemplars to copy the shape from are `mori://shinzui/keiro` at
blueprints/keiro-upgrade/ and `mori://shinzui/kiroku` at blueprints/kiroku-upgrade/,
whose release skills decide at every release whether an edge is needed. Installed
blueprints resolve from ~/.config/seihou/installed/<name>, a symlink under
~/.config/seihou/modules/ exposes a working-tree blueprint for previews, and
`seihou agent --debug migrate` renders the pending prompts without contacting a provider
or writing anything. The seihou-schema checkout registered in Mori predates the
`versionProbe` and `entails` fields; the sibling blueprints pin a newer schema commit
by URL and hash, shown under Interfaces and Dependencies.


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

Rename the shared decision type `ValidatedDiagnostic a` to `DiagnosticDecision a`,
keeping its three constructors. Change `resolutionDiagnostic` to consume the token and
return `DiagnosticDecision a` rather than `Maybe Text`; change `validatedDiagnostic` to
consume the same token and return the renamed type. Document
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
`extra-source-files`; they are not test-suite modules. The repository formatter
(`nix fmt`, backed by treefmt with fourmolu) formats every Haskell file, and
`nix flake check` runs the same formatter check, so keep the fixtures formatted. Add
scripts/check-diagnostic-dispatch-api.sh to run the positive and negative compiler checks
against the Cabal package environment and inspect expected error categories; the
repository has no scripts/ directory yet, so create it, and the formatter does not touch
shell scripts. This makes the migration requirement executable instead of relying on
prose alone.

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
examples/settei-conformance/test/Settei/Example/ConformanceTest.hs passing; the
conformance suite calls `contractDiagnostic` directly with a prebuilt contract and keeps
compiling only because that selector's signature is unchanged.

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


Update the diagnostic sections and examples in docs/guides/cli-application.md,
docs/guides/environment-and-cli.md, and docs/guides/deployment-contract.md, and the
README.md files beneath examples/settei-cli/, examples/settei-service/, and
examples/settei-deployment/. The deployment-contract guide currently tells adopters to
dispatch `schemaDiagnostic` and then `contractDiagnostic` before loading inputs and
presents the selector's `Nothing` as the path to every other mode; rewrite that passage
around preparation so no guide still teaches the composition this plan rejects. Show an
exhaustive preparation match, input loading solely
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

Record the signature changes, the decision type rename with its unchanged constructors,
and the fixed unsupported text failure in docs/compatibility.md and settei-optparse-applicative/CHANGELOG.md, and note
the deployment example's migration in examples/settei-deployment/CHANGELOG.md; the CLI
and service examples have no changelog. Target the
already planned next shared major release; leave numeric version bumps and release pins
to release tooling. If implementation occurs after 0.3.0.0 is released, re-evaluate the
next major version before assigning one. Update README.md and docs/release-checklist.md
to describe the implemented safety change without treating old validation evidence as
new acceptance. Successful schema/contract/resolution JSON schemas and exit conventions
remain unchanged. Unsupported contract requests, including JSON mode, produce fixed
plain-text stderr and exit 4 in reference applications; the library itself exits nowhere.

Amend docs/adr/0014-application-invariant-validation.md and
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md to record
the checked preparation requirement and startup-only-on-continue rule, and change
ADR-14's no-`Show`-or-`Eq` note to name `DiagnosticDecision`. Preserve ADR-12's
source-free contract interpretation. Update
docs/capabilities/configuration-diagnostic-options.md,
docs/capabilities/structured-application-validation.md, and
docs/capabilities/deployment-configuration-contract.md, which presents
`contractDiagnostic` as the early application dispatch, only after behavior is implemented.
Preserve handles, advance changed document timestamps as applicable, maintain bundle logs
with `okf log add`, and validate all changed bundles. Do not claim this plan is already a
shipped capability while only planning it.


### Milestone 4: publish the Seihou upgrade blueprint


Without a blueprint, every consumer of the 0.3.0.0 break would reconstruct the migration
from the changelog and compatibility notes by hand. This milestone creates the blueprint
the sibling libraries already ship and wires it into the release collateral so each
later breaking release adds its own edge.

Create seihou-registry.dhall at the repository root with the record shape the keiro
registry uses: `repoName = "settei"`, explicitly typed empty `modules`, `recipes`, and
`prompts` lists, and one `blueprints` entry named `settei-upgrade` at version `0.1.0`,
path `blueprints/settei-upgrade`, tags `haskell`, `configuration`, `settei`, and
`migration`. Create blueprints/settei-upgrade/blueprint.dhall pinned to the seihou-schema
import shown under Interfaces and Dependencies. Declare one edge from `0.2.0.0` to
`0.3.0.0` importing blueprints/settei-upgrade/migrations/0.2.0.0-to-0.3.0.0.md. The
`from` is the last released version before the break, not the earliest version the
guidance could apply to, because Seihou selects an edge whose `from` is at or after the
consumer's recorded position. If the release number changes before implementation,
change both ends together. Declare no `entails`.

Supply the version probe as the one read-only command that reports the `settei` version
a consumer's build plan resolved:

```bash
jq -r '."install-plan"[] | select(."pkg-name"=="settei") | ."pkg-version"' dist-newstyle/cache/plan.json 2>/dev/null | sort -u | tail -1 | grep .
```

It reads the core package because every family consumer depends on it and the family
versions move in lockstep. A project without a configured Cabal build or without `jq`
gets a reported probe failure and is asked for `--to`; that degradation is intended.
Seihou runs the probe in the consumer's project root and takes its last non-empty line.

Write blueprints/settei-upgrade/prompt.md as the guidance shared by every edge: the nine
public packages release under one version with exact intra-family pins, so an edge moves
every Settei package a project depends on together; the surfaces a Settei project may
use (declarations and decoders, file and environment sources, the optparse-applicative
diagnostic dispatch, validators, the deployment contract, preflight); and ground rules:
find real call sites before editing, grep for added constructors because `-Wall` only
warns on an incomplete match, change only what the edge names, prove the result with
the project's own build and test commands, never import `Settei.Prelude`, and never log
or print the typed configuration value because it carries real secrets.

Write the edge prompt as the consumer-facing half of docs/compatibility.md. Its
precondition is that the project depends on at least one Settei package; otherwise the
agent reports the edge not applicable, which Seihou records without marking the edge
done. The edge then walks, in order: raise every Settei bound in lockstep; add
`InvariantError` to exhaustive `ConfigError` matches and kind `invariant` to JSON error
consumers; add `DeploymentContractText` and `DeploymentContractJson` to exhaustive
`DiagnosticMode` matches; replace the old schema, contract, load, and resolve
composition with `prepareDiagnostic`, an exhaustive match on `DiagnosticPreparation`,
input loading only under `DiagnosticNeedsRuntime`, the token passed to
`resolutionDiagnostic` or `validatedDiagnostic`, and an exhaustive match on
`DiagnosticDecision`, with `Nothing` declaring that the application supplies no
deployment contract; and, for applications with validators, the two-document stderr
convention for validated JSON explain failures. It states what the agent must not do:
restore the old unchecked composition, pass `Just` a contract built from the wrong
inputs to silence the compiler, or add a public flag that disables contract support. It
names the validation that proves the edge: the project's build and tests, then invoking
its executable with `--describe-config-json` and `--deployment-contract-json` against a
missing configuration path and no credentials, expecting exit 0 and no startup. The
before-and-after dispatch code in this prompt is the same code as the guide's main
example and the compile-pass fixture; keep the three in step.

Add blueprints/settei-upgrade/README.md with the consumer commands, the declared edge
table, the probe, and the maintainer rule that every breaking release adds its edge in
the same change that cuts the release, mirroring the keiro blueprint's README. Add
blueprints/settei-upgrade/files/checked-dispatch.md holding the before-and-after
dispatch example for the agent to read, declared in the blueprint's `files` list.

Wire the release collateral so the blueprint cannot rot. docs/release-checklist.md gains
a Seihou upgrade blueprint item under its final-candidate metadata section requiring an
edge for the release window or a recorded decision that none is needed, bumped blueprint
and registry versions, a passing `seihou validate-blueprint`, and a debug preview
transcript. agents/skills/release/SKILL.md, which is not Seihou-managed, gains a
"Blueprint migration edge" step in its release-preparation section modelled on the keiro
release skill: decide at every release whether an edge is needed and record the decision
either way, write the edge, append the `S.BlueprintMigration` entry, bump the blueprint
and registry versions, update the README edge table, validate, preview, and verify
before tagging that the blueprint commit is on the pushed remote, because consumers
install from git. README.md and docs/compatibility.md name
`seihou install https://github.com/shinzui/settei.git --module settei-upgrade` followed
by `seihou agent migrate settei-upgrade` as the supported upgrade path beside the written
notes. Change nothing in mori.dhall: whether Mori should list a library's blueprint is a
registry question outside this plan, and keiro's registration lists none today.

Milestone acceptance is a passing `seihou validate-blueprint` and a debug preview that
shows exactly one step for the window, using the commands under Concrete Steps, plus
the release collateral edits.


### Milestone 5: verify and close the request


Run the commands below on the integrated candidate. Record concise acceptance evidence,
including tests for the omitted-contract case, compile failures for the old API, valid
normal startup, retained dynamic diagnostic behavior, and the blueprint validation and
preview transcript. Run the full workspace because
all reference applications and the preflight subprocesses depend on the adapter. Resolve
relevant failures without changing the requested semantics. Complete the ADR distillation
pass, fill Outcomes & Retrospective, and set IR-5 to completed with its targetPlan retained
only when AC-1 through AC-6 are demonstrated. No release, tag, push, or downstream
deployment is part of this plan; the blueprint ships with the release, and the release
skill step added in milestone 4 requires it to be pushed before the tag.


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

The script must build the adapter library, then use `cabal exec -- ghc -fno-code -package settei
-package settei-optparse-applicative` on each fixture, capturing compiler output in a
fresh temporary directory. `cabal exec` computes the project plan without building
anything and exposes only libraries that are already built through a temporary GHC
environment file, which is why the build step comes first; a plan review on 2026-10-21
confirmed that this invocation typechecks a standalone fixture against the built adapter
from the repository root. The positive fixture must compile; each negative fixture
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
env -i SETTEI_DEPLOYMENT_TEST_FAIL_ON_STARTUP=1 "$worker_bin" --config "$probe_dir/missing.yaml" --describe-config-json
printf 'exit %s\n' "$?"
env -i SETTEI_DEPLOYMENT_TEST_FAIL_ON_STARTUP=1 "$worker_bin" --config "$probe_dir/missing.yaml" --deployment-contract-json
printf 'exit %s\n' "$?"
env -i SETTEI_DEPLOYMENT_TEST_FAIL_ON_STARTUP=1 "$worker_bin" --config "$probe_dir/missing.yaml" --check-config
printf 'exit %s\n' "$?"
rmdir "$probe_dir"
```

The first two commands produce their existing version-1 `settei.schema` and
`settei.contract` JSON documents with exit 0, no stderr, and no startup summary. The
third must report a source-load error with exit 3 and never print `configuration valid`.
The deployment executables in examples/settei-deployment/app/server/Main.hs and
app/worker/Main.hs already pass a startup action that raises an IO error when
`SETTEI_DEPLOYMENT_TEST_FAIL_ON_STARTUP` is `1`, so an uncaught
`deployment startup action invoked` failure in any probe proves the executable reached
startup. Repeat the static probes with text flags and the server executable, plus
equivalent CLI and service flags using their existing parser options; those two
executables have no startup switch, so their probes show only output and exit codes.
Tests must cover the same property at their injected reader boundaries; executable
success alone cannot prove no read occurred.

After authoring the blueprint, run:

```bash
seihou validate-blueprint blueprints/settei-upgrade --lint
ln -s "$PWD/blueprints/settei-upgrade" ~/.config/seihou/modules/settei-upgrade
seihou list --blueprints | grep settei-upgrade
seihou agent --debug migrate settei-upgrade --from 0.2.0.0 --to 0.3.0.0
```

Validation evaluates the Dhall, rejects an empty prompt, an unparseable version, an edge
whose `from` is not below its `to`, and duplicate starts, and with `--lint` prints
advisory warnings; it executes nothing. The symlink exposes the working-tree blueprint
as a user-local artifact, the same way existing local blueprints are exposed under
~/.config/seihou/modules/, so the preview resolves this checkout rather than a stale or
absent installed copy; the listing must show `settei-upgrade` with a `user [blueprint]`
source. The preview prints `Blueprint migrations for settei-upgrade: 0.2.0.0 -> 0.3.0.0`
and exactly one `[1/1] settei-upgrade 0.2.0.0 -> 0.3.0.0` section containing the shared
guidance, the edge instructions, and the mounted files path. It contacts no provider and
writes nothing, but it does run the version probe in the current directory and reports
it with its source; in this repository the probe reads 0.2.0.0 from the Cabal plan, and
the explicit flags win. Remove the symlink afterwards with
`rm ~/.config/seihou/modules/settei-upgrade` unless you want the working tree to keep
shadowing a later git install. Consumers install the published blueprint with
`seihou install https://github.com/shinzui/settei.git --module settei-upgrade`.

For integrated validation run:

```bash
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c bash scripts/check-diagnostic-dispatch-api.sh
nix develop -c cabal haddock settei-optparse-applicative
seihou validate-blueprint blueprints/settei-upgrade --lint
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
The `settei-upgrade` blueprint passes `seihou validate-blueprint`, its debug preview
shows exactly one step for the 0.2.0.0 to 0.3.0.0 window with the shared prompt, the
edge prompt, and the reference file resolved, the edge prompt's dispatch example is the
same code as the compile-pass fixture, and docs/release-checklist.md and
agents/skills/release/SKILL.md name the blueprint gate.


## Idempotence and Recovery


Builds and tests are repeatable and use existing local fixtures. The new compiler-check
script uses an isolated temporary directory and returns meaningful failure output; retry
a failed build after repairing the actual cause, never accept a missing package as an
expected negative test. Inspect git status before edits and stage only this plan's files.
Keep the current branch and preserve unrelated changes. No migration of persisted data,
remote consumer, or dependency pin is required. The blueprint is plain files that can be
rewritten freely before release; `seihou validate-blueprint` and the debug preview write
nothing, the preview symlink is user-local and removable, and a consumer who previously
installed a same-named blueprint from another source needs `seihou install --force`.

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
  -> DiagnosticDecision a

validatedDiagnostic
  :: RuntimeDiagnosticMode
  -> ValidatedResult a
  -> DiagnosticDecision a

-- Renamed from ValidatedDiagnostic; the three constructors are retained.
data DiagnosticDecision a
  = DiagnosticFailure !Text
  | DiagnosticOutput !Text
  | DiagnosticContinue a
```

The abstract declaration above describes the export surface, not an empty runtime data
type. Implement its four private constructors in the adapter module. Export
`DiagnosticPreparation` with all three constructors and `prepareDiagnostic` next to the
abstract token type, because applications and guide examples match on the preparation
exhaustively. `DiagnosticPreparation` needs no `Generic` instance. `prepareDiagnostic` accepts a lazy optional contract result,
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

The planned blueprint declaration in blueprints/settei-upgrade/blueprint.dhall is:

```dhall
let S =
      https://raw.githubusercontent.com/shinzui/seihou-schema/49ff1e5b353b171b1b52946f478623ee4423ea93/package.dhall
        sha256:cadacb688dd31ec39feb7f2fe599973a1ad58ef8fcc8ed1100bf3da22a1222cb

in  S.Blueprint::{
    , name = "settei-upgrade"
    , version = Some "0.1.0"
    , description = Some
        "Upgrade guidance for Settei consumers: one agent-guided edge per released version window that needs judgement work"
    , prompt = ./prompt.md as Text
    , versionProbe = Some
        "jq -r '.\"install-plan\"[] | select(.\"pkg-name\"==\"settei\") | .\"pkg-version\"' dist-newstyle/cache/plan.json 2>/dev/null | sort -u | tail -1 | grep ."
    , allowedTools = Some [ "Bash(cabal *)", "Bash(rg *)" ]
    , files =
      [ S.Blueprint.BlueprintFile::{
        , src = "checked-dispatch.md"
        , description = Some "Before-and-after diagnostic dispatch for the 0.3.0.0 checked boundary"
        }
      ]
    , migrations =
      [ S.BlueprintMigration::{
        , from = "0.2.0.0"
        , to = "0.3.0.0"
        , prompt = ./migrations/0.2.0.0-to-0.3.0.0.md as Text
        }
      ]
    , tags = [ "haskell", "configuration", "settei", "migration" ]
    }
```

The schema import is the commit and hash the keiro, kiroku, and kioku blueprints pin;
the seihou-schema checkout registered in Mori lacks `versionProbe` and would reject this
record. The root seihou-registry.dhall lists the blueprint with the same name, version,
path, description, and tags, and explicitly typed empty `modules`, `recipes`, and
`prompts` lists as in the keiro registry. `seihou` and `jq` are host tools used by the
author and the consumer; no Cabal dependency, bound, or Nix input changes for the
blueprint.


Revision note (2026-10-21): reviewed against the current adapter, examples, tests, ADRs,
and a `cabal exec` compile-check spike. Added the deployment-contract guide, the contract
capability, and the deployment example changelog to the documentation scope so no
published text keeps teaching the rejected selector composition; made the executable
probes use the deployment executables' existing startup-failure switch; recorded that
`cabal exec` exposes only built libraries, that scripts/ is new, and that the formatter
covers the compile fixtures; and required exporting the preparation constructors.
Implementation milestones remain open.

Revision note (2026-10-21, later): renamed the shared decision type to
`DiagnosticDecision` after discussion, because the bare resolution helper will return it
without running validators and the type is still unreleased. Constructors and helper
names are unchanged; the Decision Log records the trade-off.

Revision note (2026-10-21, blueprint): added milestone 4, publishing the `settei-upgrade`
Seihou blueprint with the 0.2.0.0 to 0.3.0.0 edge, a read-only version probe, a root
registry file, and release-collateral gates, so consumers upgrade with
`seihou agent migrate` as they do for the sibling libraries; verification moved to
milestone 5. The Decision Log records why the edge covers the whole release window.
