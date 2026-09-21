---
title: "Typed, inspectable configuration declarations"
type: Capability
description: "Declare typed settings, decoders, defaults, and conditional branches once, then inspect every possible key without reading configuration input."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
capabilityId: CAP-1
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.1.0.0"
packages:
  - settei
interface:
  - Settei
  - Settei.Config
  - Settei.Default
  - Settei.Setting
  - Settei.Value
  - Settei.Schema
evidence:
  - kind: test
    resource: settei/test/Settei/ConfigTest.hs
    proves: Applicative and Selective declarations expose necessary and conditional settings while skipping unselected branches at evaluation time.
  - kind: test
    resource: settei/test/Settei/ValueTest.hs
    proves: Built-in and compositional decoders preserve typed results and secret-safe failure messages.
  - kind: guide
    resource: docs/guides/getting-started.md
    proves: A consumer-facing declaration, decoder, conditional, default, and source-free schema workflow is documented end to end.
---

# Typed, inspectable configuration declarations

A consumer describes application configuration as a `Config a` built from typed
`Setting` values. Each setting owns its structural key, decoder, description, and
`Public` or `Secret` sensitivity. Applicative composition handles independent settings;
Selective composition and the `whenConfig`, `whenEq`, and `fallbackTo` helpers express
runtime branches without losing their static footprint. Named constant, derived, and
case defaults declare fallback behavior and dependencies.

`describe` turns the declaration into a complete `Schema` without opening a file,
reading the environment, or parsing arguments:

```haskell
serviceConfig =
  ServiceConfig
    <$> required environmentSetting
    <*> withDefault portSetting portDefault
    <*> whenEq
          (required environmentSetting)
          Production
          (required passwordSetting)

schema = describe serviceConfig
```

## Limits

- `Config` intentionally has no `Monad` instance. A key chosen from a resolved value
  could not be included in the complete source-free schema.
- Settings must classify sensitivity correctly; Settei cannot infer secrets from key
  names or origins.
- Custom decoders are responsible for accepting the raw shapes their selected source
  adapters produce. Environment and command-line sources, for example, produce text.
- The compatibility promise remains experimental at 0.2.0.0; only the documented public
  modules form the supported adoption surface.
