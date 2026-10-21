# Compatibility matrix

This matrix describes the working tree for the unreleased shared 0.3.0.0 release,
including all four deployment features implemented on 2026-10-21. The workspace still
uses version 0.2.0.0 until the coordinated bump; that released version does not include
`Settei.Contract`, `Settei.Validate`, supplied-name validation, or `settei-preflight`.

The 2026-10-21 documentation audit re-ran all 561 tests in 14 suites on the toolchain
below. Dependency versions come from that Cabal solver plan; declared bounds describe
the intended solver range, not a claim that every point in a range has been tested.
See the [release checklist](release-checklist.md) for remaining final-candidate gates.


## Toolchain

| Component | Validated version | Notes |
| --- | --- | --- |
| GHC | 9.12.4 | Packages use `GHC2024` and require `base >=4.21`. |
| `base` | 4.21.2.0 | Supplied by GHC 9.12.4. |
| Cabal CLI | 3.16.1.0 | Used for workspace build, tests, Haddocks, checks, and source distributions. |
| Cabal library in solver plan | 3.16.1.0 | Recorded by the workspace Cabal build. |
| Nix | 2.35.2 (Determinate Nix 3.23.0) | Flake inputs are pinned by `flake.lock`. |
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
| JSON values/reports | `aeson-2.2.5.1` | Dhall adapter: `>=2.2 && <2.3` |
| Exact numeric conversion | `scientific-0.3.9.0` | YAML, KDL, and Dhall adapters: `>=0.3.7 && <0.4` |
| Dhall parse positions | `megaparsec-9.8.3` | Dhall adapter: `>=9 && <10` |
| Mounted-directory traversal | `directory-1.3.10.1` | Kubernetes adapter: `>=1.3.8 && <1.4` |
| Mounted path handling | `filepath-1.5.5.0` | Kubernetes adapter: `>=1.5.4 && <1.6` |
| Freshness timestamps | `time-1.14` | Kubernetes adapter: `>=1.14 && <1.17` |
| Preflight subprocesses | `process-1.6.26.1` | `>=1.6.19 && <1.7`; Linux/macOS SIGTERM and pipe semantics |
| Preflight private directories | `temporary-1.3` | `>=1.3 && <1.4`; explicit cleanup verification in addition to bracket fallback |
| Preflight tooling JSON | `aeson-2.2.5.1`, `aeson-2.3.2.0` | `>=2.2.5.1 && <2.4`; separate solver tests preserve other adapters' bounds |
| Test framework | `tasty-1.5.5` | `>=1.5 && <1.6` |

Nix overrides Dhall and dhall-json to the pinned optparse-applicative 0.19 derivation so
reference applications have one CLI ABI. Cabal is the complete test authority because the
locked nixpkgs Tasty derivation still carries optparse-applicative 0.18; Nix builds the
affected package artifacts without mixing those test closures.


## Input contracts

| Adapter | Maintained contract |
| --- | --- |
| Environment | Explicit name-to-key bindings; no prefix discovery; opt-in validation of supplied names against bindings and allowances. |
| optparse-applicative | Ordered overrides with occurrence provenance; 0.19 option groups are used by examples. |
| YAML | One strict mapping document with exact locations; only case-insensitive `true` and `false` are booleans, YAML 1.1 spellings remain text, exponent magnitudes above 4096 fail, and ambiguous features fail. |
| KDL | Canonical KDL v2 mapping with exact spans; one argument is scalar, two or more are an array, and numeric exponent magnitudes above 4096 fail. |
| Dhall | JSON-compatible normalized values under `NoImports` or explicit `LocalImportsWithin`; root and local-import parse failures carry one-based positions. |
| Preflight request | Strict `settei.preflight-request` schema version 1; closed keys and forms, reference-only real secrets, explicit inheritance, relative file paths, notes reduce coverage. |
| `settei-kubernetes` | Mounted ConfigMap/Secret directories with explicit per-file key bindings and atomic-writer symlink handling; no cluster access. |


## Public modules

The supported adoption surface for the next release is:

- Core umbrella: `Settei`.
- Core focused modules: `Settei.Config`, `Settei.Contract`, `Settei.Default`, `Settei.Error`, `Settei.Key`,
  `Settei.Origin`, `Settei.Provenance`, `Settei.Render`, `Settei.Report`, `Settei.Resolve`,
  `Settei.Schema`, `Settei.Setting`, `Settei.Source`, `Settei.Validate`, and `Settei.Value`.
- Adapters: `Settei.Env`, `Settei.Optparse`, `Settei.Yaml`, `Settei.Kdl`, and
  `Settei.Dhall`.
- Multi-format umbrella: `Settei.Formats` and `Settei.Formats.Optparse`.
- `settei-kubernetes` adapter: `Settei.Kubernetes` and
  `Settei.Kubernetes.Bindings`.

The unreleased preflight package exposes `Settei.Preflight` and `Settei.Preflight.Request`.
Its `Settei.Preflight.Internal` module is private.

Modules beneath `Settei.Internal` and all packages beneath `examples/` are not public API.
The family is experimental and does not promise semantic stability beyond these
documented modules and their release notes.

### Versioning policy

The next shared release, 0.3.0.0, adds `InvariantError` to `ConfigError`, requiring
adopters to update exhaustive matches. `Settei.Validate`, validation report types, and
`validatedDiagnostic` add a post-resolution boundary; the existing `resolve` API stays
unchanged. Version-1 error JSON gains kind `invariant`; the validated resolution renderer
adds an `invariants` array, while bare resolution JSON remains byte-identical. The release
workflow updates all family versions and exact intra-family pins together.


The packages in this family follow the Haskell Package Versioning Policy (PVP). The
surface adopters may depend on and pin against is exactly the modules listed above, in
the packages listed above, at the versions this matrix validates. `Settei.Prelude` is
internal to the settei package family: it exists so the sibling packages share one
import baseline, its re-exports track the `lens` package, and it may change in any
release without a corresponding major version bump — do not import it from adopting
code. Modules beneath `Settei.Internal` and all packages beneath `examples/` remain
non-public. No lens type appears in any public signature (verified by the EP-20
signature audit); record patterns can read public result fields without adding `lens`
to application dependencies. The family releases in lockstep from one repository, and adapter packages pin the core exactly
(`settei ==X.Y.Z.W`); mixed-version family installs are unsupported. Deprecations are
announced with a `DEPRECATED` pragma and a changelog entry at least one major release
before removal.


## Unreleased deployment contract

The next shared release targets 0.3.0.0. Core adds `Settei.Contract`,
`renderContractText`, and `renderContractJson`; environment bindings gain an
`inputBindings` conversion. `DiagnosticMode` gains `DeploymentContractText` and
`DeploymentContractJson`, a major PVP change for exhaustive pattern matches.
`contractDiagnostic` dispatches those modes without changing the existing helpers.

`settei.schema` and `settei.resolution` JSON are unchanged. `settei.contract` is a
separate version 1 document, reusing setting metadata and origin encodings. Existing
`--describe-config-json` consumers require no migration. No third-party dependency
bounds or pins change for this feature.


## Unreleased supplied-name validation

`Settei.Env` adds `acceptedNames`, external-consumer `allowance` declarations,
`checkSuppliedNames`, `snapshotNames`, `checkedEnvSource`, and
`checkedEnvironmentSource`, with text and version-1 `settei.supplied-names` JSON
renderers. Existing environment source builders remain permissive. Missing bound names
are not errors; other sources and defaults can supply them. Validate ordered deployment
entries before translating them into a snapshot or extracting effective names if you need
to catch duplicates. See the [environment guide](guides/environment-and-cli.md#validate-the-names-a-deployment-supplies).

## Unreleased application validation

`Settei.Validate` adds checked pure rule collections and `validate`, preserving the
resolved report and warnings. `Settei.Report` adds the invariant outcome trace;
`renderValidationText` and `renderValidatedResolutionJson` render it.
`Settei.Optparse.validatedDiagnostic` consumes the validated answer for startup, check,
and explain modes. Applications with validators must use it after validation so
`--check-config` cannot report success early. Static describe/contract dispatch remains
before input loading. See the [migration example](guides/cli-application.md#validate-cross-setting-invariants-after-resolution).

Update exhaustive `ConfigError` matches for `InvariantError`, and JSON error consumers
for kind `invariant`. Bare `renderResolutionJson` remains unchanged. The validated
renderer always adds an `invariants` array, including `[]` for an empty collection.
JSON explain rejection through `validatedDiagnostic` returns two newline-separated documents (`settei.errors`, then
`settei.resolution`), including base resolution failures with rules `not-run`. The
application owns stream routing and exit codes; the deployment example sends both to
stderr and exits 4. Successful JSON explanation emits one resolution document to stdout.
Validator metadata and public details are author-supplied text, with the
[security obligations](security.md#application-validators) described separately.

## Unreleased deployment preflight

`settei-preflight` joins the family for the next shared 0.3.0.0 release; it is not in
the released 0.2.0.0 package set. Its Cabal manifest uses the current workspace family
version until the coordinated release bump. Reports expose sanitized fields through
read-only accessors and carry no public lens types. Request and input types deliberately
lack Show. Execution targets are Linux and macOS; acceptance was run on aarch64-darwin.

Both `settei.preflight-request` and `settei.preflight` use schemaVersion 1. Requests reject
unknown fields/forms, so adding a field/form or changing meaning requires a new version.
All notes in version 1 reduce coverage. These tooling formats use Aeson with fixed pair
order and byte-identical goldens; existing core schema/resolution documents are unchanged.
The standalone Aeson 2.3 suite excludes the Dhall adapter rather than widening its bounds.
