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
