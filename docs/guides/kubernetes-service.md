# Building a Kubernetes-shaped service

The [`settei-example-service`](../../examples/settei-service/) package demonstrates the
configuration boundary visible to a Kubernetes process: a mounted public file, direct
environment values, and an environment value sourced from a Secret. It does not use a
Kubernetes SDK or contact a cluster.


## Typed service configuration

The service resolves nested `ServiceConfig`, `HttpConfig`, and `DatabaseConfig` records.
Record fields are strict, reusable labels such as `#http . #port` are used for access, and
secret-bearing records deliberately have no `Show` instance.

| Key | Development | Test | Production |
| --- | ---: | ---: | ---: |
| `http.port` | `8080` | `18080` | `8080` |
| `database.poolSize` | `2` | `1` | `20` |
| `database.port` | `5432` | `5432` | `5432` |
| `database.password` | Not selected | Not selected | Required |

The port and pool values are named `caseDefault` rules that depend on
`runtime.environment`. A Selective branch evaluates `database.password` only for
Production, so static inspection still lists the secret while a Development report marks
it `NotSelected`.


## Delivery paths and provenance

The reviewed manifests live in
[`examples/settei-service/kubernetes/`](../../examples/settei-service/kubernetes/).

| Kubernetes delivery | Process-visible input | Trusted Settei annotation |
| --- | --- | --- |
| ConfigMap `settei-example-service`, key `application.yaml` | Mounted file passed as `yaml:/etc/settei/application.yaml` | Object kind, name, and key are attached to file candidates. |
| Deployment field `HASKELL_ENV` | Explicit environment binding | Environment variable name is retained. |
| Secret `settei-example-service-database`, key `password` | `DATABASE_PASSWORD` via `secretKeyRef` | Secret object name and key are attached; the value remains redacted. |

These annotations assert how the operator delivered a value. Settei does not verify that
the object exists, that the mount is fresh, or that the process is authorized to read it.


## Running locally

Development needs only the public mounted-file fixture and an injected environment name:

```bash
HASKELL_ENV=development nix develop -c cabal run settei-example-service -- \
  --config yaml:examples/settei-service/test/fixtures/application.yaml \
  --check-config
```

Use `--explain-config` or `--explain-config-json` for a redacted report. Normal mode emits
only a deterministic startup summary containing the environment, HTTP address, database
address, and pool size; it never renders the password-bearing record.

Production behavior is exercised with an injected snapshot in the test suite so a secret
does not need to appear in shell history:

```bash
nix develop -c cabal test settei-example-service-tests --test-show-details=direct
```


## File and Dhall policy

The service accepts one explicitly tagged YAML, KDL, or Dhall file followed by environment
bindings. YAML and KDL mounted-file helpers attach the ConfigMap reference. Dhall also
attaches the reference but defaults to `NoImports`; an annotated root plus import closure
would still not provide leaf-level import attribution after normalization.


## Operational checklist

- Mount public configuration read-only.
- Source credentials through `secretKeyRef`; never commit a rendered Secret manifest.
- Keep the placeholder [`secret.yaml.example`](../../examples/settei-service/kubernetes/secret.yaml.example)
  free of a usable or stable credential.
- Treat environment variables and mounted Secret files as process-readable plaintext.
- Prefer `--check-config` in validation jobs and redacted explanations in diagnostics.
- Test Development and Production separately because they select different declaration
  branches.
- Do not log typed values or adapter parse excerpts that have not passed through Settei's
  sensitivity boundary.
