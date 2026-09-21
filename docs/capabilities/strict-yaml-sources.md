---
title: "Strict, location-preserving YAML sources"
type: Capability
description: "Translate one strict YAML mapping document into a provenance-aware source with exact node locations and explicit errors for ambiguous or unsupported constructs."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
capabilityId: CAP-8
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - settei-yaml
interface:
  - Settei.Yaml
requires:
  - CAP-2
evidence:
  - kind: test
    resource: settei-yaml/test/Settei/YamlTest.hs
    proves: Nested values retain exact locations, portable scalar meanings, precedence, Kubernetes annotations, safe IO errors, and secret redaction through core resolution.
  - kind: conformance
    resource: settei-yaml/test/Settei/YamlCharacterizationTest.hs
    proves: Duplicate keys, multiple documents, aliases, merge keys, custom tags, non-string keys, invalid booleans, and oversized exponents fail under the maintained contract.
  - kind: guide
    resource: docs/guides/yaml.md
    proves: The accepted YAML mapping, source options, file loading, error rendering, provenance, and deliberate exclusions are documented.
---

# Strict, location-preserving YAML sources

`settei-yaml` decodes an in-memory byte string or reads a file into a Settei source for
[layered resolution (CAP-2)](layered-resolution-and-provenance.md). Nested mapping keys
become structural keys, arrays remain leaf values, scalar meanings are portable, and
each candidate retains an exact one-based line and column. Stable categorized errors and
their renderers retain structural context without raw scalar values.

```haskell
loaded <-
  readYamlSource
    (yamlSourceOptions "application.yaml")
    "application.yaml"
```

Booleans follow the YAML 1.2 core schema, so only case-insensitive `true` and `false`
become booleans; spellings such as `yes`, `no`, and `on` remain text.

## Limits

- The top level must be one mapping document. Multiple documents, aliases and anchors,
  merge keys, custom tags, non-string keys, dotted literal keys, and duplicate keys are
  rejected rather than assigned ambiguous semantics.
- Special floating values are rejected, and base-10 exponent magnitudes above 4096 fail
  before exact conversion.
- Source options can assert mounted-file Kubernetes metadata but do not contact a
  cluster or make a setting secret.
- The pure decoder contains unexpected synchronous failures as source-free syntax
  errors; asynchronous exceptions still propagate.
