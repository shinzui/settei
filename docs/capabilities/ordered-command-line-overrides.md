---
title: "Ordered command-line override sources"
type: Capability
description: "Parse generic or named optparse-applicative options into secret-safe source fragments whose occurrence order determines leaf-level precedence."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
capabilityId: CAP-6
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - settei-optparse-applicative
interface:
  - Settei.Optparse
requires:
  - CAP-2
evidence:
  - kind: test
    resource: settei-optparse-applicative/test/Settei/OptparseTest.hs
    proves: Repeated overrides preserve a shadow trace, the final occurrence wins, malformed winners do not fall back, named flags are optional fragments, and origin spellings omit values.
  - kind: example
    resource: examples/settei-cli/test/Settei/Example/CliTest.hs
    proves: A reference CLI places override fragments above environment and file sources and safely reports resolution failures.
  - kind: guide
    resource: docs/guides/environment-and-cli.md
    proves: Generic --set options, named options, custom option metadata, and precedence assembly are documented.
---

# Ordered command-line override sources

`settei-optparse-applicative` parses repeated `--set KEY=VALUE` occurrences as ordered
`CliOverride` values and converts each occurrence to its own source fragment. Under
[core resolution (CAP-2)](layered-resolution-and-provenance.md), the final occurrence for
a key wins and every earlier occurrence remains in the provenance shadow trace. `namedOption`
turns a normal text flag into an optional one-key source.

```haskell
overrideParser = overrideOptions

orderedSources =
  fileSources
    <> [environmentSource]
    <> cliSources "arguments" parsedOverrides
```

The retained origin spelling names the option and key but never includes the raw value.

## Limits

- Override values remain text until the winning setting decoder runs. Option parsing
  validates the key, not the application value.
- Repeated generic overrides preserve raw occurrence order, but precedence between
  separately parsed groups such as named options and `--set` is chosen by the
  application's assembly function.
- A malformed high-precedence value fails resolution instead of revealing or selecting a
  lower value.
- This package does not load paths returned by its untagged `--config PATH` parser; the
  application must choose and document a format policy.
