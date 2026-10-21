# Changelog for settei-kubernetes

## 0.3.0.0 — 2026-10-21

### Other Changes

- Released in lockstep with the shared 0.3.0.0 Settei family; exact `settei` family
  pins move to `==0.3.0.0`. No API or behavior change in this package.
- Normalize the Cabal file with the configured formatter.

## 0.2.0.0 — 2026-07-19

- Initial experimental release.
- Add a mounted-directory source for projected ConfigMap and Secret volumes with
  explicit per-file key bindings, atomic-writer symlink handling, per-file
  provenance, and secret-safe categorized errors with text renderers.
- Add `Settei.Kubernetes.Bindings`: derive validated environment bindings from a
  ConfigMap or Secret reference in one construction, so each binding's provenance
  annotation is generated from the same data key that feeds it.
- Mounted-directory origins now carry freshness identity: `kubernetes.mount-path`,
  per-key `kubernetes.file-modified`, and source-wide `kubernetes.read-at`
  (ISO-8601 UTC). Descriptive only; precedence is unchanged.
