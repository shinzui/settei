# Changelog

## 0.3.0.0 — 2026-10-21

Initial release.

### New Features

- Add the reusable `Settei.Preflight` deployment preflight harness with explicit
  input classifications, controlled environment/file channels, timeout, cleanup,
  exact-value secret redaction, and deterministic text and JSON reports.
- Add strict reference-only secret requests through `Settei.Preflight.Request`
  and the `settei-preflight --request PATH [--json]` executable.
- Accept `aeson >=2.2.4.1 && <2.4` (tested on 2.2.4.1, 2.2.5.1, and 2.3.2.0), so the
  package also builds against the locked nixpkgs Haskell set.
