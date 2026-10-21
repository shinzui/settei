---
type: Improvement Request
title: Prevent diagnostic modes from falling through to application startup
description: Make complete diagnostic dispatch explicit so an unhandled schema or deployment-contract request fails safely instead of loading runtime inputs or continuing toward application startup.
requestId: IR-5
status: accepted
targetPlan: docs/plans/30-require-complete-diagnostic-dispatch-before-application-startup.md
origin: mori://tan/notification-hub
generated:
  by: process:codex
  at: "2026-10-21T18:35:45Z"
reviews:
  - kind: model
    reviewer: process:codex
    reviewed_at: "2026-10-21T18:35:45Z"
    document_timestamp: "2026-10-21T18:35:45Z"
    scope: content-and-metadata
    outcome: commented
    provider: openai
    model: gpt-6
    effort: unspecified
    context: Author self-check against current Settei diagnostic helpers, notification-hub's existing runner, and the isolated consumer validation that reproduced contract-mode fall-through; no independent review or implementation acceptance claimed.
acceptanceCriteria:
  - id: AC-1
    statement: The supported complete diagnostic dispatch path permits application continuation only for NoDiagnostic; every requested diagnostic returns its output or an explicit failure disposition.
    verification: Exercise every DiagnosticMode with successful configuration and instrument startup to fail if entered; assert that only NoDiagnostic can reach startup and that future constructors require an explicit dispatch decision.
  - id: AC-2
    statement: Schema and deployment-contract modes dispatch before file loading, process environment reads, runtime resolution, application validators, or resource acquisition, including when required runtime values are absent.
    verification: Use failing or counted input-reader, resolver, validator, and startup actions; request text and JSON static diagnostics with nonexistent runtime files and no credentials and prove none of those actions runs.
  - id: AC-3
    statement: Missing support or metadata for a requested diagnostic produces a safe explicit non-success outcome before runtime input loading rather than silently falling through, reporting configuration success, or running the application.
    verification: Omit the deployment-contract handler or contract inputs in a notification-hub-shaped runner; request both contract modes and verify a fixed safe failure and nonzero application exit with no source reads or startup.
  - id: AC-4
    statement: Existing post-resolution diagnostic helpers cannot silently return a startup decision for static diagnostic modes, and partial-helper composition and migration requirements are documented and enforced through a checked or explicit dispatch boundary.
    verification: Reproduce the current schemaDiagnostic then load/resolve then resolutionDiagnostic pattern and the validatedDiagnostic static-mode cases; prove the supported replacement refuses unhandled modes and documents any intentionally partial lower-level helpers.
  - id: AC-5
    statement: Check and explanation modes retain their existing resolution, application-validation, provenance, warning, and secret-redaction behavior, and check success is emitted only after all applicable validators succeed.
    verification: Run successful and failing check/text-explain/JSON-explain cases with missing settings, invalid values, invariant failures, and secret sentinels; verify outputs, non-success dispositions, and absence of secret values.
  - id: AC-6
    statement: Public examples and migration guidance demonstrate the safe dispatch boundary with executable regression evidence and an explicit compatibility decision for changed helper types, constructors, and JSON or exit conventions.
    verification: Update the CLI and deployment reference runners and guides, test a notification-hub-shaped adopter with an initially omitted contract handler, and run affected API and executable acceptance checks before release.
---

# Prevent diagnostic modes from falling through to application startup

## Planned implementation

[ExecPlan 30](../plans/30-require-complete-diagnostic-dispatch-before-application-startup.md)
accepts this request after inspection confirmed both the static-mode continuation in
`validatedDiagnostic` and the unchecked `Maybe Text` fallback in `resolutionDiagnostic`.
The plan requires complete static preparation before runtime input acquisition and a
checked runtime-mode token for both post-resolution helpers, with explicit migration
and consumer-shaped regression evidence. The request is accepted for implementation;
none of AC-1 through AC-6 is claimed complete by creating the plan.

## Problem and observed consumer behavior

The deployment-contract flags introduced by
[IR-1](export-a-deployment-configuration-contract.md) extend `DiagnosticMode`, and
`diagnosticModeOptions` recognizes them in existing application parsers. Applications
must separately insert `contractDiagnostic` before their effectful source-loading path.

The existing runner in
`mori://tan/notification-hub/packages/notification-hub-server` handles static schema
diagnostics, then loads and resolves inputs, and finally calls `resolutionDiagnostic`.
After substituting the unreleased Settei checkout, an isolated consumer test confirmed
that parsing `--deployment-contract-json` and passing valid inputs through the pure
runner returns its application-start outcome instead of contract output. The test did
not acquire application resources, but the ordinary executable would treat that outcome
as permission to proceed toward startup.

The [current validated dispatcher](../../settei-optparse-applicative/src/Settei/Optparse.hs)
also returns `DiagnosticContinue` for `DescribeConfigText`, `DescribeConfigJson`,
`DeploymentContractText`, and `DeploymentContractJson` when resolution succeeds. Its
assumption that static modes were already handled is therefore capable of hiding an
omitted handler. Correct reference examples do not make that assumption safe for an
adopter following an older dispatch pattern.

## Requested outcome

Provide an explicit complete dispatch boundary that handles static diagnostics before
input acquisition and permits startup only when no diagnostic was requested. The API
may compose the existing helpers or introduce a checked decision type; the exact shape
is an implementation decision. Make missing diagnostic support observable as failure
rather than a normal-run decision.

The boundary must preserve laziness of effectful callbacks or equivalent application
actions: constructing a source-free response must not require a resolved configuration,
available credentials, existing runtime files, or already executed input readers.
Likewise, discovering that the requested contract handler is unavailable must not first
load those inputs in an attempt to continue.

Address the post-resolution continuation cases as well as the new composed entry point.
If lower-level helpers intentionally remain partial selectors, label their scope clearly
and require a safe final disposition for a mode they do not handle. Document and test
the migration path rather than implying that dependency substitution alone adopts
contract export. A compatibility-preserving optional helper is insufficient if the
recommended complete dispatcher still accepts a static mode as permission to start.

## Scope and acceptance

This is a follow-up to the diagnostic integration in
[IR-4](integrate-application-validation-into-structured-diagnostics.md). It does not
reopen application invariant semantics, default introspection, or the preflight request
format. Applications retain ownership of stream routing, exit-code conventions, and
their resource-start actions; the library must give them an unambiguous diagnostic
decision and an example that preserves it.

Update the CLI and deployment examples and the
[CLI guide](../guides/cli-application.md). Keep normal startup and existing dynamic
diagnostics compatible where possible, and explicitly record any breaking API decision
in the next shared release. Fixed failure metadata must contain no configuration values
or secrets.

The related consumer adoption is tracked by
`mori://tan/notification-hub/okf/improvement-requests/concepts/IR-4`. Pulumi input
extraction and CI gating remain owned by `mori://tan/tan-app-infrastructure`; they
cannot repair an application's diagnostic dispatcher by themselves.

AC-1 through AC-6 define future acceptance. This request records the missing Settei
change; it does not implement it, claim release readiness, or authorize a deployment.
