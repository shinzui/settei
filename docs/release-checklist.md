# Release checklist

This checklist prepares the six publishable Settei packages for an initial 0.1.0.0
release. The three packages beneath `examples/` are internal validation artifacts and must
not be uploaded. Completing this document does not authorize publication, tag creation,
signing, or credential use.


## Scope and metadata

- [ ] All six publishable packages use version `0.1.0.0`.
- [ ] Synopsis, description, homepage, bug tracker, BSD-3-Clause license, maintainer, and
  source repository metadata pass `cabal check`.
- [ ] `tested-with` and the compatibility matrix match the validated GHC.
- [ ] Exposed modules match the compatibility matrix; no `Settei.Internal` module is
  exposed.
- [ ] Each package source distribution includes `LICENSE`, `CHANGELOG.md`, and required
  fixtures or goldens.
- [ ] Dependency bounds match the versions actually resolved in the pinned workspace.
- [ ] Current Hackage releases and upstream tags were checked before any bound, pin, or
  compatibility workaround changed.


## Documentation and security

- [ ] Root README declaration, precedence, derived-default, and package-map examples match
  the public API.
- [ ] YAML, KDL, Dhall, environment/CLI, CLI application, and Kubernetes service guides
  are linked from the root README.
- [ ] Security documentation covers setting-owned sensitivity, adapter errors,
  environment exposure, Kubernetes Secret limitations, Dhall imports, and safe logging.
- [ ] Text and JSON reports, captured stdout/stderr, and golden files contain no secret
  sentinel.
- [ ] Example Secret manifests contain placeholders only.


## Automated validation

- [ ] `nix fmt`
- [ ] `nix develop -c cabal build all`
- [ ] `nix develop -c cabal test all --test-show-details=direct`
- [ ] `nix develop -c cabal haddock all`
- [ ] `nix develop -c cabal sdist all`
- [ ] `cabal check` in every package directory
- [ ] Every publishable source distribution is unpacked in a new temporary directory and
  builds from its own contents.
- [ ] `mori show --full`
- [ ] `nix flake check`
- [ ] `git diff --check`


## Manual publication — requires separate authorization

- [ ] Review the final commit and clean worktree without modifying user-owned local files.
- [ ] Choose and create a signed release tag.
- [ ] Produce and verify checksums/signatures for release artifacts.
- [ ] Upload packages to Hackage in dependency order.
- [ ] Publish release notes and links to generated Haddocks.
- [ ] Smoke-test installation from the public registry.
