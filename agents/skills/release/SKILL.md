---
name: release
description: Release the Settei packages to Hackage following PVP, with a single shared version, in dependency order.
argument-hint: "[major|minor|patch]"
disable-model-invocation: true
allowed-tools: Read, Bash, Edit, Glob, Grep, Write, AskUserQuestion
---

# Settei Release Skill

Release the publishable Settei packages to [Hackage](https://hackage.haskell.org/)
using a single shared version, following the Haskell **PVP** (`A.B.C.D`).

This is a multi-package Nix + Cabal repository. All publishable packages share
one version and are released together under a single signed git tag.

## Versioning Strategy

All publishable packages share the **same version number** and are released
together. A single signed git tag `v<version>` marks each release.

The Haskell PVP version format is `A.B.C.D`:

- `A.B` is the **major** version — bump for breaking API changes (removed or
  renamed exports, changed types, changed semantics).
- `C` is the **minor** version — bump for backwards-compatible API additions
  (new exports, new modules, new instances).
- `D` is the **patch** version — bump for bug fixes, docs, internal-only
  changes, and performance improvements.

Increment rules:

- **major**: increment `B`, reset `C` and `D` to `0` (e.g. `0.1.0.0` → `0.2.0.0`).
- **minor**: increment `C`, reset `D` to `0` (e.g. `0.1.0.0` → `0.1.1.0`).
- **patch**: increment `D` (e.g. `0.1.0.0` → `0.1.0.1`).

## Packages (in dependency order)

The publishable packages MUST be uploaded in this order because of
inter-package `build-depends`. Each depends only on packages listed above it.

1. **settei** — `settei/` — core framework (no internal deps).
2. **settei-env** — `settei-env/` — depends on `settei`.
3. **settei-dhall** — `settei-dhall/` — depends on `settei`.
4. **settei-kdl** — `settei-kdl/` — depends on `settei`.
5. **settei-yaml** — `settei-yaml/` — depends on `settei`.
6. **settei-optparse-applicative** — `settei-optparse-applicative/` — depends on
   `settei` and `settei-env` (publish last).

The following packages are **NOT released** to Hackage — they are internal
reference and conformance artifacts under `examples/`:

- **settei-example-cli** (`examples/settei-cli/`) — reference CLI application.
- **settei-example-service** (`examples/settei-service/`) — Kubernetes-shaped
  reference service.
- **settei-example-conformance** (`examples/settei-conformance/`) — cross-format
  conformance test suite.

## Arguments

`$ARGUMENTS` is optional:

- `major`, `minor`, or `patch` — specifies the bump level.
- If omitted, determine the bump level from the changes (see step 2).

## Steps

### 1. Determine what changed since the last release

- Read the current version from any publishable `.cabal` file (they all share
  the same version — e.g. `settei/settei.cabal`).
- Find the latest git tag matching `v*` (`git tag --list 'v*'`) to identify the
  last release point. This repo may have **no tags yet** — in that case this is
  the initial release; use the full history instead of a tag range.
- Run `git log --oneline <last-tag>..HEAD` (or `git log --oneline` if there is
  no tag) to list commits since the last release.
- If there is a last tag and no commits since it, tell the user there is nothing
  to release and stop.

Present a summary showing:

- Current version.
- Last release tag (or "none — initial release").
- Number of commits since last release.
- Which package directories have changes.

### 2. Determine the next version using PVP

- If `$ARGUMENTS` is `major`, `minor`, or `patch`, use that bump level.
- Otherwise, analyze the commits to determine the appropriate bump:
  - "breaking", "remove", "rename", "change type", `!`/`BREAKING CHANGE` → major.
  - "add", "new", "feat", "export" → minor.
  - "fix", "docs", "refactor", "test", "chore", "internal" → patch.
- For an **initial release** where the current version is already the intended
  first published version (e.g. `0.1.0.0` with no prior tag), confirm with the
  user that no bump is needed rather than mechanically incrementing.
- Present the proposed bump and resulting version to the user and ask for
  confirmation before proceeding.

### 3. Update versions, internal bounds, and changelogs

#### Version update

Edit the `version:` field in every publishable cabal file to the new version:

- `settei/settei.cabal`
- `settei-env/settei-env.cabal`
- `settei-dhall/settei-dhall.cabal`
- `settei-kdl/settei-kdl.cabal`
- `settei-yaml/settei-yaml.cabal`
- `settei-optparse-applicative/settei-optparse-applicative.cabal`

Verify every publishable package is at the target version before committing.

#### Internal dependency bounds

Internal sibling dependencies are pinned to the exact shared version using
`==<version>` (the current repo convention). Because all packages share one
version, update every internal `settei*` bound to `==<new-version>`:

- In `settei-env`, `settei-dhall`, `settei-kdl`, `settei-yaml`: the `settei`
  bound (library and test-suite sections).
- In `settei-optparse-applicative`: the `settei` and `settei-env` bounds
  (library and test-suite sections).
- In the internal example packages (`examples/*`): update their `settei*`
  bounds too, so the workspace continues to build even though they are not
  published. Grep for `, settei` across all cabal files to catch every site:

  ```bash
  grep -rn ", settei" --include='*.cabal' .
  ```

Keep the existing `==<version>` style; do not switch to `^>=` unless the user
asks.

#### Changelog update

- For each publishable package with a `CHANGELOG.md`
  (`settei/`, `settei-env/`, `settei-dhall/`, `settei-kdl/`, `settei-yaml/`,
  `settei-optparse-applicative/`), add a new section for the new version above
  previous entries, using today's date in `YYYY-MM-DD` format.
- Move any content from an "Unreleased" section into the new version section.
- Summarize commits since the last release, grouped by (include only
  non-empty categories):
  - **Breaking Changes** (if major)
  - **New Features** (if minor or major)
  - **Bug Fixes**
  - **Other Changes** (docs, refactoring, tests, chores)

Show the user ALL changes (version bumps, internal bounds, changelog entries)
for review before committing.

### 4. Verify (format, build, test, check gates)

Run this project's gates — mirrors `docs/release-checklist.md`. Stop and fix on
any failure before proceeding.

- `nix fmt` — format (fourmolu, cabal-fmt, nixpkgs-fmt via treefmt).
- `nix develop -c cabal build all` — build every package.
- `nix develop -c cabal test all --test-show-details=direct` — run all test
  suites.
- `nix develop -c cabal haddock all` — confirm documentation builds.
- `nix develop -c cabal sdist all` — confirm every source distribution packs.
- `cabal check` in each **publishable** package directory (see step 6).
- Unpack each publishable sdist into a fresh temporary directory and confirm it
  builds from its own contents (catches missing `extra-source-files`/goldens).
- `nix flake check` — treefmt + pre-commit gates. Note: newly created files must
  be `git add`-ed first, since Nix evaluates the git tree.
- `git diff --check` — no whitespace errors or conflict markers.

### 5. Commit, tag, and push

- Stage all modified `.cabal` and `CHANGELOG.md` files (and any new changelogs).
- Create a single commit using a Conventional Commits message:
  `chore(release): <new-version>`. The body should summarize what's in the
  release and why this bump level was chosen.
- Create a single **signed** annotated git tag:
  `git tag -s v<version> -m "Release <version>"`.
- Push the commit and tag: `git push && git push --tags`.

### 6. Publish to Hackage (in dependency order)

For EACH publishable package, in this order —
`settei` → `settei-env` → `settei-dhall` → `settei-kdl` → `settei-yaml` →
`settei-optparse-applicative`:

1. `cd <pkg-dir>`.
2. `cabal check` — verify no packaging issues.
3. `cabal sdist`, then `cabal upload --publish <tarball-path>` to publish the
   source distribution.
4. `cabal haddock --haddock-for-hackage --haddock-hyperlink-source --haddock-quickjump`,
   then `cabal upload --publish --documentation <docs-tarball-path>` to publish
   the Haddocks.
5. Report the Hackage URL:
   `https://hackage.haskell.org/package/<pkg>-<version>`.

After all packages are published, present a summary table:

| Package | Version | Hackage URL |
|---------|---------|-------------|
| settei | X.Y.Z.W | https://hackage.haskell.org/package/settei-X.Y.Z.W |
| settei-env | X.Y.Z.W | https://hackage.haskell.org/package/settei-env-X.Y.Z.W |
| settei-dhall | X.Y.Z.W | https://hackage.haskell.org/package/settei-dhall-X.Y.Z.W |
| settei-kdl | X.Y.Z.W | https://hackage.haskell.org/package/settei-kdl-X.Y.Z.W |
| settei-yaml | X.Y.Z.W | https://hackage.haskell.org/package/settei-yaml-X.Y.Z.W |
| settei-optparse-applicative | X.Y.Z.W | https://hackage.haskell.org/package/settei-optparse-applicative-X.Y.Z.W |

### 7. Create the GitHub release

After all Hackage uploads succeed, create a GitHub release for the tag:

```bash
gh release create v<version> --title "v<version>" --notes "$(cat <<'EOF'
## Packages

| Package | Hackage |
|---------|---------|
| settei | https://hackage.haskell.org/package/settei-X.Y.Z.W |
| settei-env | https://hackage.haskell.org/package/settei-env-X.Y.Z.W |
| settei-dhall | https://hackage.haskell.org/package/settei-dhall-X.Y.Z.W |
| settei-kdl | https://hackage.haskell.org/package/settei-kdl-X.Y.Z.W |
| settei-yaml | https://hackage.haskell.org/package/settei-yaml-X.Y.Z.W |
| settei-optparse-applicative | https://hackage.haskell.org/package/settei-optparse-applicative-X.Y.Z.W |

## What's Changed

<changelog entries for this version>
EOF
)"
```

- Use the per-package changelog entries for the release-notes body.
- Include the Hackage links table so each package is discoverable.
- Report the GitHub release URL when done.

## Important

- Always ask the user to confirm the version bump and changelogs before
  committing. The commit and tag are created only AFTER user approval.
- Always publish in dependency order:
  `settei` → `settei-env` → `settei-dhall` → `settei-kdl` → `settei-yaml` →
  `settei-optparse-applicative`.
- Never publish the `examples/*` packages (`settei-example-cli`,
  `settei-example-service`, `settei-example-conformance`).
- Never skip the check gates: `nix fmt`, `cabal build/test/haddock/sdist all`,
  per-package `cabal check`, the sdist unpack-and-build check, `nix flake check`,
  and `git diff --check`.
- Publishing to Hackage is **irreversible**. If any step fails, stop and report
  the error rather than continuing.
- If a Hackage upload fails for a package, do NOT continue uploading packages
  that depend on it.
- Use a signed tag (`git tag -s`).
