# Changelog for settei-formats

## 0.3.0.0 — 2026-10-21

### Other Changes

- Released in lockstep with the shared 0.3.0.0 Settei family; exact `settei` family
  pins move to `==0.3.0.0`. No API or behavior change in this package.
- Normalize the Cabal file with the configured formatter.

## 0.2.0.0 — 2026-07-19

- Initial experimental release.
- Add tagged `FORMAT:PATH` configuration inputs, a shared loader dispatching to the
  YAML, KDL, and Dhall adapters, and a reusable `--config FORMAT:PATH` option.
