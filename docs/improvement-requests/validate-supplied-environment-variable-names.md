---
type: Improvement Request
title: Validate supplied environment variable names against declared bindings
description: Catch misspelled or unsupported application environment variables before deployment without rejecting unrelated process variables or exposing values.
requestId: IR-2
status: completed
completedAt: "2026-10-21T16:08:03Z"
resolution: "Implemented by docs/plans/27-validate-supplied-environment-variable-names-against-declared-bindings.md; 42 adapter tests and 24 CLI tests cover names, allowances, strict snapshots, defaults, redaction, and escaped text/JSON diagnostics."
targetPlan: docs/plans/27-validate-supplied-environment-variable-names-against-declared-bindings.md
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
    context: Author self-check against the requested priorities, Settei environment translation, and notification-hub bindings; no independent review or implementation acceptance claimed.
acceptanceCriteria:
  - id: AC-1
    statement: A public helper compares an explicitly supplied collection of application environment variable names with validated Bindings and reports every unsupported name deterministically without requiring any values.
    verification: Test known names, multiple unsupported names, an empty collection, and stable diagnostic ordering using the same bindings accepted by environmentSource.
  - id: AC-2
    statement: Callers can explicitly allow variables consumed outside Settei, while unrelated inherited process variables are excluded unless the caller deliberately includes them in the validation scope.
    verification: Check an application-variable collection containing an allowed SDK variable and an unsupported name while the surrounding process contains PATH and other unrelated variables; verify only the unsupported application name is rejected.
  - id: AC-3
    statement: An opt-in strict validation path rejects unsupported supplied names before successful configuration validation can hide them behind defaults, without changing existing permissive environmentSource behavior.
    verification: Supply HASKELL_ENV to a notification-hub-shaped fixture that binds ENVIRONMENT and defaults to development; prove strict validation fails, a corrected name succeeds, and existing translation remains compatible.
  - id: AC-4
    statement: Diagnostics name variables and any declared target keys without retaining or rendering environment values, including values attached to unknown names.
    verification: Put secret sentinels in known and unknown variables and assert they are absent from errors, text and JSON output, and displayed failure structures.
  - id: AC-5
    statement: Documentation shows a deployment author checking exactly the application variables supplied by a container specification and explains that a missing variable can legitimately be supplied through another configuration source or default.
    verification: Exercise examples with environment, YAML, defaults, and an external consumer allowlist; verify the helper does not equate absent bindings with missing required configuration.
---

# Validate supplied environment variable names against declared bindings

## Problem and desired outcome

The environment adapter translates only explicitly bound variables. Unsupported names
are omitted before core resolution, so `RejectUnknownKeys` cannot report them. A typo
can leave a default active and still produce a successful `--check-config` result.

For the first deployment of `mori://tan/notification-hub`, copying another service's
`HASKELL_ENV` would fail to set `runtime.environment`: the binding in
`mori://tan/notification-hub/packages/notification-hub-core` is `ENVIRONMENT`, and its
built-in default is `development`. This request should make that mismatch visible when
checking the proposed deployment inputs.

Add a reusable name-validation helper in the environment adapter and document its use
before normal resolution. It should consume existing validated bindings and the names
the deployment author explicitly intends to supply. Existing
[binding inspection](../../settei-env/src/Settei/Env.hs) provides the necessary public
data; [IR-1](export-a-deployment-configuration-contract.md) is a useful later integration
but is not a prerequisite.

## Scope and safety

Keep validation opt-in and scoped. A container also receives runtime variables and may
configure SDKs outside Settei, so rejecting the entire process environment by default
would produce false errors. Support an explicit external-consumer allowance and make
the checked collection visible to callers. Do not silently normalize names or invent
aliases; an accepted name must have a declared binding or allowance.

This is a supplied-name check, not a required-value check. Configuration may come from
files, defaults, or CLI inputs instead. The core resolver continues to own requiredness
and value decoding. Duplicate deployment entries and their precedence must not be
silently presented as validated by this helper if its input has already lost that
information.

Settei owns the generic helper, safe diagnostics, compatibility tests, and example.
Extraction from Pulumi container inputs belongs to `mori://tan/tan-app-infrastructure`.
The structured AC-1 through AC-5 conditions are implemented and verified by
[ExecPlan 27](../plans/27-validate-supplied-environment-variable-names-against-declared-bindings.md).
The implementation is unreleased; the existing permissive translator remains unchanged.
