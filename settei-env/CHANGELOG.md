# Changelog for settei-env

## 0.3.0.0 — 2026-10-21

### New Features

- Add supplied-name validation against bindings and external-consumer allowances
  (`acceptedNames`, `allowance`, `checkSuppliedNames`, `snapshotNames`), opt-in checked
  snapshot source builders (`checkedEnvSource`, `checkedEnvironmentSource`), and safe
  text and version-1 `settei.supplied-names` JSON diagnostics. Existing source builders
  remain permissive.
- Add `inputBindings` to export validated binding metadata without reading environment values.

### Other Changes

- Released in the shared 0.3.0.0 PVP major family release; the `settei` pin moves to
  `==0.3.0.0`. This package's own API changes are additive.

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
