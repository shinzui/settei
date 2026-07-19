# ADR 0001: Adopt the Haskell project conventions

Status: Accepted

Date: 2026-07-16

Amended: 2026-07-17, 2026-07-18, 2026-07-19


## Context

Settei is planned as one core Haskell library, five adapter libraries, two reference
applications, and shared tests. Without a repository-wide baseline, those components could
drift in language edition, extensions, imports, record design, deriving, and field access.
That drift would be especially visible in Settei's public metadata records, where every
adapter needs concepts such as a source name, key, location, and annotations.

The canonical convention corpus is the Mori project `shinzui/haskell-jitsurei`. During the
2026-07-16 audit, Mori's project-details and documentation commands for that qualified name
resolved the applicable `core-standards`, `core-custom-prelude`, `core-record-patterns`,
`core-multiline-strings`, `cli-option-groups`, and `cli-hierarchical-config` documents.
Mori resolved both `lens` and `generic-lens` through `ekmett/lens`; direct source inspection
found `lens` 5.3.6, `generic-lens` 2.3.0.0, `Control.Lens`, and the orphan `IsLabel` instance
exported by `Data.Generics.Labels`.

EP-3's dependency audit resolved optparse-applicative 0.19.0.0 and its
`parserOptionGroup` API. Nixpkgs' GHC 9.12.4 package set still carries 0.18, and its
`tasty` derivation embeds that older ABI, so simply overriding the adapter dependency
would mix incompatible optparse-applicative instances in the Nix test component.

The initial implementation put the core package at the repository root and adapter
packages beneath `packages/`. A 2026-07-17 layout review found that this differs from the
owner's established multi-package Haskell repositories. Mori resolved the registered
`shinzui/mori` and `shinzui/shibuya` source trees; their `cabal.project` files list
package-named top-level siblings such as `mori-core`, `mori-cli`, and `shibuya-core`
directly, without a generic package container or a special package rooted at `.`.

A 2026-07-18 release audit found that Mori's registered `kdl-hs` checkout was 1.0.1 while
Hackage and the upstream repository had released 1.1.1. The audit also confirmed that the
other version-sensitive choices remained current: optparse-applicative 0.19.0.0,
selective 0.7.0.1, yaml 0.11.11.2, libyaml 0.1.4, dhall 1.42.3, and dhall-json 1.7.12.
The `generic-lens >=2.2 && <2.4` range already includes its current 2.3.0.0 release.


## Decision

Every Settei Cabal component uses GHC 9.12 or newer. Each package's `.cabal` file declares
the same package-local `common common` stanza with `default-language: GHC2024` and the
extensions `DeriveAnyClass`, `DuplicateRecordFields`, `OverloadedLabels`, and
`OverloadedStrings`; every component in that file imports the stanza. Cabal common stanzas
do not cross package-file boundaries, so adapter and example packages repeat the canonical
stanza rather than relying on the root package's declaration.

The core package exposes `Settei.Prelude`. That module uses a file-local `PackageImports`
pragma for unambiguous re-exports and re-exports the small common surface plus
`Control.Lens`, except for the lens library's setter type alias named `Setting`. That alias
collides with Settei's public `Setting` metadata type, so the prelude hides it once at the
boundary while retaining the operators and other lens API. Code that specifically needs
the lens alias can import it directly under a distinct local name. `PackageImports` is not
a global extension. `Settei.Prelude` does not import or re-export
`Data.Generics.Labels`; each module that uses generic-lens `#label` syntax imports
`Data.Generics.Labels ()` locally.

Records use strict fields without type-name prefixes and derive instances with explicit
`stock`, `newtype`, or `anyclass` strategies. Record reads and updates use lens operators;
record-held maps use `at` and `ix` rather than direct map operations wrapped in record
updates. Qualified imports use postpositive `qualified`. Operators remain unqualified, and
an operator collision is resolved by hiding the unwanted operator from the
`Settei.Prelude` import.

The core package depends on `lens` and `generic-lens`. Any adapter, example, or test package
that imports `Data.Generics.Labels ()` declares `generic-lens` directly rather than relying
on transitive package visibility. `MultilineStrings` is enabled locally or for a narrowly
scoped component only when the source embeds a multi-line value.

Dependency research always begins with Mori so source code, documentation, and known
consumer usage can be inspected locally. Release selection is a separate step: before an
exact lower bound, archive pin, or compatibility workaround is adopted, check Hackage and
the dependency's upstream release tags for the current published version. A stale corpus
checkout must not become a release ceiling. Reusable Cabal libraries express an audited
compatible release range; reproducible Nix inputs may lock the selected release archive.

For command-line components using optparse-applicative 0.19 or newer, related options are
wrapped in short, intent-based groups such as “Configuration” and “Diagnostics”. Other CLI
patterns from the corpus are adopted only when the component actually needs them. The
hierarchical-config guidance to keep independent concerns separate remains valid, but it
does not replace Settei's defining behavior: ordered sources for the same declared setting
schema are merged by core precedence rules.

The flake pins the source-inspected optparse-applicative 0.19.0.0 Hackage release for the
command-line adapter's Nix output. Cabal is the authoritative executable test graph because
its solver selects one coherent optparse-applicative version for the full suite. Until the
nixpkgs `tasty` graph advances to the same ABI, only the Nix derivation for
`settei-optparse-applicative` uses `pkgs.haskell.lib.dontCheck`; the library still builds
against 0.19, and `cabal test all` must run all adapter tests.

Every publishable Settei package lives in a same-named directory directly beneath the
repository root. The core is rooted at `settei/`; adapters are rooted at `settei-env/`,
`settei-optparse-applicative/`, `settei-yaml/`, `settei-kdl/`, and `settei-dhall/`. Each
package directory owns its `.cabal` file, `src/`, `test/`, fixtures, and package-specific
documentation. The repository root owns `cabal.project`, Nix and Mori workspace metadata,
the package-family README, shared documentation, and planning records. Non-published
reference packages remain beneath `examples/` so their role is visibly distinct from the
publishable package family.

Package and Haskell module identities do not depend on these source-tree paths. Moving a
package changes Cabal, Nix, Mori, documentation, fixture, and source-distribution paths but
does not rename the package, its exposed modules, or its public API. Active plans and build
configuration must use the sibling roots; completed plan history may retain an old path
only when a revision note identifies the later migration.

Amendment (2026-07-19, EP-20): `Settei.Prelude` remains an exposed module because the
sibling packages import it across Cabal package boundaries, but it is documented as
internal to the settei package family and excluded from the PVP-stable public surface in
`docs/compatibility.md`. Its re-exports track the `lens` package and may change in any
release. The `lens` and `generic-lens` conventions remain unchanged. The Dhall test
suites now use the same `lens >=5.3 && <5.4` range as the core instead of a leftover
`microlens` prototype dependency. Exact intra-family pins remain intentional while the
family is released in lockstep from this repository.


## Consequences

Plan 1 owns the canonical Cabal stanza contents and `Settei.Prelude`; every later plan
repeats that package-local stanza and consumes the prelude. Public record sketches use
reusable labels such as `name`, `key`, `value`, `location`, and `annotations`, and nested
domain records replace flat type-prefixed fields when concepts would otherwise collide.
This adds `lens` and `generic-lens` to the baseline dependency surface, and it requires
direct `generic-lens` dependencies in non-core packages that use the label instance.
The single `Control.Lens.Setting` exclusion makes the central Settei type unambiguous for
all packages and examples while leaving ordinary lens usage unchanged.

Implementation and release validation must inspect every component for the common stanza
and representative modules for strict fields, explicit deriving, local label-instance
imports, lens access, and postpositive qualified imports. CLI help tests also verify the
applicable option-group headings.

Pinning one small Hackage source makes the Nix CLI output reproducible against the public
API used by Cabal. Temporarily disabling that derivation's checks avoids an ABI-invalid
test graph without removing any test from the repository's acceptance suite. The exception
is narrowly scoped and should be removed once nixpkgs supplies a compatible `tasty` graph.

Mori-backed source inspection remains mandatory, but package freshness is verified
independently. This keeps local corpus knowledge useful without allowing its update cadence
to force an older dependency or an unnecessary compatibility workaround into a public
package. Every release upgrade still runs the adapter's characterization and workspace
acceptance tests before its supported range is widened.

All package additions now have one predictable location. Cabal and Nix configuration must
name explicit package roots instead of relying on the entire repository as the core source,
and each package source distribution must be self-contained within its directory. In
particular, the core needs package-local documentation and tests beneath `settei/`, while
the root README remains the family-wide navigation document. Layout-only moves require the
full workspace test suite and source-distribution checks because package-relative fixtures
and goldens can fail even when Haskell module imports are unchanged.


## Rejected Alternatives

Keeping type-prefixed selectors was rejected because it conflicts with the canonical
record convention and would make public APIs noisier. Re-exporting `Data.Generics.Labels`
from `Settei.Prelude` was rejected because its orphan `IsLabel` instance would leak into
every module and can conflict with other label-based DSLs. Creating a different prelude for
each adapter was rejected because the packages form one project and need a shared baseline.
Applying every CLI cookbook pattern to the small reference executable was rejected as
scope without a user requirement.
Building the adapter against nixpkgs' optparse-applicative 0.18 was rejected because it
lacks the adopted option-group API. Relaxing the Cabal lower bound or silently skipping
the tests everywhere was rejected because either would weaken the source-inspected API or
the acceptance evidence.
Treating the newest version visible in Mori as the newest released dependency was rejected
because Mori's corpus and upstream package publication have independent update cadences.
Requiring every module to import `Settei.Prelude hiding (Setting)` was rejected because
the collision is universal to Settei consumers and can be resolved once at the prelude
boundary. Renaming Settei's domain type was rejected because `Setting` is the clearest
public name for one declared configuration value.
Keeping the core at the repository root while placing adapters under `packages/` was
rejected because it gives one package exceptional structure and conflicts with the owner's
other multi-package Haskell workspaces. Moving only the adapters to top-level siblings was
also rejected because the root package would remain the same exception. Putting
non-published reference applications beside publishable packages was rejected because it
would blur package-family and example ownership; `examples/` remains the explicit boundary.
Moving `Settei.Prelude` to a Cabal public sublibrary was rejected for now: documentation
demotion gives adopters a clear PVP contract without adding Haddock, Nix, and source-
distribution tooling risk. Replacing `lens` with microlens and generic-lens-lite was
rejected because the canonical convention corpus mandates `lens` and `generic-lens`, and
the fleet-wide dependency-closure reduction does not justify the unrequested churn.
