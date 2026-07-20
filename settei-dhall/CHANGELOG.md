# Changelog for settei-dhall

## 0.2.0.0 — 2026-07-19

- Use the family-standard `lens` package in test suites instead of the leftover
  `microlens` prototype dependency.
- Add `renderDhallErrorText` and `renderDhallErrorsText` for stable, operator-readable,
  secret-safe adapter diagnostics with optional source positions.

## 0.1.0.0 — 2026-07-19

- Initial experimental release.
- Add typed Dhall-to-Settei translation with NoImports and LocalImportsWithin policies.
- Retain root and transitive import-closure provenance without claiming unavailable
  leaf-level import attribution.
- Document that import-policy preflight and file reads are not atomic, so an
  untrusted-writable import root remains vulnerable to a time-of-check/time-of-use race.
- Add optional one-based line and column fields to `DhallSourceError`, expose them through
  `dhallErrorLine` and `dhallErrorColumn`, and populate them for root and local-import
  parse failures.
