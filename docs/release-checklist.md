# Release checklist

This checklist prepares the nine publishable Settei packages for the next shared
**0.3.0.0** release. The four packages beneath `examples/` are internal validation
artifacts and must not be uploaded. Workspace versions and exact family pins currently
remain `0.2.0.0`; the coordinated release bump is still pending.

Checked audit items below were verified on 2026-10-21. Unchecked final-candidate gates
must be completed against the version-bumped tree; historical 0.1.0.0/0.2.0.0 acceptance
and completed implementation plans do not substitute for those checks.

## Package scope and order

Publish in this dependency order (the release workflow uses the same inventory):

1. `settei`
2. `settei-env`
3. `settei-dhall`
4. `settei-kdl`
5. `settei-yaml`
6. `settei-kubernetes`
7. `settei-optparse-applicative`
8. `settei-preflight` (new library and executable)
9. `settei-formats`

Exclude `settei-example-cli`, `settei-example-service`,
`settei-example-conformance`, and `settei-example-deployment` from publication.
See the repository's [release workflow](../agents/skills/release/SKILL.md).

## Feature documentation coverage

| Completed plan | User guide | Public contract and migration | Release notes |
| --- | --- | --- | --- |
| [26: deployment contract](plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md) | [First deployment](guides/deployment-contract.md) | [ADR-12](adr/0012-deployment-contract-export-semantics.md), [CAP-14](capabilities/deployment-configuration-contract.md), [compatibility](compatibility.md#unreleased-deployment-contract) | [Core](../settei/CHANGELOG.md), [environment](../settei-env/CHANGELOG.md), [CLI](../settei-optparse-applicative/CHANGELOG.md) |
| [27: supplied environment names](plans/27-validate-supplied-environment-variable-names-against-declared-bindings.md) | [Bindings and allowances](guides/environment-and-cli.md#validate-the-names-a-deployment-supplies) | [CAP-5](capabilities/explicit-environment-sources.md), [compatibility](compatibility.md#unreleased-supplied-name-validation) | [Environment](../settei-env/CHANGELOG.md) |
| [28: preflight harness](plans/28-provide-a-reusable-deployment-preflight-harness-around-application-check-mode.md) | [Proposed-input checks](guides/deployment-preflight.md) | [ADR-13](adr/0013-deployment-preflight-harness-semantics.md), [CAP-15](capabilities/deployment-preflight-harness.md), [compatibility](compatibility.md#unreleased-deployment-preflight) | [Preflight](../settei-preflight/CHANGELOG.md) |
| [29: application invariants](plans/29-integrate-application-validation-into-structured-configuration-diagnostics.md) | [Validation and dispatch](guides/cli-application.md#validate-cross-setting-invariants-after-resolution) | [ADR-14](adr/0014-application-invariant-validation.md), [CAP-16](capabilities/structured-application-validation.md), [compatibility](compatibility.md#unreleased-application-validation) | [Core](../settei/CHANGELOG.md), [CLI](../settei-optparse-applicative/CHANGELOG.md) |
| [30: checked dispatch](plans/30-require-complete-diagnostic-dispatch-before-application-startup.md) | [Complete dispatch](guides/cli-application.md#add-diagnostics-that-match-user-intent) | [ADR-7](adr/0007-reference-applications-are-the-public-api-conformance-boundary.md), [ADR-14](adr/0014-application-invariant-validation.md), [compatibility](compatibility.md#unreleased-checked-diagnostic-dispatch), [upgrade blueprint](../blueprints/settei-upgrade/README.md) | [CLI adapter](../settei-optparse-applicative/CHANGELOG.md), [deployment example](../examples/settei-deployment/CHANGELOG.md) |

- [x] Root README, guide navigation, package READMEs, security guidance, and compatibility
  notes distinguish the released 0.2.0.0 API from the upcoming features.
- [x] Migration notes cover new `ConfigError`/`DiagnosticMode` constructors, opt-in
  supplied-name checks, and validated explanation JSON/stream changes.
- [x] Contracts remain source-free, missing bound names may use defaults, preflight
  partial coverage cannot pass, and validators require safe metadata and finite rules.
- [x] Preflight and supplied-name validation are documented as separate checks; ordered
  deployment names must be validated before duplicate entries are collapsed.

## Documentation audit validation — 2026-10-21

- [x] `nix develop -c cabal test all --test-show-details=direct`: 561 tests in 14 suites
  pass on GHC 9.12.4 / Cabal 3.16.1.0, `aarch64-darwin`.
- [x] Workspace build, `cabal sdist all`, formatting, and `cabal check` in all nine
  public packages pass before the version bump.
- [x] `nix flake check` passes on `aarch64-darwin`; other systems remain unvalidated.
- [x] Local paths and heading anchors resolve across 24 active documentation files.
- [x] All four OKF bundles pass their profile-enforced validators and link graphs.
- [x] Changed guide examples, including the Haskell preflight runner, compile against
  the public modules without `Settei.Prelude`.
- [x] `cabal haddock all` and a final focused core/preflight rebuild pass.
  `Settei.Contract`, `Settei.Validate`, `Settei.Preflight`, and
  `Settei.Preflight.Request` each report 100% Haddock declaration coverage.
  Missing dependency/generated-instance links remain warnings.
- [x] Documented contract, supplied-name, invariant, and preflight commands match actual
  executable output and exits, including source-free dispatch and secret-safe failures.
- [x] `git diff --check`.

## Final-candidate metadata and packaging

- [ ] Seihou upgrade blueprint: decide whether this release window needs an edge and
  record the decision either way. For a breaking release append the edge, bump
  `blueprints/settei-upgrade/blueprint.dhall` and `seihou-registry.dhall` versions,
  update the blueprint README edge table, pass `seihou validate-blueprint
  blueprints/settei-upgrade --lint`, and retain a debug preview transcript showing
  exactly the intended steps. The 0.3.0.0 edge is 0.2.0.0 to 0.3.0.0.
  Verify the blueprint commit is on the pushed remote before tagging.

- [ ] All nine public versions, internal example versions, and every exact family pin
  move together to `0.3.0.0`.
- [ ] Every public changelog has a dated `0.3.0.0` entry; move existing Unreleased notes
  and record lockstep-only changes for otherwise unchanged adapters.
- [ ] README and compatibility release status match the final artifact versions and
  distinguish final acceptance from implementation evidence.
- [ ] Synopsis, description, homepage, bug tracker, BSD-3-Clause license, maintainer,
  source repository, and `tested-with` metadata pass `cabal check` in all nine packages.
- [ ] Exposed modules match the compatibility matrix; no `Settei.Internal` or
  `Settei.Preflight.Internal` module is exposed. `Settei.Prelude` remains family-internal.
- [ ] Every public source distribution includes its license, changelog, and required
  fixtures/goldens; preflight includes its executable and request/report goldens.
- [ ] Recheck current Hackage releases and upstream tags before changing dependency
  bounds, pins, or compatibility workarounds; inspect dependency APIs through Mori.
- [ ] Mori registration reflects the final package inventory and current documentation.

## Checked dispatch implementation evidence — 2026-10-21

Plan 30 adds checked preparation before runtime work and startup only on successful
continue in all reference applications. Its API migration fixtures reject old helper
calls by token type; executable probes and automated tests cover source-free diagnostics
and omitted contract support. This implementation evidence is separate from the
version-bumped final-candidate gates below.

## Final-candidate automated validation

Run from the repository root unless a package directory is specified. Record results
and platform against the final release commit.

- [ ] `nix fmt`
- [ ] `nix develop -c cabal build all`
- [ ] `nix develop -c cabal test all --test-show-details=direct`
- [ ] `nix develop -c cabal haddock all`
- [ ] `nix develop -c cabal sdist all`
- [ ] `nix develop -c cabal check` in each of the nine public package directories.
- [ ] Unpack all nine public sdists into a fresh temporary workspace and build and test
  them using only those unpacked public sources, without original checkout paths or
  internal examples. Then check every package's own fixtures/goldens are present.
- [ ] Run all four documentation validators and graphs:

```bash
okf validate docs/adr --strict --profile docs/adr/profile.dhall --profile-enforce --log-enforce
okf graph docs/adr --json
okf validate docs/guides --strict --profile mori/user-documentation-profile.dhall --profile-enforce --log-enforce
okf graph docs/guides --json
okf validate docs/capabilities --profile docs/capabilities/profile.dhall --profile-enforce --log-enforce
okf graph docs/capabilities --json
okf validate docs/improvement-requests --strict --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
okf graph docs/improvement-requests --json
```

- [ ] Re-run the standalone Aeson 2.3 preflight solver/golden check documented in
  [plan 28](plans/28-provide-a-reusable-deployment-preflight-harness-around-application-check-mode.md#concrete-steps)
  without widening Dhall's bounds.
- [ ] Smoke static describe/contract modes with missing runtime files, supplied-name
  rejection before loading, both deployment roles, invariant text/JSON rejection,
  and preflight pass/inconclusive/rejection outcomes with fake credentials.
- [ ] Confirm secret sentinels are absent from text/JSON reports, stdout/stderr, and
  goldens; Kubernetes Secret fixtures contain placeholders only.
- [ ] Render every overlay under `examples/settei-service/deploy/` with
  `kubectl kustomize` or `kustomize build` and run its mounted-fixture check-mode smoke.
- [ ] `nix flake check` and builds of the public/example Nix outputs, including preflight
  and the deployment example. Record supported-platform limits explicitly.
- [ ] `git diff --check`

## Publication

- [ ] Review the final commit and clean worktree without modifying user-owned local files.
- [ ] Create the signed release tag and verify release artifacts/checksums.
- [ ] Upload the nine public packages and Haddocks in dependency order.
- [ ] Publish release notes with all four features, migration instructions, package and
  documentation links, and validated platforms.
- [ ] Smoke-test installation from Hackage.
