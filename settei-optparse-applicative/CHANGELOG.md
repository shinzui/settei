# Changelog for settei-optparse-applicative

## Unreleased

- Add deployment contract diagnostic flags and `contractDiagnostic`. `DiagnosticMode` gains constructors: a major PVP API change for exhaustive matches.

## 0.2.0.0 — 2026-07-19

- Breaking: replace `ExplainMode` and its parsers with `DiagnosticMode`, which also
  supports `--check-config`, `--describe-config`, and `--describe-config-json`.
- Add `schemaDiagnostic` and `resolutionDiagnostic` helpers for the source-free and
  post-resolution diagnostic paths.

## 0.1.0.0 — 2026-07-18

- Initial experimental release.
- Add ordered generic and named command-line overrides for optparse-applicative 0.19.
