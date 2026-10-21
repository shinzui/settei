# Settei (設定)

Typed, layered, explainable configuration for Haskell.

Settei gives command-line tools and services one inspectable declaration for typed
configuration, deterministic source precedence, derived defaults, and secret-safe answers
to “where did this value come from?”


## Release status

The current shared release is **0.3.0.0**, following 0.2.0.0. It contains nine
publishable packages, all at 0.3.0.0 with exact intra-family pins, and four internal
example packages that are not published.

Five completed ExecPlans add the 0.3.0.0 deployment workflow and checked startup boundary:

| Feature | What it provides | Guide |
| --- | --- | --- |
| [Deployment contracts (plan 26)](docs/plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md) | Discover input bindings, safe defaults, and profile requirements without reading runtime inputs. | [Author a first deployment](docs/guides/deployment-contract.md) |
| [Supplied environment names (plan 27)](docs/plans/27-validate-supplied-environment-variable-names-against-declared-bindings.md) | Reject unsupported or duplicate supplied names against explicit bindings and external-consumer allowances. | [Check supplied names](docs/guides/environment-and-cli.md#validate-the-names-a-deployment-supplies) |
| [Deployment preflight (plan 28)](docs/plans/28-provide-a-reusable-deployment-preflight-harness-around-application-check-mode.md) | Run application check mode against proposed inputs with controlled secret channels and explicit coverage. | [Run preflight checks](docs/guides/deployment-preflight.md) |
| [Application validation (plan 29)](docs/plans/29-integrate-application-validation-into-structured-configuration-diagnostics.md) | Apply pure cross-setting rules to one resolved value for startup, check, and explanation modes. | [Declare invariants](docs/guides/cli-application.md#validate-cross-setting-invariants-after-resolution) |
| [Checked dispatch (plan 30)](docs/plans/30-require-complete-diagnostic-dispatch-before-application-startup.md) | Complete diagnostics before runtime inputs; start only on successful normal continuation. | [Migrate diagnostic dispatch](docs/guides/cli-application.md#add-diagnostics-that-match-user-intent) |

Final 0.3.0.0 release acceptance on 2026-10-21 used GHC 9.12.4 on `aarch64-darwin`:
workspace build, tests, and Haddocks, per-package `cabal check`, an isolated build and
test of the nine unpacked source distributions, the four documentation bundle
validations, executable smoke checks, and `nix flake check`. Other systems remain
unvalidated. See the [release checklist](docs/release-checklist.md) for the evidence.

Version 0.3.0.0 requires updates to exhaustive matches on `ConfigError` and
`DiagnosticMode`. Existing bare schema and resolution JSON remain unchanged; validated
explanations can include an invariant trace. The family remains experimental. See the
[compatibility and migration notes](docs/compatibility.md) for the supported modules,
JSON contracts, toolchain, and dependency bounds.

The 0.3.0.0 API requires `prepareDiagnostic` before input acquisition;
only a successful `DiagnosticContinue` permits application startup. See the
[checked dispatch migration](docs/compatibility.md#0300-checked-diagnostic-dispatch).
After updating dependencies together and resolving the build plan, upgrade source with:

```bash
seihou install https://github.com/shinzui/settei.git --module settei-upgrade
seihou agent migrate settei-upgrade
```

On a first migration, add `--from 0.2.0.0` if no receipt records the earlier version.
The [blueprint](blueprints/settei-upgrade/README.md) ships the complete 0.3.0.0 edge.

## Package map

| Package | Role |
| --- | --- |
| [`settei`](settei/) | Declaration algebra, hierarchical resolver, provenance, defaults, schemas, application invariants, errors, and report rendering. |
| [`settei-preflight`](settei-preflight/) | Isolated application checks on proposed inputs, strict request documents, redaction, and honest gate verdicts (new in 0.3.0.0). |
| [`settei-env`](settei-env/) | Explicit environment-variable bindings, injectable snapshots, and opt-in supplied-name validation. |
| [`settei-optparse-applicative`](settei-optparse-applicative/) | Ordered generic and named CLI overrides for optparse-applicative. |
| [`settei-formats`](settei-formats/) | Tagged `FORMAT:PATH` inputs and shared YAML, KDL, and Dhall loading. |
| [`settei-yaml`](settei-yaml/) | Strict YAML input with exact node locations. |
| [`settei-kdl`](settei-kdl/) | Canonical KDL v2 input with exact node spans. |
| [`settei-dhall`](settei-dhall/) | Typed Dhall input with enforceable import policies and root/import-closure provenance. |
| [`settei-kubernetes`](settei-kubernetes/) | Mounted ConfigMap/Secret directory source with explicit file bindings, derived env bindings, and freshness provenance. |

The non-published [`examples/`](examples/) workspace contains a layered CLI, a
Kubernetes-shaped service, a [deployment server/worker workflow](examples/settei-deployment/),
and a YAML/KDL/Dhall conformance suite.


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
candidate and retains every shadowed origin in the report. The record pattern below
uses `DisambiguateRecordFields`.

```haskell
let environmentSource = Settei.Env.environmentSource environmentBindings snapshot
    orderedSources =
      fileSources
        <> [environmentSource]
        <> cliSources "arguments" overrides

let result@ResolveResult {answer = configAnswer} =
      resolve defaultResolveOptions orderedSources serviceConfig
-- The report and warnings in result exist even when resolution fails.
config <-
  either (fail . Text.unpack . renderErrorsText) pure configAnswer
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
- [Validate supplied environment names](docs/guides/environment-and-cli.md#validate-the-names-a-deployment-supplies)
- [Tagged multi-format sources](docs/guides/formats.md)
- [YAML adapter](docs/guides/yaml.md)
- [KDL v2 adapter](docs/guides/kdl.md)
- [Dhall adapter and import policy](docs/guides/dhall.md)
- [Authoring a first deployment](docs/guides/deployment-contract.md)
- [Preflight-checking deployment inputs](docs/guides/deployment-preflight.md)
- [Building a CLI application](docs/guides/cli-application.md)
- [Validate cross-setting invariants](docs/guides/cli-application.md#validate-cross-setting-invariants-after-resolution)
- [Building a Kubernetes-shaped service](docs/guides/kubernetes-service.md)
- [Deploying one image across Kubernetes namespaces](docs/guides/kubernetes-cookbook.md)
- [Capability catalog](docs/capabilities/index.md)
- [Improvement requests](docs/improvement-requests/index.md)
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
