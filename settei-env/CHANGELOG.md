# Changelog for settei-env

## Unreleased

- Add supplied-name validation against bindings and external-consumer allowances,
  opt-in checked snapshot source builders, and safe text and versioned JSON diagnostics
  (additive API; ships in the shared 0.3.0.0 PVP major release).
- Add `inputBindings` to export validated binding metadata without reading environment values.

## 0.2.0.0 — 2026-07-19

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
