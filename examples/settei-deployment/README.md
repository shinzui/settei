# Deployment contract reference application

This internal example declares notification delivery configuration once, exports its
production deployment contract without reading runtime inputs, and checks proposed
inputs with distinct server and worker validations. It contacts no database or provider.

From the repository root:

```bash
nix develop -c cabal run settei-example-deployment-server -- --deployment-contract
nix develop -c cabal run settei-example-deployment-worker -- --deployment-contract-json
nix develop -c cabal run settei-example-deployment-server -- --config examples/settei-deployment/test/fixtures/proposed-production.yaml --check-config
nix develop -c cabal run settei-example-deployment-worker -- --config examples/settei-deployment/test/fixtures/proposed-production.yaml --check-config
```

Both check commands print `configuration valid`. The YAML contains dummy credentials
and a placeholder endpoint. Replace them for a real deployment. See the
[deployment guide](../../docs/guides/deployment-contract.md) for the complete workflow,
including missing-input and application-validation failures.

## Preflight

Build the harness and example, extract the proposed inputs from a normalized rendered
Kubernetes JSON `List`, and run the application's check mode:

```bash
nix develop -c cabal build settei-example-deployment settei-preflight
nix develop -c cabal run -v0 settei-example-deployment-preflight -- \
  --manifest examples/settei-deployment/test/fixtures/rendered-production.json \
  --deployment settei-example-deployment-server --role server \
  --executable "$(nix develop -c cabal list-bin settei-example-deployment-server)" \
  --synthetic POD_NAMESPACE=production > /tmp/server-request.json
SETTEI_PREFLIGHT_SECRET_SETTEI_EXAMPLE_DEPLOYMENT_SECRETS_DATABASE_URL='postgres://preflight.invalid/notification' \
SETTEI_PREFLIGHT_SECRET_SETTEI_EXAMPLE_DEPLOYMENT_SECRETS_WEBHOOK_SECRET='preflight-stand-in-webhook-secret' \
SETTEI_PREFLIGHT_SECRET_SETTEI_EXAMPLE_DEPLOYMENT_SECRETS_EMAIL_CREDENTIALS_JSON='{}' \
  nix develop -c cabal run -v0 settei-preflight -- --request /tmp/server-request.json
```

This returns `inconclusive` (exit 1): the namespace is synthetic. Omitting the email
credential gives the application's missing-required error (exit 4). Choose the worker
Deployment, role, and executable to exercise worker-specific checks; its mounted
projected volume adds a coverage limitation. All fixture credentials are fake.

The reference extractor handles literal env, same-namespace ConfigMap keys, Secret
references without reading their values, unresolved fieldRef, ordered envFrom with
prefixes, explicit env overrides, ConfigMap/Secret item and all-key mounts, and file or
directory path rewriting in args. Real secrets use harness-environment references whose
names are `SETTEI_PREFLIGHT_SECRET_` plus uppercase sanitized Secret name and key.
`--synthetic` substitutes only unresolved public inputs; `--synthetic-secret` accepts
fake secret material only. Optional missing keys are omitted with notes. Duplicate
resource identities, unsafe/colliding file paths, and sanitized secret-reference
collisions fail extraction.

This is an example extractor, with no cluster client or image inspection. It expects an
already collected JSON List; kustomize YAML and Pulumi outputs need normalization first.
Unknown valueFrom forms, unknown envFrom keys, resourceFieldRef, projected/downwardAPI,
csi/emptyDir/PVC mounts, binaryData, subPath/subPathExpr, optional-volume semantics,
container command overrides, unexpanded `$(VAR)`, and unmatched absolute argument paths
produce notes. Every note prevents `pass`. Arguments are applied to the caller-supplied
host executable; matching the deployed image's entrypoint remains the caller's duty.
The harness cannot notice a renamed unbound variable such as `HASKELL_ENV`; use supplied
name validation as a separate check. Configuration acceptance establishes neither
connectivity nor readiness. The startup action is instrumented to fail when
`SETTEI_DEPLOYMENT_TEST_FAIL_ON_STARTUP=1`; both real role checks skip it, and non-check
controls prove it is reached.


## Rejection lines changed

The next shared 0.3.0.0 release moves the existing checks to role-specific `Validators`.
Valid inputs, typed values, and rejection exit 4 are unchanged. The old worker line was:

```text
workers.visibilityTimeoutSeconds: must be at least twice workers.concurrency
```

The structured replacement names the stable rule and both declared keys:

```text
workers.visibilityTimeoutSeconds, workers.concurrency: invariant worker-visibility-covers-concurrency failed: workers.visibilityTimeoutSeconds must be at least twice workers.concurrency
```

`--explain-config` retains the full report and appends ordered rule outcomes.
`--explain-config-json` failures now emit two JSON documents on separate stderr lines
(errors then resolution with `invariants`), including on base resolution failures;
the previous path mixed text errors with a JSON report. Source-load failures stay text
and exit 3. Static describe and contract modes still load no sources or validators.
See [structured validation](../../docs/guides/cli-application.md#validate-cross-setting-invariants-after-resolution)
for the author contract and migration dispatch.
