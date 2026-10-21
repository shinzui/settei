# settei

`settei` is the core package in the Settei family of typed, layered, explainable
configuration libraries for Haskell. It owns the inspectable declaration language,
hierarchical resolution semantics, provenance model, derived defaults, and secret-safe
text and JSON reports. It also exports source-free deployment contracts (`Settei.Contract`)
and pure post-resolution application validation (`Settei.Validate`). These additions target
the unreleased shared 0.3.0.0 version; workspace manifests retain 0.2.0.0 until release.

Use `deploymentContract` to inspect input bindings, safe defaults, and explicit profile
requirements. Use `validators` to check rule declarations once, then `validate` to retain
provenance and accumulate structured invariant failures after resolution. Validators
receive real typed secrets: keep rule metadata and optional details safe to publish.
The original `resolve` API is unchanged.

Import `Settei` for the supported public entry point. Format and integration adapters are
published as separate `settei-*` packages so applications only depend on the parsers and
boundaries they use.

The package family, guides, architecture records, and implementation plans live in the
[Settei repository](https://github.com/shinzui/settei).
