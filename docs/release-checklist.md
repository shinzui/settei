# Release checklist

This checklist prepares the eight publishable Settei packages for an initial 0.1.0.0
release. The three packages beneath `examples/` are internal validation artifacts and must
not be uploaded. Completing this document does not authorize publication, tag creation,
signing, or credential use. The checked automated evidence was re-validated on 2026-07-19
after the fleet-adoption correctness-hardening pass.


## Scope and metadata

- [x] All eight publishable packages use version `0.1.0.0`.
- [x] Synopsis, description, homepage, bug tracker, BSD-3-Clause license, maintainer, and
  source repository metadata pass `cabal check`.
- [x] `tested-with` and the compatibility matrix match the validated GHC.
- [x] Exposed modules match the compatibility matrix; no `Settei.Internal` module is
  exposed, including both `settei-kubernetes` public modules.
- [x] Each package source distribution includes `LICENSE`, `CHANGELOG.md`, and required
  fixtures or goldens.
- [x] Dependency bounds match the versions actually resolved in the pinned workspace.
- [x] Current Hackage releases and upstream tags were checked before any bound, pin, or
  compatibility workaround changed.


## Documentation and security

- [x] Root README declaration, precedence, derived-default, and package-map examples match
  the public API.
- [x] YAML, KDL, Dhall, environment/CLI, CLI application, and Kubernetes service guides
  are linked from the root README.
- [x] Security documentation covers setting-owned sensitivity, adapter errors,
  environment exposure, Kubernetes Secret limitations, Dhall imports, and safe logging.
- [x] Text and JSON reports, captured stdout/stderr, and golden files contain no secret
  sentinel.
- [x] Example Secret manifests contain placeholders only.


## Automated validation

- [x] `nix fmt`
- [x] `nix develop -c cabal build all`
- [x] `nix develop -c cabal test all --test-show-details=direct`
- [x] `nix develop -c cabal haddock all`
- [x] `nix develop -c cabal sdist all`
- [x] `cabal check` in every package directory
- [x] Every publishable source distribution is unpacked in a new temporary directory and
  builds and passes its tests from its own contents.
- [x] The conformance `booleans.yaml` fixture proves untagged `no` and `on` remain text.
- [x] The YAML and KDL huge-exponent fixtures are rejected with their stable adapter
  categories.
- [x] A forced resolution failure retains a provenance report, and its errors and report
  redact a secret sentinel.
- [x] `mori registry show shinzui/settei --full`
- [ ] Every overlay under `examples/settei-service/deploy/` renders without error via
  `kubectl kustomize` or `kustomize build`; when neither binary is available in the
  shell, record an equivalent client-side render transcript from a machine that has it.
- [ ] Mounted-fixture smoke: the reference service exits 0 for `--check-config` with a
  temporary mounted Secret directory and exits 3 when that directory does not exist.
- [x] `nix flake check`
- [x] `git diff --check`


## Manual publication — requires separate authorization

- [ ] Review the final commit and clean worktree without modifying user-owned local files.
- [ ] Choose and create a signed release tag.
- [ ] Produce and verify checksums/signatures for release artifacts.
- [ ] Upload packages to Hackage in dependency order.
- [ ] Publish release notes and links to generated Haddocks.
- [ ] Smoke-test installation from the public registry.
