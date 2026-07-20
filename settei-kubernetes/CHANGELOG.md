# Changelog for settei-kubernetes

## 0.1.0.0 — Unreleased

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
