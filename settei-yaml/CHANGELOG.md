# Changelog for settei-yaml

## 0.1.0.0 — 2026-07-19

- Initial experimental release.
- Add a strict YAML mapping with exact node locations, explicit unsupported-feature
  errors, and mounted-file Kubernetes annotations.
- Reject numeric scalars whose base-10 exponent magnitude exceeds 4096 instead of
  attempting an unbounded exact conversion at load time.
- Restrict boolean scalars to the YAML 1.2 core schema: only case-insensitive `true` and
  `false` are booleans, whether plain or tagged `!!bool`. The YAML 1.1 spellings `y`,
  `yes`, `on`, `n`, `no`, and `off` are now plain text, eliminating the Norway problem.
- Contain all synchronous failures at the pure decode boundary; unexpected exceptions
  become `YamlSyntaxError` with a fixed secret-safe message, while asynchronous exceptions
  continue to propagate.
