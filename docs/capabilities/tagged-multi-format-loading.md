---
title: "Tagged YAML, KDL, and Dhall loading"
type: Capability
description: "Parse ordered FORMAT:PATH inputs and dispatch them through the maintained YAML, KDL, and Dhall adapters with one shared option and error policy."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
capabilityId: CAP-11
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.2.0.0"
packages:
  - settei-formats
interface:
  - Settei.Formats
  - Settei.Formats.Optparse
requires:
  - CAP-8
  - CAP-9
  - CAP-10
evidence:
  - kind: test
    resource: settei-formats/test/Settei/FormatsTest.hs
    proves: Explicit tags parse, each adapter loads and resolves values, annotations propagate, Dhall imports default closed, and adapter errors remain structured.
  - kind: test
    resource: settei-formats/test/Settei/FormatsOptparseTest.hs
    proves: Repeated --config inputs preserve occurrence order while unsupported tags fail option parsing and caller metadata remains customizable.
  - kind: guide
    resource: docs/guides/formats.md
    proves: Tagged option parsing, ordered loading, annotation policy, errors, and explicit Dhall capability widening are documented.
---

# Tagged YAML, KDL, and Dhall loading

`settei-formats` is the shared dispatcher for applications that deliberately support the
[YAML (CAP-8)](strict-yaml-sources.md), [KDL (CAP-9)](canonical-kdl-sources.md), and
[Dhall (CAP-10)](policy-bounded-dhall-sources.md) adapters. `ConfigInput` requires an
explicit lowercase `yaml:`, `kdl:`, or `dhall:` tag, and the optparse-applicative helper
preserves repeated input order.

```text
--config yaml:config/base.yaml
--config kdl:config/local.kdl
--config dhall:config/application.dhall
```

`loadConfigInput` delegates to the named adapter and wraps its full structured error
list. Shared options attach trusted annotations and mounted-file Kubernetes identity;
Dhall imports remain disabled unless the application explicitly supplies a bounded
policy.

## Limits

- The package supports exactly YAML, KDL, and Dhall. It does not auto-detect formats or
  infer them from file extensions.
- Supporting all three parser stacks is the adoption tradeoff. A single-format
  application should depend directly on that adapter.
- Loading one input does not establish precedence by itself; the caller must retain input
  order when assembling sources.
- Shared Kubernetes metadata is descriptive only, and `defaultLoadOptions` intentionally
  denies Dhall imports.
