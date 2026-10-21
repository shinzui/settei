---
type: Guide
title: Authoring a first deployment from the configuration contract
description: Discover environment bindings and safe defaults before assembling proposed inputs and running application configuration checks.
docId: DOC-11
tags: [settei, deployment, configuration]
generated:
  by: process:codex
  at: 2026-10-21T16:45:00Z
---

# Authoring a first deployment from the configuration contract

Export the application's deployment contract before writing its first deployment. A
contract joins its existing declaration, external input bindings, explicitly supplied
default sources, and optional deployment profile. You can discover inputs without
credentials, configuration files, a database, or a successful resolution.

The runnable [deployment example](../../examples/settei-deployment/README.md) resembles
`mori://tan/notification-hub`: required declarations backed by a built-in defaults source,
`ENVIRONMENT` and `DATABASE_URL` bindings, a development webhook secret, and distinct
server and worker checks. It is an internal example; adopting services own their profiles
and validation policies.

## Export before supplying credentials

From the repository root:

```bash
nix develop -c cabal run settei-example-deployment-server -- --deployment-contract
nix develop -c cabal run settei-example-deployment-worker -- --deployment-contract-json
```

Both commands exit 0 with no environment variables set. They also work with
`--config /definitely/missing.yaml`: static diagnostics precede source loading. JSON
starts with `{"schemaVersion":1,"type":"settei.contract",` before the remaining
fields. Settings are in key order; conditions follow declaration
order. Cabal may print build messages before the executable output; use the built
executable directly when capturing a JSON document for a tool.

Read the production contract as follows:

| Key | External input | Binding and default |
| --- | --- | --- |
| `database.url` | Required | `DATABASE_URL`; secret, no default. |
| `email.credentials` | Conditional | `EMAIL_CREDENTIALS_JSON`; secret, required when production is selected. |
| `runtime.environment` | Required by production profile | `ENVIRONMENT`; built-in public default `development` remains visible. |
| `server.webhookSecret` | Required by production profile | `WEBHOOK_SECRET`; a source default exists, with value redacted. |
| `workers.deliveryEndpoint` | Required by production profile | `DELIVERY_ENDPOINT`; public source default `http://127.0.0.1:18091`. |
| `database.poolSize`, `server.host`, `server.port` | Defaulted by source | `DATABASE_POOL_SIZE=10`, `HTTP_HOST=127.0.0.1`, `PORT=8080`. |
| `workers.concurrency` | Declaration fallback | `WORKER_CONCURRENCY`; case on `runtime.environment`, three alternatives, no fallback. |
| `workers.visibilityTimeoutSeconds` | Declaration fallback | `WORKER_VISIBILITY_TIMEOUT_SECONDS`; constant `180`. |
| `telemetry.serviceName` | Declaration fallback | `OTEL_SERVICE_NAME`; derived from `runtime.environment`, value not computed during export. |

A profile is explicit application data: the production profile demands a deliberate
environment, non-development webhook secret, and non-loopback delivery endpoint despite
available defaults. Exporting that profile does not select the runtime environment or
enforce the profile during resolution. The operator must supply those inputs and run the
application's checks.

## Propose inputs, then run both application checks

An incomplete proposal fails with exit 4 for either role. Start from a shell where
`DATABASE_URL` and `EMAIL_CREDENTIALS_JSON` are unset:

```bash
env -u DATABASE_URL -u EMAIL_CREDENTIALS_JSON ENVIRONMENT=production \
  nix develop -c cabal run settei-example-deployment-server -- --check-config
```

```text
database.url: required value is missing
email.credentials: required value is missing
```

The [packaged production proposal](../../examples/settei-deployment/test/fixtures/proposed-production.yaml)
contains dummy credentials and an explicit endpoint. Its shape is:

```yaml
runtime:
  environment: production
database:
  url: postgres://example.invalid/notification
email:
  credentials: '{"account":"dummy"}'
server:
  webhookSecret: explicit-production-test-secret
workers:
  deliveryEndpoint: https://delivery.example.invalid
```

Check the proposal with both roles (in a shell without overriding example environment
variables):

```bash
nix develop -c cabal run settei-example-deployment-server -- --config examples/settei-deployment/test/fixtures/proposed-production.yaml --check-config
nix develop -c cabal run settei-example-deployment-worker -- --config examples/settei-deployment/test/fixtures/proposed-production.yaml --check-config
```

Each prints `configuration valid` and exits 0. Source precedence is built-ins < YAML
files in argument order < environment < `--set` overrides in argument order. Use dummy
values only for this example; real deployment credentials remain an operator concern.

The server and worker perform different checks. Starting from the complete proposal:

```bash
nix develop -c cabal run settei-example-deployment-server -- --config examples/settei-deployment/test/fixtures/proposed-production.yaml --set server.webhookSecret=short --check-config
nix develop -c cabal run settei-example-deployment-worker -- --config examples/settei-deployment/test/fixtures/proposed-production.yaml --set workers.visibilityTimeoutSeconds=1 --check-config
```

Both exit 4, respectively:

```text
server.webhookSecret: must be at least 16 characters
workers.visibilityTimeoutSeconds: must be at least twice workers.concurrency
```

Neither message echoes the rejected value. The worker also rejects the development
webhook secret in production. These failures are application checks after successful
resolution; merely exporting a static contract cannot discover them.

## Wire the public API into your application

Keep the declaration and bindings as the application's single definitions. Explicitly
select which sources represent defaults; their name or `SourceKind` does not confer that
status. The library never opens runtime paths or reads process environment values:

```haskell
contractInputs :: ContractInputs
contractInputs = ContractInputs
  { inputs = inputBindings environmentBindings,
    defaultSources = [builtInDefaultsSource],
    profile = Just productionProfile
  }

contract :: Either (NonEmpty ConfigError) DeploymentContract
contract = deploymentContract contractInputs appConfig
```

Import `Settei`, `Settei.Env`, and `Settei.Optparse`. `setteiOptions` provides the two
mutually exclusive flags; custom parsers can use `diagnosticModeOptions`. Dispatch
`schemaDiagnostic` first, then `contractDiagnostic mode contract`, before running any
environment-reader action or loading files. `contractDiagnostic` returns `Nothing` for
other modes without inspecting the contract, `Just (Left errors)` for a cycle, or
`Just (Right output)` for the requested text/JSON. Send cycle errors through
`renderErrorsText`. See the reference application's
[runner](../../examples/settei-deployment/src/Settei/Example/Deployment.hs) for executable
wiring and exit codes (usage 2, source 3, resolution or application check 4).

## Interpret uncertainty and diagnostics

Schema `requirement` and `presence` are merged independently across requests for the
same key. They describe the declaration; they do not determine whether external input
is required. The contract tracks each individual request before merging. An
unconditional optional request plus a conditional required request can therefore have
schema `required/necessary` and external-input verdict `conditional`. A source value
rejected only by a conditional decoder likewise remains conditional. A necessary decoder
rejection makes input required, and an invalid winning candidate never falls back to a
lower source or declaration default.

`declaredDefaults` distinguishes visible constants, redacted constants, and public
constants without renderers (`unrenderable`). Derived and case defaults show dependency
keys, with alternative count and fallback presence for cases. Their values are never
computed during export. Declaration coverage means a fallback is declared: dependencies
may be missing, a case may not cover the eventual input, or a computation may fail.
Inspect the dependencies, presence, conditions, and diagnostics and validate proposed
inputs at runtime.

`sourceDefault` retains winning and shadowed origins and decoder validity. A profile
requirement takes precedence over default coverage. The export also diagnoses undeclared
binding/profile keys, undeclared default leaves, source structural conflicts, and mixed
sensitivities. Mixed-sensitivity keys become secret before default values are retained.
Default cycles are fatal and return the existing `ConfigError`; other inconsistencies
remain useful structured diagnostics inside the contract. Treat them as issues to resolve
before deployment.

The contract does not validate provider credentials, connectivity, Kubernetes resources,
arbitrary cross-setting invariants, or deployment wiring. The example's JSON credential
field is opaque text; passing its check does not validate a real provider account. Pair
static discovery with application check mode and operational validation.

## Compatibility and security

The existing `settei.schema` and `settei.resolution` documents are unchanged. Consumers
of `--describe-config-json` keep working. `settei.contract` is a separate version 1
JSON document that reuses schema field names and resolution origin encoding.
`DiagnosticMode` gains constructors, so exhaustive matches need updating in the next
major PVP release. This feature is unreleased and targets the shared 0.3.0.0 version.

Secret defaults expose availability and origin metadata, with their values absent or
redacted before storage in the contract. Keys, variable names, caller-supplied
annotations, public defaults, and dependency topology are operational metadata; keep
secrets out of descriptions, rule explanations, profile reasons, and annotations. See
the [security model](../security.md).


## Structured check failures

The example now declares server and worker `Validators` and consumes
`validatedDiagnostic`. Acceptance, successful typed values, and exit code 4 are preserved.
A timeout of 1 in production rejects startup and check mode before resources open;
text explanation includes the winning environment origin and both worker rule outcomes.
JSON explanation emits two stderr lines. Its first document is:

```json
{"schemaVersion":1,"type":"settei.errors","errors":[{"kind":"invariant","rule":"worker-visibility-covers-concurrency","keys":["workers.visibilityTimeoutSeconds","workers.concurrency"],"expectation":"workers.visibilityTimeoutSeconds must be at least twice workers.concurrency","detail":null}]}
```

The second is version-1 `settei.resolution`, including the environment origin and
`invariants` statuses. Missing or malformed base settings also use two JSON documents,
with rules `not-run`. Source-load errors remain adapter text and exit 3. See the
[validation guide](cli-application.md#validate-cross-setting-invariants-after-resolution)
for the declaration and author contract. Validators never verify live connectivity or
credentials.
