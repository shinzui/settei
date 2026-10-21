# Changelog

## Unreleased

- Add the reusable `Settei.Preflight` deployment preflight harness with explicit
  input classifications, controlled environment/file channels, timeout, cleanup,
  exact-value secret redaction, and deterministic text and JSON reports.
- Add strict reference-only secret requests through `Settei.Preflight.Request`
  and the `settei-preflight --request PATH [--json]` executable.
