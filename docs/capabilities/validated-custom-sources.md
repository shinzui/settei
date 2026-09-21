---
title: "Validated custom source construction"
type: Capability
description: "Build hierarchical configuration sources from validated key/value pairs and attach exact locations and provenance annotations for application-specific adapters."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
capabilityId: CAP-4
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - settei
interface:
  - Settei.Source
  - Settei.Origin
requires:
  - CAP-2
evidence:
  - kind: test
    resource: settei/test/Settei/SourceTest.hs
    proves: Validated pair construction rejects duplicates and prefix overlaps while locations and layered annotations reach the matching candidate origins.
  - kind: module
    resource: settei/src/Settei/Source.hs
    proves: The public constructors, lookup semantics, annotation hooks, and unaddressable-leaf inspection contract are defined at the adapter boundary.
  - kind: guide
    resource: docs/guides/getting-started.md
    proves: The source abstraction and low-to-high ordering contract are introduced as the extension seam used by every maintained adapter.
---

# Validated custom source construction

Applications and third-party adapters can construct `Source` values for boundaries the
published adapters do not cover. `sourceFromPairs` takes validated structural `Key`
values, rejects duplicates and prefix overlaps, and guarantees every resulting leaf is
addressable. `locateSource`, `annotateSource`, and `annotateSourceAt` attach source-wide
and per-key explanation data consumed by [resolution (CAP-2)](layered-resolution-and-provenance.md).

```haskell
customSource =
  sourceFromPairs
    "service discovery"
    (CustomSource "discovery")
    [(hostKey, RawText host), (portKey, RawText port)]
```

## Limits

- `sourceFromPairs` checks tree addressability, not application decoding or sensitivity;
  those remain properties of the matching declaration.
- The lower-level `source` constructor is an unvalidated escape hatch for adapters that
  already guarantee a valid tree. Empty or dotted object segments can otherwise create
  leaves invisible to lookup and unknown-key diagnostics.
- Annotations are trusted descriptive metadata. They do not attest an external system or
  affect precedence.
- A custom adapter must keep its own parse failures secret-safe because the core cannot
  classify raw input before it becomes a source candidate.
