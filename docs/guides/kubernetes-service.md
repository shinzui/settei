# Building a Kubernetes service

This is the application-code half of running Settei on Kubernetes. It configures a
service from a mounted public file, a mounted Secret directory, and explicit environment
values. The deployment half—namespaces, ConfigMaps, Secrets, rollout
gates, and the incident runbook—is in the
[namespace deployment cookbook](kubernetes-cookbook.md).

Settei works with the files and environment visible to the process; it does not require
a Kubernetes client or cluster access.

The complete working implementation and manifests are in
[`settei-example-service`](../../examples/settei-service/).

## Model the process-visible inputs

A practical deployment uses a low-to-high source order such as:

```text
mounted ConfigMap file < mounted Secret directory < environment variables < optional command-line overrides
```

Keep public, structured settings in a mounted YAML, KDL, or Dhall file. Use explicit
file bindings for projected directories and explicit environment bindings for
deployment-specific values. The source order belongs in application code, not in the
Kubernetes manifest.

For a YAML and environment deployment, add:

```cabal
build-depends:
  , settei
  , settei-env
  , settei-kubernetes
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
import Settei.Kubernetes qualified as Kubernetes
import Settei.Kubernetes.Bindings qualified as KubernetesBindings
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
    ( do
        ordinaryBindings <-
          bindings
            [ binding (EnvName "HASKELL_ENV") (validKey "runtime.environment"),
              binding (EnvName "HTTP_HOST") (validKey "http.host"),
              binding (EnvName "HTTP_PORT") (validKey "http.port"),
              binding (EnvName "DATABASE_HOST") (validKey "database.host"),
              binding (EnvName "DATABASE_PORT") (validKey "database.port"),
              binding (EnvName "DATABASE_POOL_SIZE") (validKey "database.poolSize")
            ]
        secretBindings <-
          KubernetesBindings.bindingsFromSecret
            Nothing
            "my-service-database"
            [ KubernetesBindings.objectKeyBinding
                "password"
                (EnvName "DATABASE_PASSWORD")
                (validKey "database.password")
            ]
        mergeBindings [ordinaryBindings, secretBindings]
    )
```

`bindingsFromSecret` derives every environment binding and its Kubernetes provenance
from the same object-key row. It does not query Kubernetes or verify the pod spec. The
annotation may name the Secret and key in reports, while the setting value remains
`<redacted>`. `mergeBindings` revalidates cross-collection variable names and target
keys, so derived and ordinary bindings cannot silently overlap.

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
  :: IO (Either (NonEmpty FormatLoadError) Source)
loadMountedConfiguration =
  loadConfigInput
    (fromKubernetesMountedFile mountedConfigReference defaultLoadOptions)
    (configInput YamlFormat "/etc/my-service/application.yaml")
```

The shared loader applies the mounted-file annotation for YAML, KDL, and Dhall. For
Dhall, start with its safe `NoImports` default or set a narrow `LocalImportsWithin` policy.

The annotation is trusted metadata supplied by application code. It does not prove that a
volume is current or mounted from the named object.

For a projected Secret directory, map each visible file explicitly and load it through
`Settei.Kubernetes`:

```haskell
passwordFiles :: Kubernetes.FileBindings
passwordFiles =
  either (error . Text.unpack . Kubernetes.renderKubernetesErrorsText) id
    ( Kubernetes.fileBindings
        [Kubernetes.fileBinding "password" (validKey "database.password")]
    )

loadMountedSecret :: IO (Either Text Source)
loadMountedSecret = do
  loaded <-
    Kubernetes.readMountedDirectorySource
      ( Kubernetes.mountedDirectoryOptions
          "mounted database secret"
          (kubernetesRef SecretObject Nothing "my-service-database" Nothing)
      )
      passwordFiles
      "/etc/my-service/secrets"
  pure (either (Left . Kubernetes.renderKubernetesErrorsText) Right loaded)
```

The adapter follows Kubernetes' atomic-writer symlinks, records the mount path and file
modification time, and leaves an absent bound file absent for the typed resolver to
diagnose. Its object reference is trusted explanation metadata, not cluster attestation.

## Resolve once at startup

Load each effectful source before starting listeners or worker threads:

```haskell
resolveService
  :: Source
  -> Source
  -> Source
  -> ResolveResult ServiceConfig
resolveService mountedFile mountedSecret environmentSource =
  resolve
    defaultResolveOptions
    [mountedFile, mountedSecret, environmentSource]
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

By default, Settei does not watch mounted volumes. The typed value already held by the
process does not change when a file changes. If the application implements live reload,
reload every relevant source, resolve the complete declaration, and replace the active
configuration only after full success. For Dhall graphs, obtain the import closure with
`loadDhallSourceDetailed` so the watcher covers every local dependency. The
[cookbook's rotation section](kubernetes-cookbook.md#8-rotate-by-restarting) documents
the recommended Kubernetes restart posture.

## Expose safe diagnostics

Provide `--check-config`, `--describe-config`, `--describe-config-json`, `--explain-config`, and `--explain-config-json` as described in
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

The [cookbook's rollout gate](kubernetes-cookbook.md#6-gate-rollouts-with---check-config)
shows how to run check mode with the same image, environment, and mounts before the
service receives traffic. Consider `RejectUnknownKeys` for services where a misspelled
file key must fail startup rather than emit an advisory warning.

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

## Application checklist

- Bind every supported environment variable explicitly.
- Mark sensitive settings with `secretSetting` regardless of delivery path.
- Keep Kubernetes names, keys, paths, and custom annotations safe to display.
- Resolve all startup configuration before opening listeners.
- Reserve explanation modes for explicit diagnostics; never log the typed record.
- Test every environment-dependent default and Selective branch.
- Assert that secret sentinels never appear in stdout, stderr, logs, errors, or reports.

Continue with the [namespace deployment cookbook](kubernetes-cookbook.md) and its
checked-in [Kubernetes manifests](../../examples/settei-service/deploy/). Review those
alongside the full
[`Settei.Example.Service`](../../examples/settei-service/src/Settei/Example/Service.hs)
composition; application annotations and manifest object names must remain in sync.
