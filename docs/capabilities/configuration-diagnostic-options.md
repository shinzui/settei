---
title: "Reusable configuration diagnostic options"
type: Capability
description: "Add mutually exclusive describe, check, and explain modes to an optparse-applicative program and render the matching source-free or post-resolution output."
generated:
  by: openai/codex
  at: 2026-10-21T20:02:35Z
capabilityId: CAP-7
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.2.0.0"
packages:
  - settei-optparse-applicative
interface:
  - Settei.Optparse
requires:
  - CAP-1
  - CAP-2
  - CAP-3
evidence:
  - kind: test
    resource: settei-optparse-applicative/test/Settei/OptparseTest.hs
    proves: Diagnostic flags are mutually exclusive, default correctly, render the requested schema or resolution form, and appear in an intent-grouped help surface.
  - kind: example
    resource: examples/settei-cli/test/Settei/Example/CliTest.hs
    proves: Describe modes avoid source loading while explain and check modes operate after resolution with documented output and exit behavior.
  - kind: guide
    resource: docs/guides/cli-application.md
    proves: A complete CLI wires diagnostic mode selection around declaration inspection, source loading, resolution, rendering, and exits.
---

# Reusable configuration diagnostic options

The 0.2.0.0 command-line surface adds a standard `DiagnosticMode` for
`--describe-config`, `--describe-config-json`, `--check-config`,
`--explain-config`, and `--explain-config-json`. The next 0.3.0.0 release also adds
`--deployment-contract` and `--deployment-contract-json`. The unreleased checked API
uses `prepareDiagnostic mode schema contractSupport` before all input acquisition.
It renders schema or [deployment contract (CAP-14)](deployment-configuration-contract.md)
output, rejects unavailable contract support, or returns a private runtime-only token.
Only that token can be passed to `resolutionDiagnostic` or `validatedDiagnostic`.

```haskell
case prepareDiagnostic mode (describe serviceConfig) contractSupport of
  DiagnosticRejected problems -> reject problems
  DiagnosticRendered output -> emit output
  DiagnosticNeedsRuntime token -> do
    result <- acquire
    case resolutionDiagnostic token result of
      DiagnosticFailure problems -> reject problems
      DiagnosticOutput output -> emit output
      DiagnosticContinue config -> runApplication config
```

The [compiling example](../guides/cli-application.md#add-diagnostics-that-match-user-intent)
shows public imports. `Nothing` contract support rejects both flags with fixed plain
text before runtime work. Partial selectors remain renderers; their `Nothing` is never
startup permission. Tokens belong to their invocation and must not be cached for reuse.

`setteiOptions` packages the conventional configuration and diagnostics option groups;
the lower-level parsers remain available for customized applications.

For applications with [validators (CAP-16)](structured-application-validation.md),
call `validate` and then `validatedDiagnostic`. Its `DiagnosticFailure`,
`DiagnosticOutput`, and `DiagnosticContinue` decisions share rejection across all modes
and keep check success after validation. JSON explain failures produce two versioned
JSON documents on stderr; successful JSON explanation produces one on stdout.

## Limits

- The helpers return output text; the application still owns source loading, error
  routing, stdout/stderr selection, and exit codes.
- Both runtime helpers check their answer before check success. With validators use
  `validatedDiagnostic` after `validate`. Neither helper reloads or watches configuration.
- Call preparation before application-owned effects. `DiagnosticNeedsRuntime` authorizes
  resolution; only successful `DiagnosticContinue` authorizes startup.
- The option vocabulary is experimental and the 0.2.0.0 release already replaced the
  earlier `ExplainMode` API.
