# Compatibility matrix

This matrix records the workspace actually validated for Settei 0.2.0.0 on 2026-07-20.
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
| Exact numeric conversion | `scientific-0.3.8.1` | YAML, KDL, and Dhall adapters: `>=0.3.7 && <0.4` |
| Dhall parse positions | `megaparsec-9.8.1` | Dhall adapter: `>=9 && <10` |
| Mounted-directory traversal | `directory-1.3.10.1` | Kubernetes adapter: `>=1.3.8 && <1.4` |
| Mounted path handling | `filepath-1.5.5.0` | Kubernetes adapter: `>=1.5.4 && <1.6` |
| Freshness timestamps | `time-1.14` | Kubernetes adapter: `>=1.14 && <1.17` |
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
| YAML | One strict mapping document with exact locations; only case-insensitive `true` and `false` are booleans, YAML 1.1 spellings remain text, exponent magnitudes above 4096 fail, and ambiguous features fail. |
| KDL | Canonical KDL v2 mapping with exact spans; one argument is scalar, two or more are an array, and numeric exponent magnitudes above 4096 fail. |
| Dhall | JSON-compatible normalized values under `NoImports` or explicit `LocalImportsWithin`; root and local-import parse failures carry one-based positions. |
| `settei-kubernetes` | Mounted ConfigMap/Secret directories with explicit per-file key bindings and atomic-writer symlink handling; no cluster access. |


## Public modules

The supported adoption surface is:

- Core umbrella: `Settei`.
- Core focused modules: `Settei.Config`, `Settei.Default`, `Settei.Error`, `Settei.Key`,
  `Settei.Origin`, `Settei.Provenance`, `Settei.Render`, `Settei.Report`, `Settei.Resolve`,
  `Settei.Schema`, `Settei.Setting`, `Settei.Source`, and `Settei.Value`.
- Adapters: `Settei.Env`, `Settei.Optparse`, `Settei.Yaml`, `Settei.Kdl`, and
  `Settei.Dhall`.
- Multi-format umbrella: `Settei.Formats` and `Settei.Formats.Optparse`.
- `settei-kubernetes` adapter: `Settei.Kubernetes` and
  `Settei.Kubernetes.Bindings`.

Modules beneath `Settei.Internal` and all packages beneath `examples/` are not public API.
Version 0.2.0.0 is experimental and does not promise semantic stability beyond these
documented modules and their release notes.

### Versioning policy

The packages in this family follow the Haskell Package Versioning Policy (PVP). The
surface adopters may depend on and pin against is exactly the modules listed above, in
the packages listed above, at the versions this matrix validates. `Settei.Prelude` is
internal to the settei package family: it exists so the sibling packages share one
import baseline, its re-exports track the `lens` package, and it may change in any
release without a corresponding major version bump — do not import it from adopting
code. Modules beneath `Settei.Internal` and all packages beneath `examples/` remain
non-public. No lens type appears in any public signature (verified by the EP-20
signature audit); adopting code never needs `lens` in its own build-depends. The family
releases in lockstep from one repository, and adapter packages pin the core exactly
(`settei ==X.Y.Z.W`); mixed-version family installs are unsupported. Deprecations are
announced with a `DEPRECATED` pragma and a changelog entry at least one major release
before removal.
