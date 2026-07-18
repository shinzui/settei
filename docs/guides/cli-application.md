# Building a CLI application

The [`settei-example-cli`](../../examples/settei-cli/) package is an executable reference
for applications that combine built-in values, explicit files, environment variables,
and command-line overrides. Its declaration lives in a library module so tests and other
tools can inspect the schema without spawning a process.


## Declaration and layers

The example declares these keys:

| Key | Requirement |
| --- | --- |
| `runtime.environment` | Required enum: `development`, `test`, or `production`. |
| `service.endpoint` | Required text. |
| `service.timeout` | Required integral seconds. |
| `output.format` | Required enum: `text` or `json`. |
| `credentials.token` | Optional secret text. |

The executable constructs sources in this low-to-high order:

```text
CLI built-in values
< each --config file in occurrence order
< explicitly bound environment variables
< each --set override in occurrence order
```

Later candidates do not destroy earlier provenance. The selected node records every
shadowed origin, which makes a repeated override such as `9000` followed by `9001`
explainable rather than merely last-write-wins.


## File input

Pass each file as `--config FORMAT:PATH`, where `FORMAT` is `yaml`, `kdl`, or `dhall`.
The tag is required; the example never guesses from content or an ambiguous extension.

```bash
nix develop -c cabal run settei-example-cli -- \
  --config yaml:examples/settei-conformance/test/fixtures/service.yaml \
  --check-config
```

YAML and KDL use the strict mappings documented in their adapter guides. Dhall is loaded
with `NoImports`, so the CLI cannot read another file, the process environment, or the
network through a Dhall expression. An application that needs a local import graph should
offer a separate explicit root and use `LocalImportsWithin`; it should not silently widen
the default policy.


## Environment and command-line input

Environment variables are opt-in bindings, not a prefix scan:

| Variable | Key |
| --- | --- |
| `HASKELL_ENV` | `runtime.environment` |
| `SERVICE_ENDPOINT` | `service.endpoint` |
| `SERVICE_TIMEOUT` | `service.timeout` |
| `OUTPUT_FORMAT` | `output.format` |
| `SERVICE_TOKEN` | `credentials.token` |

`SERVICE_TOKEN` is annotated as Secret `settei-example-cli`, key `token`, for
Kubernetes-shaped deployments. The annotation is trusted metadata; it does not fetch or
authenticate a Kubernetes object.

Generic `--set KEY=VALUE` options preserve command-line occurrence order. Applications
can also construct named overrides with `namedOption` when a stable user-facing flag is
better than a generic key.


## Diagnostics and exit codes

| Option | Behavior |
| --- | --- |
| `--describe-config` | Render the static schema without loading files or environment values. |
| `--check-config` | Load and validate configuration without running the example action. |
| `--explain-config` | Render the selected, shadowed, derived, and skipped nodes as text. |
| `--explain-config-json` | Render the versioned JSON report. |

Usage errors exit with `2`, file IO or parse errors with `3`, and resolution/decode errors
with `4`. Successful diagnostics and the example action exit with `0`. Explanation modes
do not print the typed result afterward, which avoids bypassing report redaction.

The options are grouped by user intent under “Configuration” and “Diagnostics” while
optparse-applicative retains its ordinary help section.


## Adoption checklist

- Keep the `Config` declaration in a library module.
- Make all source ordering visible in one application assembly function.
- Inject `EnvSnapshot` in tests instead of consulting the developer's environment.
- Require explicit file formats and an explicit Dhall import policy.
- Assign sensitivity in each `Setting`; do not try to redact after rendering a record.
- Test usage, source, and resolution failures separately.
- Capture stdout and stderr with secret sentinels and assert that neither contains them.

See [`Settei.Example.Cli`](../../examples/settei-cli/src/Settei/Example/Cli.hs) and its
[end-to-end tests](../../examples/settei-cli/test/Settei/Example/CliTest.hs) for the full
public-API composition.
