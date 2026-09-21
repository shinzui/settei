---
title: "Reusable configuration diagnostic options"
type: Capability
description: "Add mutually exclusive describe, check, and explain modes to an optparse-applicative program and render the matching source-free or post-resolution output."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
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
`--explain-config`, and `--explain-config-json`. `schemaDiagnostic` renders the
[source-free declaration (CAP-1)](typed-inspectable-declarations.md) before any input is
loaded. `resolutionDiagnostic` consumes a [resolution result (CAP-2)](layered-resolution-and-provenance.md)
and delegates explanations to the [safe renderers (CAP-3)](secret-safe-diagnostics.md).

```haskell
case schemaDiagnostic mode (describe serviceConfig) of
  Just output -> putStr output
  Nothing -> loadAndResolve mode
```

`setteiOptions` packages the conventional configuration and diagnostics option groups;
the lower-level parsers remain available for customized applications.

## Limits

- The helpers return output text; the application still owns source loading, error
  routing, stdout/stderr selection, and exit codes.
- `CheckConfig` can only confirm the `ResolveResult` supplied by the caller. It does not
  independently reload or watch configuration.
- Describe modes are source-free only when the application dispatches them before its
  own loading code, as the reference applications do.
- The option vocabulary is experimental and the 0.2.0.0 release already replaced the
  earlier `ExplainMode` API.
