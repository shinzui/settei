# Changelog for settei-yaml

## 0.1.0.0 — 2026-07-18

- Initial experimental release.
- Add a strict YAML mapping with exact node locations, explicit unsupported-feature
  errors, and mounted-file Kubernetes annotations.
- Reject numeric scalars whose base-10 exponent magnitude exceeds 4096 instead of
  attempting an unbounded exact conversion at load time.
