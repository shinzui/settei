# Deploying one image across Kubernetes namespaces

This cookbook is the deployment half of the
[Kubernetes service guide](kubernetes-service.md). It shows how to promote one image
unchanged through `dev`, `test`, and `production`, while each namespace supplies its own
configuration. The checked-in companion manifests live under
[`examples/settei-service/deploy/`](../../examples/settei-service/deploy/).

The examples stay at the process boundary: Kubernetes delivers files and environment
variables, and Settei reads those ordinary inputs. Neither the application nor the
client-side manifest checks contact the Kubernetes API. Commands that do contact a
cluster are explicitly marked as manual operations.


## 1. One image, many namespaces

Build the service image once and promote the same digest through every namespace. Each
namespace contains objects with the same names:

- ConfigMap `settei-example-service` holds `HASKELL_ENV` and `application.yaml`.
- Secret `settei-example-service-database` holds the `password` key.
- Deployment `settei-example-service` refers only to those stable names.

The base Deployment contains no namespace or runtime-environment value. The overlays
stamp the namespace and supply data. In the checked-in example, the same image reference
therefore sees `development` and `postgres.dev.internal` in `dev`, `test` and
`postgres.test.internal` in `test`, then `production` and
`postgres.production.internal` in `production`. A real secret-management pipeline
supplies a different credential in each namespace.

That makes promotion easy to audit: the diff between two overlay directories is the
complete configuration difference. There is no Kubernetes-specific selection mechanism
inside Settei, and none is needed.


## 2. Record the namespace identity

The downward API is Kubernetes' mechanism for telling a pod about itself. A `fieldRef`
in the pod specification turns the pod's namespace into an ordinary environment
variable. The
[base Deployment](../../examples/settei-service/deploy/base/deployment.yaml) injects it
into both the init container and the service container:

```yaml
env:
  - name: POD_NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
```

Declare the namespace as an ordinary public setting and bind the variable explicitly in
application code, as you would any other environment variable:

```haskell
namespaceKey :: Key
namespaceKey = either (error . show) id (parseKey "kubernetes.namespace")

namespaceSetting :: Setting Text
namespaceSetting = publicSetting namespaceKey "Kubernetes namespace" textDecoder

namespaceBinding :: EnvBinding
namespaceBinding = binding (EnvName "POD_NAMESPACE") namespaceKey
```

The reference service includes `optional namespaceSetting` in its `Config` declaration
because the same binary also runs locally outside Kubernetes. A service that runs only
in Kubernetes can make it `required`. In either form, the namespace value records where
the running instance lives without selecting application behavior. `--explain-config`
includes it among the ordinary resolved settings, which answers the first question
during an incident without coupling the declaration to cluster naming.


## 3. Choose the environment explicitly

Every overlay's ConfigMap contains one of the spellings accepted by the service's
`RuntimeEnvironment` decoder:

```yaml
data:
  HASKELL_ENV: production
```

The base Deployment reads that key through `configMapKeyRef`:

```yaml
- name: HASKELL_ENV
  valueFrom:
    configMapKeyRef:
      name: settei-example-service
      key: HASKELL_ENV
```

The environment binding maps `HASKELL_ENV` to `runtime.environment`. Named defaults then
choose the HTTP port and database pool size, and the declaration requires a database
password only in Production.

Keep this switch explicit. Namespace names describe cluster topology; they are often
team-prefixed, generated for pull requests, or renamed during a migration. An explicit
ConfigMap value survives those changes and remains visible in an overlay review. The
deliberate `dev` namespace versus `development` value in this repository demonstrates
that the two concepts are independent.

Deriving behavior from a namespace name is reasonable only when one authority governs
every namespace spelling. In that case, replace the ordinary runtime-environment setting
and binding with a decoder for the governed names:

```haskell
runtimeEnvironmentFromNamespace :: Setting RuntimeEnvironment
runtimeEnvironmentFromNamespace =
  publicSettingWithRenderer
    runtimeEnvironmentKey
    "Runtime environment selected by a governed namespace name"
    ( enumDecoder
        [ ("payments-dev", Development),
          ("payments-test", Test),
          ("payments-production", Production)
        ]
    )
    renderEnvironment

namespaceSelectsEnvironment :: EnvBinding
namespaceSelectsEnvironment =
  binding (EnvName "POD_NAMESPACE") runtimeEnvironmentKey
```

Every new spelling then becomes a code change, and generated preview namespaces fail
unless the decoder handles their convention. The explicit ConfigMap switch is the safer
fleet default.


## 4. Deliver per-namespace values

Use a mounted ConfigMap file for structured public configuration. The base projects
`application.yaml` into `/etc/settei`, and the reference service loads it with:

```console
settei-example-service --config yaml:/etc/settei/application.yaml
```

Its YAML loader is annotated with `fromKubernetesMountedFile`, so explanations name
ConfigMap `settei-example-service`, key `application.yaml`, without querying a cluster.

Use an environment variable for a single Secret key when that matches the platform's
delivery model. The shipped `Settei.Kubernetes.Bindings` module constructs the binding
and its Kubernetes provenance from the same row. Import
`Settei.Kubernetes.Bindings` alongside `Settei.Env`:

```haskell
databasePasswordBindings :: Bindings
databasePasswordBindings =
  either
    (error . show)
    id
    ( bindingsFromSecret
        Nothing
        "settei-example-service-database"
        [ objectKeyBinding
            "password"
            (EnvName "DATABASE_PASSWORD")
            databasePasswordKey
        ]
    )
```

Combine it with ordinary validated collections through
`mergeBindings [ordinaryBindings, databasePasswordBindings]`; cross-collection duplicate
variables and overlapping target keys remain construction errors.

The report can safely name the Secret and object key, while a `secretSetting` value is
always rendered as `<redacted>`. The checked-in Secret manifests contain only a loud
replacement marker. Never deploy that marker as a credential and never commit a real,
encoded, or realistic credential.

### Secrets as mounted files

Kubernetes can also project a Secret as a directory with one visible file per data key.
The `Settei.Kubernetes` module understands the atomic-writer symlink layout and requires
an explicit file-to-Settei-key mapping:

```haskell
passwordFiles <-
  either (fail . show) pure $
    fileBindings [fileBinding "password" databasePasswordKey]

let secretRef =
      kubernetesRef
        SecretObject
        Nothing
        "settei-example-service-database"
        Nothing
    options = mountedDirectoryOptions "database-secret" secretRef

loaded <-
  readMountedDirectorySource options passwordFiles "/etc/settei/secrets"

secretSource <-
  either (fail . show) pure loaded
```

Production code should render the `Left` value with `renderKubernetesErrorsText` before
exiting. Add the successful `Source` to the normal low-to-high precedence list. Its
origins record the mounted path, per-file location and modification time, and the source
read time. Those annotations are descriptive; source list position still controls
precedence.

The checked-in Deployment passes `--secrets-dir /etc/settei/secrets`, mounts the same
Secret there, and also retains `DATABASE_PASSWORD` through `secretKeyRef`. The reference
service orders the inputs as configuration file < mounted Secret directory < environment,
so the environment value wins while the explanation retains the mounted file as a
shadowed origin. This deliberately demonstrates both common delivery modes and their
precedence rather than prescribing that production applications must enable both.


## 5. Walk through the manifests

The checked-in tree is the source of truth:

- [`deploy/base/deployment.yaml`](../../examples/settei-service/deploy/base/deployment.yaml)
  owns the namespace-agnostic pod template, input wiring, and startup gate.
- [`deploy/base/kustomization.yaml`](../../examples/settei-service/deploy/base/kustomization.yaml)
  lists the common Deployment.
- The [`dev`](../../examples/settei-service/deploy/overlays/dev/kustomization.yaml),
  [`test`](../../examples/settei-service/deploy/overlays/test/kustomization.yaml), and
  [`production`](../../examples/settei-service/deploy/overlays/production/kustomization.yaml)
  overlays stamp a namespace and add that namespace's ConfigMap and placeholder Secret.
- [`deploy/validate.sh`](../../examples/settei-service/deploy/validate.sh) renders all
  three and checks the topology and values without a cluster.

An overlay is deliberately small:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: production
resources:
  - ../../base
  - configmap.yaml
  - secret.yaml
```

Render one overlay locally:

```bash
nix develop -c kubectl kustomize \
  examples/settei-service/deploy/overlays/production
```

Run every checked-in invariant:

```bash
nix develop -c bash examples/settei-service/deploy/validate.sh
```

The default gate is offline. Add the networked kubeconform schema check with:

```bash
SETTEI_VALIDATE_SCHEMAS=1 \
  nix develop -c bash examples/settei-service/deploy/validate.sh
```

[Kubeconform downloads its default schemas](https://github.com/yannh/kubeconform#overriding-schemas-location),
so the script keeps that step opt-in.

Applying an overlay is a manual cluster operation, not a repository test. Before doing
so, replace the reserved-invalid image and arrange for your secret pipeline to replace
the placeholder object. Then create the namespace and apply:

```bash
kubectl create namespace dev
kubectl apply -k examples/settei-service/deploy/overlays/dev
```


## 6. Gate rollouts with `--check-config`

An init container must finish successfully before Kubernetes starts the main container.
The base runs the same image with the same environment and mounts in check mode:

```yaml
initContainers:
  - name: check-config
    image: example.invalid/settei-example-service:replace-me
    args:
      - --config
      - yaml:/etc/settei/application.yaml
      - --secrets-dir
      - /etc/settei/secrets
      - --check-config
```

Keep the init container's `env` and `volumeMounts` identical to the service container's.
A gate that checks different inputs is a false gate.

The reference CLI reserves four exit codes:

- `0`: configuration is valid.
- `2`: command-line usage is invalid.
- `3`: a configured file could not be read or parsed.
- `4`: typed resolution failed, for example because a required public setting is absent
  from an otherwise readable file.

The checked-in `secretKeyRef` is non-optional. If its Secret or `password` key is absent,
[Kubernetes prevents the pod's containers from starting](https://kubernetes.io/docs/concepts/configuration/secret/#optional-secrets)
and records an event; the checker does not get far enough to emit exit `4`. This is a
platform-level gate alongside the application-level gate. Use `kubectl describe pod` for
the former and container logs for the latter.

A failed init container prevents the new pod from becoming Ready. Under a normal rolling
Deployment, the rollout cannot complete and existing available replicas are retained
according to the Deployment strategy. A readiness probe has a different job: it gates
traffic to a process that has started. Real services normally use both. The reference
binary prints a startup summary and exits, so its manifest contains only a commented
readiness-probe template.

The same binary can check rendered values during review. This command uses the dev
overlay's public data and was run against the built reference executable:

```bash
printf '%s\n' \
  'http:' \
  '  host: 0.0.0.0' \
  'database:' \
  '  host: postgres.dev.internal' \
  '  port: 5432' |
  env HASKELL_ENV=development \
    nix develop -c cabal run settei-example-service -- \
      --config yaml:/dev/stdin --check-config
```

```text
configuration valid
```

Run `deploy/validate.sh` first so the values mirrored into such a binary check cannot
drift from the overlay. For Production, the validation job must receive a short-lived
credential from the same secret pipeline used by deployment; do not put it in a command
line, repository file, or CI log.


## 7. Use the incident runbook

Start with rollout and init-container state:

```bash
kubectl -n production rollout status deployment/settei-example-service
kubectl -n production get pods -l app=settei-example-service
kubectl -n production describe pod POD_NAME
kubectl -n production logs POD_NAME -c check-config --previous
```

For a real long-running service, run the explanation mode as a second process inside a
pod. The reference binary exits after its startup summary, so reproduce its explanation
with the same image and inputs rather than expecting it to remain available for `exec`:

```bash
kubectl -n production exec POD_NAME -c service -- \
  settei-example-service \
    --config yaml:/etc/settei/application.yaml \
    --secrets-dir /etc/settei/secrets \
    --explain-config
```

Use `--explain-config-json` instead when tooling needs the versioned structured report.
The following output shape was captured from the built reference binary with a temporary
mounted `password`, the production environment, and a different non-secret sentinel in
`DATABASE_PASSWORD`; neither value appears:

```text
database.host = "postgres.production.internal"
  from file source /dev/stdin (YAML) from Kubernetes ConfigMap settei-example-service key application.yaml
database.password = <redacted>
  from environment variable DATABASE_PASSWORD from Kubernetes Secret settei-example-service-database key password
  shadowed: kubernetes-mounted-directory source mounted service secrets at /etc/settei/secrets from Kubernetes Secret settei-example-service-database key password (modified 2026-07-20T03:53:35Z)
database.poolSize = 20
  from default rule database-pool-size-by-environment
  because runtime.environment = "production"
    from environment variable HASKELL_ENV
database.port = 5432
  from file source /dev/stdin (YAML) from Kubernetes ConfigMap settei-example-service key application.yaml
http.host = "0.0.0.0"
  from file source /dev/stdin (YAML) from Kubernetes ConfigMap settei-example-service key application.yaml
http.port = 8080
  from default rule http-port-by-environment
  because runtime.environment = "production"
    from environment variable HASKELL_ENV
kubernetes.namespace = "production"
  from environment variable POD_NAMESPACE
runtime.environment = "production"
  from environment variable HASKELL_ENV
branch 1 [selected]: runtime.environment -> database.password
```

The ConfigMap path is `/dev/stdin` only because the public document capture was
deliberately performed without a cluster; inside the pod it is
`/etc/settei/application.yaml`. The mounted Secret line above normalizes the temporary
test directory to the deployed `/etc/settei/secrets` path; the object, key, shadow, and
redaction behavior are otherwise identical.

When the binary is launched without a Production password—for example in a local image
check independent of the non-optional Kubernetes reference—`--check-config` exits `4`.
Re-running the same inputs with `--explain-config` emits the error followed by the
evaluated provenance report:

```text
database.password: required value is missing
database.host = "postgres.production.internal"
  from file source /dev/stdin (YAML) from Kubernetes ConfigMap settei-example-service key application.yaml
database.password = <missing>
database.poolSize = 20
  from default rule database-pool-size-by-environment
  because runtime.environment = "production"
    from environment variable HASKELL_ENV
database.port = 5432
  from file source /dev/stdin (YAML) from Kubernetes ConfigMap settei-example-service key application.yaml
http.host = "0.0.0.0"
  from file source /dev/stdin (YAML) from Kubernetes ConfigMap settei-example-service key application.yaml
http.port = 8080
  from default rule http-port-by-environment
  because runtime.environment = "production"
    from environment variable HASKELL_ENV
runtime.environment = "production"
  from environment variable HASKELL_ENV
branch 1 [selected]: runtime.environment -> database.password
```

Read the report as a causal chain: each winning source is named, named default rules show
their dependency, unselected branches are explicit, and secret values never enter the
rendered structure.


## 8. Rotate by restarting

[Mounted ConfigMap and Secret volumes are eventually updated](https://kubernetes.io/docs/tutorials/configuration/updating-configuration-via-a-configmap/)
after kubelet observes an object change. Settei resolves configuration once during
startup, so a running process does not adopt the new typed values merely because the
files changed. Environment variables are stricter: Kubernetes does not update
`HASKELL_ENV` or `DATABASE_PASSWORD` inside an existing process at all.

Use restart-to-reload for both delivery paths:

```bash
kubectl -n production rollout restart deployment/settei-example-service
kubectl -n production rollout status deployment/settei-example-service
```

This is intentional operational behavior. A configuration change becomes a visible
rollout, every new pod passes the `--check-config` gate, and an invalid update cannot
silently mutate the typed configuration of an already-running process. Kubernetes also
documents that projected-volume updates can lag by the kubelet synchronization and cache
propagation delay; do not treat file modification time as proof that every pod has
reloaded the value.


## 9. Reject unknown keys

`defaultResolveOptions` warns about unknown input keys. For fleet services, promote them
to errors:

```haskell
strictResolveOptions :: ResolveOptions
strictResolveOptions = ResolveOptions {unknownKeyPolicy = RejectUnknownKeys}
```

A typo such as `database.poolsize` can otherwise be ignored while a default wins only in
one namespace. With `RejectUnknownKeys`, the typo makes that namespace's
`--check-config` gate fail. Keep schema migrations coordinated when enabling strictness:
an old binary must not receive a ConfigMap key that only a newer binary declares.


## 10. FAQ

### Should the environment be derived from the namespace name?

Prefer the explicit `HASKELL_ENV` switch from section 3. Derive from namespace only when
one authority controls every spelling and the code-change cost for new names is
acceptable.

### How do preview namespaces work?

An overlay for `pr-4711` can set `HASKELL_ENV: test` or `development`; no application
change is required. Name-derived selection would need a parser for every preview naming
convention and a policy for which runtime behavior each prefix means.

### What changes in a multi-container pod?

Each container has its own environment list, so each sidecar binds only the variables it
uses. Several containers may mount the same ConfigMap volume. The init container still
gates the whole pod: no application or sidecar container starts until configuration
validation succeeds.

### Does this require a Kubernetes client library?

No. The application sees ordinary files and environment variables. `kubectl` is used to
render or operate the deployment outside the process; Settei never queries cluster
state.
