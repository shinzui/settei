---
id: 20
slug: tighten-the-public-surface-and-dependency-hygiene
title: "Tighten the public surface and dependency hygiene"
kind: exec-plan
created_at: 2026-07-19T14:54:49Z
intention: "intention_01kxxdt2m8eysvxggq33jsmt2v"
master_plan: "docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md"
---

# Tighten the public surface and dependency hygiene

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Settei is about to be adopted by roughly 70 codebases (about 50 microservices and 20
applications). Today, the core package `settei` exposes a module named `Settei.Prelude`
that re-exports the entire `Control.Lens` module from the `lens` package, plus the
standard `Prelude` and a few common container types. Under the Haskell Package Versioning
Policy (the "PVP", the community rule that says a package's version number must reflect
changes to its API — see the definition in Context and Orientation below), everything
reachable through an exposed module is part of the package's API. That means every time
the `lens` package adds or changes an export in a minor release, `settei`'s API has
technically changed, and a strict PVP reading forces a `settei` major version bump for a
change nobody in this repository made. Worse, any of the 70 adopting codebases can write
`import Settei.Prelude` and silently couple themselves to the whole lens vocabulary
through a configuration library's prelude.

This plan is a DECISION plan with implementation. Milestone 1 evaluates three options
(keep-but-demote, Cabal public sublibrary, or replace lens with microlens), decides one
(the recommended default is Option 1, keep-but-demote), and records the decision in this
plan and in an amendment to docs/adr/0001-haskell-project-conventions.md. Milestone 2
implements whatever was decided. Milestone 3 writes down, in docs/compatibility.md, the
exact PVP-stable surface adopters may pin against, so that "what is public" is a
documented fact rather than an accident of the module list.

After this plan is complete, a novice adopter can open docs/compatibility.md and read an
explicit statement of which modules are stable API, learn that `Settei.Prelude` is
family-internal plumbing whose exports track `lens` and may change in any release, and
verify that no lens type appears in any public signature — so their own code never needs
`lens` at all. You can see it working by rebuilding the Haddock documentation
(`nix develop -c cabal haddock all` from the repository root) and observing the new
"Internal to the settei package family" warning at the top of the `Settei.Prelude` page,
and by reading the new "Versioning policy" section in docs/compatibility.md.


## Progress

- [ ] Milestone 1: Re-read ADR 0001 in full and confirm the current mandate (exposed
      `Settei.Prelude`, lens + generic-lens across the family).
- [ ] Milestone 1: Run the lens-type signature audit over every exposed module of every
      publishable package and record the result in Surprises & Discoveries.
- [ ] Milestone 1: Check which of EP-15 through EP-19 have landed (masterplan registry
      table plus on-disk evidence) and record the surface actually being audited,
      including whether the settei-formats package from EP-16 exists.
- [ ] Milestone 1: If Option 2 is under serious consideration, run the sublibrary spike
      (temporary `visibility: public` sublibrary, then `nix flake check` and the sdist
      round-trip) and record pass/fail evidence.
- [ ] Milestone 1: Confirm the option choice with the owner, or in their absence adopt
      the recommended default (Option 1); record the decision in the Decision Log.
- [ ] Milestone 2: Implement the decided option (for Option 1: rewrite the
      `Settei.Prelude` Haddock header; for Option 2: restructure into the
      `settei:internal-prelude` sublibrary and update every sibling package's
      build-depends; Option 3 only on explicit owner override).
- [ ] Milestone 2: Audit every publishable package's `exposed-modules` against
      docs/compatibility.md's "Public modules" list and reconcile both directions,
      including settei-formats if it has landed.
- [ ] Milestone 2: Audit dependency bounds across the family for consistency
      (base, containers, text, generic-lens, tasty, tasty-hunit, and intra-family pins)
      and reconcile or record deliberate exceptions.
- [ ] Milestone 2: Update settei/CHANGELOG.md, and the changelog of any other package
      whose cabal metadata changed.
- [ ] Milestone 2: Amend docs/adr/0001-haskell-project-conventions.md with a dated note
      recording the chosen option and the rejected alternatives.
- [ ] Milestone 3: Write the "Versioning policy" (PVP) section in docs/compatibility.md
      and remove `Settei.Prelude` from the supported-module list (Option 1/2) or adjust
      per the decided option.
- [ ] Milestone 3: Rebuild Haddocks and visually confirm the `Settei.Prelude` warning
      and that the compatibility-matrix module list matches the generated documentation.
- [ ] Milestone 3: Run the full validation suite (`cabal build all`, `cabal haddock all`,
      `cabal test all --test-show-details=direct`, `nix flake check`, plus the sdist
      round-trip if Option 2 was chosen) and record the transcripts.
- [ ] Completion: ADR distillation pass; update masterplan Progress rows for EP-20;
      Outcomes & Retrospective written.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Frame this plan as a decision plan with implementation — milestone 1
  evaluates and decides, milestone 2 implements, milestone 3 documents the PVP surface —
  rather than prescribing one packaging change up front.
  Rationale: The three candidate remedies differ in risk and in how much of ADR 0001 they
  overturn. The evaluation itself (the signature audit, the sublibrary spike) produces
  evidence the decision needs; committing to an implementation before that evidence
  exists would be guessing.
  Date: 2026-07-19

- Decision: Record Option 1 (keep `Settei.Prelude` exposed, but demote it out of the
  documented public adoption surface) as the recommended default. The final choice stays
  open until milestone 1: the implementer confirms with the owner, and in the owner's
  absence follows this recommendation.
  Rationale: The sibling packages live in separate Cabal packages and import
  `Settei.Prelude`; a module can only be imported across package boundaries if it is
  exposed, so it cannot simply move to `other-modules`. Documentation-level demotion
  removes the PVP coupling for adopters at near-zero implementation risk, while Options 2
  and 3 carry tooling and churn risk respectively (detailed in Plan of Work).
  Date: 2026-07-19

- Decision: Option 3 (replace lens with microlens/microlens-ghc plus generic-lens-lite
  internally) is documented as a rejected alternative unless the owner explicitly
  overrides.
  Rationale: docs/adr/0001-haskell-project-conventions.md adopts the owner's canonical
  convention corpus, which mandates `lens` and `generic-lens` across the owner's
  projects; the change would touch every module in the family for a dependency-closure
  win the owner has not asked for. Recording it keeps the trade-off visible without
  spending the churn.
  Date: 2026-07-19

- Decision: This plan runs after the API-adding plans EP-15 through EP-19 (soft
  dependencies, per the masterplan registry) and audits whatever surface has actually
  landed at execution time, with an explicit contingency for the settei-formats package
  from EP-16.
  Rationale: Auditing exposed modules and bounds before the API-adding plans land would
  audit a moving target; the masterplan's Decision Log already fixes this ordering, and
  the plan must therefore not hard-code the pre-EP-15 module list as the final answer.
  Date: 2026-07-19

- Decision: The option choice itself. (OPEN — to be resolved in milestone 1 and recorded
  here with rationale, date, and whether the owner confirmed or the default was applied.)
  Rationale: Pending milestone 1 evidence.
  Date: (pending)


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Everything in this section is stated from scratch; you need no prior knowledge of this
repository.

### What Settei is and how the repository is laid out

Settei is a Haskell library family for typed, layered, explainable application
configuration. The repository root is a multi-package Cabal workspace
(`cabal.project` at the root lists the packages) with a Nix flake (`flake.nix`,
`flake.lock`, `nix/`) providing the toolchain. The publishable packages each live in a
same-named top-level directory:

- `settei/` — the core package (declaration language, resolution, provenance, reporting).
- `settei-env/`, `settei-yaml/`, `settei-kdl/`, `settei-dhall/`,
  `settei-optparse-applicative/` — one adapter package per configuration source.
- `examples/settei-cli/`, `examples/settei-service/`, `examples/settei-conformance/` —
  non-published reference applications and conformance tests.

A soft-dependency plan, docs/plans/16-provide-shared-tagged-format-configuration-loading.md
(EP-16), will add a new publishable package (working name `settei-formats`) in its own
top-level directory. As of 2026-07-19, EP-16 is an unfilled skeleton and no
`settei-formats/` directory exists on disk. This plan must re-check that at execution
time (see the contingency in Plan of Work).

### Terms of art

The PVP (Haskell Package Versioning Policy) is the community versioning rule for
Hackage packages. In plain language: a package version has the shape A.B.C.D; if you
remove or change anything a client could already be using — an exported function, a
type, an instance, or the exports of an exposed module — you must bump the major version
(A.B); if you only add things, you must bump at least C. Crucially, the "API" for PVP
purposes is everything reachable through the package's exposed modules, including
re-exports of other packages' modules.

An exposed module is a module listed under `exposed-modules:` in a package's `.cabal`
file; it can be imported by other packages. An `other-modules:` module is internal and
cannot be imported across package boundaries at all.

A re-export is when a module's export list includes `module X`, making everything `X`
exports available to importers. `settei/src/Settei/Prelude.hs` re-exports
`module Control.Lens` (the main module of the `lens` package) and `module X` where `X`
covers `Prelude`, `Data.List.NonEmpty (NonEmpty)`, `GHC.Generics (Generic)`,
`Data.Map.Strict (Map)`, `Data.Set (Set)`, and `Data.Text (Text)`. It hides exactly one
name from `Control.Lens`: the setter type alias `Setting`, which collides with Settei's
own public `Setting` metadata type.

A Cabal public sublibrary is a second library component inside one `.cabal` package,
declared as `library <name>` with `visibility: public`, which other packages can depend
on as `<package>:<name>`. This is relevant to Option 2 below.

Haddock is the Haskell documentation generator; "the Haddock header" of a module is the
`-- |` comment block at the top that becomes the module's documentation page.

### The problem being decided

`Settei.Prelude` is one of the core package's exposed modules
(`settei/settei.cabal`, `exposed-modules:` list, which today reads: `Settei`,
`Settei.Config`, `Settei.Default`, `Settei.Error`, `Settei.Key`, `Settei.Origin`,
`Settei.Prelude`, `Settei.Provenance`, `Settei.Render`, `Settei.Report`,
`Settei.Resolve`, `Settei.Schema`, `Settei.Setting`, `Settei.Source`, `Settei.Value`;
the internal modules `Settei.Internal.Config` and `Settei.Internal.Schema` are correctly
in `other-modules:`). Because `Settei.Prelude` re-exports all of `Control.Lens`, the
PVP-visible API of `settei` includes the entire lens API. Two concrete harms follow.
First, versioning: any `lens` minor release that adds an export changes `settei`'s API
without any settei commit, so strict PVP compliance would force settei major bumps on
lens's schedule. Second, coupling and weight: `lens` is a heavy dependency (it brings a
large transitive closure), every adopting microservice carries it, and adopters do not
need it — the 2026-07-19 API review verified, and this plan's milestone 1 re-verifies,
that settei's public API exports plain accessor functions and no lens types.

`Settei.Prelude` cannot simply be unexposed, because it is imported from five other
Cabal packages' library code and from every test suite and example. The complete list
of importing files outside the core package, verified on 2026-07-19 with
`grep -rn "import Settei.Prelude"`, is:

- `settei-env/src/Settei/Env.hs` and `settei-env/test/Settei/EnvTest.hs`
- `settei-yaml/src/Settei/Yaml.hs` and `settei-yaml/test/Settei/YamlTest.hs`
- `settei-kdl/src/Settei/Kdl.hs`, `settei-kdl/test/Settei/KdlTest.hs`, and
  `settei-kdl/test/Settei/KdlCharacterizationTest.hs`
- `settei-dhall/src/Settei/Dhall.hs` and `settei-dhall/test/Settei/DhallTest.hs`
- `settei-optparse-applicative/src/Settei/Optparse.hs` and
  `settei-optparse-applicative/test/Settei/OptparseTest.hs`
- `examples/settei-cli/src/Settei/Example/Cli.hs`,
  `examples/settei-service/src/Settei/Example/Service.hs`,
  `examples/settei-conformance/test/Settei/Example/ConformanceTest.hs`, and the two
  example test modules `examples/settei-cli/test/Settei/Example/CliTest.hs` and
  `examples/settei-service/test/Settei/Example/ServiceTest.hs`

Within the core package itself, every `settei/src/Settei/*.hs` module (and the two
`Settei.Internal.*` modules) imports it as well. Cross-package imports require an
exposed module (or a public sublibrary), which is why "just hide it" is not an option.

### The documentation surface being corrected

docs/compatibility.md is the release-validated compatibility matrix. Its "Public
modules" section (currently around lines 53–66) lists the supported adoption surface
and today includes `Settei.Prelude` among the "Core focused modules". That is the
statement this plan revises: whatever option is chosen, `Settei.Prelude` must stop being
presented as a module adopters may rely on, and the section must gain an explicit
versioning-policy statement.

docs/release-checklist.md records the project's validation commands. The relevant ones,
all run from the repository root, are `nix develop -c cabal build all`,
`nix develop -c cabal test all --test-show-details=direct`,
`nix develop -c cabal haddock all`, `nix develop -c cabal sdist all` followed by an
unpack-and-build round-trip in a temporary directory, `cabal check` per package
directory, and `nix flake check`.

### Relevant ADRs (consulted 2026-07-19)

- docs/adr/0001-haskell-project-conventions.md — directly governs this plan. Its
  Decision section currently MANDATES that "The core package exposes `Settei.Prelude`"
  re-exporting `Control.Lens` minus the `Setting` alias, and that "The core package
  depends on `lens` and `generic-lens`", with adapters declaring `generic-lens`
  directly. Any change this plan makes to the prelude's exposure, its documented status,
  or the lens dependency is an amendment to ADR 0001 — a dated note added to that file —
  never a silent deviation. The ADR also records that the convention corpus
  (`shinzui/haskell-jitsurei` via Mori) is the source of the lens mandate, which is why
  Option 3 is not recommended.
- docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md —
  the examples under `examples/` are the conformance boundary for the public API; this
  plan keeps example edits to at most mechanical build-depends changes (Option 2 only)
  and leaves the coherent example sweep to EP-21, per the masterplan's Integration
  Points.
- The parent masterplan,
  docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md, is the
  final authority on exposed modules, dependency bounds, and the PVP statement (its
  Integration Points section names EP-20 as that authority) and schedules this plan
  after EP-15 through EP-19 as soft dependencies.
- No other ADR (0002 through 0006) bears on packaging or the prelude; they cover the
  configuration algebra and adapter input semantics and were scanned but not needed.

### Planning-time audit snapshot (2026-07-19, before EP-15..EP-19)

These facts were verified while writing this plan and give the implementer a baseline;
milestone 1 re-verifies them against the tree that actually exists at execution time.

Lens-type spot check: a source grep over every exposed library module in `settei/src`
and all five adapter `src` trees for the lens vocabulary types (`Lens'`, `Traversal'`,
`Prism'`, `Iso'`, `Getter`, `Fold`, `ASetter`, `Getting`, `LensLike`) found no
occurrence outside `settei/src/Settei/Prelude.hs` itself. A companion grep for
`makeLenses`/`makePrisms`/`makeClassy` (Template Haskell lens generators) found none,
and a scan of `instance` declarations found no instances of lens typeclasses in any
library module (the only noteworthy instance is `Selective Config` in
`settei/src/Settei/Internal/Config.hs`, which references the `selective` package, not
lens). This supports — but does not yet formally establish, since export lists and
Haddock-rendered signatures must also be checked — the claim that lens types do not
appear in any public signature.

Dependency-bounds snapshot: across `settei/settei.cabal` and the five adapter cabal
files, the shared bounds are currently consistent: `base >=4.21 && <5`,
`containers >=0.6.8 && <0.8`, `text >=2.1 && <2.2`, `generic-lens >=2.2 && <2.4`,
`tasty >=1.5 && <1.6`, `tasty-hunit >=0.10.2 && <0.11`. Only the core declares
`lens >=5.3 && <5.4`; no adapter declares `lens` directly (consistent with ADR 0001).
Two deliberate-looking irregularities to re-examine in milestone 2: (a) the two
`settei-dhall` test suites depend on `microlens >=0.4.14 && <0.6` — a lens-family
exception inside the very family whose ADR mandates `lens`, apparently a leftover from
the Dhall prototype spike; (b) every adapter pins the core exactly
(`settei ==0.1.0.0`), an intra-family exact pin that is fine pre-release but must be
consciously affirmed or revised in the PVP statement. The example packages' bounds were
not enumerated at planning time; the milestone 2 audit procedure covers them. All
packages declare `cabal-version: 3.8`, which matters for Option 2 (public sublibraries
require cabal-version 3.4 or newer, so 3.8 is sufficient).


## Plan of Work

The work is three milestones: decide, implement, document. Each is independently
verifiable and each ends with the full workspace still building and testing green.

### Milestone 1 — Evaluate the options, decide, and record the decision

Scope: no production code changes land in this milestone except an optional, clearly
temporary spike for Option 2. At the end of the milestone, the Decision Log in this plan
contains the chosen option with rationale, the signature audit result is recorded in
Surprises & Discoveries, and the surface being audited (which of EP-15 through EP-19
landed, whether settei-formats exists) is written down.

First, establish the ground truth. Re-read docs/adr/0001-haskell-project-conventions.md
in full so you know exactly what you would be amending. Check the masterplan registry
table in docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md for
the status of EP-15 through EP-19, and confirm on disk: does a `settei-formats/`
directory (or whatever package name EP-16's own plan records) exist with a `.cabal`
file? Do `settei/settei.cabal`'s exposed modules differ from the fifteen listed in
Context and Orientation? Record what you find.

Second, run the lens-type signature audit. The claim to verify is: "no lens type
appears in any public signature of any publishable package." The audit procedure is in
Concrete Steps; in summary, you grep every exposed module's source for the lens
vocabulary, inspect each exposed module's explicit export list, build Haddocks and
inspect the rendered signatures of every exported name, and check exported instances.
Record the outcome — pass, or the exact offending signatures — in Surprises &
Discoveries. If the audit fails (some public signature mentions a lens type), Option 1's
premise is weakened: the PVP statement cannot claim lens-freedom, and you must either
refactor that signature to a plain function (small, preferred) or record the exception
explicitly in the PVP paragraph. Do not proceed to milestone 3 with an unverified claim.

Third, weigh the three options honestly.

Option 1 (recommended default): keep `Settei.Prelude` exposed, demote it from the
documented public surface. The prelude stays in `exposed-modules:` because the five
sibling packages need cross-package imports of it. What changes is its documented
status: its Haddock header gains a prominent warning — "Internal to the settei package
family — not part of the PVP-stable API; re-exports track lens and may change in any
release" — it is removed from docs/compatibility.md's supported-module list, and the new
PVP policy paragraph states that settei's stable surface is the listed modules minus
`Settei.Prelude`, and that lens types appear in no public signature (as verified by the
audit). Trade-offs, stated honestly: this is a documentation-level fix. Nothing
technically prevents an adopter from importing `Settei.Prelude` anyway; the protection
is the documented contract plus the loud Haddock warning, which is exactly how many
mature Hackage packages (e.g. `*.Internal` modules) handle the same tension. The lens
build dependency also remains in every consumer's closure — Option 1 fixes the PVP and
coupling story, not the build weight. In exchange, the change is tiny, riskless,
reversible, and requires no restructuring; ADR 0001 is amended only in the prelude's
documented status, not in its existence or the lens convention.

Option 2: move `Settei.Prelude` into a Cabal public sublibrary of the `settei` package
— a `library internal-prelude` stanza with `visibility: public` in
`settei/settei.cabal`, consumed by the sibling packages via
`build-depends: settei:internal-prelude`. This makes the demotion structural: the main
`settei` library's exposed modules no longer include the prelude at all, so the PVP
surface of `settei` proper is mechanically lens-free, while siblings keep their imports
by depending on the named sublibrary. Feasibility, honestly assessed: public
sublibraries require `cabal-version: 3.4` or newer and every package here declares 3.8,
so Cabal itself is fine; Hackage has accepted public sublibraries since roughly
hackage-server 1.7. But tooling friction is real: Haddock generation for sublibraries,
the nixpkgs Haskell builder (`nix/` and `flake.nix` here build each package with the
standard nixpkgs machinery, which has historically had uneven sublibrary support), and
doctest-style tooling all have known rough edges. The lens dependency also still ships —
it moves to the sublibrary that everything in the family depends on, so consumer
closures are unchanged. And adopters who (against advice) imported `Settei.Prelude`
break loudly, which is arguably a feature but is a breaking change. Because of the
tooling risk, Option 2 must not be chosen on paper: milestone 1 includes a spike task —
create the sublibrary stanza, point the siblings at it, and run `nix flake check` plus
the sdist round-trip from docs/release-checklist.md. If the spike fails or fights the
Nix infrastructure, fall back to Option 1 and record the failure evidence in Surprises &
Discoveries. The spike is temporary: revert it fully (git checkout of the touched files)
before milestone 2 unless Option 2 is chosen.

Option 3 (documented rejected alternative — do not implement without explicit owner
override): replace `lens` with `microlens`/`microlens-ghc` and `generic-lens-lite`
internally, shrinking the dependency closure for all 70 adopters. Why it is not
recommended now: ADR 0001 adopts the owner's convention corpus, which mandates `lens`
and `generic-lens` across the owner's projects — this option overturns a deliberate,
recorded, cross-project convention; the churn touches every module in the family
(every module imports `Settei.Prelude`, and operator/type availability differs between
lens and microlens, so this is not a one-line swap); and the payoff is a build-closure
reduction the owner has not asked for and may not value against convention uniformity.
If the owner overrides, this plan must be revised (Revision Protocol note at the bottom)
with a concrete migration milestone before any implementation; as written, this plan
only records the rejection in the ADR 0001 amendment.

Fourth, decide. Ask the owner to choose, presenting the trade-offs above and the audit
and spike evidence. If the owner is unavailable, adopt Option 1 (the recorded
recommended default). Fill in the open Decision Log entry with the choice, the
rationale, whether the owner confirmed, and the date. Milestone 1 is complete when the
Decision Log entry is filled, the audit result is recorded, and (if the spike ran) its
evidence is captured.

### Milestone 2 — Implement the decision and reconcile the family's metadata

Scope: the decided option is implemented; the exposed-modules and dependency-bounds
audits are performed and reconciled; changelogs and ADR 0001 are updated. At the end,
`nix develop -c cabal build all` and the test suite are green and the metadata across
all publishable packages is consistent.

If Option 1 was chosen, the code change is exactly one file:
`settei/src/Settei/Prelude.hs` gets a rewritten Haddock header (exact text in Concrete
Steps) marking it internal to the package family. No cabal file changes for the prelude
itself. Then update `settei/CHANGELOG.md` with an entry noting that `Settei.Prelude` is
reclassified as family-internal and excluded from the PVP-stable surface (a
documentation-level change, so no version-component implication beyond the pending
release notes).

If Option 2 was chosen, restructure `settei/settei.cabal`: add a
`library internal-prelude` stanza with `visibility: public`, its own `hs-source-dirs`
(move `settei/src/Settei/Prelude.hs` to, say, `settei/prelude-src/Settei/Prelude.hs` so
the two libraries do not share a source directory), the `common common` import, and
build-depends `base`, `containers`, `lens`, `text`; make the main library depend on
`settei:internal-prelude` and remove `Settei.Prelude` from its `exposed-modules`; add
`, settei:internal-prelude` to the build-depends of every component that imports the
prelude in `settei-env/settei-env.cabal`, `settei-yaml/settei-yaml.cabal`,
`settei-kdl/settei-kdl.cabal`, `settei-dhall/settei-dhall.cabal`,
`settei-optparse-applicative/settei-optparse-applicative.cabal`, the three
`examples/*/settei-example-*.cabal` files, and the core's own test-suite stanza; and
verify the Nix packaging (`nix/`, `flake.nix`) still evaluates. Every package whose
cabal file changed gets a changelog entry. Note the sdist round-trip becomes mandatory
validation for this option.

Under either option, then perform the two audits.

Exposed-modules reconciliation: enumerate `exposed-modules:` from every publishable
package's cabal file (command in Concrete Steps) and diff the union against
docs/compatibility.md's "Public modules" section. Reconcile in both directions: modules
exposed but not listed get either listed (if they are meant to be public — anything
EP-15 through EP-19 added, such as new core modules or the settei-formats modules if
that package landed) or justified as intentionally undocumented (there should be none;
`Settei.Internal.*` must remain in `other-modules`, which the release checklist already
asserts); modules listed but not exposed are documentation bugs to fix. Contingency: if
EP-16's settei-formats package has landed, its exposed modules MUST be added to the
compatibility list and its cabal file included in the bounds audit and changelog pass;
if it has not landed, record that in this plan's Progress notes and leave a one-line
remark in the compatibility matrix's versioning section that the list reflects the
packages released at that date (EP-21 performs the final sweep regardless).

Dependency-bounds reconciliation: extract every `build-depends` block across all
publishable packages (and the examples, which per ADR 0001 must still declare
`generic-lens` directly where they use labels) and compare ranges per dependency. The
planning-time snapshot (Context and Orientation) says base/containers/text/generic-lens/
tasty/tasty-hunit are already uniform; verify that is still true after EP-15..EP-19, and
resolve the two known irregularities: decide whether the `settei-dhall` test-suite
`microlens` dependency should be replaced with `lens` (recommended, for ADR 0001
consistency — it is test-only, so the change is low-risk; if kept, record why in the
Decision Log), and affirm or revise the `settei ==0.1.0.0` intra-family exact pins
(recommendation: keep exact intra-family pins pre-Hackage-release and say so in the PVP
paragraph, since the family releases in lockstep from one repository). Any bound
widened or changed must respect ADR 0001's rule that release selection checks Hackage
and upstream tags, not just the local Mori corpus.

Finally, amend docs/adr/0001-haskell-project-conventions.md: add the current date to
its `Amended:` line and append a dated paragraph to the Decision section (and a matching
note under Rejected Alternatives) recording the chosen option — for Option 1, that
`Settei.Prelude` remains exposed for intra-family imports but is documented as internal
to the package family and excluded from the PVP-stable surface; for Option 2, the
sublibrary structure — and recording the not-chosen options as rejected alternatives
with their one-line rationales (Option 3's lens-convention rationale in particular).

### Milestone 3 — Document the PVP surface and validate everything

Scope: docs/compatibility.md gains the explicit versioning policy; the module list is
final; Haddocks are rebuilt and inspected; the full validation suite runs green.

Edit docs/compatibility.md's "Public modules" section: remove `Settei.Prelude` from the
"Core focused modules" line (Option 1/2), add any modules from landed EP-15..EP-19
work and settei-formats, and append a new subsection titled "Versioning policy" whose
exact draft text is in Concrete Steps. The paragraph must state: what adopters may pin
(the listed modules of the listed packages, under PVP semantics); what is internal
(`Settei.Prelude`, everything under `Settei.Internal`, all `examples/` packages, and —
if Option 2 — the `settei:internal-prelude` sublibrary); the lens statement backed by
the milestone 1 audit (lens types appear in no public signature, so adopters never need
lens in their own build-depends); the intra-family pin policy; and how deprecations
will be announced (a `DEPRECATED` pragma plus a changelog entry at least one major
release before removal).

Then rebuild documentation and verify by observation: run
`nix develop -c cabal haddock all` (this is the project's actual haddock command,
confirmed in docs/release-checklist.md), open the generated `Settei.Prelude` page under
`dist-newstyle/build/.../doc/html/settei/Settei-Prelude.html`, and confirm the internal
warning renders; cross-check that every module named in the compatibility list has a
generated page and no public page exists that the list omits. Then run the full
validation suite from Validation and Acceptance. Milestone 3 — and the plan — is
complete when all commands pass, the masterplan's two EP-20 progress rows are checked,
and the ADR distillation pass and Outcomes & Retrospective entry are written.


## Concrete Steps

All commands run from the repository root, /Users/shinzui/Keikaku/bokuno/settei, unless
stated otherwise. Every commit in this plan uses Conventional Commits (types such as
`docs:`, `feat:`, `chore:`, with an optional scope) and MUST carry these three git
trailers, exactly as written, at the end of the commit message body:

```text
MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/20-tighten-the-public-surface-and-dependency-hygiene.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

For example, a milestone 2 Option 1 commit message would look like:

```text
docs(settei): mark Settei.Prelude internal to the package family

Reclassify the shared prelude out of the PVP-stable surface per EP-20
milestone 1 decision; adopters should import the documented modules only.

MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/20-tighten-the-public-surface-and-dependency-hygiene.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

Commit at every coherent stopping point (audit recorded, decision recorded, each
implementation edit, each doc edit); do not create a feature branch — commit to the
current branch per the repository's convention.

### Step 1 — Ground truth (milestone 1)

Read docs/adr/0001-haskell-project-conventions.md in full. Then check which sibling
plans landed and whether settei-formats exists:

```bash
grep -n "| 1[5-9] " docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ls -d settei-formats 2>/dev/null || echo "settei-formats: not present"
find . -maxdepth 2 -name '*.cabal' -not -path './dist-newstyle/*' -not -path './mori/*'
```

Record in Progress which plans landed and which package set you are auditing.

### Step 2 — Lens-type signature audit (milestone 1)

The claim: no lens type appears in any public signature. Run each check and record
results in Surprises & Discoveries.

First, the source-level vocabulary grep over every publishable library source tree
(add `settei-formats/src` if it exists):

```bash
grep -rnE "Lens'|Traversal'|Prism'|Iso'|Getter|Fold |ASetter|Getting|LensLike|Optic'" \
  settei/src settei-env/src settei-yaml/src settei-kdl/src settei-dhall/src \
  settei-optparse-applicative/src --include='*.hs' | grep -v "Settei/Prelude.hs"
```

Expected output: nothing (exit status 1). Any hit outside `Settei/Prelude.hs` must be
inspected: is the name in an exported signature? Second, check for Template Haskell lens
generation and lens-class instances:

```bash
grep -rn "makeLenses\|makePrisms\|makeClassy" settei/src settei-*/src --include='*.hs'
grep -rnE "^instance (Ixed|At|Each|Wrapped|Field[0-9]|Plated|AsEmpty)" \
  settei/src settei-*/src --include='*.hs'
```

Expected output: nothing from both. Third, the authoritative check — read each exposed
module's explicit export list (every module under `settei/src/Settei/` except
`Internal/`, plus the single exposed module of each adapter) and confirm each exported
name's type signature mentions no lens type; then build Haddocks and spot-verify the
rendered signatures match:

```bash
nix develop -c cabal haddock all
```

The generated HTML lands under `dist-newstyle/build/<platform>/ghc-9.12.4/<pkg>-0.1.0.0/doc/html/`.
Record the audit verdict as a dated entry in Surprises & Discoveries, for example:

```text
2026-07-XX signature audit: PASS — no lens type, TH splice, or lens-class instance in
any exposed module of settei, settei-env, settei-yaml, settei-kdl, settei-dhall,
settei-optparse-applicative[, settei-formats]. Evidence: greps above returned no hits;
export lists inspected module-by-module.
```

### Step 3 — Option 2 spike (milestone 1, only if Option 2 is under consideration)

Make the temporary edits described in Plan of Work milestone 2 (Option 2 paragraph) to
`settei/settei.cabal` and one downstream package (settei-env is the smallest), then:

```bash
nix develop -c cabal build settei settei-env
nix flake check
nix develop -c cabal sdist settei
mkdir -p /private/tmp/claude-501/-Users-shinzui-Keikaku-bokuno-settei/408bb322-0fbf-4387-b27e-75ead6a482d4/scratchpad/sdist-spike
tar -xzf dist-newstyle/sdist/settei-0.1.0.0.tar.gz \
  -C /private/tmp/claude-501/-Users-shinzui-Keikaku-bokuno-settei/408bb322-0fbf-4387-b27e-75ead6a482d4/scratchpad/sdist-spike
```

Then attempt a build of the unpacked sdist in that directory with the workspace's GHC.
Success criteria: all four steps pass and Haddock still generates a page set for both
libraries. On any failure, capture the error output into Surprises & Discoveries,
revert the spike completely (`git checkout -- settei/settei.cabal settei-env/settei-env.cabal`
plus restoring any moved file), and fall back to Option 1.

### Step 4 — Record the decision (milestone 1)

Confirm with the owner or apply the default; replace the open Decision Log entry in
this file with the resolved decision, rationale, evidence pointers, and date. Commit:

```text
docs(plans): record EP-20 public-surface decision

MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/20-tighten-the-public-surface-and-dependency-hygiene.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

### Step 5 — Implement Option 1 (milestone 2; skip if Option 2 chosen)

Edit `settei/src/Settei/Prelude.hs`, replacing the current header comment (the
`-- |` block spanning lines 3–5) with:

```haskell
-- |
-- Module: Settei.Prelude
-- Description: Internal shared prelude for the settei package family.
--
-- __Internal to the settei package family — not part of the PVP-stable API.__
--
-- This module exists so that the settei core, its sibling adapter packages,
-- and the reference applications share one import baseline. It re-exports
-- the full "Control.Lens" surface (hiding the lens @Setting@ type alias,
-- which collides with Settei's own 'Settei.Setting.Setting') together with
-- "Prelude" and a few common types. Because its exports track the @lens@
-- package, they may change in any settei release, including patch releases.
-- Code outside this repository must not import this module; the supported
-- adoption surface is listed in the compatibility matrix
-- (@docs/compatibility.md@ in the source distribution).
```

No other line of the module changes. Update `settei/CHANGELOG.md` (add under the
unreleased/current version heading):

```text
- `Settei.Prelude` is now documented as internal to the settei package family and is
  excluded from the PVP-stable public surface; adopters should import the documented
  public modules instead. Its exports track the `lens` package and may change in any
  release.
```

Commit as shown in the example at the top of this section.

### Step 6 — Implement Option 2 (milestone 2; only if chosen)

Promote the spike edits properly across all packages listed in Plan of Work milestone 2
(five adapters, three examples, the core test-suite), move
`settei/src/Settei/Prelude.hs` to `settei/prelude-src/Settei/Prelude.hs`, update
`nix/` and `flake.nix` as needed, add changelog entries to every package whose cabal
file changed, and re-run the full spike validation plus
`nix develop -c cabal build all`. Use one commit per package or one family-wide commit
(`feat(settei)!: move Settei.Prelude to a public sublibrary` — note the `!`, since this
is API-breaking for anyone importing the prelude from `settei` directly), always with
the three trailers.

### Step 7 — Exposed-modules reconciliation (milestone 2)

Enumerate the exposed modules of every publishable package:

```bash
for f in settei/settei.cabal settei-env/settei-env.cabal settei-yaml/settei-yaml.cabal \
         settei-kdl/settei-kdl.cabal settei-dhall/settei-dhall.cabal \
         settei-optparse-applicative/settei-optparse-applicative.cabal; do
  echo "== $f"
  sed -n '/exposed-modules:/,/other-modules:\|build-depends:/p' "$f"
done
```

(Include `settei-formats/settei-formats.cabal` if it exists.) Diff the result by hand
against the "Public modules" section of docs/compatibility.md and fix both directions
as described in Plan of Work. Also confirm `Settei.Internal.Config` and
`Settei.Internal.Schema` (and any Internal modules added by EP-15..EP-19) remain in
`other-modules:`. Commit any compatibility-list fix as
`docs(compatibility): reconcile public module list with exposed-modules` with the
trailers.

### Step 8 — Dependency-bounds reconciliation (milestone 2)

Extract all bounds and compare per dependency:

```bash
grep -hE '^\s*,?\s*[a-z][a-zA-Z0-9-]*\s+(>=|==|\^>=)' \
  settei/settei.cabal settei-*/*.cabal examples/*/*.cabal | sort | uniq -c | sort -rn
```

Every dependency name should map to exactly one range across the family. For each
mismatch, decide the canonical range (prefer the range already validated in
docs/compatibility.md's "Libraries and adapters" table), edit the outlier cabal files,
and note the change in the owning package's CHANGELOG.md. Explicitly resolve the two
known items: the `settei-dhall` test-suite `microlens` dependency (recommended: replace
with `lens >=5.3 && <5.4` and delete the microlens lines, keeping the tests compiling —
they use only basic optics that lens also provides; if that fails, keep microlens and
record why) and the `settei ==0.1.0.0` intra-family pins (recommended: keep, and state
the lockstep-release policy in the PVP paragraph). Any widened bound must be checked
against current Hackage releases and upstream tags first, per ADR 0001. Commit as
`chore(cabal): reconcile dependency bounds across the package family` with the trailers.

### Step 9 — Amend ADR 0001 (milestone 2)

In docs/adr/0001-haskell-project-conventions.md: append the current date to the
`Amended:` line near the top; append to the Decision section a dated paragraph, for
Option 1 for example:

```text
Amendment (2026-07-XX, EP-20): `Settei.Prelude` remains an exposed module because the
sibling packages import it across Cabal package boundaries, but it is now documented as
internal to the settei package family and is excluded from the PVP-stable public
surface recorded in docs/compatibility.md. Its re-exports track the `lens` package and
may change in any release. The `lens` and `generic-lens` conventions are unchanged.
```

and append to Rejected Alternatives the not-chosen options: moving the prelude to a
public sublibrary (if Option 1 chosen: rejected for now because the documentation-level
demotion achieves the PVP goal without sublibrary tooling risk in Haddock/Nix/sdist —
or cite the spike failure evidence), and replacing lens with microlens/generic-lens-lite
(rejected because the convention corpus mandates lens across the owner's projects and
the fleet-wide churn is not justified by an unrequested closure reduction). Commit as
`docs(adr): amend ADR 0001 with the EP-20 public-surface decision` with the trailers.

### Step 10 — PVP policy section in docs/compatibility.md (milestone 3)

Remove `Settei.Prelude` from the "Core focused modules" list, add any newly landed
public modules, and append after the existing closing paragraph of "Public modules":

```markdown
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
```

Adjust the prelude sentence if Option 2 was chosen (it then reads that the prelude
lives in the `settei:internal-prelude` public sublibrary, which is likewise not part of
the stable surface), and qualify the lens-freedom sentence if the milestone 1 audit
found exceptions. Commit as
`docs(compatibility): state the PVP-stable surface and versioning policy` with the
trailers.

### Step 11 — Full validation and closure (milestone 3)

Run the commands in Validation and Acceptance, capture short transcripts into this
plan, check off the Progress items, update the masterplan's two EP-20 Progress rows and
its registry Status cell, perform the ADR distillation pass (confirm the ADR 0001
amendment covers everything durable; no other ADR should be needed unless Option 2
introduced a new packaging pattern worth its own ADR), and write the Outcomes &
Retrospective entry. Final commit:
`docs(plans): complete EP-20 with validation evidence` with the trailers.


## Validation and Acceptance

All commands run from the repository root. The project's validated command forms are
taken from docs/release-checklist.md.

```bash
nix develop -c cabal build all
nix develop -c cabal haddock all
nix develop -c cabal test all --test-show-details=direct
nix flake check
```

Expected results: `cabal build all` compiles every package with no warnings beyond the
pre-existing baseline; `cabal haddock all` ends with "Documentation created" lines for
every package and zero Haddock parse errors (the rewritten `Settei.Prelude` header is a
common place to break Haddock markup — a failure here most likely means an unescaped
character in the new comment); the test run prints per-suite `All N tests passed`
summaries and exits zero; `nix flake check` completes without error (for Option 2 this
is the critical gate, since it exercises the Nix package builds against the sublibrary
layout).

If Option 2 was chosen, additionally run the sdist round-trip exactly as the release
checklist prescribes: `nix develop -c cabal sdist all`, unpack each publishable
tarball into a fresh temporary directory under the scratchpad, and build each from its
own contents; also run `cabal check` in every package directory and expect
"No errors or warnings could be found in the package."

Behavioral acceptance, beyond green commands:

1. Open the generated Haddock page for `Settei.Prelude`. It must display, at the top of
   the module documentation, the bolded sentence "Internal to the settei package family
   — not part of the PVP-stable API." (Option 1), or the module must appear only under
   the `internal-prelude` sublibrary's documentation (Option 2).
2. Open docs/compatibility.md. The "Public modules" section must not list
   `Settei.Prelude`, and the "Versioning policy" subsection must be present and must
   state the pinnable surface, the internal surface, the lens-signature claim with its
   audit provenance, the intra-family pin policy, and the deprecation announcement rule.
3. Cross-check: every module named in the compatibility list corresponds to an
   `exposed-modules:` entry in exactly one publishable package's cabal file, and vice
   versa (with `Settei.Prelude` as the sole documented exception in the Option 1
   layout). The Step 7 enumeration command is the checkable procedure.
4. docs/adr/0001-haskell-project-conventions.md contains the dated amendment paragraph
   and the updated rejected-alternatives entries, and its `Amended:` line includes the
   new date.
5. `settei/CHANGELOG.md` (and, under Option 2, every touched package's changelog)
   records the change.
6. This plan's Decision Log contains the resolved option decision, Surprises &
   Discoveries contains the signature-audit verdict (and spike evidence if run), and
   Progress is fully checked.


## Idempotence and Recovery

Every step in this plan is safe to repeat. The audits (Steps 1, 2, 7, 8) are read-only
and can be re-run at any time; re-running them after upstream plans land is in fact
required. The documentation edits (Steps 5, 9, 10) are plain-text file edits — applying
them twice is a no-op, and any misstep is recoverable with `git checkout -- <file>` or
`git revert` of the offending commit, since every step commits separately.

The Option 2 spike (Step 3) is the only step that temporarily destabilizes the build,
and it is explicitly bounded: it touches `settei/settei.cabal`, one downstream cabal
file, and possibly a moved source file, and it must be fully reverted with git before
milestone 2 begins unless Option 2 is chosen. If a spike is interrupted midway, `git
status` shows exactly the touched files; restore them and re-run
`nix develop -c cabal build all` to confirm the tree is back to green.

Nothing in this plan is destructive to data, and no migration is involved. The riskiest
irreversible act would be publishing to Hackage, which is explicitly out of scope
(docs/release-checklist.md gates publication behind separate authorization). If the
bounds reconciliation (Step 8) breaks the solver (`cabal build all` fails to find an
install plan), revert the single cabal edit that introduced the failure and re-examine
the canonical range against docs/compatibility.md before retrying. If the sdist
round-trip fails under Option 2, that is the designated fallback trigger: revert to the
Option 1 implementation, update the Decision Log, and amend ADR 0001 accordingly — the
plan's structure (decision recorded separately from implementation) exists precisely so
this fallback is a small, documented pivot rather than a restart.


## Interfaces and Dependencies

No new library dependencies are introduced by Option 1; its whole effect is
documentation and metadata. The files owned by this plan are:
`settei/src/Settei/Prelude.hs` (Haddock header only, Option 1),
`settei/settei.cabal` and the five adapter plus three example cabal files (bounds
reconciliation always; build-depends restructuring only under Option 2),
`docs/compatibility.md` (module list and the new Versioning policy subsection),
`docs/adr/0001-haskell-project-conventions.md` (dated amendment),
`settei/CHANGELOG.md` and sibling changelogs (as touched), and this plan file. Under
Option 2 the plan additionally owns the `library internal-prelude` stanza in
`settei/settei.cabal`, the moved source at `settei/prelude-src/Settei/Prelude.hs`, and
whatever `nix/`/`flake.nix` adjustments the Nix builder needs.

At the end of milestone 2, the following must hold at the interface level. Under
Option 1, `settei`'s `exposed-modules` still include `Settei.Prelude` (unchanged module
name, unchanged export list: `module X` re-exports of Prelude, `NonEmpty`, `Generic`,
`Map`, `Set`, `Text`, plus `module Control.Lens` hiding `Setting`), so every existing
`import Settei.Prelude` in the family continues to compile with zero source changes.
Under Option 2, the module `Settei.Prelude` with that same export list is provided by
the public sublibrary `settei:internal-prelude` (Cabal dependency syntax:
`build-depends: settei:internal-prelude ==0.1.0.0`), the main `settei` library depends
on it and no longer exposes the module itself, and every family component that imports
the prelude names the sublibrary in its build-depends. No exported Haskell type or
function signature changes under either option; this plan deliberately introduces no
new types.

The dependency ranges this plan treats as canonical (from the planning-time snapshot,
to be re-verified in Step 8 against the executed tree and against current Hackage
releases per ADR 0001): `base >=4.21 && <5`, `containers >=0.6.8 && <0.8`,
`text >=2.1 && <2.2`, `generic-lens >=2.2 && <2.4`, `lens >=5.3 && <5.4` (core only —
and, if Step 8 adopts the recommendation, the settei-dhall test suites),
`tasty >=1.5 && <1.6`, `tasty-hunit >=0.10.2 && <0.11`, and exact intra-family pins
`settei ==0.1.0.0` (and sibling equivalents) while the family releases in lockstep.
Adapter-specific ranges (yaml/kdl/dhall/optparse-applicative stacks) are out of this
plan's scope except where the family-wide dependencies above appear alongside them; the
compatibility matrix's "Libraries and adapters" table remains their authority. External
services: none. Toolchain: GHC 9.12.4 via `nix develop`, Cabal CLI 3.16.1.0, as
recorded in docs/compatibility.md's Toolchain table.
