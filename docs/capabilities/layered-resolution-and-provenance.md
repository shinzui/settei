---
title: "Layered resolution, defaults, and provenance"
type: Capability
description: "Resolve typed declarations against low-to-high ordered sources with leaf-wise precedence, named defaults, complete provenance, and reports that survive failure."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
capabilityId: CAP-2
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - settei
interface:
  - Settei.Resolve
  - Settei.Report
  - Settei.Origin
  - Settei.Provenance
requires:
  - CAP-1
evidence:
  - kind: test
    resource: settei/test/Settei/ResolveTest.hs
    proves: Rightmost precedence, shadow traces, structural errors, conditional branches, failure reports, warnings, and strict unknown-key handling follow the documented policy.
  - kind: test
    resource: settei/test/Settei/DefaultTest.hs
    proves: Constant and dependency-aware defaults record derivations, skip unnecessary dependencies, and reject cycles.
  - kind: example
    resource: examples/settei-cli/test/Settei/Example/CliTest.hs
    proves: A complete application orders files, environment values, and command-line overrides and retains provenance on both success and failure.
---

# Layered resolution, defaults, and provenance

`resolve` interprets an inspectable [declaration (CAP-1)](typed-inspectable-declarations.md)
against sources ordered from lowest to highest precedence. Selection is leaf-wise: the
rightmost candidate for one key wins, arrays replace as whole values, and every shadowed
origin remains ordered in the `ResolutionReport`. Named default derivations, skipped
Selective branches, unknown keys, and structural conflicts appear in the same report.

```haskell
result =
  resolve
    defaultResolveOptions
    (builtIns <> fileSources <> [environmentSource] <> cliSources)
    serviceConfig
```

`ResolveResult` always carries its report and warnings, even when its typed `answer`
fails. Consumers can therefore explain which candidates were examined instead of losing
diagnostic context at the first error.

## Limits

- Source order is the precedence policy. Settei does not assign an intrinsic priority
  to files, environment variables, or arguments.
- An invalid winning value is an error; resolution does not silently fall back to a
  lower candidate or a default.
- Arrays are leaves and replace rather than merge. Traversing through a scalar, array,
  or null to reach a deeper key is a structural error.
- Default dependencies must be expressible as an inspectable `Config`; cycles fail before
  source evaluation.
