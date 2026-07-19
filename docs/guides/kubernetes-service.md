# Building a Kubernetes service

This guide configures a service from a mounted public file, direct environment values,
and a Secret-backed environment variable. Settei works with the files and environment
visible to the process; it does not require a Kubernetes client or cluster access.

The complete working implementation and manifests are in
[`settei-example-service`](../../examples/settei-service/).

## Model the process-visible inputs

A practical deployment uses a low-to-high source order such as:

```text
mounted ConfigMap file < environment variables < optional command-line overrides
```

Keep public, structured settings in a mounted YAML, KDL, or Dhall file. Use explicit
environment bindings for deployment-specific values and Secret references. The source
order belongs in application code, not in the Kubernetes manifest.

For a YAML and environment deployment, add:

```cabal
build-depends:
  , settei
  , settei-env
  , settei-yaml
  , text
```

The [`settei-formats`](formats.md) package bundles tagged loading and Kubernetes
annotation attachment across YAML, KDL, and Dhall mounted files. Services that support
all three formats can use it instead of maintaining separate dispatch code.

Add `settei-kdl`, `settei-dhall`, or `settei-optparse-applicative` only when the service
uses those inputs.

The declaration excerpts use:

```haskell
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Settei
import Settei.Env
import Settei.Yaml
```

## Declare typed service configuration

Keep secret-bearing types from acquiring a revealing `Show` instance:

```haskell
data RuntimeEnvironment = Development | Test | Production
  deriving stock (Eq, Ord, Show)

newtype SecretText = SecretText Text
  deriving stock (Eq)

data ServiceConfig = ServiceConfig
  { environment :: !RuntimeEnvironment,
    http :: !HttpConfig,
    database :: !DatabaseConfig
  }
  deriving stock (Eq)

data HttpConfig = HttpConfig
  { host :: !Text,
    port :: !Int
  }
  deriving stock (Eq, Show)

data DatabaseConfig = DatabaseConfig
  { host :: !Text,
    port :: !Int,
    poolSize :: !Int,
    password :: !(Maybe SecretText)
  }
  deriving stock (Eq)
```

Declare the password with `secretSetting` and a decoder that does not retain rejected
input:

```haskell
databasePasswordSetting :: Setting SecretText
databasePasswordSetting =
  secretSetting
    (validKey "database.password")
    "Database password"
    secretTextDecoder

secretTextDecoder :: Decoder SecretText
secretTextDecoder = decoder $ \targetKey -> \case
  RawText value -> Right (SecretText value)
  _ -> Left (decodeFailure targetKey "text")

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
```

Sensitivity belongs to the setting. It does not matter whether a value arrives through a
Secret, ConfigMap, ordinary environment variable, or command-line source: a secret setting
is always redacted, and a public setting is not automatically protected by its delivery
method.

## Use environment-dependent defaults and requirements

Named defaults make environment-specific behavior visible in the resolution report:

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

If a credential is required only in Production, express the condition in the `Config`
declaration with `whenEq`:

```haskell
productionPassword :: Config (Maybe SecretText)
productionPassword =
  whenEq (required environmentSetting) Production (required databasePasswordSetting)
```

Static schema inspection still lists `database.password`. A Development resolution does
not require or decode it and reports the setting as not selected. Test every conditional
branch explicitly. The general `select` operation from the `selective` package remains
available for arbitrary branch shapes.

## Bind Kubernetes-delivered environment variables

Map only supported variables:

```haskell
environmentBindings :: Bindings
environmentBindings =
  either (error . Text.unpack . renderEnvErrorsText) id
    ( bindings
        [ binding (EnvName "HASKELL_ENV") (validKey "runtime.environment"),
          binding (EnvName "HTTP_HOST") (validKey "http.host"),
          binding (EnvName "HTTP_PORT") (validKey "http.port"),
          binding (EnvName "DATABASE_HOST") (validKey "database.host"),
          binding (EnvName "DATABASE_PORT") (validKey "database.port"),
          binding (EnvName "DATABASE_POOL_SIZE") (validKey "database.poolSize"),
          fromKubernetesObject
            ( kubernetesRef
                SecretObject
                Nothing
                "my-service-database"
                (Just "password")
            )
            (binding (EnvName "DATABASE_PASSWORD") (validKey "database.password"))
        ]
    )
```

`fromKubernetesObject` records how the application expects the variable to be delivered.
It does not query Kubernetes or verify the pod spec. The annotation may name the Secret
and key in reports, while the setting value remains `<redacted>`. Its
`KubernetesRef -> EnvBinding -> EnvBinding` flow is unchanged: it annotates one binding
before `bindings` validates the complete list, and its metadata semantics do not move.

## Load an annotated mounted file

A mounted YAML ConfigMap can retain its Kubernetes origin:

```haskell
mountedConfigReference :: KubernetesRef
mountedConfigReference =
  kubernetesRef
    ConfigMapObject
    Nothing
    "my-service"
    (Just "application.yaml")

loadMountedConfiguration
  :: IO (Either (NonEmpty YamlSourceError) Source)
loadMountedConfiguration =
  readYamlSource
    ( fromKubernetesMountedFile
        mountedConfigReference
        (yamlSourceOptions "mounted application configuration")
    )
    "/etc/my-service/application.yaml"
```

KDL has an equivalent `fromKubernetesMountedFile`. For Dhall, apply
`kubernetesAnnotations mountedConfigReference` with `annotateDhallSourceOptions` and choose
`NoImports` or a narrow `LocalImportsWithin` root.

The annotation is trusted metadata supplied by application code. It does not prove that a
volume is current or mounted from the named object.

## Resolve once at startup

Load each effectful source before starting listeners or worker threads:

```haskell
resolveService
  :: Source
  -> Source
  -> ResolveResult ServiceConfig
resolveService mountedFile environmentSource =
  resolve
    defaultResolveOptions
    [mountedFile, environmentSource]
    serviceConfig
```

Recommended startup sequence:

1. Parse command-line usage.
2. Read and translate mounted files.
3. Snapshot explicitly bound environment variables.
4. Resolve the typed declaration and inspect `result ^. #answer`.
5. Emit warnings and, on success, an allowlisted non-secret startup summary.
6. Construct resources and start serving.

Fail startup when a source cannot be read or translated, a required setting is absent, or
the winning value cannot be decoded. Do not start with a partial configuration or fall
back to a lower candidate after malformed explicit input.

The resolver's report and warnings remain available when `answer` contains errors. A
failed startup can therefore log or return the same redacted provenance view as a
successful validation, showing which sources won, what they shadowed, and what remained
missing without exposing the typed record.

By default, Settei does not watch mounted volumes. Kubernetes may update a projected
ConfigMap or Secret after startup, but the typed value already held by the process does not
change. Use rollout restarts for simple deployments. If the application implements live
reload, reload every relevant source, resolve the complete declaration, and replace the
active configuration only after full success. For Dhall graphs, obtain the import closure
with `loadDhallSourceDetailed` so the watcher covers every local dependency.

## Create the ConfigMap and Deployment

Mount public configuration read-only:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-service
data:
  application.yaml: |
    http:
      host: 0.0.0.0
    database:
      host: postgres.internal
      port: 5432
```

Map the environment and Secret into the container:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
spec:
  selector:
    matchLabels:
      app: my-service
  template:
    metadata:
      labels:
        app: my-service
    spec:
      containers:
        - name: service
          image: registry.example/my-service:VERSION
          args:
            - --config
            - yaml:/etc/my-service/application.yaml
          env:
            - name: HASKELL_ENV
              value: production
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: my-service-database
                  key: password
          volumeMounts:
            - name: configuration
              mountPath: /etc/my-service
              readOnly: true
      volumes:
        - name: configuration
          configMap:
            name: my-service
```

The `yaml:` tag is an application-level policy used by the example service. If your
service accepts only YAML, a plain path is sufficient. Keep the CLI syntax and loader in
agreement.

Create real Secret values through the deployment's secret manager or delivery pipeline.
Do not commit a usable Secret manifest, encoded credential, or stable placeholder that
could be mistaken for a credential.

## Expose safe diagnostics

Provide `--check-config`, `--explain-config`, and `--explain-config-json` as described in
the [CLI application guide](cli-application.md). Use `--check-config` in image smoke tests
or deployment validation where all required mounted files and environment values are
available.

When a pod is crash-looping because resolution fails, run the same container with
`--explain-config` (or its JSON variant). The reference service prints the errors followed
by the redacted failure report to stderr and keeps exit code `4`, so the diagnostic shows
winning origins, shadowed inputs, missing values, and unselected branches even though the
service cannot start.

Do not run the long-lived container permanently in an explanation mode; those modes should
render and exit. For a running service, log only:

- whether configuration validation succeeded;
- unknown-key warnings;
- Settei's redacted resolution report when explicitly requested; and
- a hand-written allowlist of non-secret operational fields.

Never log the complete typed record. Secret-bearing record types should have no automatic
`Show` instance.

## Run and test locally

The example service can validate its development fixture without a secret:

```bash
HASKELL_ENV=development cabal run settei-example-service -- \
  --config yaml:examples/settei-service/test/fixtures/application.yaml \
  --check-config
```

For tests, inject `EnvSnapshot` rather than putting a secret in shell history:

```haskell
productionSnapshot :: EnvSnapshot
productionSnapshot =
  envSnapshot
    [ ("HASKELL_ENV", "production"),
      ("DATABASE_PASSWORD", "test-only-secret")
    ]
```

Cover Development and Production separately, file-over-environment precedence, missing
Secret values, malformed public and secret values, unknown keys, and secret sentinels in
all text and JSON output.

## Operational checklist

- Mount structured public configuration read-only.
- Deliver credentials through the cluster's Secret integration, not command-line values.
- Bind every supported environment variable explicitly.
- Mark sensitive settings with `secretSetting` regardless of delivery path.
- Keep Kubernetes names, keys, paths, and custom annotations safe to display.
- Resolve all startup configuration before opening listeners.
- Choose rollout restart or an atomic full-resolution reload strategy.
- Use `--check-config` for validation and reserve explanation modes for diagnostics.
- Test every environment-dependent default and Selective branch.
- Assert that secret sentinels never appear in stdout, stderr, logs, errors, or reports.

Review the example [Kubernetes manifests](../../examples/settei-service/kubernetes/) and
the full [`Settei.Example.Service`](../../examples/settei-service/src/Settei/Example/Service.hs)
composition together; the Haskell annotations and manifest object names must remain in
sync.
