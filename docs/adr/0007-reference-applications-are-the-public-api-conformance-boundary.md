# ADR 0007: Use internal reference applications as the public-API conformance boundary

Status: Accepted

Date: 2026-07-18

Amended: 2026-07-19


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


## Amendment 2026-07-19: hardening behaviors belong at the conformance boundary

Release-critical behavior regressions that do not belong in the reference applications'
domain models use standalone fixtures in the conformance package and exercise public
adapter, source, and resolver functions directly. This keeps the CLI and service examples
realistic while still proving that the package family composes at its supported boundary.

The conformance suite now locks YAML 1.2 boolean interpretation, the YAML and KDL numeric
exponent bounds with their format-specific stable error categories, and normalized-equal
failure reports across YAML, KDL, and Dhall. Failure reports must retain honest consulted
origins, and the end-to-end sentinel scan covers text and JSON reports plus errors on the
failure path. Cross-format comparison still normalizes only shared semantics; it does not
invent a common adapter error type or erase format-specific provenance.

(`docs/plans/14-revalidate-correctness-and-update-release-collateral.md`)


## Amendment 2026-07-19: shared diagnostics and advisory warning behavior

The reference CLI and service use `Settei.Optparse.DiagnosticMode` rather than
application-local diagnostic parsers. `--describe-config` and
`--describe-config-json` are source-free schema operations: they must complete without
opening configuration files or reading environment variables. `--check-config` resolves
normally, prints `configuration valid` on success, and otherwise preserves the existing
usage (2), source (3), and resolution (4) exit-code discipline. Text and JSON explain
modes render the resolution report only after resolution.

On a successful resolution, applications render non-empty resolver warnings to stderr
and still exit 0. Warnings are advisory; applications that require unknown keys to fail
must select the resolver's `RejectUnknownKeys` policy, which turns them into structured
resolution errors. Reference applications do not add a second CLI-level strictness flag
or combine advisory warning output with an already failing diagnostic.
