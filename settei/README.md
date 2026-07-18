# settei

`settei` is the core package in the Settei family of typed, layered, explainable
configuration libraries for Haskell. It owns the inspectable declaration language,
hierarchical resolution semantics, provenance model, derived defaults, and secret-safe
text and JSON reports.

Import `Settei` for the supported public entry point. Format and integration adapters are
published as separate `settei-*` packages so applications only depend on the parsers and
boundaries they use.

The package family, guides, architecture records, and implementation plans live in the
[Settei repository](https://github.com/shinzui/settei).
