---
okf_version: "0.2"
title: "Settei capability catalog"
---

# What Settei provides today

Settei provides typed, layered, provenance-aware configuration for Haskell. This catalog
groups the public package family by the behaviors a consumer can adopt and verify
independently:

| Handle | Capability | Packages | Since |
|---|---|---|---|
| [CAP-1](typed-inspectable-declarations.md) | Typed, inspectable configuration declarations | settei | 0.1.0.0 |
| [CAP-2](layered-resolution-and-provenance.md) | Layered resolution, defaults, and provenance | settei | 0.1.0.0 |
| [CAP-3](secret-safe-diagnostics.md) | Secret-safe text and JSON diagnostics | settei | 0.1.0.0 |
| [CAP-4](validated-custom-sources.md) | Validated custom source construction | settei | 0.1.0.0 |
| [CAP-5](explicit-environment-sources.md) | Explicit environment-variable sources | settei-env | 0.1.0.0 |
| [CAP-6](ordered-command-line-overrides.md) | Ordered command-line override sources | settei-optparse-applicative | 0.1.0.0 |
| [CAP-7](configuration-diagnostic-options.md) | Reusable configuration diagnostic options | settei-optparse-applicative | 0.2.0.0 |
| [CAP-8](strict-yaml-sources.md) | Strict, location-preserving YAML sources | settei-yaml | 0.1.0.0 |
| [CAP-9](canonical-kdl-sources.md) | Canonical, span-preserving KDL v2 sources | settei-kdl | 0.1.0.0 |
| [CAP-10](policy-bounded-dhall-sources.md) | Typed Dhall sources with bounded imports | settei-dhall | 0.1.0.0 |
| [CAP-11](tagged-multi-format-loading.md) | Tagged YAML, KDL, and Dhall loading | settei-formats | 0.2.0.0 |
| [CAP-12](kubernetes-mounted-directory-sources.md) | Kubernetes mounted-directory sources | settei-kubernetes | 0.2.0.0 |
| [CAP-13](kubernetes-environment-bindings.md) | Kubernetes-derived environment bindings | settei-kubernetes, settei-env | 0.2.0.0 |

Every record is `status: shipped` and `stability: experimental`. The package family is
released and usable at 0.2.0.0, while the compatibility policy explicitly makes no
semantic-stability promise beyond the documented modules and release notes.

## Deliberately excluded

- The three packages under `examples/` are internal conformance and reference
  applications. They provide evidence for public capabilities but are not themselves
  consumer dependencies.
- Individual decoders, declaration combinators, source accessors, renderer functions,
  parser error categories, and command-line flags are grouped under their independently
  adoptable mechanisms rather than copied into one record per symbol.
- The namespace deployment manifests and cookbook compose Settei with Kubernetes
  deployment machinery. The repository provides the mounted-file and binding adapters;
  it does not claim cluster deployment as a library capability.
- No planned behavior is listed. A feature without shipped repository evidence belongs
  in an improvement request, not this catalog.
