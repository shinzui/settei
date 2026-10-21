# Changelog for settei-kdl

## 0.3.0.0 — 2026-10-21

### Other Changes

- Released in lockstep with the shared 0.3.0.0 Settei family; exact `settei` family
  pins move to `==0.3.0.0`. No API or behavior change in this package.
- Normalize the Cabal file with the configured formatter.

## 0.2.0.0 — 2026-07-19

- Add `renderKdlErrorText` and `renderKdlErrorsText` for stable, operator-readable,
  secret-safe adapter diagnostics, including related spans when present.

## 0.1.0.0 — 2026-07-19

- Initial experimental release.
- Add the canonical KDL v2 mapping with exact spans, deterministic cardinality, explicit
  ambiguity errors, and mounted-file Kubernetes annotations.
- Reject numeric values whose base-10 exponent magnitude exceeds 4096 instead of
  attempting an unbounded exact conversion at load time.
