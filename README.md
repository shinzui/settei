# Settei (設定)

Typed, layered, explainable configuration for Haskell.

Settei is intended to give command-line tools, applications, and services one shared way
to declare configuration, load it from multiple sources, and explain how every resolved
value was constructed.


## The name

**設定** is pronounced *settei* and means “settings” or “configuration” in Japanese. The
word can also describe the act of establishing or setting something up: **設** carries the
sense of establishing or arranging, while **定** carries the sense of deciding or fixing.

The name was chosen because it describes the library's subject directly. It is written in
kanji rather than as a katakana rendering of an English technical term. The package and
module family uses the romanized name `settei` so it remains conventional to use in
Haskell tooling and source code.


## Goals

Settei is being designed around these requirements:

- Typed configuration declarations shared by CLIs, applications, and microservices.
- Hierarchical keys and deterministic, ordered configuration layers.
- Sources for environment variables, command-line options, YAML, KDL, and Dhall.
- Provenance showing the selected source, shadowed candidates, and derivation path for
  every value.
- Named defaults derived from other declared settings, such as different defaults for
  Development, Test, and Production.
- Static inspection of possible and conditional settings without loading configuration.
- Secret-safe errors and explanations that redact sensitive values.
- Kubernetes-friendly loading through environment variables and mounted files, without
  requiring access to the Kubernetes API.


## Packages

- [`settei`](settei/) provides the declaration algebra, hierarchical resolver, provenance
  model, derived defaults, and report rendering.
- [`settei-env`](settei-env/) translates explicitly mapped environment variables into
  Settei sources.
- [`settei-optparse-applicative`](settei-optparse-applicative/) provides reusable
  command-line configuration options.
- [`settei-yaml`](settei-yaml/) translates a strict, location-preserving YAML subset into
  Settei sources.
- [`settei-kdl`](settei-kdl/) translates a canonical, span-preserving KDL v2 subset into
  Settei sources.
- [`settei-dhall`](settei-dhall/) evaluates typed Dhall records under explicit no-import or
  canonical-root local-import policies and retains honest root/import-closure provenance.

The public configuration language is planned to support Functor, Applicative, and
Selective composition without exposing a Monad instance. Selective branches allow Settei
to express conditions such as “the database password is required only in Production” while
retaining a static over-approximation of every setting the application may use. Named
rules with declared dependencies provide explainable derived defaults; Selective itself is
not treated as a provenance system.


## Project status

The core package under [`settei/`](settei/) now provides validated hierarchical keys,
parser-neutral raw values, secret-safe decoders, typed setting declarations, selective
composition,
source-free schema inspection, deterministic precedence, provenance reports, named
defaults, and text and JSON explanations. `settei-env`,
`settei-optparse-applicative`, `settei-yaml`, `settei-kdl`, and `settei-dhall` provide the first source
adapters; see the
[environment and command-line guide](docs/guides/environment-and-cli.md) for a migration
and precedence example, the [YAML guide](docs/guides/yaml.md) for strict YAML input, and
the [KDL guide](docs/guides/kdl.md) for the canonical KDL v2 mapping, and the
[Dhall guide](docs/guides/dhall.md) for typed input and import policy. The
architecture and implementation sequence are documented in the
[Settei MasterPlan](docs/masterplans/1-build-settei-as-a-provenance-aware-configuration-library-for-haskell.md).
The child ExecPlans in [`docs/plans/`](docs/plans/) define independently verifiable work for
the core, source adapters, and reference CLI and Kubernetes service applications.
