# Settei (設定)

Typed, layered, explainable configuration for Haskell.

Settei gives command-line tools and services one inspectable declaration for typed
configuration, deterministic source precedence, derived defaults, and secret-safe answers
to “where did this value come from?”


## Release status

Settei 0.1.0.0 is implementation-complete and prepared for its initial release. The six
publishable packages have aligned version, license, changelog, dependency-bound, and
`tested-with` metadata. The MasterPlan and all eight ExecPlans are complete.

The release candidate has been validated with GHC 9.12.4 and Cabal 3.16.1.0 on
`aarch64-darwin`:

- All nine workspace packages build, including the three internal example packages.
- All 138 tests pass both in the repository and from isolated unpacked source
  distributions.
- Package checks, Haddocks, source distributions, formatting, Mori inventory, example
  Nix outputs, CLI smoke tests, and `nix flake check` pass.
- Package-family guides, security guidance, compatibility policy, release metadata, and
  the automated release checklist are complete.

The release has **not** been tagged, signed, or uploaded to Hackage. Those manual actions,
including a public-registry installation smoke test, require separate authorization and
remain tracked in the [release checklist](docs/release-checklist.md). Version 0.1.0.0 is
experimental; consult the [compatibility matrix](docs/compatibility.md) for the validated
platform, dependency bounds, and public adoption surface.


## Package map

| Package | Role |
| --- | --- |
| [`settei`](settei/) | Declaration algebra, hierarchical resolver, provenance, defaults, schemas, errors, and report rendering. |
| [`settei-env`](settei-env/) | Explicit environment-variable bindings and injectable snapshots. |
| [`settei-optparse-applicative`](settei-optparse-applicative/) | Ordered generic and named CLI overrides for optparse-applicative. |
| [`settei-yaml`](settei-yaml/) | Strict YAML input with exact node locations. |
| [`settei-kdl`](settei-kdl/) | Canonical KDL v2 input with exact node spans. |
| [`settei-dhall`](settei-dhall/) | Typed Dhall input with enforceable import policies and root/import-closure provenance. |

The non-published [`examples/`](examples/) workspace contains a layered CLI, a
Kubernetes-shaped service, and a YAML/KDL/Dhall conformance suite.


## Declare configuration once

A declaration is a `Config a`: it names settings, decodes public or secret values, and
describes defaults and conditional branches without loading a source.

```haskell
serviceConfig :: Config ServiceConfig
serviceConfig =
  ServiceConfig
    <$> required environmentSetting
    <*> ( HttpConfig
            <$> required httpHostSetting
            <*> withDefault httpPortSetting httpPortDefault
        )
    <*> databaseConfig
```

`Config` supports Functor, Applicative, and Selective composition. It deliberately has no
Monad instance, so `describe serviceConfig` can inspect every possible setting before any
file, environment variable, or command-line argument is read.


## Assemble ordered sources

Sources are passed from lowest to highest precedence. The resolver selects the rightmost
candidate and retains every shadowed origin in the report.

```haskell
environmentSource <-
  either (fail . show) pure
    (envSource "environment" environmentBindings snapshot)

let orderedSources =
      fileSources
        <> [environmentSource]
        <> cliSources "arguments" overrides

let result = resolve defaultResolveOptions orderedSources serviceConfig
-- result ^. #report and result ^. #warnings exist even when resolution fails.
config <-
  either (fail . Text.unpack . renderErrorsText) pure (result ^. #answer)
```

The reference CLI demonstrates the complete order:

```text
named built-in values
< config files in command-line order
< explicitly mapped environment variables
< command-line overrides in occurrence order
```


## Explain derived defaults

Defaults are named rules with declared configuration dependencies. The chosen rule and
dependency edges appear in the same report as file and environment origins.

```haskell
httpPortDefault :: Default Int
httpPortDefault =
  caseDefault
    (RuleName "http-port-by-environment")
    "Choose the HTTP port for the runtime environment"
    (required environmentSetting)
    ((Development, 8080) :| [(Test, 18080), (Production, 8080)])
    Nothing
```

Settings own their `Public` or `Secret` sensitivity. Secret candidates are redacted before
they are retained in structured errors or reports; text and versioned JSON renderers do
not receive a recoverable secret value.


## Guides and examples

- [Getting started](docs/guides/getting-started.md)
- [Guide index](docs/guides/README.md)
- [Environment and CLI sources](docs/guides/environment-and-cli.md)
- [YAML adapter](docs/guides/yaml.md)
- [KDL v2 adapter](docs/guides/kdl.md)
- [Dhall adapter and import policy](docs/guides/dhall.md)
- [Building a CLI application](docs/guides/cli-application.md)
- [Building a Kubernetes-shaped service](docs/guides/kubernetes-service.md)
- [Security model](docs/security.md)
- [Compatibility matrix](docs/compatibility.md)
- [Release checklist](docs/release-checklist.md)

Run the complete pinned workspace with:

```bash
nix develop -c cabal test all --test-show-details=direct
```

The supported public modules and exact tested toolchain are listed in the
[compatibility matrix](docs/compatibility.md). The documented public modules are the
intended adoption surface, but semantic stability is not promised beyond the release
notes.


## The name

**設定** is pronounced *settei* and means “settings” or “configuration” in Japanese. The
package and module family uses the romanized name so it remains conventional in Haskell
tooling and source code.


## Design record

The [MasterPlan](docs/masterplans/1-build-settei-as-a-provenance-aware-configuration-library-for-haskell.md)
and [architecture decisions](docs/adr/) record the implementation sequence, accepted
semantics, and rejected alternatives.
