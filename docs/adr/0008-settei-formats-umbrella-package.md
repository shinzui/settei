# ADR 0008: Isolate multi-format loading in an umbrella package

Status: Accepted

Date: 2026-07-19


## Context

Applications that support YAML, KDL, and Dhall need two shared behaviors: parsing an
explicit `FORMAT:PATH` input and dispatching that input to the matching adapter. Both
reference applications implemented the same parser and nearly the same loader. Repeating
that policy across roughly seventy planned adopters would create many copies whose
grammar, security defaults, annotations, and error handling could drift.

The dispatcher necessarily depends on `settei-yaml`, `settei-kdl`, and `settei-dhall` at
the same time. None of those adapters should depend on the others, and the core `settei`
package must remain adapter-agnostic. Putting the dispatcher in
`settei-optparse-applicative` would also make every command-line consumer build all three
format stacks, even when it only needs `--set` overrides or one file adapter.


## Decision

Create the dedicated `settei-formats` umbrella package. It owns the `ConfigFormat` and
`ConfigInput` types, the `FORMAT:PATH` grammar, shared load options, the structured
three-adapter error sum, the dispatching loader, and the reusable command-line option.

The dependency direction is one-way and load-bearing. `settei-formats` may depend on the
core, all three file adapters, and `settei-optparse-applicative`. No source adapter may
depend on `settei-formats`. `settei-optparse-applicative` remains adapter-free and must
not depend on `settei-yaml`, `settei-kdl`, or `settei-dhall`.

Within the umbrella package, `Settei.Formats` owns the tagged types and loader, while
`Settei.Formats.Optparse` owns the command-line parser. Consumers can import the loader
module without importing optparse-applicative symbols. The package remains one
distribution because splitting one small parser module would add release and registration
work without creating a useful independent capability.

The umbrella boundary defaults Dhall loading to `NoImports`. Following filesystem
imports always requires an explicit `LocalImportsWithin` policy naming the allowed
directory. Kubernetes references remain trusted process-visible annotations; the loader
does not contact a cluster.


## Consequences

Multi-format applications can use one parser and one loader while preserving input order,
structured adapter failures, and consistent provenance annotations. The shared default
prevents one `dhall:` argument from silently widening the process's filesystem access.

Applications that use only one format should continue depending directly on that adapter
and avoid the umbrella's larger dependency closure. Adding a future file format requires
extending `ConfigFormat`, the dispatcher, the error sum, tests, and this package's
dependencies. That addition changes the public sum types and therefore requires a major
version bump of `settei-formats`, but it does not require changing any existing adapter.

The package-level separation prevents dependency cycles, but the umbrella package still
links all three format stacks and optparse-applicative. Module separation controls the
imported API surface, not the package build closure.


## Rejected Alternatives

Extending `settei-optparse-applicative` was rejected because it would force all YAML, KDL,
and Dhall dependencies on every CLI consumer. A separate `settei-formats-optparse`
package was rejected because one small module does not justify another cabal file, Nix
derivation, Mori entry, changelog, and coordinated release.

Putting the dispatcher in the core `settei` package was rejected because the core must
remain dependency-light and independent of concrete source formats. Keeping the parser
and dispatch in each application was rejected because the existing duplication already
demonstrates fleet-wide drift risk.
