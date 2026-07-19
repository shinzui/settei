---
id: 2
slug: harden-settei-correctness-before-fleet-wide-adoption
title: "Harden Settei correctness before fleet-wide adoption"
kind: master-plan
created_at: 2026-07-19T14:54:04Z
intention: "intention_01kxxdt2f0enp928nc1wbcsd2t"
---

# Harden Settei correctness before fleet-wide adoption

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

Settei 0.1.0.0 is implementation-complete but has not shipped. A 2026-07-19 API review
(recorded in this MasterPlan's Decision Log and in each child plan) found a small number of
correctness defects that must be fixed before the library is adopted by roughly 50
microservices and 20 applications. After this initiative is complete, the following holds:

- A key declared `Secret` anywhere in a declaration can never appear unredacted in any
  report, error, or rendered output, even when another part of the declaration declares the
  same key `Public`. Conflicting sensitivity is a structured error, not a silent left-bias.
- No configuration file can hang or out-of-memory a process at startup. Numeric scalars
  with astronomically large exponents (for example `1e1000000000`) are rejected by the YAML
  and KDL adapters with a structured error instead of being converted to `Rational`.
- The YAML adapter follows the YAML 1.2 core schema for untagged booleans: only `true` and
  `false` (case-insensitive) are booleans. `y`, `yes`, `on`, `n`, `no`, and `off` are plain
  text, eliminating the Norway problem.
- Resolution failures return the same provenance report and warnings that successes do, so
  an operator debugging a failed pod can still see which sources were consulted, what won,
  what was shadowed, and what was missing.
- Source annotation semantics are consistent across the whole package family, custom
  sources cannot silently contain unaddressable keys, Dhall parse failures carry a source
  position, and report rendering uses decimal notation instead of fractions.
- All guides, the security model document, the compatibility matrix, per-package
  changelogs, the reference applications, and the conformance fixtures reflect every
  behavior change. Docs and examples updates are in scope for every child plan, and the
  final child plan re-validates the entire release collateral.

Out of scope: ergonomics improvements (tracked separately in
docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md), any Hackage
publication step, Kubernetes cluster integration, and hot-reload/watch behavior.


## Decomposition Strategy

The review findings cluster into five independent functional concerns plus one final
verification concern, decomposed to maximize parallelism and keep each plan independently
verifiable:

1. The sensitivity-merge redaction hole is a core-only semantic fix (schema merge plus
   report-node construction) with its own adversarial tests.
2. Numeric conversion bounds are an adapter-boundary fix shared by YAML and KDL; both call
   `toRational` on unbounded `Scientific` values, and the guard logic and its tests are one
   concern even though two packages change.
3. YAML boolean strictness is a separate scalar-semantics decision with its own ADR
   amendment; it is kept apart from the numeric guard so each behavior change has an
   independently revertible commit history and distinct characterization tests.
4. Failure-path reporting is a core resolver API change (the shape returned by `resolve`)
   that touches every consumer, so it is one plan with the examples migration inside it.
5. The remaining smaller hardening items (annotation merge semantics, validated custom
   source construction, YAML decode exception tightening, Dhall parse locations, decimal
   rendering) are individually too small to be plans and share the same
   files, so they form one sweep plan.
6. A final plan re-runs the full release validation and reconciles every document, example,
   changelog, and golden file, because the reference applications are the public-API
   conformance boundary (docs/adr/0007) and the release checklist claims in README.md must
   remain true.

Relevant ADRs consulted: docs/adr/0002-inspectable-configuration-algebra.md and
docs/adr/0003-resolution-provenance-and-default-semantics.md (redaction and report
semantics that plans EP-9 and EP-12 amend), docs/adr/0004-yaml-input-semantics.md (scalar
semantics amended by EP-10, EP-11, and EP-13), docs/adr/0005-canonical-kdl-v2-input-semantics.md
(amended by EP-10), docs/adr/0006-dhall-input-import-and-provenance-semantics.md (parse
diagnostics and the documented preflight race, EP-13), and
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md (EP-14's
authority). docs/adr/0001-haskell-project-conventions.md governs code style in every plan.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 9 | Close the shared-key sensitivity redaction hole | docs/plans/9-close-the-shared-key-sensitivity-redaction-hole.md | None | None | Not Started |
| 10 | Bound numeric scalar conversion in the YAML and KDL adapters | docs/plans/10-bound-numeric-scalar-conversion-in-the-yaml-and-kdl-adapters.md | None | None | Not Started |
| 11 | Adopt YAML 1.2 core-schema boolean scalars | docs/plans/11-adopt-yaml-1-2-core-schema-boolean-scalars.md | None | EP-10 | Not Started |
| 12 | Report resolution provenance and warnings on failure | docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md | None | EP-9 | Not Started |
| 13 | Harden source construction and adapter diagnostics | docs/plans/13-harden-source-construction-and-adapter-diagnostics.md | None | EP-10, EP-11, EP-12 | Not Started |
| 14 | Revalidate correctness and update release collateral | docs/plans/14-revalidate-correctness-and-update-release-collateral.md | EP-9, EP-10, EP-11, EP-12, EP-13 | None | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-9).


## Dependency Graph

EP-9, EP-10, EP-11, EP-12, and EP-13 are all implementable from the current tree; none
depends on another plan's artifacts to compile or make sense, so up to five contributors
can work in parallel.

The soft dependencies exist to serialize edits to shared files and shared documents, not to
gate correctness. EP-11 lists EP-10 as a soft dependency because both edit the scalar
pipeline in settei-yaml/src/Settei/Yaml.hs and both amend docs/adr/0004-yaml-input-semantics.md;
landing EP-10 first avoids rebasing the ADR amendment. EP-12 lists EP-9 as a soft
dependency because both touch settei/src/Settei/Resolve.hs and settei/src/Settei/Error.hs;
EP-9 adds a new `ConfigError` constructor that EP-12's failure-path report tests should
exercise. EP-13 lists EP-10, EP-11, and EP-12 as soft dependencies because it edits the
same YAML module and the shared render module last, keeping the sweep plan's diffs small.

EP-14 has hard dependencies on all five: it is the release re-validation pass and is
meaningless until every behavior change has landed. It must be the final plan.


## Integration Points

Shared error vocabulary (EP-9, EP-12): both plans extend or reshape types in
settei/src/Settei/Error.hs and their rendering in settei/src/Settei/Render.hs. EP-9 owns
the new sensitivity-conflict error constructor and its text/JSON rendering; EP-12 consumes
whatever constructors exist when it changes the failure return shape. EP-12 must not
rename or remove EP-9's constructor.

Resolver result shape (EP-12, EP-14, and the ergonomics MasterPlan): EP-12 owns the new
shape returned by `resolve` in settei/src/Settei/Resolve.hs (report and warnings available
on both success and failure). Both reference applications under examples/ consume it, and
docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md rewrites those
same applications afterwards. This MasterPlan must complete before the ergonomics
MasterPlan's example-facing plans begin (see Decision Log).

YAML scalar pipeline (EP-10, EP-11, EP-13): the functions `scalarValue`,
`parseYamlNumber`, and `yamlBoolean` in settei-yaml/src/Settei/Yaml.hs are edited by
EP-10 (numeric guard) and EP-11 (boolean set), and EP-13 touches the module's decode
boundary. Land in registry order. All three amend docs/adr/0004-yaml-input-semantics.md;
each amendment appends its own dated note rather than rewriting earlier ones.

Versioned JSON documents and golden files (EP-9, EP-12, EP-13, EP-14): the deterministic
JSON renderers in settei/src/Settei/Render.hs are covered by golden tests under
settei/test/golden/. Additive fields keep `schemaVersion: 1` per
docs/adr/0003-resolution-provenance-and-default-semantics.md; any golden change must be
reconciled once more by EP-14.

Reference applications and conformance fixtures (all plans): examples/settei-cli,
examples/settei-service, and examples/settei-conformance are the conformance boundary
(docs/adr/0007). Every behavior-changing plan updates the examples and fixtures it
invalidates; EP-14 is the final owner that re-runs the whole suite and reconciles
remaining drift.

Cross-plan decisions that should become ADRs: EP-9's most-restrictive-sensitivity rule and
conflict error (amend docs/adr/0003), EP-10's numeric exponent bound (amend docs/adr/0004
and docs/adr/0005), EP-11's YAML 1.2 core-schema boolean set (amend docs/adr/0004), and
EP-12's always-available report semantics (amend docs/adr/0003).


## Progress

- [ ] EP-9: sensitivity conflicts detected and redaction enforced most-restrictively in core
- [ ] EP-9: adversarial secret-sentinel tests, docs, and security model updated
- [ ] EP-10: exponent-bounded numeric conversion in settei-yaml and settei-kdl with tests
- [ ] EP-10: ADR 0004/0005 amendments, guides, and changelogs updated
- [ ] EP-11: YAML untagged booleans restricted to true/false with characterization tests
- [ ] EP-11: ADR 0004 amendment, YAML guide, and conformance fixtures updated
- [ ] EP-12: resolve returns report and warnings on failure; renderers and core tests updated
- [ ] EP-12: reference applications surface failure reports; guides updated
- [ ] EP-13: annotation merge, validated source construction, YAML decode hardening landed
- [ ] EP-13: Dhall parse locations, decimal rendering, docs and ADR notes landed
- [ ] EP-14: full workspace validation green (tests, goldens, examples, sdist, nix)
- [ ] EP-14: security model, compatibility matrix, changelogs, README reconciled


## Surprises & Discoveries

- During plan authoring (2026-07-19), EP-10 research found that settei-kdl has no direct
  `scientific` dependency even though kdl-hs hands it `Scientific` values; EP-10 adds
  `scientific >=0.3.7 && <0.4` (matching settei-yaml) and EP-14's compatibility-matrix
  reconciliation must reflect the new bound.
- EP-14 research found the conformance package already contains a secret-sentinel scan
  (`never-render-this-conformance-secret` in its Security test group), so EP-9's
  adversarial coverage extends an existing mechanism rather than inventing one.


## Decision Log

- Decision: Split the 2026-07-19 API review remediation into two MasterPlans — this
  correctness initiative and docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md —
  and land this one first.
  Rationale: The owner is adopting Settei across roughly 50 microservices and 20
  applications and wants the library bulletproof from day one. Correctness changes alter
  public semantics (redaction, scalar acceptance, resolver result shape) and must settle
  before ergonomics work rewrites the same examples and guides on top of them.
  Date: 2026-07-19

- Decision: Decompose into five parallel remediation plans plus one hard-gated final
  revalidation plan (EP-14), rather than folding documentation into a single docs plan.
  Rationale: Each behavior change must carry its own tests, ADR amendment, guide updates,
  and example updates so it is independently verifiable and revertible; a shared docs plan
  would create hidden coupling. The final plan exists because the release checklist and
  conformance boundary (docs/adr/0007) require one coherent pass after all changes.
  Date: 2026-07-19

- Decision: Fix the sensitivity-merge hole with most-restrictive-wins plus a structured
  conflict error, not silently unifying to Secret alone.
  Rationale: Silent unification hides a real declaration bug (the same key declared Public
  and Secret) from the 70 adopting codebases; erroring surfaces it at resolve time while
  most-restrictive-wins keeps reports safe even before callers handle the error. The child
  plan records the detailed semantics.
  Date: 2026-07-19

- Decision: Keep the YAML boolean change (EP-11) separate from the numeric bound (EP-10).
  Rationale: Independent revertibility and distinct characterization-test surfaces; both
  amend ADR 0004 but answer different questions (which scalars are booleans versus which
  numbers are representable).
  Date: 2026-07-19


## Outcomes & Retrospective

(To be filled during and after implementation.)
