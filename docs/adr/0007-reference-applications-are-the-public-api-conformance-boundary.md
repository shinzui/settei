# ADR 0007: Use internal reference applications as the public-API conformance boundary

Status: Accepted

Date: 2026-07-18


## Context

The core and five source adapters have independently tested contracts, but an initial
release also needs evidence that their public modules compose into realistic application
boundaries. Existing production consumers use different configuration approaches and
release cycles. Migrating one of them would couple Settei's first release to unrelated
operational work and would not provide a controlled cross-format comparison.

YAML, KDL, and Dhall should resolve equal application values while preserving different
truthful origin precision. A Kubernetes-shaped example should explain process-visible
mounted files and environment values without implying that Settei verifies cluster state.
The examples themselves are adoption evidence, not publishable general-purpose libraries.


## Decision

Keep three internal packages beneath `examples/`: a layered CLI, a Kubernetes-shaped
service, and a conformance test package. Register all three in Cabal, Nix, and Mori, but do
not publish them to Hackage or list their modules as stable API.

The CLI orders named built-ins below explicit files, explicitly mapped environment
variables, and command-line occurrences. Its declaration is available to tests without
spawning a process, static description loads no sources, and diagnostics use distinct
usage, source, and resolution exit codes.

The service uses nested records, named environment-dependent defaults, and a Selective
Production-only password requirement. Kubernetes ConfigMap and Secret references are
trusted origin annotations attached to ordinary mounted files and environment bindings;
the application never contacts a cluster and never renders a password-bearing record.

The conformance package loads self-contained YAML, KDL, and import-free Dhall fixtures
through public adapter modules. It compares typed values and a normalized report shape
containing keys, setting states, default dependency edges, branch decisions, source
classes, and shadow counts. It separately asserts YAML paths and lines, KDL spans, and
Dhall root/import precision instead of forcing origin payloads to be identical.


## Consequences

Every maintained package is exercised in an application composition before release, and
the examples can evolve with Settei without coordinating a production deployment. The
shared fixtures and sentinel scans form an end-to-end regression boundary for precedence,
malformed higher values, conditional requirements, and redaction.

The examples prove only the documented process boundary. They do not prove Kubernetes API
access, remote secret management, network service behavior, automatic file discovery, or
a migration path for an existing consumer. Such work requires separately authorized
plans.

Format-independent semantics are compared without discarding honest adapter limitations.
Consumers can depend on equal values and report structure, but they must handle
format-specific locations and annotations when presenting detailed origins.


## Rejected Alternatives

Migrating a production consumer first was rejected because it would expand scope and make
the library release depend on another system's deployment. Unit tests alone were rejected
because they would not exercise component graphs, executable parsers, packaged fixtures,
or application-safe output.

A live Kubernetes integration test was rejected because configuration delivery is already
visible as files and environment variables and no public cluster client is part of Settei.
Forcing byte-identical reports across YAML, KDL, and Dhall was rejected because it would
erase or fabricate provenance. Publishing the example libraries was rejected because
their APIs exist to make tests inspectable, not to create a second supported abstraction
layer.
