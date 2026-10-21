---
type: Improvement Request
title: Integrate application validation into structured configuration diagnostics
description: Represent post-resolution application invariants as safe structured failures shared by startup, check mode, and text or JSON explanations.
requestId: IR-4
status: in-progress
targetPlan: docs/plans/29-integrate-application-validation-into-structured-configuration-diagnostics.md
origin: mori://tan/notification-hub
generated:
  by: process:codex
  at: "2026-10-21T16:24:00Z"
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
    context: Author self-check against notification-hub post-resolution validators and Settei resolution and rendering boundaries; no independent review or implementation acceptance claimed.
acceptanceCriteria:
  - id: AC-1
    statement: A public mechanism applies application-owned pure validators to a successfully resolved typed configuration and returns structured failures with stable rule identifiers and references to the involved declared setting keys.
    verification: Validate notification-hub-shaped pool-capacity, visibility-timeout, replica, and provider-account rules; assert stable identifiers and correct key references, including rejection or explicit handling of invalid references.
  - id: AC-2
    statement: Normal startup, configuration check mode, and text or JSON explanation modes can consume one validated result so application invariant failures reject configuration consistently while retaining the resolution provenance report.
    verification: Feed the same failing configuration through every mode and verify non-success, matching rule and key information, winning-source provenance, and compatibility with existing source and decode failures.
  - id: AC-3
    statement: Structured failures and their rendering contain safe rule metadata rather than the typed configuration or rejected raw values, with an explicit contract for author-supplied messages and sensitivity handling.
    verification: Use secret-bearing configurations and sentinel values in multi-key failures; assert no sentinel appears in retained failure structures, text, JSON, or Show output, and document how custom validators must avoid embedding values in metadata.
  - id: AC-4
    statement: Validator sequencing, independent-error accumulation or fail-fast behavior, applicability to process roles, and behavior when base resolution fails are explicitly defined without losing static configuration inspection.
    verification: Exercise multiple independent failures, dependent checks, role-specific checks, skipped checks after failed resolution, and deterministic ordering; prove describe mode does not run validators or acquire application resources.
  - id: AC-5
    statement: A migration example moves an existing post-resolution check into the shared mechanism without duplicating domain rules, changing successful typed values, weakening startup rejection, or breaking existing consumers without a documented compatibility path.
    verification: Compare old and new acceptance behavior for valid and invalid fixtures, include a failure that currently returns plain Text after resolution, and verify the documented versioning of affected public APIs and JSON output.
---

# Integrate application validation into structured configuration diagnostics

## Problem and desired outcome

Per-setting decoders cannot express every relationship needed to accept an application
configuration. In `mori://tan/notification-hub/packages/notification-hub-workers`,
post-resolution checks enforce visibility-timeout bounds, job-pool capacity, replica
relationships, and email-account consistency. The server's checks in
`mori://tan/notification-hub/packages/notification-hub-server` also reject malformed
provider event keys before resources open.

These checks are already used by startup and check mode, but their failures are returned
through application-specific text paths after Settei resolution. Applications have to
arrange consistent exits and diagnostics themselves. Such failures can bypass the
ordinary explanation report and cannot be consumed as structured Settei JSON with
stable rule identities and related setting keys.

Provide a shared post-resolution validation boundary and structured diagnostics while
keeping domain policy in the application. A deployment preflight consumer should be
able to identify the failed rule, locate the relevant settings, and retain their
provenance without parsing English messages or reimplementing the rule in Pulumi.

## Requested semantics

Apply validators only when a typed configuration is available. Define their ordering
and error-collection behavior, including whether dependent validators stop after a
prerequisite failure. Let applications select the validators relevant to each process
role, and ensure the validated result is usable by startup as well as diagnostic modes.
Do not allow a successful check-mode message to precede application validation.

Failures should carry stable identifiers, references to existing setting keys, and safe
expectation or explanation metadata. They must not retain the configuration record,
raw input, provider credentials, or a revealing automatically derived Show instance.
Because a custom validator can deliberately interpolate secret values into a message,
document its responsibility and design structured constructors to minimize accidental
leakage; do not claim that arbitrary caller-supplied text can be automatically sanitized.

Preserve the original resolution report on validation failure and define how renderers
and CLI helpers represent both base resolution failures and application invariant
failures. The [inspectable declaration algebra](../../settei/src/Settei/Config.hs) must
retain source-free describe behavior; this request does not require a Monad instance or
runtime-generated setting keys.

## Scope, adoption, and acceptance

Settei owns the reusable validation result, safe failure representation, renderer and
CLI integration, and a focused migration example. Applications own their invariants
and the meaning of valid role configuration. Validation of network access, database
state, provider credentials, or other live dependencies remains a separate operational
check; the requested validators are pure configuration acceptance checks.

[IR-3](provide-a-reusable-deployment-preflight-workflow.md) is a future consumer of the
structured result and can be implemented using current application checks first. No
hard dependency on the deployment-contract export in
[IR-1](export-a-deployment-configuration-contract.md) is required. AC-1 through AC-5
define future completion; this request does not claim those capabilities are shipped.
