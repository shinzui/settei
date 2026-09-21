---
title: "Typed Dhall sources with bounded imports"
type: Capability
description: "Evaluate typed, JSON-compatible Dhall into provenance-aware sources under an explicit no-import or canonical local-directory import policy."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
capabilityId: CAP-10
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - settei-dhall
interface:
  - Settei.Dhall
requires:
  - CAP-2
evidence:
  - kind: test
    resource: settei-dhall/test/Settei/DhallTest.hs
    proves: Typed records and official JSON shapes translate correctly, import policies reject escape capabilities, import closures remain cache-independent, errors are safe and positioned, and higher sources override through core resolution.
  - kind: conformance
    resource: settei-dhall/test/Settei/DhallPrototypeTest.hs
    proves: NoImports and LocalImportsWithin reject parent, symlink, environment, remote, missing, and alternative import escape paths before evaluation.
  - kind: guide
    resource: docs/guides/dhall.md
    proves: Typed loading, schema defaults, import-policy selection, closure provenance, and the preflight race are documented.
---

# Typed Dhall sources with bounded imports

`settei-dhall` type-checks and normalizes an expression, converts its official
JSON-compatible shape into a source, and feeds it to
[layered resolution (CAP-2)](layered-resolution-and-provenance.md). `NoImports` rejects
every embedded import. `LocalImportsWithin root` permits only canonical local paths below
that explicit root while rejecting parent and symlink escapes, environment and remote
imports, missing imports, and alternatives.

```haskell
options =
  dhallSourceOptions
    "application.dhall"
    (LocalImportsWithin "config")

loaded <- loadDhallSourceDetailed options (DhallFile "config/application.dhall")
```

The detailed result reports the root and cache-independent transitive local import
closure, including import mode and an optional semantic hash.

## Limits

- Only JSON-compatible normalized values become Settei sources. This is not an arbitrary
  Haskell-type decoder.
- Remote and environment imports are outside the maintained surface. `NoImports` is the
  safest default for general loaders.
- Local policy enforcement is a canonicalization preflight, not an operating-system
  sandbox. An untrusted actor able to mutate files or symlinks concurrently can race the
  check and upstream read.
- Normalization prevents honest leaf-to-import attribution. Provenance reports the root
  and closure, not a fabricated origin for each leaf.
