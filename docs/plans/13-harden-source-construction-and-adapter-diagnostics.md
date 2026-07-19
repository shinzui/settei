---
id: 13
slug: harden-source-construction-and-adapter-diagnostics
title: "Harden source construction and adapter diagnostics"
kind: exec-plan
created_at: 2026-07-19T14:54:42Z
intention: "intention_01kxxdt2f0enp928nc1wbcsd2t"
master_plan: "docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md"
---

# Harden source construction and adapter diagnostics

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Settei is a Haskell configuration library (workspace root: this repository) about to be
adopted by roughly 50 microservices and 20 applications. A 2026-07-19 API review found
five small, related hardening defects that this sweep plan fixes together. After this plan
is complete, an adopter observes five concrete improvements:

First, calling `annotateSource` twice on the same `Source` no longer silently discards the
first call's annotations; every annotation combinator in the package family now merges
with the same left-biased convention, so metadata attached by an adapter and metadata
attached by an application compose instead of clobbering each other.

Second, an application that builds a custom `Source` by hand can use a new validated
constructor, `sourceFromPairs`, that makes it impossible to create leaves that the
resolver can never address (object keys containing dots) or keys that structurally overlap
(one key being a prefix of another). Today such leaves are silently invisible to both
`lookupSource` and unknown-key diagnostics. A new total inspection function,
`sourceUnaddressableLeaves`, also makes any such leaves in a hand-built source visible.

Third, the YAML adapter's pure decode boundary can no longer leak an arbitrary synchronous
exception out of ostensibly pure code: any unexpected synchronous exception is mapped to a
structured `YamlSyntaxError` with a fixed, secret-safe message, while asynchronous
exceptions are still deliberately rethrown.

Fourth, a Dhall syntax error now reports a one-based line and column (like the YAML and
KDL adapters already do) instead of only the fixed text "invalid Dhall syntax" with no
position, without ever retaining the offending source snippet.

Fifth, provenance reports render non-integer numbers as decimals when the value has an
exact terminating decimal form: an operator reading a report sees `0.5` instead of the
technically-exact but hostile `1/2`. Values without a terminating decimal form (such as
one third) keep the exact fraction rendering, because reports must never display a value
the source did not contain.

To see it working after implementation: run the whole test suite from the repository root
with `nix develop -c cabal test all --test-show-details=direct` and observe the new tests
in `settei-tests`, `settei-yaml-tests`, and `settei-dhall-tests` passing; each milestone
below also names a small observable behavior you can check directly.


## Progress

- [x] (2026-07-19T18:07:01Z) M1: changed `annotateSource` in settei/src/Settei/Source.hs to merge annotations
      left-biased and update its haddock to state that new annotations win on collision.
- [x] (2026-07-19T18:07:01Z) M1: audited and confirmed no behavior change for internal callers (settei-yaml,
      settei-kdl, settei-dhall, settei-optparse-applicative) and record the audit result
      in Surprises & Discoveries or the Decision Log.
- [x] (2026-07-19T18:07:01Z) M1: added merge-semantics unit tests to settei/test/Settei/SourceTest.hs.
- [x] (2026-07-19T18:07:01Z) M1: appended a dated amendment note to docs/adr/0003-resolution-provenance-and-default-semantics.md.
- [x] (2026-07-19T18:07:57Z) M1 validation: `nix develop -c cabal test settei-tests
      --test-show-details=direct` passed all 67 tests.
- [x] (2026-07-19T18:10:59Z) M2: added `SourceConstructionError` and `sourceFromPairs` to settei/src/Settei/Source.hs
      and export both (they flow through the `Settei` re-export automatically).
- [x] (2026-07-19T18:10:59Z) M2: added `sourceUnaddressableLeaves` and haddock warnings on `source` and
      `sourceLeaves` naming `source` as the unvalidated escape hatch.
- [x] (2026-07-19T18:10:59Z) M2: added construction, duplicate-rejection, overlap-rejection, dotted-key
      characterization, and unaddressable-leaf tests to settei/test/Settei/SourceTest.hs.
- [x] (2026-07-19T18:10:59Z) M2 validation: `nix develop -c cabal test settei-tests
      --test-show-details=direct` passed all 71 tests, and `nix develop -c cabal build all`
      compiled every workspace package and component.
- [x] (2026-07-19T18:13:04Z) M3: tightened the exception catch in `decodeMarkedEvents` in
      settei-yaml/src/Settei/Yaml.hs to synchronous `SomeException` with async rethrow and
      a fixed secret-free fallback message.
- [x] (2026-07-19T18:13:04Z) M3: added a regression test (malformed input still yields `YamlSyntaxError`) to
      settei-yaml/test/Settei/YamlTest.hs and record the code-review acceptance criterion.
- [x] (2026-07-19T18:13:04Z) M3: appended a dated amendment note to docs/adr/0004-yaml-input-semantics.md.
- [x] (2026-07-19T18:13:04Z) M3 validation: `nix develop -c cabal test settei-yaml-tests
      --test-show-details=direct` passed all 33 tests, and `nix develop -c cabal build all`
      compiled the workspace.
- [x] (2026-07-19T18:19:35Z) M4: extended `DhallSourceError` with optional line/column fields and the
      `dhallErrorLine`/`dhallErrorColumn` accessors in settei-dhall/src/Settei/Dhall.hs.
- [x] (2026-07-19T18:19:35Z) M4: populated positions from the Megaparsec bundle at both `DhallParseError`
      construction sites (root parse and import preflight) and add `megaparsec` to
      settei-dhall.cabal.
- [x] (2026-07-19T18:19:35Z) M4: added root and imported-file position tests to settei-dhall/test/Settei/DhallTest.hs.
- [x] (2026-07-19T18:19:35Z) M4: appended a dated amendment note to docs/adr/0006-dhall-input-import-and-provenance-semantics.md
      and update the error section of docs/guides/dhall.md.
- [x] (2026-07-19T18:19:35Z) M4: added the LocalImportsWithin TOCTOU-race warning to docs/security.md (verified
      absent as of 2026-07-19).
- [x] (2026-07-19T18:19:35Z) M4 validation: `nix develop -c cabal test settei-dhall-tests
      --test-show-details=direct` passed all 16 tests; the root and imported fixture both
      pinned line 2, column 13; `nix develop -c cabal build all` compiled the workspace;
      the solved direct dependency is Megaparsec 9.8.1.
- [ ] M5: implement terminating-decimal rendering in `renderRawValue` in
      settei/src/Settei/Provenance.hs.
- [ ] M5: add rendering unit tests; run golden tests and reconcile
      settei/test/golden/ files if any drift appears (none expected — see Context).
- [ ] Cross-cutting: update settei/CHANGELOG.md, settei-yaml/CHANGELOG.md, and
      settei-dhall/CHANGELOG.md.
- [ ] Cross-cutting: run the full workspace validation and confirm green.
- [ ] Completion: write Outcomes & Retrospective and perform the ADR distillation pass.


## Surprises & Discoveries

- The Milestone 1 caller audit confirmed the pre-plan result: every in-repository adapter
  calls `annotateSource` exactly once around a freshly constructed `source`, so merging
  against the initially empty annotation map is observationally identical for those
  callers. Only repeated application by downstream callers changes behavior.
  Evidence: `rg -n "annotateSource" settei settei-env settei-yaml settei-kdl settei-dhall
  settei-optparse-applicative --glob '*.hs'` found the four documented adapter call sites
  and no additional production use.
- The unexpected synchronous YAML exception branch cannot be induced without corrupting
  parser internals, so Milestone 3 used its planned review gate. The diff catches
  `SomeException`; rethrows both `SomeAsyncException` and `AsyncException` before mapping;
  uses a fixed fallback literal without exception content; and leaves `unsafePerformIO`
  and `NOINLINE` intact. Ordinary malformed input remains covered by a positioned
  `YamlSyntaxError` regression test.
- Mori located the registered Dhall 1.42.3 source and confirmed that
  `Dhall.Parser.ParseError` exposes its Megaparsec bundle. Direct inspection of current
  Megaparsec 9.8.1 then found that `reachOffsetNoLine` returns an updated `PosState`, not
  the `(SourcePos, PosState)` tuple assumed by the authored plan. The implementation reads
  `pstateSourcePos` from that returned state. Hackage and upstream tags both identify
  9.8.1, so the direct dependency remains the planned `>=9 && <10` range without a
  compatibility workaround.


## Decision Log

- Decision: `annotateSource` merges with `%~ (annotations <>)` — the new annotations are
  the left operand of `Data.Map`'s left-biased `<>` (which is `Map.union`), so new
  annotations win on a name collision and all other existing entries are retained.
  Rationale: this is exactly the convention already used by `annotateBinding`
  (settei-env), `annotateYamlSourceOptions` (settei-yaml), `annotateKdlSourceOptions`
  (settei-kdl), and `annotateDhallSourceOptions` (settei-dhall), and it matches the
  spirit of `annotateSourceAt`, whose later hooks also win. Replacing (`.~`) silently
  discards earlier metadata, which is a correctness trap for adopters.
  Date: 2026-07-19

- Decision: introduce a new error type `SourceConstructionError` in `Settei.Source`
  (constructors `DuplicateSourceKey !Key` and `OverlappingSourceKeys !Key !Key`) and give
  `sourceFromPairs` the signature
  `Text -> SourceKind -> [(Key, RawValue)] -> Either (NonEmpty SourceConstructionError) Source`,
  accumulating all problems rather than returning only the first.
  Rationale: reusing settei-env's `EnvError` would make the core depend on adapter
  vocabulary (and `EnvError` carries environment-name constructors that make no sense
  here). `NonEmpty` accumulation matches the established family convention
  (`envSource`, `decodeYamlSource`, `decodeKdlSource`, `loadDhallSource` all return
  `Either (NonEmpty e) Source`); the single-error signature originally suggested by the
  review was rejected as an inconsistency adopters would notice.
  Date: 2026-07-19

- Decision: keep `sourceLeaves` and `source` total. Surface invalid leaves through a new
  additive function `sourceUnaddressableLeaves :: Source -> [[Text]]` returning the raw
  segment paths (never values) of leaves that cannot form a valid `Key`, plus explicit
  haddock warnings naming `source` as the unvalidated escape hatch and `sourceFromPairs`
  as the recommended constructor.
  Rationale: making `source` partial (rejected) would turn a long-standing total public
  constructor into one that errors, breaking adapters that construct provably valid trees;
  making `sourceLeaves` return `Either` (rejected) would ripple through the resolver's
  unknown-key pipeline for a defect that only hand-built sources can exhibit. The additive
  function keeps totality, makes the defect observable and testable, and costs nothing on
  the validated path. Only key paths are returned because raw values may be secret.
  Date: 2026-07-19

- Decision: `decodeMarkedEvents` catches synchronous `SomeException`, explicitly rethrows
  anything whose `fromException` matches `SomeAsyncException` or `AsyncException`, keeps
  the existing `YamlException` mapping, and maps every other synchronous exception to
  `YamlSyntaxError` with the fixed message "YAML decoding failed with an unexpected
  error" containing no exception text.
  Rationale: ADR 0004 deliberately accepts the `unsafePerformIO` boundary and deliberately
  does not catch asynchronous exceptions — both decisions are preserved. Including
  `displayException` output of an arbitrary exception (rejected) could echo raw input,
  violating the secret-safety rule that adapter errors never retain source excerpts.
  Date: 2026-07-19

- Decision: extract Dhall parse positions structurally from the Megaparsec
  `ParseErrorBundle` inside `Dhall.Parser.ParseError` (field `unwrap`), using
  `errorOffset` of the first bundle error and `reachOffsetNoLine` against
  `bundlePosState`; populate positions at both `DhallParseError` sites (the root parse in
  `loadDhallSourceDetailed` and the import-preflight parse in `visitImport`). The rendered
  error and the source snippet are never retained. Documented fallback if the structural
  API proves unavailable at the resolved megaparsec version: parse the `label:line:column`
  head line of the rendered error exactly as settei-kdl's `parseErrorLocation` does,
  discarding the rest.
  Rationale: a position is not a secret; the snippet is (ADR 0006). `reachOffsetNoLine`
  computes a `SourcePos` without materializing the offending line, so no rendered text
  ever exists in the adapter. Both parse sites are extended so in-root and imported-file
  syntax errors are equally diagnosable.
  Date: 2026-07-19

- Decision: render a non-integer `Rational` as a plain decimal exactly when its reduced
  denominator has the form 2^a * 5^b, using direct factor-stripping and scaling by
  10^max(a,b) (algorithm spelled out in Milestone 5); otherwise keep the exact `n/d`
  fraction form. Rejected: rounding to a fixed number of decimal places, because reports
  must never show a value the source did not contain. Rejected:
  `Data.Scientific.fromRationalRepetend` within a digit budget, because it would add a
  `scientific` dependency to the core package (which has none today) and introduces
  repetend-truncation policy questions for values we have decided to keep exact.
  Date: 2026-07-19

- Decision: the decimal-rendering change alters display strings only; per ADR 0003's
  versioned-JSON rule, display strings may change pre-release and `schemaVersion` stays 1.
  No new-schema-version bump is performed; any golden drift is reconciled in place.
  Date: 2026-07-19

- Decision: land this plan after EP-10, EP-11, and EP-12 (soft dependencies from the
  MasterPlan registry). All milestones compile from the current tree, but EP-10/EP-11 edit
  the same settei-yaml module and EP-12 causes Render/golden churn; landing last keeps
  this sweep plan's diffs small. Each ADR amendment appends its own dated note rather than
  rewriting earlier ones.
  Date: 2026-07-19

- Decision: use the Megaparsec 9.x structural position API by taking
  `pstateSourcePos` from the `PosState` returned by `reachOffsetNoLine`; keep the direct
  dependency at `megaparsec >=9 && <10`.
  Rationale: Mori-located Dhall 1.42.3 supports Megaparsec `>=8 && <10`, while the
  authoritative registry and upstream tags identify 9.8.1 as current. The 9.x API avoids
  rendering a source line and the PVP-compatible bound covers the released major without
  pinning one patch version.
  Date: 2026-07-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Settei is a multi-package Cabal workspace. The packages relevant here:

- `settei/` — the core. `settei/src/Settei/Source.hs` defines `Source` (a named,
  hierarchical tree of `RawValue` plus location and annotation hooks), the unvalidated
  constructor `source`, the combinators `annotateSource`, `annotateSourceAt`,
  `locateSource`, the exact-key lookup `lookupSource`, and the leaf enumeration
  `sourceLeaves`. `settei/src/Settei/Provenance.hs` defines `Candidate`,
  `ReportedValue`, and the private display renderer `renderRawValue`.
  `settei/src/Settei/Key.hs` defines `Key` (a validated non-empty list of dot-free
  segments; `mkKey` rejects empty or dotted segments with `KeyError`).
  `settei/src/Settei.hs` re-exports all core modules, so anything exported from
  `Settei.Source` is automatically public through `Settei`.
- `settei-env/` — environment adapter. `settei-env/src/Settei/Env.hs` contains
  `annotateBinding` (merging, line 63) and the private helpers `overlapErrors`,
  `isPrefixKey`, and `insertRawValue` (lines 181–247) whose validation-then-insert shape
  Milestone 2 mirrors inside the core.
- `settei-yaml/` — YAML adapter. `settei-yaml/src/Settei/Yaml.hs` contains
  `decodeMarkedEvents` (line 187), the `unsafePerformIO`/`NOINLINE` pure decode boundary
  around `Text.Libyaml.decodeMarked`, currently catching only `Libyaml.YamlException`.
- `settei-kdl/` — KDL adapter. `settei-kdl/src/Settei/Kdl.hs` contains
  `decodeKdlSource` (line 172, which composes `"kdl.version"` with caller annotations in
  a single `annotateSource` call) and `parseErrorLocation` (line 228), the
  head-line `line:column` parser that Milestone 4's fallback imitates.
- `settei-dhall/` — Dhall adapter. `settei-dhall/src/Settei/Dhall.hs` contains
  `DhallSourceError` (line 134), `loadDhallSourceDetailed` (line 227) whose parse branch
  (lines 236–237) discards the Megaparsec error entirely, and the import preflight
  `visitImport` whose local-import parse failure (around line 399) does the same.
- `settei-optparse-applicative/` — CLI adapter. `settei-optparse-applicative/src/Settei/Optparse.hs`
  calls `annotateSource` at lines 180 and 195; part of the Milestone 1 caller audit.

Terms used below: a "leaf" is a non-object `RawValue` reached by descending `RawObject`
maps; its address is the list of map keys on the way down. A `Key` is the validated form
of such an address — dots are structural separators only, so a map key containing a
literal dot can never be spelled as a `Key`. An "annotation" is a `Map Text Text` of
descriptive metadata attached to origins; annotations never affect precedence
(docs/adr/0003). "Left-biased" for `Data.Map` means `m1 <> m2` (which is `Map.union`)
keeps `m1`'s value when both maps contain the same key.

Relevant ADRs consulted (repository-relative paths):

- docs/adr/0003-resolution-provenance-and-default-semantics.md — defines source-wide and
  per-key annotations ("per-key entries take precedence when names overlap"), the
  redaction rules (raw values never enter reports; adapter annotations must never copy
  raw candidate values), and the versioned-JSON rule (JSON reports carry
  `schemaVersion: 1`; additive display changes keep version 1). Milestones 1 and 5 amend
  it with dated notes.
- docs/adr/0004-yaml-input-semantics.md — accepts the `unsafePerformIO` decode boundary as
  referentially transparent and explicitly does not catch asynchronous exceptions; adapter
  errors carry fixed safe messages and never retain a raw scalar or excerpt. Milestone 3
  preserves both decisions and amends the ADR with a dated note.
- docs/adr/0006-dhall-input-import-and-provenance-semantics.md — parse failures use stable
  categories and fixed messages without snippets or retained upstream exceptions; the
  Consequences section already documents that `LocalImportsWithin` preflight validation
  can be raced by a concurrent filesystem writer (TOCTOU) and is not an OS sandbox.
  Milestone 4 amends it with a dated note and copies the race warning into
  docs/security.md, which (verified 2026-07-19) currently omits it.
- docs/adr/0001-haskell-project-conventions.md governs code style (custom
  `Settei.Prelude` with generic-lens labels: `&`, `^.`, `.~`, `%~`, `at`).

Facts established by pre-plan research (so the implementer does not have to re-derive
them):

- `annotateSource` (settei/src/Settei/Source.hs lines 56–57) is the only member of the
  annotation family that replaces (`#annotations .~ annotations`). Every internal caller
  (settei-yaml line 160, settei-kdl line 182, settei-dhall line 251,
  settei-optparse-applicative lines 180 and 195) applies it exactly once to a source
  freshly built by `source`, whose `annotations` field is `Map.empty` — so merging with
  the empty map is observationally identical to replacing it, and the Milestone 1 change
  cannot alter any adapter's behavior.
- `sourceLeaves` (settei/src/Settei/Source.hs lines 116–128) drops any leaf whose segment
  path fails `mkKey` (the `Left _ -> []` case at line 126). `lookupSource` (line 89) can
  never address such a leaf either, because `Key` segments cannot contain dots.
- `Dhall.Parser.ParseError` in the registered `dhall` 1.42.3 sources
  (/Users/shinzui/Keikaku/hub/haskell/dhall-haskell-project/dhall-haskell/dhall/src/Dhall/Parser.hs,
  lines 52–55) is a record `ParseError { unwrap :: Text.Megaparsec.ParseErrorBundle Text
  Void, input :: Text }`. dhall.cabal allows `megaparsec >= 8 && < 10`. Megaparsec's
  `errorOffset`, `bundleErrors`, `bundlePosState`, `reachOffsetNoLine`, `sourceLine`,
  `sourceColumn`, and `unPos` are all exported from `Text.Megaparsec` in that range and
  give one-based positions.
- No golden file under settei/test/golden/ currently contains a fraction rendering
  (`grep -rn '[0-9]/[0-9]'` matches nothing there, nor under examples/), and no core test
  currently renders a non-integer `RawNumber`, so Milestone 5's expected golden churn is
  zero — but the plan still requires running the golden suite to prove it.
- No guide under docs/guides/ documents hand-built `source` construction (verified by
  grepping the guides for `annotateSource`, `source "` and "custom source"), so the only
  guide edit in this plan is docs/guides/dhall.md.
- Test suite names: `settei-tests`, `settei-env-tests`, `settei-yaml-tests`,
  `settei-kdl-tests`, `settei-dhall-tests` (plus `settei-dhall-prototype-tests`).

MasterPlan integration: this is EP-13 of
docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md, with soft
dependencies on EP-10 and EP-11 (same YAML module) and EP-12 (Render/golden churn). Land
after them; if their edits have landed, rebase mechanically — no milestone here touches
`scalarValue`, `parseYamlNumber`, `yamlBoolean`, or the resolver result shape.


## Plan of Work

The work is five independent milestones plus a cross-cutting documentation pass. Each
milestone compiles and tests on its own and is committed separately.


### Milestone 1 — annotation merge semantics

Scope: one-line semantic fix in the core plus tests and an ADR note. Today, a second
`annotateSource` call replaces the whole source-wide annotation map; afterwards it merges,
with the newest annotations winning on a name collision. At the end of this milestone, an
application that layers metadata (for example, a deployment tool stamping
`deploy.revision` onto a source an adapter already annotated) keeps both maps.

Edit settei/src/Settei/Source.hs. Change the body of `annotateSource` (line 57) from
`sourceValue & #annotations .~ annotations` to `sourceValue & #annotations
%~ (annotations <>)`. `Data.Map`'s `<>` is left-biased union, so placing the new
`annotations` argument on the left makes new entries win on a key collision — the same
convention as `annotateBinding`, `annotateYamlSourceOptions`, `annotateKdlSourceOptions`,
and `annotateDhallSourceOptions`. Rewrite the haddock to state the semantics explicitly,
for example:

```haskell
-- | Attach adapter-specific descriptive metadata. It never changes precedence.
--
-- Repeated calls merge: annotations from a later call win when the same annotation
-- name is already present, and entries under other names are retained. Per-key
-- annotations from 'annotateSourceAt' still take precedence over source-wide entries.
annotateSource :: Map Text Text -> Source -> Source
annotateSource annotations sourceValue =
  sourceValue & #annotations %~ (annotations <>)
```

Confirm the caller audit recorded in Context and Orientation: every internal call site
applies `annotateSource` once to a `source`-built value with an empty annotation map, so
no adapter's output changes. If you find any call site not matching that description, stop
and record it in Surprises & Discoveries before proceeding.

Add tests to settei/test/Settei/SourceTest.hs (the module already builds `sampleSource`
with `source "built-in" BuiltInSource ...`): (a) two `annotateSource` calls compose —
after `annotateSource (Map.singleton "b" "2") (annotateSource (Map.singleton "a" "1")
sampleSource)`, `sourceAnnotations` contains both entries; (b) on collision the newer call
wins — annotating `"a" -> "old"` then `"a" -> "new"` yields `Just "new"` at `"a"`;
(c) origins observe the merged map — `lookupSource servicePort` on the doubly annotated
source returns a candidate whose origin annotations contain both names (this exercises
`originFor`, which already unions per-key over source-wide annotations).

Append a dated note at the bottom of
docs/adr/0003-resolution-provenance-and-default-semantics.md (do not rewrite existing
text), for example:

```text
Amendment (2026-07-19): `annotateSource` originally replaced the source-wide annotation
map, unlike every sibling combinator. It now merges left-biased: annotations supplied by
a later call win on a name collision and other entries are retained, matching
`annotateSourceAt` and the adapter option combinators. Per-key entries still take
precedence over source-wide entries when names overlap.
```

Acceptance: `nix develop -c cabal test settei-tests --test-show-details=direct` passes,
including the three new cases; before the fix, test (a) fails (the `"a"` entry is gone).


### Milestone 2 — validated custom source construction

Scope: an additive validated constructor and an additive inspection function in
settei/src/Settei/Source.hs, plus haddock honesty on the existing escape hatch. At the end
of this milestone, `sourceFromPairs "my-source" BuiltInSource [(portKey, RawNumber 8080)]`
either returns a `Source` whose every leaf is addressable, or a structured explanation of
why not; and `sourceUnaddressableLeaves` exposes the leaves a hand-built `source` hid.

The defect: `source name kind (RawObject ...)` accepts any tree. An object key containing
a dot (say `"a.b"`) produces a leaf `lookupSource` can never reach (dots are structural
separators only — `parseKey "a.b"` means the two-segment path `a` then `b`, and `mkKey`
rejects any single segment containing a dot). `sourceLeaves` silently drops such leaves
(the `Left _ -> []` case at line 126), so unknown-key diagnostics never mention them: the
data is simply invisible.

In settei/src/Settei/Source.hs add, and export from the module header (they become public
through `Settei` automatically):

```haskell
-- | Why a list of key/value pairs cannot form one addressable source tree.
data SourceConstructionError
  = -- | The same key appears more than once.
    DuplicateSourceKey !Key
  | -- | One key is a structural prefix of another, so one leaf would sit
    -- inside the object the other needs to traverse.
    OverlappingSourceKeys !Key !Key
  deriving stock (Generic, Eq, Show)

-- | Build a source from validated keys, rejecting duplicates and prefix overlaps.
--
-- Every leaf of the result is addressable by 'lookupSource' and enumerated by
-- 'sourceLeaves'. This is the recommended constructor for hand-built sources;
-- 'source' is the unvalidated escape hatch.
sourceFromPairs ::
  Text ->
  SourceKind ->
  [(Key, RawValue)] ->
  Either (NonEmpty SourceConstructionError) Source
```

Implementation shape (mirroring settei-env's validate-then-insert): first collect
`DuplicateSourceKey` for every key occurring more than once (reuse the counting idea of
settei-env's private `duplicates`), then collect `OverlappingSourceKeys lower higher` for
every ordered pair where one key's segment list is a proper prefix of the other's
(mirroring `overlapErrors`/`isPrefixKey` in settei-env/src/Settei/Env.hs lines 181–233 —
those helpers are private to settei-env, so reimplement them locally in `Settei.Source`;
do not add a dependency). If any error was collected, return them all as a `NonEmpty` in
deterministic order (duplicates first, then overlaps in input order). Otherwise fold the
pairs into a nested `RawObject` with a local `insertRawValue :: Key -> RawValue ->
RawValue -> RawValue` exactly like settei-env's (lines 235–247): descend segments,
creating empty objects as needed, placing the value at the final segment. Because
overlaps were rejected, the non-object collision branch is unreachable; keep settei-env's
`error` call there with the same "validated keys cannot overlap" wording. Finish with
`source name kind root` so location and annotation hooks start empty. Note that two keys
sharing a proper common prefix without either being a prefix of the other (for example
`service.port` and `service.host`) are valid and share the `service` object.

Also add the total inspection function:

```haskell
-- | Return the raw segment paths of leaves that no 'Key' can address.
--
-- A non-empty result means the source was built by hand with object keys that are
-- empty or contain dots; such leaves are invisible to 'lookupSource',
-- 'sourceLeaves', and unknown-key diagnostics. Only key paths are returned; raw
-- values are never exposed because they may be secret.
sourceUnaddressableLeaves :: Source -> [[Text]]
```

Implement it as a sibling traversal to `sourceLeaves` that keeps exactly the paths the
`Left _` case discards (descend `RawObject`s accumulating segments; at a non-object leaf,
emit the accumulated path when `NonEmpty.nonEmpty prefix >>= mkKey` fails — including the
root-is-addressed-by-empty-path case, which `sourceLeaves` also skips but which is not an
error, so exclude the empty-prefix case: an empty prefix means the root itself is a
scalar, which `sourceFromPairs` cannot produce and `source` documents). Update the
haddocks of `source` (line 44) and `sourceLeaves` (line 113) to warn: `source` performs no
validation, leaves whose object keys contain dots or are empty are unaddressable and
silently absent from `sourceLeaves`, and `sourceFromPairs` is the recommended path.
`sourceLeaves` itself stays total and its type is unchanged (see Decision Log for the
rejected alternatives).

Tests in settei/test/Settei/SourceTest.hs: (a) `sourceFromPairs` with
`[("service.port", 8080), ("service.host", "db")]` (keys via the file's existing
`validKey` helper) succeeds; `lookupSource` finds both; `sourceLeaves` enumerates both in
key order; `sourceUnaddressableLeaves` is empty. (b) A duplicated key yields
`DuplicateSourceKey`. (c) `[("service", ...), ("service.port", ...)]` yields
`OverlappingSourceKeys` naming both keys. (d) Characterization of the escape hatch: a
hand-built `source` whose root is `RawObject (Map.singleton "a.b" (RawText "hidden"))`
has `sourceLeaves` equal to `[]` and `sourceUnaddressableLeaves` equal to `[["a.b"]]` —
this is the dotted-key-rejection test at the only layer where a dotted key can exist,
since `mkKey`/`parseKey` (already covered by settei/test/Settei/KeyTest.hs) make dotted
segments unrepresentable as `Key`s.

Acceptance: `nix develop -c cabal test settei-tests --test-show-details=direct` passes
with all new cases; case (d) documents today's silent-drop behavior as now-visible.


### Milestone 3 — YAML decode exception boundary

Scope: tighten one catch site in settei-yaml/src/Settei/Yaml.hs, add a regression test,
amend ADR 0004. At the end of this milestone, no synchronous exception of any type can
escape `decodeYamlSource`'s pure signature; asynchronous exceptions still propagate.

The defect: `decodeMarkedEvents` (lines 187–193) wraps the libyaml conduit in
`unsafePerformIO` and catches only `Libyaml.YamlException`. Any other synchronous
exception (from conduit plumbing, resource management, or the C binding) escapes from
ostensibly pure code as an imprecise exception. ADR 0004 explicitly accepts the
`unsafePerformIO` boundary and deliberately does not catch asynchronous exceptions;
preserve both. Rewrite the helper as:

```haskell
decodeMarkedEvents :: YamlSourceOptions -> ByteString -> Either YamlSourceError [Libyaml.MarkedEvent]
decodeMarkedEvents options bytes = unsafePerformIO $ do
  decoded <-
    try @SomeException
      (runConduitRes (Libyaml.decodeMarked bytes .| ConduitList.consume))
  case decoded of
    Right events -> pure (Right events)
    Left exception
      | Just (SomeAsyncException _) <- fromException exception -> throwIO exception
      | Just (asynchronous :: AsyncException) <- fromException exception -> throwIO asynchronous
      | Just yamlException <- fromException @Libyaml.YamlException exception ->
          pure (Left (syntaxError options yamlException))
      | otherwise ->
          pure (Left (yamlError options YamlSyntaxError Nothing [] "YAML decoding failed with an unexpected error"))
{-# NOINLINE decodeMarkedEvents #-}
```

Extend the `Control.Exception` import (line 30) with `AsyncException`, `SomeAsyncException
(..)`, `SomeException`, `fromException`, and `throwIO`, and enable
`ScopedTypeVariables`-style pattern annotation if the module needs it (the workspace
already compiles with GHC2021-era defaults; match the file's existing extensions). The
fallback message is a fixed literal: it must never interpolate `displayException` or any
exception field, because an arbitrary exception's text could echo raw input bytes
(secret-safety, ADR 0004). Keep `unsafePerformIO` and `NOINLINE` exactly as they are.

Testing, honestly: constructing a synchronous non-`YamlException` from the libyaml
conduit on demand is not practical without corrupting library internals, so the
unexpected-exception branch is validated by code review, not by a test. Record this
acceptance criterion in the review checklist for the commit: (1) the catch type is
`SomeException`; (2) both `SomeAsyncException` and `AsyncException` are rethrown before
any mapping; (3) the fallback message is a string literal with no exception content;
(4) `unsafePerformIO`/`NOINLINE` are unchanged. What is testable is the regression that
ordinary malformed input still takes the `YamlException` path: add to
settei-yaml/test/Settei/YamlTest.hs a case decoding `"key: [unclosed"` (bytes via the
file's existing encoding helpers) and asserting the single error has
`yamlErrorCategory == YamlSyntaxError` with `yamlErrorLine`/`yamlErrorColumn` present —
if a similar assertion already exists (there is one around line 80), extend it to pin the
category exactly rather than an `elem` set, or add a dedicated case.

Append a dated note to docs/adr/0004-yaml-input-semantics.md:

```text
Amendment (2026-07-19): the pure decode boundary originally caught only `YamlException`,
so another synchronous exception could escape `decodeYamlSource`. The boundary now
catches synchronous `SomeException`, still rethrows asynchronous exceptions
(`SomeAsyncException`/`AsyncException`), and maps unexpected synchronous exceptions to
`YamlSyntaxError` with a fixed message that deliberately includes no exception text,
because rendered exception text could echo raw input. The `unsafePerformIO` boundary
decision is unchanged.
```

Acceptance: `nix develop -c cabal test settei-yaml-tests --test-show-details=direct`
passes; the review checklist above is satisfied on the diff.


### Milestone 4 — Dhall parse-error positions and security-doc parity

Scope: additive record change and position plumbing in settei-dhall/src/Settei/Dhall.hs,
one cabal dependency, tests, an ADR note, a guide touch-up, and one documentation-only
addition to docs/security.md. At the end of this milestone, a Dhall syntax error carries a
one-based line and column, matching the YAML adapter (which retains libyaml marks) and the
KDL adapter (which parses a `line:column` header), and docs/security.md states the
preflight TOCTOU race that ADR 0006 already documents.

Extend `DhallSourceError` (line 134) additively:

```haskell
data DhallSourceError = DhallSourceError
  { category :: !DhallErrorCategory,
    name :: !Text,
    path :: !(Maybe FilePath),
    line :: !(Maybe Int),
    column :: !(Maybe Int),
    message :: !Text
  }
  deriving stock (Generic, Eq, Show)
```

Add accessors in the existing style, exported from the module header next to the other
`dhallError*` accessors:

```haskell
-- | Return the one-based line associated with an error, when known.
dhallErrorLine :: DhallSourceError -> Maybe Int
dhallErrorLine problem = problem ^. #line

-- | Return the one-based column associated with an error, when known.
dhallErrorColumn :: DhallSourceError -> Maybe Int
dhallErrorColumn problem = problem ^. #column
```

`singleError` (line 513) fills `line = Nothing, column = Nothing`; add a positioned
variant (or extend `singleError`/`failure` with position parameters — pick one shape and
use it at both parse sites) so only `DhallParseError` construction supplies positions.

Position extraction: `DhallParser.exprFromText` returns
`Left DhallParser.ParseError` where `ParseError` is a record with `unwrap ::
Text.Megaparsec.ParseErrorBundle Text Void` (verified in the registered dhall 1.42.3
sources under /Users/shinzui/Keikaku/hub/haskell/dhall-haskell-project/dhall-haskell/dhall/src/Dhall/Parser.hs,
lines 52–55). Add a private helper:

```haskell
import Data.List.NonEmpty qualified as NonEmpty
import Text.Megaparsec qualified as Megaparsec

parseErrorPosition :: DhallParser.ParseError -> (Maybe Int, Maybe Int)
parseErrorPosition parseError =
  let bundle = DhallParser.unwrap parseError
      offset = Megaparsec.errorOffset (NonEmpty.head (Megaparsec.bundleErrors bundle))
      reached = Megaparsec.reachOffsetNoLine offset (Megaparsec.bundlePosState bundle)
      position = Megaparsec.pstateSourcePos reached
   in ( Just (Megaparsec.unPos (Megaparsec.sourceLine position)),
        Just (Megaparsec.unPos (Megaparsec.sourceColumn position))
      )
```

`reachOffsetNoLine` computes an updated `PosState` without materializing the offending
source line; `pstateSourcePos` exposes its `SourcePos`, so no snippet ever exists in the
adapter. The `ParseError` value itself is consumed here and never stored. Change the root
parse branch of `loadDhallSourceDetailed` (lines
236–237) from `Left _ -> ... "invalid Dhall syntax"` to bind the error, extract the
position, and emit the same fixed message with the position filled in. Do the same at the
import-preflight parse site in `visitImport` (around line 399, message "invalid syntax in
local import"): extend the private `PreflightFailure` record with `line, column ::
!(Maybe Int)` defaulting to `Nothing` in `throwPreflight`, add a positioned throw for the
parse case, and thread the fields through the `failure` mapping in `resolveExpression`.
The fixed messages do not change; only positions are added. Never retain the rendered
error or the snippet.

Add `megaparsec >=9 && <10` to the library `build-depends` of
settei-dhall/settei-dhall.cabal (the workspace's dhall 1.42.3 already constrains
`megaparsec >= 8 && < 10`; match whatever major version the freeze/Nix set resolves — run
`nix develop -c cabal build settei-dhall` and adjust the lower bound to the resolved
major if 9 is not what solves). Documented fallback if `reachOffsetNoLine` is unavailable
at the resolved version: render the bundle with `Megaparsec.errorBundlePretty`, parse only
the head line for its trailing `line:column` integers exactly as settei-kdl's
`parseErrorLocation` does (settei-kdl/src/Settei/Kdl.hs lines 228–242), and discard the
rendered text immediately — the head line contains only the label and position, not the
snippet, but prefer the structural API so no rendered text exists at all.

Tests in settei-dhall/test/Settei/DhallTest.hs (which already asserts `DhallParseError`
for a truncated expression around line 194): (a) `dhallExpression "broken" "{ port ="`
fails with `DhallParseError`, `dhallErrorLine = Just 1`, and `dhallErrorColumn` present;
(b) a known multi-line fixture `dhallExpression "broken2" "let a = 1\nin { port = }"`
reports `dhallErrorLine = Just 2` (pin the exact column the implementation produces once
observed, then assert it exactly so regressions are caught); (c) the existing
secret-sentinel parse test still shows no sentinel text in the error's `Show` output.

Documentation: append a dated note to
docs/adr/0006-dhall-input-import-and-provenance-semantics.md:

```text
Amendment (2026-07-19): parse failures now carry an optional one-based line and column
extracted structurally from the Megaparsec error bundle (or, as a fallback, from the
rendered header's line:column), matching the YAML and KDL adapters. Positions are not
secrets; rendered snippets remain excluded, and messages remain fixed.
```

Update the "Render Dhall errors" section of docs/guides/dhall.md to mention
`dhallErrorLine` and `dhallErrorColumn` alongside `dhallErrorName`/`dhallErrorPath` as
safe context. Finally, docs/security.md's "Dhall import policy" section (verified
2026-07-19 to omit this) gains the warning ADR 0006 already carries — add after the
policy bullet list:

```text
`LocalImportsWithin` is preflight validation, not an operating-system sandbox: import
paths are canonicalized and checked before evaluation, so an actor able to mutate files
or symlinks concurrently can race the preflight and the upstream read (a
time-of-check/time-of-use race). Never treat a directory writable by untrusted actors as
a safe import root.
```

Acceptance: `nix develop -c cabal test settei-dhall-tests --test-show-details=direct`
passes with the new position assertions; grepping the diff shows no call that stores
`errorBundlePretty` output or `ParseError`'s `input` field.


### Milestone 5 — decimal rendering of rationals

Scope: change one private function in settei/src/Settei/Provenance.hs, add unit tests,
prove goldens are unaffected. At the end of this milestone, a public report shows `0.5`
where it previously showed `1/2`, while `1/3` still renders as the exact fraction.

`renderRawValue` (lines 77–88) currently renders a non-integer `RawNumber value` as
`show numerator <> "/" <> show denominator`. Replace the `RawNumber` branch: integers
(denominator 1) are unchanged; a non-integer renders as a plain decimal exactly when its
reduced denominator is of the form 2^a * 5^b (that is, the value has a terminating
decimal expansion); otherwise the exact fraction form is kept. The conversion algorithm,
concretely (no new dependency — the core package deliberately has no `scientific`
dependency; see Decision Log for why `fromRationalRepetend` was rejected):

```haskell
renderDecimal :: Rational -> Maybe Text
renderDecimal value = do
  let numerator = Ratio.numerator value
      denominator = Ratio.denominator value
      (twos, afterTwos) = countFactor 2 denominator
      (fives, residual) = countFactor 5 afterTwos
  if residual /= 1
    then Nothing
    else do
      let scale = max twos fives
          scaled = abs numerator * (10 ^ scale) `quot` denominator
          digits = Text.pack (show scaled)
          padded = Text.replicate (max 0 (scale + 1 - Text.length digits)) "0" <> digits
          (whole, fractional) = Text.splitAt (Text.length padded - scale) padded
          sign = if numerator < 0 then "-" else ""
      Just (sign <> whole <> "." <> fractional)

countFactor :: Integer -> Integer -> (Int, Integer)
countFactor factor = go 0
  where
    go count remaining
      | remaining `rem` factor == 0 = go (count + 1) (remaining `quot` factor)
      | otherwise = (count, remaining)
```

Why this is exact and canonical: `Rational` values from `Data.Ratio` are always in lowest
terms, so the numerator shares no factor of 2 or 5 with the denominator; `scale = max a b`
is the minimal power of ten the denominator divides, so `scaled` is an exact integer and
its last digit is never zero — the output has no trailing zeros to strip and no rounding
occurs anywhere. Worked examples the tests pin: `1/2` renders `0.5`; `-3/8` renders
`-0.375`; `1/1000` renders `0.001` (padding produces the leading zeros); `1/3` has
residual 3 and keeps `1/3`; `7/12` keeps `7/12`; integers keep the integer branch. Wire it
in as: non-integer `RawNumber` tries `renderDecimal` and falls back to the existing
fraction rendering. This transitively changes every rendering path that displays a public
non-integer value: `reportedValue Public`, array and object element rendering inside
`renderRawValue` itself, and the text/JSON report renderers in
settei/src/Settei/Render.hs that display `ReportedValue` — no edit is needed outside
`Provenance.hs` because `renderRawValue` is the single choke point.

Tests: add cases to settei/test/Settei/RenderTest.hs (or a small new group in
settei/test/Settei/ValueTest.hs if RenderTest's fixtures are awkward — prefer RenderTest
so the behavior is exercised through `reportedValue Public`): `renderReportedValue
(reportedValue Public (RawNumber (1 Ratio.% 2)))` is `"0.5"`; `(-3) Ratio.% 8` is
`"-0.375"`; `1 Ratio.% 1000` is `"0.001"`; `1 Ratio.% 3` is `"1/3"`; an array
`RawArray [RawNumber (1 Ratio.% 2), RawNumber (1 Ratio.% 3)]` renders `"[0.5, 1/3]"`.
Then run the golden suite: no golden file under settei/test/golden/ contains a fraction
today (pre-verified), so `nix develop -c cabal test settei-tests
--test-show-details=direct` must pass with zero golden churn; if EP-12's landed changes
introduced fractional values into goldens in the meantime, regenerate/update those files
in the same commit and note it in Surprises & Discoveries. Per ADR 0003 and the Decision
Log, this is a display-string change only: `schemaVersion` stays 1 and no schema bump
occurs (the library is pre-release; nothing has shipped).

Acceptance: the new unit tests pass; the golden tests pass; a manual check — running any
example that renders a report containing a fractional public value — shows `0.5`-style
output.


### Cross-cutting documentation and changelog pass

After the milestones, update the three changelogs by appending bullets to the existing
`0.1.0.0` sections (nothing has shipped, so the unreleased 0.1.0.0 entry is amended
rather than adding a new version — the same convention the sibling EPs use):

- settei/CHANGELOG.md: `annotateSource` now merges (new annotations win on collision);
  added `sourceFromPairs`, `SourceConstructionError`, and `sourceUnaddressableLeaves`;
  report rendering shows terminating decimals instead of fractions.
- settei-yaml/CHANGELOG.md: the pure decode boundary now contains all synchronous
  exceptions; unexpected ones map to `YamlSyntaxError` with a fixed message.
- settei-dhall/CHANGELOG.md: `DhallSourceError` gained optional line/column with
  `dhallErrorLine`/`dhallErrorColumn`; parse failures now carry positions.

Guides: docs/guides/dhall.md was updated in Milestone 4; a search of docs/guides/
(pre-verified) found no guide documenting hand-built `source` construction, so no other
guide changes are required — re-run the search
(`grep -rn "annotateSource\|source \"\|custom source" docs/guides/`) before closing the
plan in case a sibling EP added one, and mention `sourceFromPairs` there if so.


## Concrete Steps

All commands run from the repository root, /Users/shinzui/Keikaku/bokuno/settei, inside
the Nix development shell. Prefix Cabal commands with `nix develop -c` (or enter the
shell once with `nix develop`).

Work milestone by milestone; after each, run its targeted suite, then commit. The
commands and their expected shapes:

```bash
cd /Users/shinzui/Keikaku/bokuno/settei
nix develop -c cabal build all                 # must compile after every edit
nix develop -c cabal test settei-tests --test-show-details=direct        # M1, M2, M5
nix develop -c cabal test settei-yaml-tests --test-show-details=direct   # M3
nix develop -c cabal test settei-dhall-tests --test-show-details=direct  # M4
nix develop -c cabal test all --test-show-details=direct                 # final gate
```

Expected success shape for a targeted suite (counts will differ):

```text
Test suite settei-tests: RUNNING...
...
All NN tests passed (0.xx s)
Test suite settei-tests: PASS
```

A failing golden test prints a diff of the golden file versus the produced document; per
Milestone 5 no such diff is expected — if one appears, inspect it, update the golden file
only if the change is exactly the decimal-rendering change, and record it in Surprises &
Discoveries.

Commit after each milestone (five milestone commits plus one docs/changelog commit is the
expected shape; folding the ADR/guide note for a milestone into that milestone's commit is
also fine — keep each behavior change and its tests in one commit). Every commit message
follows Conventional Commits (per the repository's committing conventions) and must carry
these trailers exactly:

```text
MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
ExecPlan: docs/plans/13-harden-source-construction-and-adapter-diagnostics.md
Intention: intention_01kxxdt2f0enp928nc1wbcsd2t
```

Suggested commit subjects:

```text
fix(settei): merge annotateSource annotations instead of replacing
feat(settei): add validated sourceFromPairs and unaddressable-leaf inspection
fix(settei-yaml): contain unexpected synchronous exceptions at the decode boundary
feat(settei-dhall): report line and column on Dhall parse failures
feat(settei): render terminating rationals as decimals in reports
docs: update changelogs, security model, and guides for EP-13
```

Commit directly to the current branch (do not create a feature branch). Update this
plan's Progress section at every stopping point, and update the MasterPlan's EP-13 status
(docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md registry row
and Progress checklist) when starting and when finishing.


## Validation and Acceptance

Overall gate: `nix develop -c cabal test all --test-show-details=direct` from the
repository root is green, including golden tests and both Dhall suites.

Behavioral acceptance, per milestone, phrased as observable outcomes:

1. Annotation merge: in GHCi (`nix develop -c cabal repl settei`), evaluating
   `sourceAnnotations (annotateSource (Map.singleton "b" "2") (annotateSource
   (Map.singleton "a" "1") (source "s" BuiltInSource (RawObject Map.empty))))` yields a
   map containing both `"a" -> "1"` and `"b" -> "2"`. Before this plan it contained only
   `"b" -> "2"`. The collision test shows the newer call winning.
2. Validated construction: `sourceFromPairs` accepts sibling keys under a shared prefix,
   rejects a duplicate with `DuplicateSourceKey`, rejects `service` alongside
   `service.port` with `OverlappingSourceKeys`, and its output satisfies
   `null (sourceUnaddressableLeaves s)`. The characterization test shows a hand-built
   dotted-key source producing `sourceLeaves == []` and
   `sourceUnaddressableLeaves == [["a.b"]]`.
3. YAML boundary: decoding `"key: [unclosed"` returns `Left` with one error of category
   `YamlSyntaxError` carrying a line and column. The unexpected-exception branch is
   accepted by the four-point code-review checklist in Milestone 3 (catch type,
   async rethrow, literal message, unchanged `unsafePerformIO`/`NOINLINE`) because a
   direct test cannot be constructed honestly.
4. Dhall positions: loading `dhallExpression "broken2" "let a = 1\nin { port = }"` under
   `NoImports` returns `DhallParseError` with `dhallErrorLine = Just 2` and a pinned
   column; the message is still exactly "invalid Dhall syntax"; the secret-sentinel test
   still finds no sentinel in any error output. docs/security.md contains the TOCTOU
   sentence.
5. Decimal rendering: `renderReportedValue (reportedValue Public (RawNumber (1 % 2)))`
   is `"0.5"`, `1 % 3` stays `"1/3"`, `-3 % 8` is `"-0.375"`, `1 % 1000` is `"0.001"`,
   and the golden suite passes without churn.

Failure signatures to recognize: a compile error mentioning `#annotations` or `#line`
means an accessor/record edit missed a construction site (search the module for the
record name); a golden mismatch in `settei-tests` outside Milestone 5 means an unintended
rendering change — stop and investigate before updating any golden file.


## Idempotence and Recovery

Every step is an ordinary source edit plus a test run; all are safe to repeat. No
migrations, no destructive operations, no generated files other than golden updates
(which are plain checked-in text — regenerating them is repeatable, and `git diff`
against the previous commit shows exactly what changed). If a milestone stalls
mid-implementation, `git status` plus this plan's Progress section identify the
remaining work; each milestone is independent, so a partially complete milestone can be
finished or reverted (`git restore <paths>` for uncommitted work, `git revert <commit>`
for committed work) without touching the others. The record-field extensions in
Milestones 4 (`DhallSourceError`, `PreflightFailure`) are additive; if a construction
site is missed the compiler reports it — fix and rerun, nothing latent survives a clean
build. If EP-10/EP-11/EP-12 land while this plan is in flight, rebase: the only shared
file is settei-yaml/src/Settei/Yaml.hs, and this plan touches only `decodeMarkedEvents`
and the import list, which those plans do not.


## Interfaces and Dependencies

Libraries: no new dependency for the core (`settei` deliberately avoids `scientific`;
Milestone 5 uses only `Data.Ratio` and `Data.Text`, already imported in Provenance.hs).
`settei-dhall` gains `megaparsec` (bounds matching the workspace's resolved major, target
`>=9 && <10`) solely to destructure `ParseErrorBundle`; `dhall` 1.42.3 already carries it
transitively. `settei-yaml` gains no dependency — `Control.Exception` is in `base`.

Interfaces that must exist at the end of each milestone, with full module paths:

Milestone 1 — `Settei.Source.annotateSource :: Map Text Text -> Source -> Source`,
unchanged type, merge semantics, haddock stating that new annotations win on collision.

Milestone 2 — in `Settei.Source` (re-exported by `Settei`):

```haskell
data SourceConstructionError
  = DuplicateSourceKey !Key
  | OverlappingSourceKeys !Key !Key

sourceFromPairs ::
  Text -> SourceKind -> [(Key, RawValue)] ->
  Either (NonEmpty SourceConstructionError) Source

sourceUnaddressableLeaves :: Source -> [[Text]]
```

Milestone 3 — `Settei.Yaml.decodeMarkedEvents` keeps its private type
`YamlSourceOptions -> ByteString -> Either YamlSourceError [Libyaml.MarkedEvent]`; the
public `Settei.Yaml.decodeYamlSource` and `readYamlSource` signatures are unchanged.

Milestone 4 — in `Settei.Dhall`: `DhallSourceError` gains private fields
`line, column :: Maybe Int`; new public accessors
`dhallErrorLine :: DhallSourceError -> Maybe Int` and
`dhallErrorColumn :: DhallSourceError -> Maybe Int`; all other signatures unchanged.

Milestone 5 — `Settei.Provenance.renderRawValue` remains private with type
`RawValue -> Text`; the public surface (`reportedValue`, `renderReportedValue`) is
unchanged in type, changed only in the display strings it produces.

Services: none. Everything runs locally through the Nix development shell and Cabal.
