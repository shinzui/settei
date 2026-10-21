---
title: Structured application validation
type: Capability
description: Apply pure application invariants to typed configuration with checked rule metadata, ordered outcomes, shared rejection paths, and retained provenance.
generated:
  by: process:codex
  at: 2026-10-21T20:02:35Z
capabilityId: CAP-16
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.3.0.0"
packages:
  - settei
  - settei-optparse-applicative
interface:
  - Settei.Validate
  - Settei.Report
  - Settei.Render
  - Settei.Optparse
requires:
  - CAP-1
  - CAP-2
  - CAP-3
  - CAP-7
evidence:
  - kind: test
    resource: settei/test/Settei/ValidateTest.hs
    proves: Checked declarations, ordered accumulation, prerequisite skipping, not-run outcomes, role lists, unchanged values, golden diagnostics, and secret sentinel scans.
  - kind: test
    resource: settei-optparse-applicative/test/Settei/OptparseTest.hs
    proves: All modes reject invariant failures consistently and explanations retain provenance; check success follows validation.
  - kind: example
    resource: examples/settei-deployment/test/Settei/Example/DeploymentTest.hs
    proves: Existing role checks migrate without changing valid values, rejection outcomes, or static source-free dispatch.
  - kind: guide
    resource: docs/guides/cli-application.md#validate-cross-setting-invariants-after-resolution
    proves: Declaration, role composition, dispatch, diagnostics, and the author contract are documented.
---

# Structured application validation

`Settei.Validate` declares named pure rules over the resolved configuration. `validators`
checks identifiers, declared key membership, prerequisites, and declaration cycles once
into an opaque collection without a `Generic` construction bypass. `validate` preserves
resolution provenance and warnings, accumulating independent failures as `InvariantError`
values in declaration order. Dependent rules skip after unmet prerequisites; base
resolution failure leaves all rules not run. Roles compose shared validators into separate
collections. `describe` and deployment contracts stay source-free and unchanged.

`prepareDiagnostic` precedes input acquisition and returns a checked runtime token.
`validatedDiagnostic` consumes that token and supplies `DiagnosticDecision` for startup, check mode, and text or JSON
explanations. JSON errors carry kind `invariant`, rule, keys, expectation, and optional
detail. The validated resolution renderer adds an optional ordered `invariants` trace
to version 1. Bare report rendering is unchanged. JSON explain failures emit the error
and resolution documents on separate stderr lines. Added in the shared 0.3.0.0
release; 0.2.0.0 does not include this capability.

## Limits

- All rule metadata must be safe to publish. Fixed expectations are not automatically
  safe; `violationWithDetail` retains author text verbatim. Never embed secret values or
  log the typed record. Settei cannot sanitise arbitrary text. Keep line-oriented
  expectations and details single-line.
- Validators must be total and finite. They are configuration acceptance checks, not
  connectivity or credential checks.
- Use the collection with the same declaration used for resolution; matching result
  types cannot prove matching declarations. Conditional keys need total optional handling.
- Applications own stream routing, warnings, and exit codes. Use `validatedDiagnostic`
  after validation so check mode cannot announce success prematurely. Only successful
  `DiagnosticContinue` starts the application; the preparation token alone permits
  resolution. `DiagnosticDecision` replaces the unreleased `ValidatedDiagnostic` name.

See [ADR-14](../adr/0014-application-invariant-validation.md) for the durable contract.
