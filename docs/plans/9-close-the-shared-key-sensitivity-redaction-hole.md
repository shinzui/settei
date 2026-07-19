---
id: 9
slug: close-the-shared-key-sensitivity-redaction-hole
title: "Close the shared-key sensitivity redaction hole"
kind: exec-plan
created_at: 2026-07-19T14:54:42Z
intention: "intention_01kxxdt2f0enp928nc1wbcsd2t"
master_plan: "docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md"
---

# Close the shared-key sensitivity redaction hole

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Settei promises that a value declared `Secret` can never appear unredacted in any report,
error, or rendered output. Today that promise has a hole: if the same configuration key is
declared twice inside one `Config` declaration — once with `secretSetting` and once with
`publicSetting`, for example `database.password` declared secret in a database module and
public (by mistake) in a metrics module — nothing detects the conflict, and the report
node built for the public declaration retains and renders the raw secret value. A password
can appear in plain text in `renderResolutionText` and `renderResolutionJson` output.

After this change, two things are true and demonstrable. First, resolving any acyclic
declaration that names one key with both `Public` and `Secret` sensitivity fails with a new structured
error, `SensitivityConflict`, that identifies the key, so the declaration bug is surfaced
to the roughly 70 adopting codebases instead of being silently absorbed. Second, as
defense in depth, every internal code path — schema merging, report-node construction, and
report-node map unions — treats sensitivity most-restrictively (`Secret` wins), so even a
future refactor that weakened the error gate could not render the raw value. You can see
it working by running the settei test suite: a new adversarial test resolves a conflicting
declaration carrying a distinctive secret sentinel string and proves the sentinel appears
in no text render, no JSON render, and no `Show` output, while `resolve` returns the new
error.

This plan is EP-9 of the MasterPlan
docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md. It changes
only the core `settei` package plus documentation; no adapter package changes.


## Progress

- [x] (2026-07-19 09:29 -0700) M1: `SchemaSetting` tracks every declared sensitivity and
      `mergeSetting` in
      settei/src/Settei/Internal/Schema.hs merges sensitivity most-restrictively
      (`Secret` wins).
- [x] (2026-07-19 09:29 -0700) M1: schema-merge tests pass for both declaration orders,
      for a duplicate inside a
      selective branch, and for a duplicate inside a default dependency.
- [x] (2026-07-19 09:35 -0700) M2: `SensitivityConflictProblem` record and
      `SensitivityConflict` constructor added
      to settei/src/Settei/Error.hs.
- [x] (2026-07-19 09:35 -0700) M2: pre-evaluation `validateSensitivityConflicts` gate
      wired into `resolve` in
      settei/src/Settei/Resolve.hs alongside `validateDefaultCycles`.
- [x] (2026-07-19 09:35 -0700) M2: text and JSON rendering for the new error added to
      settei/src/Settei/Render.hs; every exhaustive `ConfigError` pattern match in the
      repository updated (core test helper plus two example test helpers).
- [x] (2026-07-19 09:35 -0700) M2: resolve-level conflict tests pass (error returned,
      correct key, both orders).
- [ ] M3: per-key effective-sensitivity map computed in `resolve` and threaded through
      `evaluate`, `evaluateSetting`, `missingNode`, `derivedNode`, and
      `defaultReportedValue`.
- [ ] M3: `redactReportedValue` added to settei/src/Settei/Provenance.hs and report-node
      map unions changed to a redact-preferring `Map.unionWith` combiner.
- [ ] M4: adversarial secret-sentinel test added covering all renderers and `Show`.
- [ ] M4: golden files under settei/test/golden/ verified unchanged; full workspace test
      suite green.
- [ ] M4: docs/adr/0003 amended with a dated note; docs/security.md, settei/CHANGELOG.md,
      and docs/guides/getting-started.md updated.
- [ ] Final: ADR distillation pass done, MasterPlan registry row and Progress updated,
      Outcomes & Retrospective written.


## Surprises & Discoveries

- The initially planned expression that appended default-cycle errors to
  sensitivity-conflict errors caused the existing cyclic-default test to stop after
  printing its test name. Computing sensitivity conflicts requires
  `schemaPossible (describeEvaluation config)`, and static description follows the
  deliberately cyclic default dependency forever. Restoring an explicit first gate for
  `validateDefaultCycles`, followed by the schema-dependent conflict gate only when that
  list is empty, made the focused cyclic test and all 54 core tests pass.

  Evidence:

  ```text
  Settei.Default
    cyclic defaults fail before source evaluation:
  ^C

  Settei.Default
    cyclic defaults fail before source evaluation: OK

  All 1 tests passed (0.00s)
  ```


## Decision Log

- Decision: Fix the hole with most-restrictive-wins semantics plus a structured
  `SensitivityConflict` error, rather than silently unifying to `Secret` alone or only
  erroring.
  Rationale: Recorded in the MasterPlan Decision Log (2026-07-19 API review). Silent
  unification would hide a real declaration bug from adopting codebases; erroring alone
  would leave a latent leak if any caller path ever bypassed the gate. Doing both
  surfaces the bug at resolve time while guaranteeing that no code path can render the
  raw value.
  Date: 2026-07-19

- Decision: Detect conflicts from the merged `Schema` by making `SchemaSetting` carry the
  set of every sensitivity it was declared with, instead of writing a second walk over
  the private `Config` syntax tree.
  Rationale: `describeConfig` in settei/src/Settei/Internal/Config.hs already unions
  every request across applicative composition, selective branches, and default
  dependencies into one `Map Key SchemaSetting`. Once `mergeSetting` accumulates a
  `Set Sensitivity`, conflict detection is a single pass over `schemaPossible`, cannot
  drift from the schema semantics, and reuses the exact structure the resolver already
  computes. A second `Config` walk would duplicate traversal logic that must forever
  agree with `describeConfig`.
  Date: 2026-07-19

- Decision: For defense in depth, `resolve` precomputes a per-key effective-sensitivity
  map from `schemaPossible (describe config)` (safe because the schema merge is now
  Secret-biased) and threads it through evaluation so every report node for a key uses
  the most restrictive sensitivity declared anywhere in the whole declaration; the
  left-biased `Map.union` calls on node maps additionally become `Map.unionWith` with a
  redact-preferring combiner.
  Rationale: `evaluateSetting` only sees its own `Setting`, so it needs whole-declaration
  knowledge injected. With the map applied at node construction, all nodes for one key
  agree and union bias becomes irrelevant; the combiner is a second, independent layer so
  neither mechanism is a single point of failure.
  Date: 2026-07-19

- Decision: `mergeSetting` keeps the left declaration's description; only sensitivity
  merging changes. `mergeRequirement` and `mergePresence` are untouched.
  Rationale: The description is display metadata with no security consequence, and the
  new conflict error already surfaces disagreeing declarations. Requirement and presence
  merge semantics are correct today (required wins, necessary wins) and are covered by
  ADR 0002; changing them is out of scope per the MasterPlan.
  Date: 2026-07-19

- Decision: The adversarial test asserts the sentinel is absent from
  `renderResolutionText` and `renderResolutionJson` using the report from the closest
  publicly reachable secret scenario, plus schema/error/Show outputs from the conflicting
  scenario itself, because after this fix `resolve` can never return a
  `ResolutionReport` for a conflicted declaration — the gate fails first, which is
  itself the guarantee. The internal defense layers are tested at their own seams (the
  test suite compiles the library sources directly, so it can import
  Settei.Internal.Schema).
  Rationale: The public API makes a mixed-sensitivity report unreachable by design.
  EP-12 (docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md) will
  later make reports available on failure; at that point the failure-path report for a
  conflicted declaration becomes observable and EP-12's tests must extend the sentinel
  assertions to it. EP-12 must not rename or remove the `SensitivityConflict`
  constructor (MasterPlan integration point "Shared error vocabulary").
  Date: 2026-07-19

- Decision: Record the changelog entry under the existing `0.1.0.0` section of
  settei/CHANGELOG.md rather than adding an "Unreleased" section.
  Rationale: 0.1.0.0 has never been published (the MasterPlan's premise is hardening
  before the first fleet-wide adoption), so the initial release notes are still the
  correct home and no version bump is required.
  Date: 2026-07-19

- Decision: Keep default-cycle validation as the first resolver gate and run
  sensitivity-conflict validation as a second declaration-level gate only when the
  declaration is acyclic.
  Rationale: Conflict detection consumes the static schema, but describing a cyclic
  default dependency does not terminate. The ordering preserves the existing guarantee
  that cycles fail before source or schema evaluation while still reporting every
  sensitivity conflict before structure validation and runtime evaluation for all valid,
  acyclic declarations. A declaration containing both defects reports its default cycle
  first instead of accumulating both error kinds.
  Date: 2026-07-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Settei is a Haskell workspace at the repository root. The core package lives in
`settei/`; adapter packages (settei-yaml, settei-kdl, and others) and reference
applications under `examples/` are not touched by this plan except for two one-line test
helper updates described below. All paths in this plan are repository-relative.

A "declaration" is a value of type `Config a`: a private typed syntax tree (a GADT in
settei/src/Settei/Internal/Config.hs) built from the public combinators `required`,
`optional`, `withDefault`, and the `Functor`/`Applicative`/`Selective` instances. A
`Setting a` (settei/src/Settei/Setting.hs) is the metadata for one logical key: a
validated dotted `Key`, a description, a decoder, an optional renderer, and a
`Sensitivity`, which is the two-value type `data Sensitivity = Public | Secret` that
controls whether reports may display the resolved value. `publicSetting` and
`secretSetting` are the smart constructors. Nothing stops two different modules from
declaring the same `Key` with different sensitivity and composing both declarations
applicatively — that is exactly the defect.

`describe` (settei/src/Settei/Config.hs, implemented by `describeConfig` in
settei/src/Settei/Internal/Config.hs) folds a declaration into a `Schema`
(settei/src/Settei/Internal/Schema.hs): a `Map Key SchemaSetting` plus selective-branch
conditions. When the same key appears twice, `combineSchema` calls `Map.unionWith
mergeSetting`, and `mergeSetting` (line ~102 of settei/src/Settei/Internal/Schema.hs)
merges only `requirement` and `presence` — it silently keeps the LEFT declaration's
`sensitivity` and `description`. This is defect part (a): the merged schema can claim a
secret key is public.

`resolve` (settei/src/Settei/Resolve.hs) interprets a declaration against ordered
sources. It runs two pre-evaluation validation passes — `validateDefaultCycles` (a pure
walk of the declaration for default-rule cycles) and `validateStructure` (shape
validation of every statically possible key against every source) — then evaluates. For
each request, `evaluateSetting` (line ~350) builds a `ResolutionNode` whose displayed
value is `reportedValue (settingSensitivity settingSpec) rawValue`: it uses only its OWN
setting's sensitivity. This is defect part (b): the node built while evaluating the
`Public` declaration of a conflicted key retains the raw value visibly (`reportedValue
Public` wraps the rendered raw text in a `VisibleValue`; see
settei/src/Settei/Provenance.hs). Finally, `applyEvaluation` (line ~412) and the
`SelectConfig` branch of `evaluate` merge node maps with left-biased `Map.union`, so
whichever node was built first wins the report. This is defect part (c). Net effect: the
secret value can appear unredacted in `renderResolutionText` and `renderResolutionJson`
output (settei/src/Settei/Render.hs).

Errors are the closed sum `ConfigError` in settei/src/Settei/Error.hs, one constructor
per problem record (for example `DefaultCycle !DefaultCycleProblem`). Text and JSON
rendering for each constructor lives in `renderErrorText` and `errorJson` in
settei/src/Settei/Render.hs. JSON documents carry `schemaVersion: 1` and must stay at
version 1 for additive changes (ADR 0003). Golden snapshots for the renderers live under
settei/test/golden/ and are compared by settei/test/Settei/RenderTest.hs; this plan adds
no golden scenarios and expects no golden drift.

The test suite (`settei-tests` in settei/settei.cabal) uses `hs-source-dirs: test src`,
meaning it compiles the library sources directly. Test modules can therefore import
internal modules such as `Settei.Internal.Schema` (already listed in the test suite's
`other-modules`), though only their exported names. The existing adversarial redaction
test is `redactionTest` in settei/test/Settei/RenderTest.hs; it injects the sentinel
`"S3cr3t-\"\\\n-[]{}-雪"` and asserts it is absent from every supported output. This plan
follows that pattern.

Relevant ADRs consulted:

- docs/adr/0002-inspectable-configuration-algebra.md — defines the `Config` GADT, the
  `Schema` terms (possible/necessary/conditional, required/optional), and the rule that
  schema merging is conservative ("necessary wins over conditional; required similarly
  wins over optional"). This plan extends that family of merge laws with "secret wins
  over public".
- docs/adr/0003-resolution-provenance-and-default-semantics.md — defines the redaction
  contract: "Redaction is applied before data enters a report or structured error",
  `ReportedValue` constructors are private, and the observable law that a secret sentinel
  is absent from every output. This plan amends ADR 0003 with a dated note recording the
  most-restrictive rule and the conflict error (see Milestone 4).

No other ADR is relevant; docs/adr/0001-haskell-project-conventions.md governs style
(GHC2024, `-Wall -Wcompat`, generic-lens `#field` labels, ormolu-style formatting — match
the surrounding code).

Coordination context from the MasterPlan: EP-12
(docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md) will later change
the return shape of `resolve` so reports and warnings are available on failure. EP-12
consumes whatever `ConfigError` constructors exist and must not rename or remove
`SensitivityConflict`; keep the constructor and problem-record names exactly as specified
here so EP-12 rebases cleanly. EP-9 has no dependencies and is implementable from the
current tree.


## Plan of Work

The work is four milestones. Each is independently verifiable with the test suite, and
each ends with a commit. Milestone 1 makes the schema honest (defense layer one).
Milestone 2 adds the structured error and the validation gate (the user-visible
behavior). Milestone 3 makes report-node construction and merging most-restrictive
(defense layer two). Milestone 4 proves the whole with adversarial tests and updates
every document that states the redaction guarantee.

### Milestone 1: Secret-biased schema merge with declared-sensitivity tracking

Scope: settei/src/Settei/Internal/Schema.hs plus tests. At the end, `describe` on a
declaration that names one key both `Public` and `Secret` returns a schema whose entry
for that key has sensitivity `Secret` regardless of declaration order, and the schema
also remembers that both sensitivities were declared, which Milestone 2 uses for
detection.

In settei/src/Settei/Internal/Schema.hs make three edits. First, add a new strict field
to `SchemaSetting`:

```haskell
data SchemaSetting = SchemaSetting
  { key :: !Key,
    description :: !Text,
    sensitivity :: !Sensitivity,
    declaredSensitivities :: !(Set Sensitivity),
    requirement :: !Requirement,
    presence :: !Presence
  }
  deriving stock (Generic, Eq, Show)
```

`declaredSensitivities` is the set of every sensitivity this key was declared with
anywhere in the declaration; `sensitivity` remains the single effective (now
most-restrictive) value that all existing consumers read. The constructor is already
private to the library (Settei.Schema exports only the type and accessor functions), so
the field is an internal, additive change. Note that `Sensitivity` already derives `Ord`
(settei/src/Settei/Setting.hs), which `Set Sensitivity` requires.

Second, initialize the field in `requestSchema`: the `entry` record gains
`declaredSensitivities = Set.singleton (settingSensitivity settingSpec)`.

Third, replace `mergeSetting` so sensitivity merges most-restrictively and the declared
set accumulates, keeping requirement/presence merging exactly as today:

```haskell
mergeSetting :: SchemaSetting -> SchemaSetting -> SchemaSetting
mergeSetting left right =
  left
    & #sensitivity
    .~ mergeSensitivity (left ^. #sensitivity) (right ^. #sensitivity)
    & #declaredSensitivities
    .~ Set.union (left ^. #declaredSensitivities) (right ^. #declaredSensitivities)
    & #requirement
    .~ mergeRequirement (left ^. #requirement) (right ^. #requirement)
    & #presence
    .~ mergePresence (left ^. #presence) (right ^. #presence)

-- | Secret wins: a key declared secret anywhere is secret everywhere.
mergeSensitivity :: Sensitivity -> Sensitivity -> Sensitivity
mergeSensitivity Secret _ = Secret
mergeSensitivity _ Secret = Secret
mergeSensitivity Public Public = Public
```

Write `mergeSensitivity` as an explicit pattern match (matching the style of
`mergeRequirement` and `mergePresence`) rather than relying on the derived `Ord`, so the
dominance rule is visible and independent of constructor order. Export
`mergeSensitivity` from the module's export list; Milestone 3's effective-sensitivity
helper in Settei.Resolve reuses it. The description stays left-biased (Decision Log).

Tests: add cases to settei/test/Settei/ConfigTest.hs (the module that owns `describe`
behavior; it already imports `Settei` and can also import `Settei.Schema` accessors).
Declare one key — use `database.password` — as `secretSetting` and `publicSetting` with a
plain `textDecoder`, compose both with `(,) <$> required a <*> required b`, and assert
`schemaSettingSensitivity` of the merged entry is `Secret` for BOTH composition orders.
Add a variant where the `Public` duplicate sits on the effectful side of a `select`
branch, and a variant where it sits inside a `withDefault` derived-default dependency,
asserting `Secret` in each — `describeConfig` unions branch and dependency schemas, so
these must merge too. Also assert `renderSchemaText` for the conflicted declaration
contains `"secret"` and not `"public"` on the conflicted key's line.

Acceptance: `nix develop -c cabal test settei-tests --test-show-details=direct` from the
repository root passes, including the new cases; the eight golden files under
settei/test/golden/ are byte-identical (`git status` shows no changes there) because the
golden snapshot declarations contain no duplicate keys.

### Milestone 2: the SensitivityConflict error, its validation gate, and rendering

Scope: settei/src/Settei/Error.hs, settei/src/Settei/Resolve.hs,
settei/src/Settei/Render.hs, plus every exhaustive `ConfigError` match and tests. At the
end, `resolve` on a conflicted declaration returns `Left` with a `SensitivityConflict`
error naming the key, rendered in both text and JSON.

In settei/src/Settei/Error.hs add a problem record following the shape of
`MissingProblem`, and a constructor at the end of `ConfigError`:

```haskell
-- | One key was declared with both public and secret sensitivity.
data SensitivityConflictProblem = SensitivityConflictProblem
  { key :: !Key
  }
  deriving stock (Generic, Eq, Show)
```

Add `SensitivityConflict !SensitivityConflictProblem` as the last `ConfigError`
constructor and export `SensitivityConflictProblem (..)` from the module header. The
top-level `Settei` module re-exports `Settei.Error` wholesale, so no further export
plumbing is needed (verify by checking settei/src/Settei.hs re-export list; if it
enumerates names instead of re-exporting the module, add the new names there too).

In settei/src/Settei/Resolve.hs add a pre-evaluation validation pass analogous to
`validateDefaultCycles` and `validateStructure`. Because Milestone 1 made the schema
carry `declaredSensitivities`, this is one pass over `schemaPossible`:

```haskell
validateSensitivityConflicts :: [SchemaSetting] -> [ConfigError]
validateSensitivityConflicts schemaSettings =
  [ SensitivityConflict (SensitivityConflictProblem {key = schemaSettingKey schemaSetting})
  | schemaSetting <- schemaSettings,
    Set.size (schemaSetting ^. #declaredSensitivities) > 1
  ]
```

This needs `import Data.Set qualified as Set` in Settei.Resolve. The `#declaredSensitivities`
label works through the `Generic` instance even though the constructor is not exported.
`schemaPossible` returns entries in key order, so multiple conflicts report
deterministically in key order.

Wire the gate into `resolve` as the second pure declaration-level validation step. The
default-cycle gate must remain first because computing `schemaSettings` follows default
dependencies and therefore cannot terminate for an already-invalid cyclic declaration:

```haskell
resolve options sources config =
  case NonEmpty.nonEmpty (validateDefaultCycles config) of
    Just errors -> Left errors
    Nothing -> case NonEmpty.nonEmpty (validateSensitivityConflicts schemaSettings) of
      Just errors -> Left errors
      Nothing -> resolveValidated
```

`schemaSettings` is already computed in `resolve`'s `where` clause as
`schemaPossible (describeEvaluation config)`; it is source-free but only safe to force
after default-cycle validation succeeds. This keeps declaration inspection ahead of any
source lookup while preserving termination. Multiple sensitivity conflicts still report
deterministically in key order; a declaration containing both a default cycle and a
sensitivity conflict reports the cycle first because its schema cannot safely be built.

In settei/src/Settei/Render.hs extend the two closed case expressions, following the
existing patterns exactly. In `renderErrorText`:

```haskell
SensitivityConflict problem ->
  renderKey (problem ^. #key)
    <> ": declared with both public and secret sensitivity; treated as secret"
```

In `errorJson` (additive, `schemaVersion` stays 1):

```haskell
SensitivityConflict problem ->
  jsonObject
    [ ("kind", jsonString "sensitivity-conflict"),
      ("key", jsonString (renderKey (problem ^. #key)))
    ]
```

Adding a `ConfigError` constructor makes three existing exhaustive matches incomplete.
Update all of them (find them with `grep -rn "DefaultCycle" --include='*.hs' .`, since
`DefaultCycle` was previously the last constructor):

- `errorKey` in settei/test/Settei/ResolveTest.hs (line ~134): add
  `SensitivityConflict problem -> problem ^. #key`.
- The analogous helper in examples/settei-conformance/test/Settei/Example/ConformanceTest.hs
  (line ~357): same one-line addition.
- The analogous helper in examples/settei-service/test/Settei/Example/ServiceTest.hs
  (line ~99): same one-line addition.

These example edits are the only changes outside `settei/` and docs; the reference
applications themselves declare no conflicting keys, so no other example change is
expected (EP-14 re-validates the conformance boundary).

Tests: in settei/test/Settei/ResolveTest.hs add a test "conflicting sensitivity
declarations fail with a structured error": build
`(,) <$> required (secretSetting databasePassword "Database password" textDecoder)
<*> required (publicSetting databasePassword "Metrics label" textDecoder)`, resolve it
against a source that provides a value for `database.password`, and assert the result is
`Left` whose only element is `SensitivityConflict` with `problem ^. #key @?=
databasePassword`; repeat with the two requests swapped. Add a test asserting the
conflict is still reported when the public duplicate is inside an unselected selective
branch (reuse the `productionPassword` pattern in that file), proving the gate is
whole-declaration and pre-evaluation. In settei/test/Settei/RenderTest.hs add a test
asserting `renderErrorsText` of the conflict contains the key and the phrase
`"both public and secret"`, and `renderErrorsJson` contains
`"\"kind\":\"sensitivity-conflict\""`.

Acceptance: `nix develop -c cabal test settei-tests --test-show-details=direct` passes;
`nix develop -c cabal test all --test-show-details=direct` passes (this compiles the
example test helpers, catching any missed exhaustive match).

### Milestone 3: most-restrictive report nodes (defense in depth)

Scope: settei/src/Settei/Resolve.hs and settei/src/Settei/Provenance.hs. At the end, no
report node can be constructed or merged with a weaker sensitivity than the most
restrictive declaration of its key anywhere in the whole declaration, independent of the
Milestone 2 gate.

First, in settei/src/Settei/Provenance.hs add and export a total redaction function:

```haskell
-- | Collapse any retained display representation to the redaction marker.
redactReportedValue :: ReportedValue -> ReportedValue
redactReportedValue _ = RedactedValue
```

This is additive public API on an exposed module and is safe by construction: it can only
discard information. It exists because `ReportedValue` constructors are private (ADR
0003), so Settei.Resolve cannot otherwise downgrade an already-built `VisibleValue`.

Second, in settei/src/Settei/Resolve.hs compute the effective sensitivity map once in
`resolve` and thread it through evaluation. Add to `resolve`'s `where` clause:

```haskell
sensitivities :: Map Key Sensitivity
sensitivities =
  Map.fromList
    [ (schemaSettingKey schemaSetting, schemaSettingSensitivity schemaSetting)
    | schemaSetting <- schemaSettings
    ]
```

Because Milestone 1 made the merge Secret-biased, `schemaSettingSensitivity` is already
the most restrictive sensitivity across ALL declarations of that key in the whole
declaration, including selective branches and default dependencies (which
`describeConfig` unions in). Add a lookup helper next to `evaluateSetting`:

```haskell
effectiveSensitivity :: Map Key Sensitivity -> Setting a -> Sensitivity
effectiveSensitivity sensitivities settingSpec =
  mergeSensitivity
    (settingSensitivity settingSpec)
    ( fromMaybe
        (settingSensitivity settingSpec)
        (Map.lookup (settingKey settingSpec) sensitivities)
    )
```

(`mergeSensitivity` is exported from Settei.Internal.Schema in Milestone 1; import it.
The `mergeSensitivity` with the local sensitivity means that even an impossible missing
map entry can only make the result MORE restrictive, never less.)

Change the signatures of `evaluate`, `evaluateRequest`, `evaluateDefaultRequest`,
`evaluateFallback`, `evaluateSetting`, `derivedFromDependencies`, `derivedEvaluation`,
`derivedNode`, `defaultReportedValue`, and `missingNode` to accept the
`Map Key Sensitivity` (a small record or an extra first parameter — an extra parameter
matches the module's current style of passing `sources`). Every recursive `evaluate`
call, including the `SelectConfig` branch evaluation and the default-dependency
evaluations in `evaluateFallback`, passes the same top-level map, which is valid because
the map was computed from the whole declaration's schema. Then replace every use of
`settingSensitivity settingSpec` that feeds a report or error with
`effectiveSensitivity sensitivities settingSpec`. Concretely, the replacement points are:

- `evaluateSetting`: the node's `sensitivity` field, the `reportedValue ... rawValue`
  call inside `outcome = Resolved ...` (line ~350 today), and the
  `rejected = reportedValue ... rawValue` field of `DecodeProblem`.
- `missingNode`: the `sensitivity` field.
- `derivedNode`: the `sensitivity` field.
- `defaultReportedValue`: the `case settingSensitivity settingSpec of` scrutinee, so a
  typed default for a conflicted key is stored as `RedactedValue`, and the public
  renderer branch (`settingValueRenderer`) is never consulted when the effective
  sensitivity is `Secret`.

Decoding is untouched: `decodeSetting settingSpec rawValue` still runs with the setting's
own decoder; only what is RETAINED FOR DISPLAY changes.

Third, harden the node-map unions. In `applyEvaluation` and in the `Right (Left input)`
branch of the `SelectConfig` case, replace `Map.union` with
`Map.unionWith mergeNodes`, where:

```haskell
mergeNodes :: ResolutionNode -> ResolutionNode -> ResolutionNode
mergeNodes left right
  | left ^. #sensitivity == Secret || right ^. #sensitivity == Secret =
      left
        & #sensitivity
        .~ Secret
        & #outcome
        %~ redactOutcome
  | otherwise = left

redactOutcome :: ResolutionOutcome -> ResolutionOutcome
redactOutcome = \case
  Resolved value -> Resolved (redactReportedValue value)
  outcome -> outcome
```

This preserves today's left bias for all metadata (origin, shadowed, derivation) — no
behavior change for non-conflicted declarations — while guaranteeing that if two nodes
for one key ever disagreed on sensitivity, the merged node is secret and redacted. After
the effective-sensitivity change this branch is unreachable in practice (all nodes for a
key agree), which is exactly what defense in depth means: two independent mechanisms must
both fail before a value leaks.

Tests: with the Milestone 2 gate in place, a mixed-sensitivity report is unreachable
through `resolve` (the plan's Decision Log records this), so this milestone's layers are
tested at their seams. In a new test group (put it in
settei/test/Settei/ResolveTest.hs), import `Settei.Internal.Schema` (available to the
test suite; add nothing to the cabal file — the module is already in the test suite's
`other-modules`) and assert `mergeSensitivity` dominance directly for all four argument
combinations. Assert via `describe` plus `schemaSettingSensitivity` (public API) that the
map the resolver derives is `Secret` for a conflicted key in both orders (this repeats a
Milestone 1 assertion at the point of consumption and is cheap). Unit-test
`redactReportedValue`: for a `visibleReportedValue "x"`, a
`derivedReportedValue Public`, and a `reportedValue Secret (RawText "x")` input,
`renderReportedValue (redactReportedValue v)` is `"<redacted>"`. Existing suites cover
the no-regression side: all current resolve/render/golden tests must still pass
unchanged, proving the threading did not alter any non-conflicted behavior.

Acceptance: `nix develop -c cabal test settei-tests --test-show-details=direct` passes;
`git status` still shows no modification under settei/test/golden/.

### Milestone 4: adversarial sentinel proof and documentation

Scope: settei/test/Settei/RenderTest.hs, docs/adr/0003, docs/security.md,
settei/CHANGELOG.md, docs/guides/getting-started.md, and the MasterPlan bookkeeping. At
the end, the redaction guarantee for conflicted keys is proven against a hostile
sentinel, and every document that states the guarantee tells the new truth.

Add a test `sensitivityConflictRedactionTest` to settei/test/Settei/RenderTest.hs,
modeled on the existing `redactionTest` in that file. Define a distinctive sentinel local
to the test, for example:

```haskell
conflictSentinel :: Text
conflictSentinel = "CONFLICT-S3cr3t-\"\\\n-[]{}-雪"
```

Build the conflicting declaration (same `database.password` key declared with
`secretSetting` and `publicSetting`, composed applicatively) and a source whose
`database.password` leaf is `RawText conflictSentinel`. Then:

- Assert `resolve defaultResolveOptions [sentinelSource] conflictingConfig` returns
  `Left errors` where the errors include `SensitivityConflict` for the key (the
  behavioral contract).
- Collect every output producible from this scenario and assert the sentinel is absent
  from all of them: `renderSchemaText (describe conflictingConfig)`,
  `renderSchemaJson (describe conflictingConfig)`, `renderErrorsText errors`,
  `renderErrorsJson errors`, and `Text.pack (show errors)`.
- Cover the resolution renderers: resolve the secret-only half of the declaration (just
  the `secretSetting` request) against the same sentinel source, take its report, and
  assert the sentinel is absent from `renderResolutionText`, `renderResolutionJson`, and
  `Text.pack (show report)`. Add a code comment (and keep the note in this plan) that a
  report for the MIXED declaration is unreachable through `resolve` because the
  `SensitivityConflict` gate fails first, and that EP-12
  (docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md), which makes
  reports available on failure, must extend this test to the failure-path report without
  renaming the constructor.
- Assert `renderSchemaText (describe conflictingConfig)` marks the key `secret` (the
  most-restrictive rule is user-visible in schema output).

Documentation edits, each stating the same rule in that document's voice:

- docs/adr/0003-resolution-provenance-and-default-semantics.md: append a dated amendment
  section at the end of the file (do not rewrite existing prose; the MasterPlan requires
  each amendment to be its own dated note), for example a heading "Amendment 2026-07-19:
  most-restrictive sensitivity and conflict error", recording that (1) when one key is
  declared with multiple sensitivities, schema merging and every report representation
  use the most restrictive (`Secret` wins), and (2) `resolve` reports the structured
  error `SensitivityConflict` for any key declared both `Public` and `Secret`, before
  evaluation, alongside default-cycle validation. Use the implementation date if it
  differs.
- docs/security.md, section "Redaction guarantees": add a short paragraph stating that a
  key declared `Secret` anywhere in a declaration is treated as secret everywhere — a
  conflicting `Public` declaration of the same key cannot weaken redaction — and that
  such a conflict is additionally reported as the structured `SensitivityConflict`
  resolution error rather than being silently merged.
- settei/CHANGELOG.md: add two bullets under the `0.1.0.0` section (unreleased; see
  Decision Log): one for the most-restrictive sensitivity merge in schemas and reports,
  one for the new `SensitivityConflict` error and its `sensitivity-conflict` JSON kind.
- docs/guides: `grep -rn "sensitiv" docs/guides` and review each hit. The statement in
  docs/guides/getting-started.md near line 104 ("Use `secretSetting` for every credential
  or sensitive value; Settei then redacts the value…") should gain one sentence:
  declaring the same key with different sensitivity in one declaration is a resolve-time
  error, and reports always use the most restrictive declaration. No other guide
  currently makes a claim invalidated by this change (the other hits are Kubernetes
  Secret objects and adapter prose); if review finds one, update it and record it in
  Surprises & Discoveries.

Finally, update the MasterPlan
docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md: set EP-9's
registry row status (In Progress at the first commit, Complete at the last) and tick the
two EP-9 Progress checkboxes when done. Perform the ADR distillation pass required by the
ExecPlan specification: the durable decisions here (most-restrictive rule, conflict
error) land in the ADR 0003 amendment above; confirm nothing else in this plan's Decision
Log or Surprises & Discoveries needs promotion, then write the Outcomes & Retrospective
entry.

Acceptance: full workspace validation green (commands in Validation and Acceptance) and
all listed documents updated.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/settei` unless
stated otherwise. The project builds inside its Nix development shell; prefix every cabal
invocation with `nix develop -c`.

Before starting, confirm the tree is clean and the baseline is green:

```bash
git status
nix develop -c cabal test settei-tests --test-show-details=direct
```

Expect every test to pass, ending with output like:

```text
All 60 tests passed (...)
Test suite settei-tests: PASS
```

(The exact count will differ; what matters is `PASS` and zero failures. If the baseline
fails, stop and investigate before changing anything.)

Then, per milestone:

1. Milestone 1 — edit settei/src/Settei/Internal/Schema.hs (field, `requestSchema`
   initializer, `mergeSetting`, `mergeSensitivity`, export list) and add the schema-merge
   tests to settei/test/Settei/ConfigTest.hs. Run the targeted suite:

   ```bash
   nix develop -c cabal test settei-tests --test-show-details=direct
   ```

   Confirm no golden drift:

   ```bash
   git status settei/test/golden/
   ```

   Expected: no modified files listed. Commit.

2. Milestone 2 — edit settei/src/Settei/Error.hs, settei/src/Settei/Resolve.hs (gate),
   settei/src/Settei/Render.hs (text + JSON), update the three exhaustive matches found
   by:

   ```bash
   grep -rn "DefaultCycle" --include='*.hs' .
   ```

   Add the resolve-level and render-level tests. Run the full workspace so the example
   test helpers compile:

   ```bash
   nix develop -c cabal test all --test-show-details=direct
   ```

   Expected: every package's suite reports `PASS`. A compile error in
   examples/settei-conformance or examples/settei-service about non-exhaustive patterns
   means a helper was missed. Commit.

3. Milestone 3 — edit settei/src/Settei/Provenance.hs (`redactReportedValue` plus export)
   and settei/src/Settei/Resolve.hs (sensitivity map, threading, `effectiveSensitivity`,
   `mergeNodes`/`redactOutcome`, `Map.unionWith` at both union sites). Add the seam
   tests. Run:

   ```bash
   nix develop -c cabal test settei-tests --test-show-details=direct
   git status settei/test/golden/
   ```

   Expected: pass, no golden drift. Commit.

4. Milestone 4 — add `sensitivityConflictRedactionTest` to
   settei/test/Settei/RenderTest.hs; edit docs/adr/0003, docs/security.md,
   settei/CHANGELOG.md, docs/guides/getting-started.md; update the MasterPlan registry
   row, MasterPlan Progress, and this plan's living sections. Run the full validation:

   ```bash
   nix develop -c cabal test all --test-show-details=direct
   ```

   Commit.

Every commit must use the Conventional Commits specification (`feat:`, `fix:`, `test:`,
`docs:` etc., with an appropriate scope) and must carry these three trailers exactly:

```text
MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
ExecPlan: docs/plans/9-close-the-shared-key-sensitivity-redaction-hole.md
Intention: intention_01kxxdt2f0enp928nc1wbcsd2t
```

Suggested commit messages (adjust if the split differs, keep the trailers):

```text
fix(settei): merge duplicate schema sensitivity most-restrictively

Track every declared sensitivity per key in SchemaSetting and make
mergeSetting Secret-biased so describe never reports a secret key as
public.

MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
ExecPlan: docs/plans/9-close-the-shared-key-sensitivity-redaction-hole.md
Intention: intention_01kxxdt2f0enp928nc1wbcsd2t
```

```text
feat(settei): report SensitivityConflict for mixed-sensitivity keys

Add a pre-evaluation validation gate, the SensitivityConflictProblem
record, and text/JSON rendering (kind "sensitivity-conflict",
schemaVersion 1, additive).

MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
ExecPlan: docs/plans/9-close-the-shared-key-sensitivity-redaction-hole.md
Intention: intention_01kxxdt2f0enp928nc1wbcsd2t
```

```text
fix(settei): build and merge report nodes with effective sensitivity

Thread a per-key most-restrictive sensitivity map through evaluation,
redact typed defaults for conflicted keys, and prefer redacted nodes
when unioning report node maps.

MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
ExecPlan: docs/plans/9-close-the-shared-key-sensitivity-redaction-hole.md
Intention: intention_01kxxdt2f0enp928nc1wbcsd2t
```

```text
docs(settei): record most-restrictive sensitivity rule and conflict error

Amend ADR 0003 with a dated note, update the security model redaction
guarantees, the getting-started guide, and the settei changelog; add
the adversarial conflict-sentinel test.

MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
ExecPlan: docs/plans/9-close-the-shared-key-sensitivity-redaction-hole.md
Intention: intention_01kxxdt2f0enp928nc1wbcsd2t
```

Commit directly to the current branch (`master`); this repository does not use feature
branches by default. Update this plan's Progress section at every stopping point.


## Validation and Acceptance

The change is accepted when all of the following observable behaviors hold, in addition
to a fully green test run.

Behavior 1 — the conflict is a structured error. Resolving any acyclic declaration that
names one key with both `Public` and `Secret` sensitivity returns `Left` containing
`SensitivityConflict (SensitivityConflictProblem {key = <that key>})`, regardless of
declaration order and even when one duplicate sits inside an unselected selective branch
or a default dependency. `renderErrorsText` for it reads, for the key
`database.password`:

```text
database.password: declared with both public and secret sensitivity; treated as secret
```

and `renderErrorsJson` contains the object
`{"kind":"sensitivity-conflict","key":"database.password"}` inside a `schemaVersion: 1`
`settei.errors` document.

A declaration containing a default cycle is rejected by `DefaultCycle` before its static
schema is built; if it also contains a sensitivity conflict, the cycle is reported first
because following the cyclic defaults to compute sensitivity metadata cannot terminate.

Behavior 2 — most-restrictive schema. `describe` on the same declaration yields a schema
whose entry for the key has sensitivity `Secret`; `renderSchemaText` shows `secret` in
that key's bracket metadata.

Behavior 3 — the sentinel never leaks. The new adversarial test injects a sentinel
containing quotes, backslashes, a newline, punctuation, and non-ASCII text through a
source for the conflicted key and asserts the sentinel is absent from
`renderSchemaText`, `renderSchemaJson`, `renderErrorsText`, `renderErrorsJson`,
`renderResolutionText`, `renderResolutionJson`, and every `Show` rendering produced in
the scenario. This test fails on the pre-fix code (the public declaration's report node
renders the raw value) and passes after.

Behavior 4 — no regression. Every pre-existing test passes unchanged and the eight golden
files under settei/test/golden/ are byte-identical. A golden diff means non-conflicted
behavior changed, which this plan forbids; find and fix the cause rather than
regenerating goldens.

Test commands and expected results, from the repository root:

```bash
nix develop -c cabal test settei-tests --test-show-details=direct
```

Expected: all tests pass, including the new groups; output ends with
`Test suite settei-tests: PASS`.

```bash
nix develop -c cabal test all --test-show-details=direct
```

Expected: every package in the workspace (core, adapters, examples) reports `PASS`. This
also proves the two example test-helper updates compile under `-Wall`.

To see the failure mode the plan fixes, you can run the new adversarial test against the
unmodified tree first (it will fail with the sentinel found in `renderResolutionText`
output); capture that failing transcript in Surprises & Discoveries as evidence.


## Idempotence and Recovery

Every step is additive and safe to repeat. Re-running any test command is side-effect
free. Re-applying an edit that is already present is a no-op; if an edit half-landed,
`git diff` against the last milestone commit shows exactly what remains.

The milestones are ordered so the tree is releasable after each commit: Milestone 1 alone
only strengthens schema merging (strictly safer), Milestone 2 alone adds a new error
(strictly stricter), Milestone 3 alone only redacts more, and Milestone 4 is tests and
docs. If a milestone goes wrong, `git revert` its commit; no migration, generated file,
or external state is involved. Golden files must never be regenerated under this plan —
if a golden comparison fails, the code change is wrong (see Validation, Behavior 4).

The only semi-risky edit is threading the sensitivity map through the evaluation
functions in settei/src/Settei/Resolve.hs, because it touches many signatures at once.
Recovery path: the compiler is the guide — make the signature changes first, then chase
type errors until `nix develop -c cabal build settei` is clean, then run the tests. If
interrupted midway, the package simply does not compile; nothing is silently wrong.

If a rebase conflict arises with a concurrently landing plan (EP-10 through EP-13 touch
disjoint files except EP-12, which is soft-ordered AFTER this plan), re-run the full
`cabal test all` after resolving; the MasterPlan's Dependency Graph section records the
serialization intent.


## Interfaces and Dependencies

No new package dependencies. The work uses only what settei/settei.cabal already
declares: base, containers (`Data.Map.Strict`, `Data.Set`), generic-lens (the `#field`
labels), lens, selective, text, and for tests tasty and tasty-hunit. All modules named
below already exist except where noted.

At the end of Milestone 1, settei/src/Settei/Internal/Schema.hs (internal module) must
export, in addition to today's names:

```haskell
mergeSensitivity :: Sensitivity -> Sensitivity -> Sensitivity
```

and `SchemaSetting` must carry `declaredSensitivities :: !(Set Sensitivity)` alongside
the existing `sensitivity :: !Sensitivity`, with `sensitivity` equal to the
`mergeSensitivity`-fold of every declared sensitivity. No public (exposed-module) API
changes in this milestone.

At the end of Milestone 2, settei/src/Settei/Error.hs (public) must export:

```haskell
data SensitivityConflictProblem = SensitivityConflictProblem {key :: !Key}
```

with `Generic`, `Eq`, `Show` derived, and `ConfigError` must gain the constructor
`SensitivityConflict !SensitivityConflictProblem`. This constructor name and record shape
are frozen for EP-12 (docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md),
which reshapes `resolve`'s return type and must consume this constructor unrenamed
(MasterPlan integration point "Shared error vocabulary"). The JSON kind string is
`sensitivity-conflict`; JSON documents remain `schemaVersion: 1`. The signature of
`resolve` in settei/src/Settei/Resolve.hs is unchanged by THIS plan:

```haskell
resolve :: ResolveOptions -> [Source] -> Config a -> Either (NonEmpty ConfigError) (ResolveResult a)
```

At the end of Milestone 3, settei/src/Settei/Provenance.hs (public) must additionally
export:

```haskell
redactReportedValue :: ReportedValue -> ReportedValue
```

and settei/src/Settei/Resolve.hs must contain the private helpers with these shapes
(names may not drift, so the plan stays a reliable map of the module):

```haskell
validateSensitivityConflicts :: [SchemaSetting] -> [ConfigError]
effectiveSensitivity :: Map Key Sensitivity -> Setting a -> Sensitivity
mergeNodes :: ResolutionNode -> ResolutionNode -> ResolutionNode
```

Nothing else in the public surface changes. `mergeRequirement` and `mergePresence` in
settei/src/Settei/Internal/Schema.hs are explicitly out of scope and must remain
byte-identical.


## Revision Note

2026-07-19: Revised Milestone 2 after validation exposed that combining default-cycle and
sensitivity-conflict error lists forces static schema description for cyclic defaults and
does not terminate. The implemented resolver now preserves default-cycle validation as
the first gate and runs sensitivity-conflict validation second for acyclic declarations;
the Progress, Surprises & Discoveries, Decision Log, Plan of Work, and acceptance context
record the ordering and its evidence.
