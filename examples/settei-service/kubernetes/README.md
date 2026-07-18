# Kubernetes delivery paths

These files demonstrate process-visible configuration delivery; the example never calls
the Kubernetes API.

- `configmap.yaml` mounts public `application.yaml`. The Haskell loader asserts ConfigMap
  `settei-example-service`, key `application.yaml`, as trusted origin metadata.
- `deployment.yaml` supplies `HASKELL_ENV` directly and `DATABASE_PASSWORD` through
  `secretKeyRef`. The explicit environment binding asserts Secret
  `settei-example-service-database`, key `password`, as its origin.
- `secret.yaml.example` contains a placeholder only. Never commit a real credential or a
  manifest generated from one.

The password setting is marked secret in the declaration. Text and JSON explanations may
name the Secret object and key but always display `<redacted>` for its value.
