# Namespace deployment examples

These manifests accompany the
[namespace-driven Kubernetes cookbook](../../../docs/guides/kubernetes-cookbook.md).
`validate.sh` renders and checks them client-side; it never contacts a Kubernetes
cluster, preserving the process boundary recorded in
[ADR 0007](../../../docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md).

Every Secret value is an unmistakable placeholder. Never commit a real credential, an
encoded real credential, or any value that could be mistaken for one. Replace the
placeholder object through your secret-management pipeline before deploying.

The base mounts `settei-example-service-database` at `/etc/settei/secrets` and passes
that directory through `--secrets-dir`. It also exposes the same `password` key through
`DATABASE_PASSWORD`, intentionally demonstrating the reference service's mounted-file <
environment precedence and shadow trace. Applications may choose either delivery form;
the duplicate delivery is a conformance example, not a requirement.

Run the offline render and invariant checks from the repository root:

```bash
nix develop -c bash examples/settei-service/deploy/validate.sh
```

Set `SETTEI_VALIDATE_SCHEMAS=1` to add kubeconform schema validation. Kubeconform's
default schema source is remote, so that opt-in check requires network access.
