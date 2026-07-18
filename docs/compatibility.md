# Compatibility matrix

This matrix records the workspace actually validated for Settei 0.1.0.0 on 2026-07-18.
Dependency bounds describe the intended solver range; they do not claim that every point
in a range has been tested.


## Toolchain

| Component | Validated version | Notes |
| --- | --- | --- |
| GHC | 9.12.4 | Packages use `GHC2024` and require `base >=4.21`. |
| `base` | 4.21.2.0 | Supplied by GHC 9.12.4. |
| Cabal CLI | 3.16.1.0 | Used for workspace build, tests, Haddocks, checks, and source distributions. |
| Cabal library in GHC package set | 3.14.2.0 | Used by the Nix package builder. |
| Nix | 2.33.3 | Flake inputs are pinned by `flake.lock`. |
| Validation system | `aarch64-darwin` | Other flake-exposed systems are not yet release-validated. |

The host's unrelated GHC 9.10 installation cannot satisfy `base >=4.21`; use
`nix develop` or another GHC 9.12-or-newer environment.


## Libraries and adapters

| Capability | Validated dependency | Declared Settei bound or policy |
| --- | --- | --- |
| Selective declarations | `selective-0.7.0.1` | `>=0.7 && <0.8` |
| CLI parsing | `optparse-applicative-0.19.0.0` | `>=0.19 && <0.20` |
| YAML parsing | `libyaml-0.1.4` | `>=0.1.4 && <0.2` |
| KDL parsing | `kdl-hs-1.1.1` | `>=1.1.1 && <1.2` |
| Dhall evaluation | `dhall-1.42.3` | `>=1.42.3 && <1.43` |
| Dhall JSON conversion | `dhall-json-1.7.12` | `==1.7.12` plus the documented Hackage-revision compatibility allowances in `cabal.project` |
| JSON values/reports | `aeson-2.2.5.0` | Dhall adapter: `>=2.2 && <2.3` |
| Test framework | `tasty-1.5.4` | `>=1.5 && <1.6` |

Nix overrides Dhall and dhall-json to the pinned optparse-applicative 0.19 derivation so
reference applications have one CLI ABI. Cabal is the complete test authority because the
locked nixpkgs Tasty derivation still carries optparse-applicative 0.18; Nix builds the
affected package artifacts without mixing those test closures.


## Input contracts

| Adapter | Maintained contract |
| --- | --- |
| Environment | Explicit name-to-key bindings; no prefix discovery. |
| optparse-applicative | Ordered overrides with occurrence provenance; 0.19 option groups are used by examples. |
| YAML | One strict mapping document; exact locations; ambiguous YAML features fail. |
| KDL | Canonical KDL v2 mapping; exact spans; one argument is scalar and two or more are an array. |
| Dhall | JSON-compatible normalized values under `NoImports` or explicit `LocalImportsWithin`. |


## Public modules

The supported adoption surface is:

- Core umbrella: `Settei`.
- Core focused modules: `Settei.Config`, `Settei.Default`, `Settei.Error`, `Settei.Key`,
  `Settei.Origin`, `Settei.Prelude`, `Settei.Provenance`, `Settei.Render`, `Settei.Report`,
  `Settei.Resolve`, `Settei.Schema`, `Settei.Setting`, `Settei.Source`, and `Settei.Value`.
- Adapters: `Settei.Env`, `Settei.Optparse`, `Settei.Yaml`, `Settei.Kdl`, and
  `Settei.Dhall`.

Modules beneath `Settei.Internal` and all packages beneath `examples/` are not public API.
Version 0.1.0.0 is experimental and does not promise semantic stability beyond these
documented modules and their release notes.
