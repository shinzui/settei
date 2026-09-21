---
title: "Secret-safe text and JSON diagnostics"
type: Capability
description: "Render schemas, successful or failed resolutions, errors, and warnings as deterministic text or versioned JSON without retaining declared secret values."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
capabilityId: CAP-3
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - settei
interface:
  - Settei.Render
  - Settei.Error
  - Settei.Provenance
requires:
  - CAP-1
  - CAP-2
evidence:
  - kind: test
    resource: settei/test/Settei/RenderTest.hs
    proves: Golden text and JSON output is deterministic, distinguishes missing from skipped settings, and redacts secret and mixed-sensitivity sentinels.
  - kind: conformance
    resource: examples/settei-conformance/test/Settei/Example/ConformanceTest.hs
    proves: Cross-format success and failure reports retain honest provenance without emitting captured secret sentinels.
  - kind: guide
    resource: docs/security.md
    proves: The exact redaction boundary, adapter-error posture, and remaining application responsibilities are documented.
---

# Secret-safe text and JSON diagnostics

Settei renders static schemas from the
[typed declaration (CAP-1)](typed-inspectable-declarations.md),
[resolution reports (CAP-2)](layered-resolution-and-provenance.md), structured errors,
and warnings in stable text and versioned deterministic JSON. A `Secret` setting is
converted to an opaque reported value before a resolution node or structured error
retains it. If the same key appears with mixed sensitivity, `Secret` wins everywhere and
resolution also returns a structured conflict.

```haskell
schemaText = renderSchemaText (describe serviceConfig)
reportJson = renderResolutionJson (result ^. #report)
errorsText = either renderErrorsText (const "") (result ^. #answer)
```

The public `ReportedValue` interface can render its safe display form but cannot recover
an underlying secret.

## Limits

- Redaction depends on the declaration author choosing `secretSetting`. It cannot repair
  a public classification after a value has been logged elsewhere.
- Adapter parsing happens before a raw value is matched to a setting. Maintained adapters
  use source-free structured errors, but applications must not append raw input or
  third-party exception text.
- Resolved typed secrets remain available to application code. Settei does not prevent an
  application from logging them or deriving revealing `Show` instances.
- Paths, keys, source names, and trusted annotations remain visible and may themselves be
  operationally sensitive.
