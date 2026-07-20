# Changelog for settei-env

## Unreleased

- BREAKING: environment bindings are validated once at construction. `Bindings` is an
  opaque validated collection built by `bindings` or `prefixedBindings`; `envSource`
  and `readEnvSource` take `Bindings` and are total; `environmentSource` and
  `readEnvironmentSource` provide the conventional `"environment"` label;
  `bindingsList` inspects a validated collection.
- Add `renderEnvErrorText` and `renderEnvErrorsText` for stable, operator-readable,
  value-free binding diagnostics.
- Add `mergeBindings`: combine validated `Bindings` collections with re-validation of
  cross-collection conflicts, enabling derived and hand-written bindings to compose.

## 0.1.0.0 — 2026-07-18

- Initial experimental release.
- Add explicit environment bindings, injected snapshots, and trusted Kubernetes object
  annotations.
