---
title: "Explicit environment-variable sources"
type: Capability
description: "Map an explicit, validated set of environment variables into injectable provenance-aware sources without decoding application values at the process boundary."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
capabilityId: CAP-5
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - settei-env
interface:
  - Settei.Env
requires:
  - CAP-2
evidence:
  - kind: test
    resource: settei-env/test/Settei/EnvTest.hs
    proves: Explicit and prefixed bindings validate once, snapshots remain injectable, annotations reach origins, collection merges revalidate conflicts, and secret values stay out of diagnostics.
  - kind: guide
    resource: docs/guides/environment-and-cli.md
    proves: Static binding construction, process snapshots, pure test snapshots, prefixed names, and security responsibilities are documented for consumers.
  - kind: example
    resource: examples/settei-service/test/Settei/Example/ServiceTest.hs
    proves: A service resolves annotated environment values at the documented precedence while redacting production secrets.
---

# Explicit environment-variable sources

`settei-env` binds selected portable environment names to structural Settei keys. An
opaque `Bindings` value proves the list has no invalid or duplicate variable names,
duplicate keys, or prefix-overlapping targets before source construction. Process reads
and pure injected `EnvSnapshot` values produce the same ordinary source for
[resolution (CAP-2)](layered-resolution-and-provenance.md).

```haskell
environmentBindings =
  bindings
    [ binding (EnvName "APP_HOST") hostKey
    , binding (EnvName "APP_PASSWORD") passwordKey
    ]

source = environmentSource validatedBindings testSnapshot
```

Missing variables create no candidate; empty strings are present text values. Bindings
may carry caller annotations or asserted Kubernetes object metadata, and independently
validated collections can be combined with `mergeBindings`.

## Limits

- Only listed variables are read. There is deliberately no ambient prefix discovery.
- Values enter as `RawText`; the setting decoder decides whether that spelling is valid.
- Environment values are plaintext at the process boundary and may be visible to child
  processes, debuggers, crash reporters, or privileged inspection despite report
  redaction.
- Kubernetes annotations are caller-supplied metadata. This package does not contact or
  attest a cluster.
