---
id: 8
slug: move-settei-packages-to-top-level-sibling-directories
title: "Move Settei packages to top-level sibling directories"
kind: exec-plan
created_at: 2026-07-17T16:03:36Z
intention: "intention_01kxr36cqgem8tmxjjtnq0t6ns"
master_plan: "docs/masterplans/1-build-settei-as-a-provenance-aware-configuration-library-for-haskell.md"
---

# Move Settei packages to top-level sibling directories

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

After this plan, every publishable Settei package is an ordinary top-level sibling named
after its Cabal package. The core lives in `settei/`, the implemented adapters live in
`settei-env/`, `settei-optparse-applicative/`, and `settei-yaml/`, and future adapters use
the same pattern. The repository root remains the workspace and documentation boundary;
it is no longer also a special package root, and there is no generic `packages/` wrapper.

This is a structural change only. Package names, Haskell module names, public APIs,
versions, test behavior, Cabal targets, and flake output names stay unchanged. A user can
verify the result by inspecting `cabal.project`, running the complete Cabal and Nix test
suites, building source distributions, and confirming that no active build or planning
path refers to `packages/`, root `src/`, root `test/`, or root `settei.cabal`.


## Progress

- [x] (2026-07-17 21:00 -0700) Recorded the clean pre-move baseline: the core,
  environment, CLI, and YAML suites passed 47 + 7 + 8 + 20 tests, respectively, for 82
  total. Inventoried the path-sensitive Cabal, Nix, Mori, documentation, fixture, and
  source-distribution references named by this plan.
- [x] (2026-07-17 21:09 -0700) Relocated the core and three implemented adapters into
  top-level package directories. Git recognizes every existing Cabal, Haskell, test,
  golden, and fixture file as a content-identical rename; package and module names are
  unchanged.
- [x] (2026-07-17 21:09 -0700) Rewired `cabal.project`, `nix/haskell.nix`, and `mori.dhall`
  for the new roots, added the package-local core README, built the workspace with Cabal,
  and built all three adapter Nix outputs against the relocated core.
- [x] (2026-07-17 21:09 -0700) Updated the family README and active planning paths while
  retaining old-layout references only in completed-plan history, revision notes, and
  this plan's explicit before/after migration instructions.
- [x] (2026-07-17 21:16 -0700) Passed formatting, Cabal build, all 82 tests, Haddocks,
  four package checks, four source distributions with inspected package-local contents,
  Mori's four-package inventory, all adapter and default Nix builds, the full flake check,
  and `git diff --check`. Confirmed obsolete paths remain only as explicit history or
  migration prose.


## Surprises & Discoveries

- Observation: the root `settei` package is coupled to the repository root in two places
  beyond `cabal.project`: `nix/haskell.nix` passes `inputs.self` to `callCabal2nix`, and
  `settei.cabal` includes root `README.md` plus `test/golden/*` in its source distribution.
  Evidence: direct inspection of those checked-in files on 2026-07-17.
  Impact: the move must give the core an explicit `../settei` Nix source, move its golden
  files with the package, and provide a package-local `settei/README.md` rather than
  relying on a file outside the package root.

- Observation: the registered Mori and Shibuya Haskell workspaces use package-named
  top-level siblings and list those directories directly in `cabal.project`.
  Evidence: `mori registry show shinzui/mori --full` and
  `mori registry show shinzui/shibuya --full` resolved the source trees; their checked-in
  project files list `mori-core`, `mori-cli`, `shibuya-core`, and related siblings without
  a `packages/` container.
  Impact: the target layout follows the owner's established multi-package convention
  instead of inventing a Settei-only exception.


## Decision Log

- Decision: Put every publishable package in a repository-root directory with the exact
  package name; move the current root package to `settei/` and remove `packages/` after its
  children have moved.
  Rationale: uniform sibling roots are conventional in the owner's Haskell workspaces and
  avoid a special root package plus a second nesting scheme for adapters.
  Date: 2026-07-17

- Decision: Keep repository-only applications under `examples/` rather than promoting
  them to publishable top-level siblings.
  Rationale: `examples/` communicates that those Cabal packages demonstrate the public
  libraries and are not part of the Hackage package family.
  Date: 2026-07-17

- Decision: Preserve all Cabal package names, Haskell module names, versions, and public
  interfaces during the move.
  Rationale: the layout refactor should be invisible to downstream Haskell code and must
  not become an accidental API migration.
  Date: 2026-07-17

- Decision: Give the relocated core a concise package-local `settei/README.md` while
  retaining the root `README.md` as the package-family and repository guide.
  Rationale: the core source distribution must be self-contained, while the root guide
  owns navigation across all adapters and examples.
  Date: 2026-07-17


## Outcomes & Retrospective

Completed on 2026-07-17. The repository now contains the publishable package roots
`settei/`, `settei-env/`, `settei-optparse-applicative/`, and `settei-yaml/`; it contains no
root `settei.cabal`, `src/`, `test/`, or `packages/` directory. Git recorded every existing
Cabal, Haskell, test, golden, and fixture file as a 100% rename. Cabal package names,
exposed `Settei.*` modules, versions, and behavior did not change.

The post-move gate passed `nix fmt`, `cabal build all`, all 82 Cabal tests, Haddocks, and
`cabal check` for every package. `cabal sdist all` produced four archives; direct archive
inspection confirmed `settei` contains its package-local README, sources, and golden
files, while `settei-yaml` contains its characterization README and YAML fixtures. Mori
reports the same four packages at same-named paths. The three named adapter Nix outputs,
the default core output, and both full flake checks pass.

[ADR 0001](../adr/0001-haskell-project-conventions.md) already records the durable sibling
layout, package-local ownership, and rejected alternatives. The completion distillation
pass found no additional durable decision or lesson to promote: the implementation
confirmed the existing ADR rather than changing it. Old paths remain only where completed
plans preserve their historical implementation steps or where this plan explains the
migration itself. EP-5 and EP-6 may now create `settei-kdl/` and `settei-dhall/` directly.


## Context and Orientation

The repository is a Cabal workspace. A package root is the directory containing one
`.cabal` file and that package's `src/`, `test/`, fixtures, and package documentation.
Currently the core package is exceptional: `settei.cabal`, `src/`, and `test/` are at the
repository root. The three implemented adapters are nested under
`packages/settei-env/`, `packages/settei-optparse-applicative/`, and
`packages/settei-yaml/`. `cabal.project` registers `.` plus those three directories, while
`nix/haskell.nix` builds the core from `inputs.self` and adapters from paths beneath
`../packages/`.

The target package roots are `settei/`, `settei-env/`,
`settei-optparse-applicative/`, and `settei-yaml/`. The core's modules therefore move from
`src/Settei/*.hs` to `settei/src/Settei/*.hs`, its tests and goldens move from `test/` to
`settei/test/`, and its Cabal file moves to `settei/settei.cabal`. Each adapter directory
moves intact from `packages/<name>/` to `<name>/`. Future plans create
`settei-kdl/settei-kdl.cabal` and `settei-dhall/settei-dhall.cabal` directly at the
repository root. Haskell module paths below each package's `src/` directory do not change.

`docs/plans/1-bootstrap-settei-and-prove-the-inspectable-configuration-algebra.md` through
`docs/plans/4-add-yaml-configuration-support.md` are completed plans and accurately record
the old layout they produced. Do not rewrite their historical progress or validation as
if the new layout had existed then. Add a superseding decision or revision note where an
old path is stated as ongoing policy. The unfinished KDL, Dhall, and reference-application
plans must use the target paths and must not start until this plan is complete.

[ADR 0001](../adr/0001-haskell-project-conventions.md) is the relevant durable record. It
defines package-local Cabal conventions and is amended by this MasterPlan revision to
define top-level sibling package roots. ADRs 0002 through 0004 own algebra, resolution,
and YAML semantics and do not need layout changes. The registered `shinzui/mori` and
`shinzui/shibuya` sources are relevant convention evidence; their APIs are not
dependencies of Settei. `mori.dhall` uses the registered `shinzui/mori-schema` project,
whose `Schema.Package` records accept package names, types, languages, and repository-root
relative paths.

The working tree may contain unrelated user changes. In particular, an untracked
`.seihou/config.dhall` existed while this plan was written. Preserve it and every other
unrelated change; the package move does not authorize cleanup or resetting the tree.


## Plan of Work

### Milestone 1: capture the baseline and relocate package trees

Start by running the complete Cabal tests and recording the package list from
`cabal.project`. Inspect `git status --short` and distinguish pre-existing user changes
from this plan's work. Then use Git-aware moves so history follows the files: create
`settei/`, move `settei.cabal`, `src/`, and `test/` beneath it, and move each adapter
directory out of `packages/` to the repository root. Remove `packages/` only after it is
empty. Do not edit Haskell modules during the move.

Create `settei/README.md` as a concise core-package document with the package purpose,
public module entry point, and a link or source-repository URL back to the family guide.
Keep root `README.md` in place. In `settei/settei.cabal`, retain `README.md` and
`test/golden/*` as package-relative extra source files. At the end of the milestone,
`rg --files` shows four package-named top-level directories, Git recognizes the old files
as moves, and no module or test content has changed merely because its parent moved.

### Milestone 2: rewire workspace, Nix, and Mori metadata

Edit `cabal.project` so its package list is `settei`, `settei-env`,
`settei-optparse-applicative`, and `settei-yaml`. Preserve all package test settings. In
`nix/haskell.nix`, build the core with `callCabal2nix "settei" ../settei { }` instead of
`inputs.self`; change adapter sources to `../settei-env`,
`../settei-optparse-applicative`, and `../settei-yaml`. Keep the existing dependency
overrides and flake output names unchanged.

Update `mori.dhall` using the checked-in schema revision so `mori show --full` lists the
four implemented libraries with paths matching their top-level package roots. Before
writing schema fields, refresh `mori registry show shinzui/mori-schema --full` and read the
reported `Schema.Package` source instead of guessing. This milestone is accepted when
`cabal build all`, the individual Nix package outputs, and `mori show --full` resolve only
the new roots.

### Milestone 3: reconcile active documentation and historical plans

Search the repository, excluding build artifacts, for `packages/`, root `settei.cabal`,
and root `src/` or `test/` references. Update root `README.md`, the MasterPlan, pending
plans, and guides wherever the text describes current or future layout. Keep completed
plans historically truthful: append a dated revision note and mark the original root or
`packages/` decision as superseded by this plan rather than rewriting completed evidence.
ADR 0001 remains the durable home for the sibling-root rule.

At the end of this milestone, unfinished plans create future adapters at
`settei-kdl/` and `settei-dhall/`, and no active instruction tells an implementer to add a
publishable package under `packages/` or treat the repository root as the core package.

### Milestone 4: prove build and distribution equivalence

Run formatting, the complete build and test suite, Haddocks, package checks, source
distributions, Mori validation, individual Nix builds, and the full flake check. Inspect
the generated source-distribution file lists for package-local source, tests, goldens,
fixtures, and README files; no package may succeed only because it can read a file outside
its package root. Confirm that all existing 82 tests still pass and that public package and
module names have not changed. Record concise evidence in Progress and Outcomes before
marking the plan complete.


## Concrete Steps

Run all commands from `/Users/shinzui/Keikaku/bokuno/settei`. First refresh the local
project and convention evidence and capture the pre-move state:

```bash
mori show --full
mori registry show shinzui/mori --full
mori registry show shinzui/shibuya --full
mori registry show shinzui/mori-schema --full
git status --short
cabal test all --test-show-details=direct
```

Perform the directory moves with Git-aware operations. Create and edit
`settei/README.md` with the repository editing mechanism rather than shell redirection:

```bash
mkdir settei
git mv settei.cabal settei/settei.cabal
git mv src settei/src
git mv test settei/test
git mv packages/settei-env settei-env
git mv packages/settei-optparse-applicative settei-optparse-applicative
git mv packages/settei-yaml settei-yaml
rmdir packages
```

After rewiring paths and metadata, prove that only intentional historical prose retains an
old layout reference:

```bash
rg -n "packages/|src/|test/|settei\\.cabal" README.md cabal.project flake.nix nix \
  mori.dhall docs settei settei-env settei-optparse-applicative settei-yaml
git diff --check
```

Complete validation is:

```bash
nix fmt
cabal build all
cabal test all --test-show-details=direct
cabal haddock all
cabal sdist all
cd settei
cabal check
cd ../settei-env
cabal check
cd ../settei-optparse-applicative
cabal check
cd ../settei-yaml
cabal check
cd ..
mori show --full
nix build --no-link .#settei-env
nix build --no-link .#settei-optparse-applicative
nix build --no-link .#settei-yaml
nix build --no-link .#
nix flake check
git diff --check
```

The meaningful test result remains:

```text
All 82 tests passed
```

`mori show --full` lists `settei`, `settei-env`,
`settei-optparse-applicative`, and `settei-yaml` with their same-named relative paths.


## Validation and Acceptance

The top-level tree contains `settei/settei.cabal`, `settei-env/settei-env.cabal`,
`settei-optparse-applicative/settei-optparse-applicative.cabal`, and
`settei-yaml/settei-yaml.cabal`. It contains no `packages/` directory, root
`settei.cabal`, root `src/`, or root `test/`. `cabal.project`, `nix/haskell.nix`, and
`mori.dhall` name the same four roots.

`cabal test all --test-show-details=direct` must run the unchanged core, environment, CLI,
and YAML suites and report all 82 tests passing. Golden rendering tests must still read the
files now under `settei/test/golden/`, and YAML tests must still load their package data
files now under `settei-yaml/test/fixtures/`. No test is accepted if it only passes when
started from a particular developer working directory.

The four `cabal check` invocations must accept their relocated metadata. `cabal sdist all`
must produce self-contained archives whose file lists include core goldens, YAML fixtures,
and package-local documentation. `nix build --no-link .#` must still build the core as the
default, and every named adapter output plus `nix flake check` must succeed without an old
path. `mori show --full` must report the four current packages at their top-level roots.

Search active build and planning files for the obsolete layout. Historical statements in
completed plan progress, outcomes, or superseded decisions may remain when that completed
plan has a clear layout note identifying EP-8 as the migration; future instructions and
durable policy must contain no `packages/<settei-package>` path. Downstream code must
still depend on packages named
`settei`, `settei-env`, `settei-optparse-applicative`, and `settei-yaml` and import the
same `Settei.*` modules as before.


## Idempotence and Recovery

Mori queries, searches, builds, tests, formatting, checks, and source-distribution creation
are safe to repeat. Git-aware moves are safe to resume by inspecting `git status --short`
and moving only paths that still exist at the old location. Never rerun the entire move
block blindly after a partial completion.

Do not reset or clean the working tree to recover. If validation fails, compare
`cabal.project`, `nix/haskell.nix`, and the package-relative file declarations against the
target tree, fix the remaining path, and rerun the narrow failing command. Preserve
unrelated user changes. Because this plan changes paths but not Haskell contents, `git
diff --summary` should show renames plus small wiring, metadata, and documentation edits;
unexpected source-code modifications require inspection before continuing.


## Interfaces and Dependencies

This plan adds no library dependency and changes no Haskell type or function. The core
continues to expose `Settei`, `Settei.Config`, `Settei.Source`, `Settei.Resolve`, and its
other existing modules from `settei/src/`. The adapters continue to expose `Settei.Env`,
`Settei.Optparse`, and `Settei.Yaml` from their package-local `src/` directories.

Cabal owns workspace discovery through `cabal.project`. Nix owns flake outputs through
`nix/haskell.nix` and must pass explicit top-level package paths to `callCabal2nix`.
`mori.dhall` owns the repository's package inventory and uses `Schema.Package` records from
the registered `shinzui/mori-schema` source. Git-aware moves preserve file history. No KDL,
Dhall, Kubernetes, parser, or application behavior belongs in this structural plan.


## Revision Note

2026-07-17: Created this plan during the MasterPlan layout revision so the already-built
core and adapters can move from the exceptional root-plus-`packages/` structure to the
owner's standard top-level sibling-package structure before KDL, Dhall, and reference
application work begins.

2026-07-17: Completed the behavior-neutral move, added package-local core documentation,
registered the four package roots in Cabal, Nix, and Mori, reconciled active documentation,
and recorded the full build, test, source-distribution, and flake evidence above.
