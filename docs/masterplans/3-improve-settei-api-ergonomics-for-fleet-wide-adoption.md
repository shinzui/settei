---
id: 3
slug: improve-settei-api-ergonomics-for-fleet-wide-adoption
title: "Improve Settei API ergonomics for fleet-wide adoption"
kind: master-plan
created_at: 2026-07-19T14:54:04Z
intention: "intention_01kxxdt2m8eysvxggq33jsmt2v"
---

# Improve Settei API ergonomics for fleet-wide adoption

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

Settei is about to be adopted by roughly 50 microservices and 20 applications. A
2026-07-19 API review found no ergonomics blocker, but it identified boilerplate that every
adopting codebase would otherwise copy-paste — the two reference applications under
examples/ already duplicate decoder definitions, format-dispatch code, and error
formatting between themselves. After this initiative is complete, the following holds:

- `Decoder` has a `Functor` instance and a combinator kit (list decoding, parser-backed
  decoding for types like URIs and durations, and friends), so a newtype-wrapping decoder
  is `SecretText <$> textDecoder` instead of a hand-written case expression.
- Multi-format applications get tagged `FORMAT:PATH` config inputs and a ready-made
  loader that dispatches to the YAML, KDL, and Dhall adapters, instead of every app
  hand-rolling the same `ReadM` parser and three-way dispatch.
- Every adapter error type (`YamlSourceError`, `KdlSourceError`, `DhallSourceError`,
  `EnvError`) has a text renderer matching the core's `renderErrorsText` tone, so no
  application prints Haskell `Show` output to operators.
- Environment bindings are validated once at construction, making source assembly total:
  no more unreachable `Left` branches or `error (show problems)` in application code.
- Declaring conditional configuration and rendered defaults needs no raw
  `Control.Selective.select` encoding and no easily-forgotten renderer plumbing.
- The public surface is deliberate: the `Settei.Prelude` exposure and the lens dependency
  footprint are explicitly decided and documented, and the compatibility matrix states the
  PVP surface adopters may rely on.
- The reusable command-line options cover the modes real services need (`--check-config`,
  `--describe-config`), warnings are actually rendered by the reference applications, and
  all guides teach the new APIs. Docs and examples updates are in scope for every child
  plan, and the final child plan performs the complete docs-and-examples sweep.

Out of scope: the correctness fixes tracked in
docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md (which must land
first), Hackage publication, configuration hot-reload, and any Kubernetes cluster client.


## Decomposition Strategy

The review's ergonomics findings group into six functional concerns plus one final sweep:

1. Decoder composition (Functor plus combinators) is a self-contained core `Settei.Value`
   extension whose success is measurable by deleting duplicated decoder code from both
   reference applications.
2. Tagged-format loading is a new deliverable — a small umbrella package — because
   settei-optparse-applicative must not depend on the YAML, KDL, and Dhall adapters, yet
   the dispatch code needs all three. A new package keeps the dependency direction clean.
3. Adapter error renderers are one concern spanning four packages: the same rendering
   contract (secret-safe, operator-readable, one line per problem) applied uniformly.
4. Environment binding totality is an API reshaping of settei-env alone.
5. Declaration sugar (selective conditionals, rendered defaults) is a core
   declaration-language concern, distinct from decoding.
6. Public-surface hygiene (Settei.Prelude exposure, lens footprint, PVP statement) is a
   packaging concern that touches every package's cabal file and is deliberately
   scheduled after the API-adding plans so it re-verifies the final surface.
7. The final sweep extends the reusable CLI options and reconciles every guide, example,
   fixture, and changelog, because the reference applications are the public-API
   conformance boundary (docs/adr/0007).

Relevant ADRs consulted: docs/adr/0001-haskell-project-conventions.md (mandates the lens
convention and the exposed Settei.Prelude — EP-20 amends it if the decision changes),
docs/adr/0002-inspectable-configuration-algebra.md (the declaration algebra EP-19 extends;
no Monad instance may be introduced), docs/adr/0003-resolution-provenance-and-default-semantics.md
(renderer and redaction rules EP-15, EP-17, and EP-19 must preserve),
docs/adr/0004-yaml-input-semantics.md, docs/adr/0005-canonical-kdl-v2-input-semantics.md,
and docs/adr/0006-dhall-input-import-and-provenance-semantics.md (adapter error
vocabularies EP-17 renders), and
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md (EP-21's
authority).


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 15 | Add a Decoder functor and combinator kit | docs/plans/15-add-a-decoder-functor-and-combinator-kit.md | None | None | Complete |
| 16 | Provide shared tagged-format configuration loading | docs/plans/16-provide-shared-tagged-format-configuration-loading.md | None | EP-17 | Complete |
| 17 | Add error renderers to every source adapter | docs/plans/17-add-error-renderers-to-every-source-adapter.md | None | None | Complete |
| 18 | Make environment bindings total and validated | docs/plans/18-make-environment-bindings-total-and-validated.md | None | EP-17 | Complete |
| 19 | Add declaration sugar for conditionals and rendered defaults | docs/plans/19-add-declaration-sugar-for-conditionals-and-rendered-defaults.md | None | None | Complete |
| 20 | Tighten the public surface and dependency hygiene | docs/plans/20-tighten-the-public-surface-and-dependency-hygiene.md | None | EP-15, EP-16, EP-17, EP-18, EP-19 | Complete |
| 21 | Extend reusable CLI options and complete the ergonomics docs sweep | docs/plans/21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md | EP-15, EP-16, EP-17, EP-18, EP-19 | EP-20 | Complete |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-15).


## Dependency Graph

EP-15 through EP-19 are complete. EP-20 is the next implementable plan and audits the
final public/dependency surface after all API-adding plans. EP-21's hard dependencies are
now satisfied, but its soft dependency on EP-20 makes EP-20 the preferred next plan so
the final compatibility wording is settled before the docs-and-examples sweep.

EP-17 fulfilled EP-16's soft dependency by replacing the tagged-format loader's temporary
`Show` fallback with adapter-owned renderers. EP-18 consumed its stable `EnvError`
renderer while reshaping environment binding construction, so no renderer fallback or
tracked cleanup remains.

EP-20 (surface hygiene) soft-depends on all API-adding plans because it audits and freezes
the final exposed-module and dependency surface; running it earlier would audit a moving
target. It has no hard dependency because the audit and cabal restructuring compile
independently of the new APIs.

EP-21 hard-depends on EP-15 through EP-19: it rewrites both reference applications and all
guides to use the new decoder kit, loader, renderers, bindings, and sugar, and deletes the
duplicated boilerplate those plans made obsolete. It soft-depends on EP-20 only for the
final compatibility-matrix wording.

Cross-MasterPlan constraint: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
changes the resolver result shape and several adapter behaviors, and its EP-14 re-validates
the same examples and guides this initiative rewrites. The correctness MasterPlan lands
first; EP-21 in particular must start from the post-correctness tree.


## Integration Points

New package settei-formats (EP-16, EP-21): EP-16 owns the package (name, cabal file,
registration in cabal.project, flake.nix, nix/, and mori.dhall, following
docs/adr/0001-haskell-project-conventions.md sibling-directory layout). It defines the
tagged-input type and loader that EP-21 adopts in both reference applications. If EP-16
settles on a different package name during implementation, it must update this MasterPlan
and EP-21 in the same change.

Decoder surface in settei/src/Settei/Value.hs (EP-15, EP-21): EP-15 owns the new
combinators and instance; EP-21 consumes them in examples and guides. EP-19 must not add
decoder combinators — decoding sugar belongs to EP-15.

Declaration and renderer surface (EP-19, EP-20, EP-21): EP-19 owns `whenConfig`,
`whenEq`, `fallbackTo`, `publicShowSetting`, and `withRenderer`. EP-20 audits these five
additive exports as part of the final public surface; EP-21 consumes them without changing
the private `Config` representation or resolver behavior.

Adapter error renderer contract (EP-17, EP-16, EP-18, EP-21): EP-17 owns the naming and
formatting convention (`render<Adapter>ErrorText` style, one line per problem, never a raw
value, matching settei/src/Settei/Render.hs tone). EP-16 and EP-18 consume it; EP-21
threads it through examples and guides.

Reference applications and guides (every plan; EP-21 final owner): examples/settei-cli,
examples/settei-service, examples/settei-conformance, and docs/guides/ are updated
incrementally by each plan for the APIs it introduces; EP-21 performs the coherent final
pass per docs/adr/0007. Plans should keep example edits minimal and additive so EP-21's
rewrite is the single large diff.

Cabal and packaging surface (EP-16, EP-20): both edit cabal.project, flake.nix, and
per-package cabal files. EP-20 is the final authority on exposed-modules lists, the
Settei.Prelude decision, dependency bounds, and the PVP statement in
docs/compatibility.md; it must amend docs/adr/0001-haskell-project-conventions.md if it
changes the prelude exposure or the lens convention.

Cross-plan decisions that should become ADRs: EP-16's umbrella-package boundary (new ADR),
EP-17's uniform renderer contract (new ADR or an amendment to docs/adr/0003), EP-18's
construction-time validation semantics (amendment to the env sections of docs/adr/0003 or
a new ADR), EP-20's public-surface and dependency decision (amendment to docs/adr/0001).


## Progress

- [x] EP-15: Decoder Functor instance and combinator kit with tests
- [x] EP-15: examples drop hand-rolled decoders; guides updated
- [x] EP-16: settei-formats package with tagged inputs and loader, registered everywhere
- [x] EP-16: loader tests and guide coverage
- [x] EP-17: text renderers for YAML, KDL, Dhall, and Env errors with tests
- [x] EP-17: examples and guides stop using Show for adapter errors
- [x] EP-18: validated Bindings construction; envSource total; default label
- [x] EP-18: examples and environment guide updated
- [x] EP-19: selective conditional helpers and rendered-default ergonomics with tests
- [x] EP-19: examples and getting-started guide use the sugar
- [x] EP-20: Settei.Prelude exposure and lens footprint decided, implemented, ADR 0001 amended
- [x] EP-20: PVP surface statement in compatibility matrix
- [x] EP-21: SetteiOptions gains check/describe modes; warnings rendered in examples
- [x] EP-21: full docs-and-examples sweep, null-semantics documentation, changelogs, validation green


## Surprises & Discoveries

- The child plans were authored in parallel on 2026-07-19, so each records
  planning-time contingencies for siblings that had not yet been written (EP-16's
  renderer stub if EP-17 is unlanded, EP-17's Dhall-position contingency pending the
  correctness MasterPlan's EP-13, EP-18's renderer fallback, EP-21's opening
  reconciliation step). Implementers must honor those reconciliation steps rather than
  assume the plans were written against each other's final text.
- New-ADR numbering was coordinated at authoring time: EP-16 expects docs/adr/0008,
  EP-17 expects docs/adr/0009, EP-18 picks the next free number at implementation
  time; each plan verifies the number is free before writing.
- EP-15 found that the broad lens surface re-exported by `Settei.Prelude` includes
  `element`, which made the natural local binder name in the list combinators trigger
  `-Wname-shadowing`. EP-15 used `elementDecoder` and stayed warning-free. EP-20 should
  include this concrete collision in its public-surface and lens-footprint audit.
- EP-16 completed before its soft dependency EP-17. EP-17 replaced
  `renderFormatLoadErrorText`'s temporary typed `Show` fallback with the adapter-owned
  renderers, removed `TODO(EP-17)`, and added direct three-adapter delegation coverage;
  callers and EP-21 need no API change.
- EP-16 reconciled its planning-time test sketch with the correctness initiative's final
  resolver API: end-to-end loader tests inspect `ResolveResult.answer`, preserving the
  always-present report and warning channels. This does not change any downstream
  interface, but later plans should use `#answer` rather than the obsolete `#value`
  assumption.
- EP-18's planning-time caller inventory omitted one environment-source helper in
  `settei-optparse-applicative/test/Settei/OptparseTest.hs` and expected
  `docs/guides/cli-application.md` to contain signature-neutral prose, but that guide also
  declared `[EnvBinding]`. EP-18's repository-wide API scan migrated both. EP-20 and
  EP-21 should treat the tree as fully converted to the opaque `Bindings` surface rather
  than reserving either cleanup for the final sweep.
- EP-19 confirmed that `whenConfig`, `whenEq`, and `fallbackTo` need no new `Config` GADT
  node or resolver branch machinery: schema and runtime reports are identical to their
  raw-`select` encodings. EP-20 should audit the five additive exports (`whenConfig`,
  `whenEq`, `fallbackTo`, `publicShowSetting`, `withRenderer`), and EP-21 can adopt them
  without coordinating an internal representation change.
- EP-20 selected the documented keep-but-demote option: `Settei.Prelude` remains exposed
  solely for intra-family imports, while the compatibility matrix makes it explicitly
  non-PVP-stable. The audit found no lens type in any supported public signature. The
  only relevant dependency inconsistency was test-only `microlens` in settei-dhall; it
  now uses the family's existing `lens >=5.3 && <5.4` range. This leaves EP-21 with no
  public-surface cleanup beyond using the compatibility policy's settled wording.


## Decision Log

- Decision: Run this initiative after
  docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md completes.
  Rationale: The correctness MasterPlan changes the resolver result shape and adapter
  scalar semantics; rewriting examples and guides twice would waste every plan's
  docs-and-examples work. The owner explicitly prioritizes a bulletproof library at day
  one over faster ergonomics delivery.
  Date: 2026-07-19

- Decision: Deliver tagged-format loading as a new umbrella package rather than extending
  settei-optparse-applicative.
  Rationale: The dispatch code needs settei-yaml, settei-kdl, and settei-dhall as
  dependencies; adding those to the optparse adapter would force every CLI consumer to
  build all three format stacks. An umbrella package keeps adapters independent while
  giving multi-format apps one import. EP-16 records the package-design details.
  Date: 2026-07-19

- Decision: Schedule public-surface hygiene (EP-20) after the API-adding plans and before
  the final sweep.
  Rationale: Auditing exposed modules, dependency bounds, and the PVP statement is only
  meaningful against the final API set; doing it first would audit a moving target.
  Date: 2026-07-19

- Decision: Keep each plan's example updates minimal and let EP-21 own the coherent
  example rewrite.
  Rationale: Five plans editing examples/settei-cli and examples/settei-service
  concurrently would conflict constantly; per docs/adr/0007 the examples are the
  conformance boundary and deserve one deliberate final pass.
  Date: 2026-07-19

- Decision: Environment binding collections are opaque and validated once through
  `bindings` or `prefixedBindings`; `envSource` and `readEnvSource` are total over
  `Bindings`, and default-label conveniences use `"environment"`.
  Rationale: EP-18 removed an impossible runtime error branch from every application
  source stack while preserving all validation and secret-safe diagnostics. The durable
  contract, including the rejection of an unsafe constructor, is recorded in
  docs/adr/0010-validate-environment-bindings-at-construction.md and is the interface
  EP-20 audits and EP-21 documents.
  Date: 2026-07-19

- Decision: Conditional declaration sugar remains definitionally expressible through the
  existing `Functor` and `Selective` operations; EP-19 adds no private `Config` syntax
  node or resolver special case.
  Rationale: Direct schema and runtime-report equivalence tests prove that the public
  helpers preserve complete inspection and branch tracing. This keeps EP-20's work to a
  public-surface audit and lets EP-21 adopt the helpers without internal reconciliation.
  The durable no-new-syntax rule is recorded in the 2026-07-19 amendment to
  docs/adr/0002-inspectable-configuration-algebra.md.
  Date: 2026-07-19

- Decision: Keep `Settei.Prelude` exposed for package-family compilation but document it
  as internal and exclude it from the PVP-stable adoption surface.
  Rationale: The explicit signature audit found no lens type in the supported public
  surface; a Cabal public-sublibrary move adds toolchain risk without reducing the
  family's lens closure, while replacing lens conflicts with the existing convention.
  ADR 0001 records the durable decision and the Dhall test-dependency reconciliation.
  Date: 2026-07-19


## Outcomes & Retrospective

All seven ExecPlans are complete. The final public API now removes each recurring
adopter-side boilerplate identified in the review: decoders compose through `Functor`
and combinators; multi-format inputs use the `settei-formats` umbrella; every source
adapter has a secret-safe text renderer; environment bindings are validated before
source assembly; declaration sugar stays within the inspectable Selective algebra; and
the supported public surface has an explicit PVP policy.

EP-21 turned those library APIs into conformance evidence. The reference CLI and service
use the final interfaces, emit advisory resolver warnings on successful runs, and retain
the documented usage/source/resolution exit codes. The guides, compatibility matrix,
README, and changelogs describe the same APIs, including explicit-null precedence.
Validation from a clean build state passed every package, example, and conformance suite;
manual CLI transcripts proved source-free descriptions, JSON descriptions, check-only
validation, advisory warnings, and typed failure behavior.

The initiative produced four durable decisions: the `settei-formats` boundary (ADR
0008), uniform adapter renderers (ADR 0009), validated opaque environment bindings (ADR
0010), and the PVP/public-surface policy (ADR 0001). EP-21's diagnostic-mode and
advisory-warning contract is now recorded in ADR 0007. No further ADR changes were
needed after the final coherence review.


## Revision Notes

2026-07-19: Completed EP-21 and closed the MasterPlan after a clean full-suite run and
manual CLI diagnostics smoke tests. ADR 0007 now records the reusable diagnostic and
warning-rendering contract.
