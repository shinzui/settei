---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Architecture Decision Record

- [Adopt the Haskell project conventions](0001-haskell-project-conventions.md) - Adopt a shared repository-wide Haskell convention baseline drawn from the shinzui/haskell-jitsurei corpus.
- [Use an explicit inspectable selective configuration algebra](0002-inspectable-configuration-algebra.md) - Represent configuration declarations as a private inspectable GADT-based selective algebra.
- [Define leaf-wise resolution, provenance, and default semantics](0003-resolution-provenance-and-default-semantics.md) - Define shared leaf-wise resolution, provenance, and default semantics across all Settei sources.
- [Parse a strict marked-event YAML subset](0004-yaml-input-semantics.md) - Parse YAML through libyaml's strict marked-event stream, rejecting duplicate keys and preserving honest source locations.
- [Adopt a canonical span-preserving KDL v2 mapping](0005-canonical-kdl-v2-input-semantics.md) - Adopt a canonical, span-preserving mapping from KDL v2 into Settei's core raw value tree.
- [Bound Dhall evaluation to observable import policies](0006-dhall-input-import-and-provenance-semantics.md) - Bound Dhall evaluation to explicit, observable local-import capability policies.
- [Use internal reference applications as the public-API conformance boundary](0007-reference-applications-are-the-public-api-conformance-boundary.md) - Use three internal reference applications as the conformance boundary that proves the public API composes.
- [Isolate multi-format loading in an umbrella package](0008-settei-formats-umbrella-package.md) - Isolate shared multi-format input parsing and dispatch in the settei-formats umbrella package.
- [Give every source adapter an operator-readable error renderer](0009-adapter-error-rendering-contract.md) - Give every source adapter a shared operator-readable error rendering contract.
- [Validate environment bindings at construction](0010-validate-environment-bindings-at-construction.md) - Validate environment bindings once at construction through an opaque Bindings collection.
- [Map Kubernetes mounted directories through explicit file bindings](0011-kubernetes-mounted-directory-input-semantics.md) - Map Kubernetes mounted directories to Settei keys through explicit validated file bindings.

