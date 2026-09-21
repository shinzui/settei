---
title: "Canonical, span-preserving KDL v2 sources"
type: Capability
description: "Translate a canonical KDL v2 document into a provenance-aware source with exact spans, deterministic cardinality, and explicit ambiguity errors."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
capabilityId: CAP-9
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - settei-kdl
interface:
  - Settei.Kdl
requires:
  - CAP-2
evidence:
  - kind: test
    resource: settei-kdl/test/Settei/KdlTest.hs
    proves: Nested nodes, arguments, properties, repeated siblings, precedence, mounted metadata, safe IO failures, and exact primary or related spans follow the canonical mapping.
  - kind: conformance
    resource: settei-kdl/test/Settei/KdlCharacterizationTest.hs
    proves: KDL v2 scalars remain typed while duplicate properties, annotations, non-finite values, invalid names, and oversized exponents fail explicitly.
  - kind: guide
    resource: docs/guides/kdl.md
    proves: The canonical mapping, location model, rejected shapes, and loading workflow are documented for consumers.
---

# Canonical, span-preserving KDL v2 sources

`settei-kdl` gives KDL v2 one deterministic mapping into a source for
[layered resolution (CAP-2)](layered-resolution-and-provenance.md). An empty node is
null, one positional argument is a scalar, two or more are an array, properties and
non-colliding children form an object, and repeated sibling nodes form an ordered array.
Every produced candidate retains its source span; collision errors can retain a second
related span.

```haskell
loaded <-
  readKdlSource
    (kdlSourceOptions "application.kdl")
    "application.kdl"
```

## Limits

- Arguments mixed with children or properties are rejected. Property/child collisions,
  duplicate properties, annotations, empty or dotted names, and non-finite numbers also
  fail rather than receiving application-specific semantics.
- Base-10 exponent magnitudes above 4096 are rejected before exact conversion.
- Repeated siblings form arrays by document order; consumers cannot select an alternate
  cardinality rule through options.
- Kubernetes references on source options are asserted metadata only and do not perform
  cluster access or sensitivity classification.
