---
type: Improvement Request
title: Provide a reusable deployment preflight workflow using application check mode
description: Validate proposed container inputs with the application's own configuration checks before first deployment, with explicit handling of secrets and unresolved values.
requestId: IR-3
status: in-progress
targetPlan: docs/plans/28-provide-a-reusable-deployment-preflight-harness-around-application-check-mode.md
origin: mori://tan/notification-hub
generated:
  by: process:codex
  at: "2026-10-21T12:45:36Z"
reviews:
  - kind: model
    reviewer: process:codex
    reviewed_at: "2026-10-21T12:45:36Z"
    document_timestamp: "2026-10-21T12:45:36Z"
    scope: content-and-metadata
    outcome: commented
    provider: openai
    model: gpt-6
    effort: unspecified
    context: Author self-check against notification-hub server and worker check paths, the requested preflight workflow, and Settei diagnostic helpers; no independent review or implementation acceptance claimed.
acceptanceCriteria:
  - id: AC-1
    statement: A documented reusable harness runs a chosen application executable in check mode with explicitly supplied proposed environment, configuration files, and CLI overrides while preserving the application's declared precedence and process role.
    verification: Check separate server and worker fixtures with conflicting file, environment, and CLI values; confirm that their check results match the normal startup configuration path without starting application resources.
  - id: AC-2
    statement: Deployment tooling can provide the inputs intended for the final container through a documented interface without reimplementing application decoders, defaults, or cross-setting validation in infrastructure code.
    verification: A deployment-shaped example checks inputs extracted from generated container configuration and fails when an environment mapping, configuration-file input, or role-specific value is deliberately changed; identify extraction assumptions explicitly.
  - id: AC-3
    statement: The workflow distinguishes fully checked inputs from unresolved generated values, unavailable secret material, and synthetic test substitutions, and never reports incomplete checking as full deployment validation.
    verification: Cover a known public input, a supplied secret, an unresolved resource output, an unavailable secret reference, and a synthetic credential; assert documented non-success or incomplete outcomes and identify the checks that could not run.
  - id: AC-4
    statement: Secret inputs are passed through controlled environment or file channels without placing secret values in command arguments, generated public artifacts, normal logs, or failure summaries, and execution errors remain attributable to the checked role.
    verification: Inject secret sentinels and inspect invocation arguments, stdout, stderr, reports, and retained artifacts; exercise executable-not-found, source-loading failure, application validation failure, and timeout paths with cleanup checks.
  - id: AC-5
    statement: The reference workflow runs configuration-only checks without cluster access, database connections, provider calls, or application startup, and separates those results from readiness or live integration evidence.
    verification: Run notification-hub-shaped server and worker checks with resource acquisition paths instrumented to fail if entered; demonstrate a configuration failure before provisioning and document later checks for connectivity and credentials.
---

# Provide a reusable deployment preflight workflow using application check mode

## Problem and desired outcome

Before deploying `mori://tan/notification-hub` for the first time, the author of its
Pulumi program needs to test the configuration the containers will receive. Reading a
schema or validating Pulumi's input YAML alone does not exercise the TypeScript wiring
that turns stack settings, generated values, and Secrets into application inputs.

The service already has valuable configuration-only checks.
`mori://tan/notification-hub/packages/notification-hub-server` validates event-webhook
public keys, and `mori://tan/notification-hub/packages/notification-hub-workers` checks
capacity, lease bounds, replicas, and email-account relationships before opening
resources. Deployment tooling should invoke these existing checks rather than create a
second implementation of their rules.

Provide a small reusable harness and an end-to-end guide for checking proposed container
inputs with the actual application executable. Define how callers supply the role,
environment, files, overrides, and expected check invocation, and how results are
reported. Avoid ambient shell settings accidentally filling missing application inputs;
document any inherited execution environment the harness needs.

## Integration and ownership

Settei owns the generic interface, execution safeguards, examples, and configuration
diagnostic conventions. Pulumi-specific extraction remains in
`mori://tan/tan-app-infrastructure`; no Pulumi SDK or Kubernetes client dependency is
required in Settei. The example must make clear whether its input extraction handles
literal environment entries, secret references, generated values, and mounted files.
Unsupported or unknown inputs must remain visible rather than silently disappear.

[IR-1](export-a-deployment-configuration-contract.md) can guide input authoring, and
[IR-2](validate-supplied-environment-variable-names.md) can check supplied variable names.
Neither is a hard prerequisite for running existing application check modes. Likewise,
the workflow can use current application-owned invariant checks before the structured
validation mechanism in [IR-4](integrate-application-validation-into-structured-diagnostics.md)
exists. These are complementary requests, not claims of implemented integration.

## Validation boundary

Real secret material may be unavailable before provisioning. A synthetic value may
exercise a decoder but does not validate the actual deployed secret, and an unresolved
Pulumi output is not a known application value. The workflow must report these limits
and define which outcomes block a caller's gate. It must not silently substitute a
placeholder and label the whole configuration valid.

The harness executes a caller-selected application check command; it cannot prove that
an arbitrary executable has no effects. The documented application contract and tested
reference paths must establish that checks exit before resource acquisition. Control
timeouts, inherited inputs, and temporary secret files, and preserve safe error and exit
information without exposing credentials. Configuration acceptance does not establish
database connectivity, provider authentication, deployed image identity, or readiness.

AC-1 through AC-5 define future acceptance. This request authorizes no provisioning or
deployment and does not prescribe an operator-side apply path.
