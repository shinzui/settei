---
id: 12
slug: report-resolution-provenance-and-warnings-on-failure
title: "Report resolution provenance and warnings on failure"
kind: exec-plan
created_at: 2026-07-19T14:54:42Z
intention: "intention_01kxxdt2f0enp928nc1wbcsd2t"
master_plan: "docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md"
---

# Report resolution provenance and warnings on failure

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Today, `resolve` in `settei/src/Settei/Resolve.hs` has this public type:

```haskell
resolve :: ResolveOptions -> [Source] -> Config a -> Either (NonEmpty ConfigError) (ResolveResult a)
```

The `ResolveResult` record — the typed value, the `ResolutionReport` (the provenance
trace: which sources were consulted, which candidate won each setting, which candidates
were shadowed, which selective branches ran, which named default rules fired), and the
list of `ConfigWarning` values — exists only on the `Right` side. When resolution fails,
the caller receives only errors. The report and the warnings are thrown away.

That is exactly backwards for operators. A 2026-07-19 API review found that resolution
failure is when the provenance view is needed most: an operator debugging a
crash-looping Kubernetes pod wants to see which sources were consulted, what won, what
was shadowed, what was missing, and which branches were selected — not just the terse
error list. The internal evaluator already builds every resolution node and branch trace
on failure paths (see `evaluationFailure` and `failed` in
`settei/src/Settei/Resolve.hs`); the information is discarded only at the public
boundary, in the `case ... of Left errors -> Left errors` plumbing at the top of
`resolve`.

After this change, `resolve` is total in its report and warnings:

```haskell
data ResolveResult a = ResolveResult
  { answer :: !(Either (NonEmpty ConfigError) a),
    report :: !ResolutionReport,
    warnings :: ![ConfigWarning]
  }

resolve :: ResolveOptions -> [Source] -> Config a -> ResolveResult a
```

The typed outcome moves into the `answer` field; the report and warnings are always
present. Both reference applications additionally gain the review's motivating behavior:
when resolution fails and the user asked for an explain mode (`--explain-config` or
`--explain-config-json`), the failure report is printed to stderr after the errors, so
an operator running the diagnostic inside a failing pod sees the full provenance view.
Exit codes are unchanged (`resolutionExitCode` stays 4).

You can see it working by running, from the repository root
`/Users/shinzui/Keikaku/bokuno/settei`:

```bash
nix develop -c cabal run settei-example-cli -- --set service.timeout=broken --explain-config
```

Before this change that prints only a decode error and exits 4. After this change it
prints the decode error followed by the full provenance report (every setting with its
winning origin, shadowed origins, missing markers, and branch decisions) to stderr, and
still exits 4.

This is a deliberate breaking change to the public `resolve` signature. Settei 0.1.0.0
has not shipped (no Hackage publication has occurred), so no external consumer exists;
the change is recorded in `settei/CHANGELOG.md` and in an amendment to
`docs/adr/0003-resolution-provenance-and-default-semantics.md`.


## Progress

- [ ] Milestone 1: reshape `ResolveResult` and `resolve` in `settei/src/Settei/Resolve.hs`; update haddocks in `Settei/Resolve.hs`, `Settei/Report.hs`, and `Settei/Render.hs`.
- [ ] Milestone 1: migrate `settei/test/Settei/ResolveTest.hs`, `settei/test/Settei/DefaultTest.hs`, and `settei/test/Settei/RenderTest.hs` to the new shape.
- [ ] Milestone 1: add failure-path semantics tests (evaluated nodes on failure, decode-failure node retains rejected value, not-selected completion, structural-exit report, cycle-exit report with empty warnings, warnings alongside errors, strict-policy parity, failure-report redaction).
- [ ] Milestone 1: add failure-path golden files `settei/test/golden/failure-resolution.txt` and `settei/test/golden/failure-resolution.json` plus their golden test cases.
- [ ] Milestone 1: `nix develop -c cabal test settei-tests --test-show-details=direct` passes; commit.
- [ ] Milestone 2: migrate the adapter test suites (`settei-yaml`, `settei-kdl`, `settei-dhall`, `settei-env`, `settei-optparse-applicative`) to the total result; commit.
- [ ] Milestone 3: migrate `examples/settei-cli/src/Settei/Example/Cli.hs` and `examples/settei-service/src/Settei/Example/Service.hs`; add failure-report-on-stderr behavior for explain modes.
- [ ] Milestone 3: migrate `examples/settei-cli/test/Settei/Example/CliTest.hs`, `examples/settei-service/test/Settei/Example/ServiceTest.hs`, and `examples/settei-conformance/test/Settei/Example/ConformanceTest.hs`; add new failure-report test cases; commit.
- [ ] Milestone 4: amend `docs/adr/0003-resolution-provenance-and-default-semantics.md` with a dated note; update `docs/guides/cli-application.md`, `docs/guides/kubernetes-service.md`, `README.md` (resolve snippet around lines 76–98), and `settei/CHANGELOG.md`; commit.
- [ ] Final: `nix develop -c cabal test all --test-show-details=direct` passes; update this plan's living sections; write Outcomes & Retrospective; confirm the ADR amendment covers the durable decisions.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Reshape `ResolveResult a` into a total outcome record —
  `answer :: Either (NonEmpty ConfigError) a`, `report :: ResolutionReport`,
  `warnings :: [ConfigWarning]` — and change `resolve` to return `ResolveResult a`
  directly instead of `Either (NonEmpty ConfigError) (ResolveResult a)`.
  Rationale: The report and warnings are meaningful on every resolution attempt, and
  failure is when operators need them most. A total record makes it impossible for the
  public boundary to discard them. The rejected alternative — keeping `resolve` as-is
  and adding a second entry point `resolveWithReport` — was rejected because two entry
  points would drift over time and the roughly 70 adopting codebases would standardize
  on whichever they saw first, most likely the lossy one. Recorded also as the amendment
  to docs/adr/0003. The implementer may refine field strictness but not the shape.
  Date: 2026-07-19

- Decision: Rename the typed-value field from `value` to `answer`.
  Rationale: Every existing caller reads `result ^. #value` expecting a plain `a`. If
  the field kept its name but changed type to `Either ...`, some call sites (those that
  only pass the value along polymorphically) could keep compiling with silently changed
  meaning. Renaming forces every consumer to be visited and consciously migrated; the
  compiler enumerates the complete migration surface.
  Date: 2026-07-19

- Decision: On evaluated failures (missing required values, decode errors, failed
  default rules, strict unknown-key errors), the failure report contains every node the
  evaluator built up to and including the failure, then `addNotSelected` completes it
  exactly as on success, so every schema-possible setting appears (as `NotSelected` or
  `MissingValue`) rather than being absent.
  Rationale: The evaluator already carries `nodes` and `branches` through
  `evaluationFailure` and `failed`; symmetry with the success path means one mental
  model for report consumers and no "sparse report" special case in renderers.
  Date: 2026-07-19

- Decision: The two pre-evaluation validation exits still produce a report: its nodes
  are the schema-derived settings marked `NotSelected` with no origins, no shadowed
  origins, and no derivations (built by applying the existing `addNotSelected` to an
  empty node map), and its branch list is empty.
  Rationale: Honesty — evaluation never ran, so no setting was consulted, and
  `NotSelected` ("not evaluated in this run") is literally true. The alternative of
  marking them `MissingValue` was rejected because "missing" asserts that sources were
  consulted and nothing was found, which would be false on these paths. Returning an
  empty report was rejected because the operator would again face a blank screen; the
  schema-shaped skeleton at least shows what the resolver would have looked for.
  Date: 2026-07-19

- Decision: Warnings (unknown-key diagnostics) are computed and returned regardless of
  outcome, with one exception: the default-cycle preflight exit returns an empty
  warnings list and the schema-only report described above, and must not inspect any
  source.
  Rationale: ADR 0003 states the observable law "mutual default cycles fail before a
  source location function can be called", and `settei/test/Settei/DefaultTest.hs`
  enforces it with a `poisonSource` whose location function calls `error`. Computing
  unknown-key warnings walks `sourceLeaves` and candidate origins, which would poison
  that law. The structural-conflict exit happens after `lookupSource` has already
  traversed every source, so computing warnings there is safe and is done. Under
  `RejectUnknownKeys` the warnings list stays empty and the same problems surface as
  `UnknownKeyError` values in `answer`, exactly as today; the structural-conflict exit
  keeps today's error contents (structural errors only, strict unknown errors not
  appended) so no error-list behavior changes.
  Date: 2026-07-19

- Decision: A setting whose winning candidate failed to decode keeps the node that
  `evaluateSetting` already builds — outcome `Resolved` carrying the rejected
  candidate's sensitivity-redacted `ReportedValue`, the winning origin, and the shadowed
  origins — in the failure report.
  Rationale: That node is the valuable provenance: it shows the operator exactly which
  source supplied the bad value and what it displaced. The `DecodeError` in `answer`
  identifies the same origin, so report and errors corroborate each other. Report
  content remains secret-safe because `ReportedValue` redaction (via `reportedValue`
  and setting sensitivity in `Settei.Provenance`) is applied upstream of this change;
  this plan adds no new path by which raw candidate data can enter a report.
  Date: 2026-07-19

- Decision: The reference applications print the failure report to stderr, after the
  rendered errors, only when the diagnostic mode is an explain mode
  (`ExplainConfigurationText` / `ExplainConfigurationJson` in the CLI,
  `ExplainServiceConfigurationText` / `ExplainServiceConfigurationJson` in the service).
  Errors keep their current text rendering in all modes; the appended report uses the
  mode's format (text render, or JSON render plus a trailing newline). All exit codes
  are unchanged (`resolutionExitCode` = 4, `sourceExitCode` = 3, `usageExitCode` = 2),
  stdout stays empty on failure, and non-explain modes keep byte-identical output.
  Rationale: This is the review's motivating operator scenario with the smallest
  behavior delta. The ergonomics MasterPlan
  (docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md) rewrites
  these examples afterwards, so example edits here stay minimal and behavior-preserving
  beyond this one addition.
  Date: 2026-07-19

- Decision: Ship as a breaking change to the unreleased 0.1.0.0 API, recorded in
  `settei/CHANGELOG.md` under the 0.1.0.0 entry, with no compatibility shim.
  Rationale: Nothing has been published to Hackage; the reference applications and test
  suites are the only consumers and are migrated inside this plan (they are the
  conformance boundary per docs/adr/0007). A shim would preserve the lossy shape this
  plan exists to remove.
  Date: 2026-07-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This repository is a Cabal multi-package workspace at
`/Users/shinzui/Keikaku/bokuno/settei` for the Haskell configuration library Settei. All
commands in this plan run from that repository root inside the Nix development shell
(prefix every cabal command with `nix develop -c`). The packages relevant here:

- `settei/` — the core library. `settei/src/Settei.hs` re-exports the public modules,
  including `Settei.Resolve` (the resolver), `Settei.Report` (the report types),
  `Settei.Render` (text and versioned JSON renderers), and `Settei.Error` (the
  `ConfigError` and `ConfigWarning` vocabulary). Its test suite is `settei-tests` with
  modules under `settei/test/Settei/` and golden snapshots under `settei/test/golden/`.
- `settei-yaml/`, `settei-kdl/`, `settei-dhall/`, `settei-env/`,
  `settei-optparse-applicative/` — source adapters. Their own libraries do not call
  `resolve`, but each adapter's test suite does (each has a local helper
  `expectResolution :: Either (NonEmpty ConfigError) a -> IO a`).
- `examples/settei-cli/`, `examples/settei-service/`, `examples/settei-conformance/` —
  internal reference applications and the cross-format conformance suite. Per
  `docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md`,
  these are the public-API conformance boundary: every public-surface change must leave
  them compiling and their tests passing.

Vocabulary used throughout this plan, defined once:

- A "source" (`Settei.Source.Source`) is one named tree of raw values (a parsed file,
  an environment snapshot, command-line overrides). Sources are passed to `resolve`
  ordered from lowest to highest precedence; the rightmost candidate for a key wins.
- A "resolution report" (`Settei.Report.ResolutionReport`) is the secret-safe trace of
  one resolution run: a `Map Key ResolutionNode` plus a list of `BranchTrace` values.
  Each `ResolutionNode` records a key, its sensitivity, an outcome (`Resolved` with a
  redaction-safe `ReportedValue`, `MissingValue`, or `NotSelected`), the winning
  `Origin`, the shadowed origins, and an optional default-rule `Derivation`.
- A "warning" (`Settei.Error.ConfigWarning`, today only `UnknownKeyWarning`) is a
  non-fatal diagnostic: a source leaf not beneath any declared key.
- "Explain mode" is a diagnostic flag in the reference applications
  (`--explain-config`, `--explain-config-json`) that renders the resolution report
  instead of running the application action.

The current resolver (`settei/src/Settei/Resolve.hs`) works in three phases inside
`resolve` (around line 85):

1. Default-cycle preflight: `validateDefaultCycles` walks the declaration's default
   syntax with an active rule-name stack, before any source is inspected. A cycle
   returns `Left` immediately.
2. Structural validation: `validateStructure` runs `lookupSource` for every
   schema-possible key against every source; shape conflicts (traversing through a
   scalar, array, or null) return `Left` immediately.
3. Evaluation: `evaluate` interprets the declaration, building an internal
   `Evaluation a` record with `answer :: Either [ConfigError] a`,
   `nodes :: Map Key ResolutionNode`, and `branches :: [BranchTrace]`. Critically, the
   failure combinators `failed` (line ~402) and `evaluationFailure` (line ~321) carry
   `nodes` and `branches` through error paths, and `evaluateSetting` (line ~334) builds
   a full provenance node (winner, shadowed origins, redacted reported value) even when
   the winning candidate fails to decode. On success, `addNotSelected` (line ~443)
   completes the node map so every schema-possible setting appears; on failure, all of
   this is discarded when `resolve` returns `Left`.

Unknown-key handling: `findUnknownKeys` computes `UnknownKeyProblem` values from
`sourceLeaves`; under `WarnUnknownKeys` they become the `warnings` field, under
`RejectUnknownKeys` they are appended to the error side via `appendErrors` and the
warnings list is empty.

Relevant ADRs consulted (repository-relative paths):

- `docs/adr/0003-resolution-provenance-and-default-semantics.md` — defines report
  semantics, redaction (raw values never enter reports; `ReportedValue` constructors
  are private), the observable law that default cycles fail before any source location
  function is called, and the versioned JSON contract (`schemaVersion: 1`; additive
  fields keep version 1). This plan amends it with a dated note.
- `docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md` —
  the examples and conformance fixtures are the release gate for public-surface
  changes; this plan migrates them in the same change.
- `docs/adr/0001-haskell-project-conventions.md` — code style conventions for all edits.
- No other ADR is relevant to this work.

Parent MasterPlan integration constraints
(`docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md`):

- EP-9 (`docs/plans/9-close-the-shared-key-sensitivity-redaction-hole.md`) is a soft
  dependency: it adds a new sensitivity-conflict `ConfigError` constructor in
  `settei/src/Settei/Error.hs` and its rendering in `settei/src/Settei/Render.hs`. This
  plan must not rename or remove that constructor. If EP-9 has landed when you
  implement this plan, extend any exhaustive `ConfigError` matches you touch (for
  example the `errorKey` helper in `settei/test/Settei/ResolveTest.hs`) with its case,
  and prefer to exercise it in one failure-path report test. If EP-9 has not landed,
  proceed without it; nothing here depends on it.
- The ergonomics MasterPlan
  (`docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md`)
  rewrites the examples after this correctness MasterPlan completes. Keep example edits
  minimal and behavior-preserving beyond the specified failure-report printing.
- EP-14 (`docs/plans/14-revalidate-correctness-and-update-release-collateral.md`)
  re-reconciles all golden files and release collateral at the end; you still keep
  goldens green here.

Current caller inventory (the complete migration surface; every file below currently
matches on `Left`/`Right` of `resolve` or wraps its `Either`):

- Core tests: `settei/test/Settei/ResolveTest.hs`, `settei/test/Settei/DefaultTest.hs`,
  `settei/test/Settei/RenderTest.hs` (each has a local
  `expectSuccess :: Either (NonEmpty ConfigError) a -> IO a`; RenderTest also has
  `expectFailure`).
- Adapter tests: `settei-yaml/test/Settei/YamlTest.hs`,
  `settei-kdl/test/Settei/KdlTest.hs`, `settei-dhall/test/Settei/DhallTest.hs`,
  `settei-env/test/Settei/EnvTest.hs`,
  `settei-optparse-applicative/test/Settei/OptparseTest.hs` (each has
  `expectResolution`; OptparseTest also pattern matches `Left errors` directly at line
  ~42).
- Examples: `examples/settei-cli/src/Settei/Example/Cli.hs` (`resolveCliOptions` ~line
  215, `runCliWithSnapshot` ~line 203, `renderSuccess` ~line 259),
  `examples/settei-service/src/Settei/Example/Service.hs` (`resolveServiceOptions`
  ~line 264, `resolveServiceSources` ~line 277, `runServiceWithSnapshot` ~line 255,
  `renderServiceSuccess` ~line 330), and their tests
  `examples/settei-cli/test/Settei/Example/CliTest.hs`,
  `examples/settei-service/test/Settei/Example/ServiceTest.hs`,
  `examples/settei-conformance/test/Settei/Example/ConformanceTest.hs`.

Documentation touched: `docs/adr/0003-resolution-provenance-and-default-semantics.md`,
`docs/guides/cli-application.md` (the `resolveCli` snippet around lines 74–88 and the
exit-behavior and testing sections around lines 262–301),
`docs/guides/kubernetes-service.md` (the `resolveService` snippet around lines 203–212,
the startup sequence at lines 214–225, and "Expose safe diagnostics" around line 299),
`README.md` (the resolve snippet at lines 76–98), and `settei/CHANGELOG.md`.


## Plan of Work

### Milestone 1 — core: a total resolver result with failure-path tests

Scope: `settei/` only. At the end of this milestone, `resolve` returns
`ResolveResult a` unconditionally, the core test suite compiles against the new shape,
new tests pin down every failure-path semantic decided in the Decision Log, and a
failure-path golden pair exists. Run
`nix develop -c cabal test settei-tests --test-show-details=direct` from the repository
root; all tests pass.

In `settei/src/Settei/Resolve.hs`:

Change the `ResolveResult` record (currently at line ~69) to the total shape and update
its haddock from "The typed result plus its safe explanation" to describe the outcome
of one resolution attempt whose report and warnings are always present:

```haskell
-- | The outcome of one resolution attempt. The provenance report and non-fatal
-- warnings are always present; the typed value or the accumulated errors live in
-- 'answer'.
data ResolveResult a = ResolveResult
  { answer :: !(Either (NonEmpty ConfigError) a),
    report :: !ResolutionReport,
    warnings :: ![ConfigWarning]
  }
  deriving stock (Generic)
```

Rewrite `resolve` (line ~85) to be total. The three phases and all evaluation internals
(`Evaluation`, `evaluate`, `evaluateSetting`, `addNotSelected`, `appendErrors`,
`toNonEmpty`, and friends) are unchanged; only the boundary plumbing changes. The
target shape:

```haskell
resolve :: ResolveOptions -> [Source] -> Config a -> ResolveResult a
resolve options sources config =
  case NonEmpty.nonEmpty (validateDefaultCycles config) of
    Just errors ->
      -- Default-cycle preflight exit: no source has been inspected and none may be.
      ResolveResult
        { answer = Left errors,
          report = ResolutionReport {nodes = schemaOnlyNodes, branches = []},
          warnings = []
        }
    Nothing -> resolveValidated
  where
    resolveValidated =
      case NonEmpty.nonEmpty structuralErrors of
        Just errors ->
          -- Structural exit: sources were traversed, so warnings are computable,
          -- but evaluation never ran.
          ResolveResult
            { answer = Left errors,
              report = ResolutionReport {nodes = schemaOnlyNodes, branches = []},
              warnings = unknownWarnings
            }
        Nothing ->
          ResolveResult
            { answer =
                case appendErrors (evaluation ^. #answer) strictUnknownErrors of
                  Left errors -> Left (toNonEmpty errors)
                  Right value -> Right value,
              report =
                ResolutionReport
                  { nodes = completeNodes,
                    branches = evaluation ^. #branches
                  },
              warnings = unknownWarnings
            }
    schemaOnlyNodes = addNotSelected schemaSettings Map.empty
    -- schemaSettings, structuralErrors, evaluation, unknownProblems,
    -- unknownWarnings, strictUnknownErrors, completeNodes: unchanged from today.
```

Semantics this encodes, restated precisely (these become tests):

- (a) On an evaluated failure, `report` contains every node the evaluator built up to
  and including the failure, completed by `addNotSelected` identically to the success
  path (`completeNodes` is applied unconditionally), so schema-possible settings that
  were never reached appear as `NotSelected` and consulted-but-absent settings appear
  as `MissingValue`, never absent from the map. `branches` contains the traces built so
  far.
- (b) Both pre-evaluation exits produce the schema-only report: every schema-possible
  setting as a `NotSelected` node with `origin = Nothing`, `shadowed = []`,
  `derivation = Nothing`, and an empty branch list. Document this in the `resolve`
  haddock. The cycle exit additionally returns `warnings = []` and must not force any
  source (the `poisonSource` test in `settei/test/Settei/DefaultTest.hs` guards this;
  do not compute `unknownWarnings` on that path).
- (c) Warnings are computed and returned regardless of outcome on every path where
  sources may be inspected (structural exit and evaluated paths). Under
  `RejectUnknownKeys` the warnings list is empty and the same problems appear as
  `UnknownKeyError` values appended to `answer`'s error side, exactly as today. The
  structural exit keeps today's error contents (structural errors only).
- (d) A setting whose winning candidate failed to decode keeps its `Resolved` node with
  the rejected candidate's sensitivity-redacted `ReportedValue`, winning origin, and
  shadowed origins — `evaluateSetting` already builds this node; do not change it. This
  is deliberate, valuable provenance. Report content remains secret-safe because
  `ReportedValue` redaction is applied upstream (in `Settei.Provenance`) before any
  value enters a node; this plan adds no new data path into reports.

Update the `resolve` haddock to state that the report and warnings are produced for
every resolution attempt and to summarize the pre-evaluation-exit report contents.

In `settei/src/Settei/Report.hs`: update the `ResolutionReport` haddock ("Complete,
secret-safe trace for one successful resolution.") to say "one resolution attempt", and
the `renderResolutionText`/`renderResolutionJson` haddocks in
`settei/src/Settei/Render.hs` ("Render one successful resolution ...") likewise. No
renderer signature changes: both already take `ResolutionReport`, which is unchanged.

Migrate the core tests. The mechanical recipe, applied per call site:

- `result <- expectSuccess (resolve opts sources config)` becomes
  `let result = resolve opts sources config` followed by
  `value <- expectAnswer result`, where the helper is:

  ```haskell
  expectAnswer :: ResolveResult a -> IO a
  expectAnswer result = case result ^. #answer of
    Left errors -> fail ("expected successful resolution: " <> show errors)
    Right value -> pure value
  ```

  Uses of `result ^. #value` become `value`; uses of `result ^. #report` and
  `result ^. #warnings` are unchanged because those fields survive.
- `case resolve ... of Left errors -> ...; Right _ -> fail ...` becomes
  `case (resolve ...) ^. #answer of` with the same arms.
- In `settei/test/Settei/RenderTest.hs`, `expectFailure` becomes
  `ResolveResult a -> IO (NonEmpty ConfigError)` matching on `answer`.
- In `settei/test/Settei/ResolveTest.hs`, if EP-9's sensitivity-conflict constructor
  exists in `ConfigError`, add its case to the `errorKey` helper.

Add new failure-path tests. Put resolver-semantics cases in
`settei/test/Settei/ResolveTest.hs` (reusing its existing fixtures: `serviceConfig`,
`productionPassword`, `treeSource`, `environmentSource`) and renderer/golden cases in
`settei/test/Settei/RenderTest.hs`:

1. "failure report retains evaluated provenance": resolve `serviceConfig` against a
   source providing only `service.port`. Assert `answer` is `Left` with exactly
   `[MissingRequired]` for `service.host`; assert the report has a `service.port` node
   with outcome `Resolved` and its true origin, and a `service.host` node with outcome
   `MissingValue`.
2. "decode failure keeps the rejected candidate's provenance": lower source with a
   valid port, higher source with `RawText "not-a-port"`. Assert `answer` is `Left`
   with one `DecodeError` at the higher origin; assert the report node for
   `service.port` has outcome `Resolved` (the redacted reported value of the rejected
   candidate), origin named for the higher source, and the lower origin in `shadowed`.
3. "failure report completes not-selected settings": use `productionPassword` with a
   development environment source plus an unrelated failing required setting (compose
   with `<*>`), assert the failing run's report still contains the
   `database.password` node with outcome `NotSelected` and the branch trace with
   `selected = False`.
4. "structural exit still reports schema and warnings": a source whose `database` key
   is a scalar (reuse the existing "structural conflicts" fixture) plus an unknown
   leaf. Assert `answer` is `Left [StructuralConflict ...]`, every schema-possible key
   is present in the report with outcome `NotSelected` and no origin, `branches` is
   empty, and the unknown-key warning is returned.
5. "cycle exit reports schema only and touches no source": adapt the `poisonSource`
   test in `settei/test/Settei/DefaultTest.hs` — after asserting the `DefaultCycle`
   error, additionally force the full report (every node) and assert `warnings == []`.
   The poison location function proves no source was inspected.
6. "warnings accompany failures": one source with an unknown leaf and a missing
   required setting; assert `answer` is `Left` and `warnings` has the unknown-key
   warning. Then with `RejectUnknownKeys`, assert the unknown key appears in the error
   list and `warnings == []` (extend the existing "unknown keys warn by default" case).
7. In `settei/test/Settei/RenderTest.hs`, extend `redactionTest`: also render the
   failure result's report (`renderResolutionText`/`renderResolutionJson` of the
   `resolve` call that fails to decode the secret) and assert the secret sentinel is
   absent and `<redacted>` is present.

Add golden coverage for a failure-path report. In
`settei/test/Settei/RenderTest.hs`, build a failure report through the real resolver
(not hand-assembled): a small declaration with one required setting missing, one
setting whose winner fails to decode over a shadowed built-in, and one not-selected
branch; render with `renderResolutionText` and `renderResolutionJson` and compare
against new files `settei/test/golden/failure-resolution.txt` and
`settei/test/golden/failure-resolution.json` using the existing `assertGolden` helper.
To create the goldens the first time, print the rendered output (temporarily via
`TextIO.putStr` in a scratch GHCi session or by writing the expected content by hand
from the renderer's documented format) and save it; then the test pins it. The JSON
golden must show `"schemaVersion":1` and `"type":"settei.resolution"` — the document
shape is unchanged (this is not a new document type, so no schema-version bump; per
docs/adr/0003, additive/unchanged representations keep version 1).

Acceptance: `nix develop -c cabal test settei-tests --test-show-details=direct` passes
with the new cases listed in its output. The pre-existing golden files
(`resolution.txt`, `resolution.json`, `errors.*`, `warnings.*`, `schema.*`) must not
change — this milestone changes no rendered byte for existing documents.

### Milestone 2 — adapter test suites compile and pass unchanged in meaning

Scope: test-only edits in `settei-yaml`, `settei-kdl`, `settei-dhall`, `settei-env`,
and `settei-optparse-applicative`. These packages' libraries do not call `resolve`;
only their tests do. At the end, `nix develop -c cabal test all` no longer fails to
compile in any adapter suite.

Apply the Milestone 1 mechanical recipe: change each local
`expectResolution :: Either (NonEmpty ConfigError) a -> IO a` to
`ResolveResult a -> IO a` matching on `answer`, and in
`settei-optparse-applicative/test/Settei/OptparseTest.hs` change the direct
`case resolve ... of Left errors -> ...` (line ~42) to match on `^. #answer`. Where a
test also reads `^. #report` or `^. #warnings`, bind the `ResolveResult` with `let` and
extract the value separately. Every assertion keeps its current expected value; this
milestone changes no test meaning.

Acceptance: `nix develop -c cabal test all --test-show-details=direct` compiles all
adapter suites and their tests pass (the examples may still be broken until Milestone 3
— if so, scope the command to the adapter packages, for example
`nix develop -c cabal test settei-yaml-tests settei-kdl-tests settei-dhall-tests settei-env-tests settei-optparse-applicative-tests --test-show-details=direct`,
using the test-suite names from each package's `.cabal` file).

### Milestone 3 — reference applications: migrate and surface failure reports

Scope: `examples/settei-cli`, `examples/settei-service`,
`examples/settei-conformance`. At the end, both applications compile against the new
shape with byte-identical behavior everywhere except the one specified addition: in
explain modes, a resolution failure prints the failure report to stderr after the
errors. Exit codes are untouched.

In `examples/settei-cli/src/Settei/Example/Cli.hs`:

- `CliFailure` (line ~235) loses its `ResolveFailure` constructor; only
  `InputFailure !Text` remains (source-loading problems are still detected before
  resolution).
- `resolveCliOptions` (line ~215) keeps its signature
  `EnvSnapshot -> CliOptions -> IO (Either CliFailure (ResolveResult CliConfig))`; its
  final `case resolve ... of Left/Right` collapses to `Right (resolve ...)` — the
  resolution outcome now travels inside the `ResolveResult`.
- `runCliWithSnapshot` (line ~203) becomes:

  ```haskell
  runCliWithSnapshot :: EnvSnapshot -> CliOptions -> IO CliRun
  runCliWithSnapshot snapshot options =
    case options ^. #diagnosticMode of
      DescribeConfiguration -> pure (successfulRun (renderSchemaText (describe cliConfig)))
      _ -> do
        resolved <- resolveCliOptions snapshot options
        pure $ case resolved of
          Left (InputFailure message) -> failedRun sourceExitCode message
          Right result -> case result ^. #answer of
            Left problems ->
              failedRun
                resolutionExitCode
                (renderErrorsText problems <> failureReport options result)
            Right config -> successfulRun (renderSuccess options config result)
  ```

  with the new helper defining the exact failure-report behavior:

  ```haskell
  -- | In explain modes, append the provenance report so a failing run still
  -- explains which sources were consulted, what won, and what was shadowed.
  failureReport :: CliOptions -> ResolveResult CliConfig -> Text
  failureReport options result =
    case options ^. #diagnosticMode of
      ExplainConfigurationText -> renderResolutionText (result ^. #report)
      ExplainConfigurationJson -> renderResolutionJson (result ^. #report) <> "\n"
      _ -> ""
  ```

  `renderErrorsText` already ends with a newline (`Text.unlines`), so the report
  starts on a fresh line. Stdout remains empty on failure; the exit code remains
  `resolutionExitCode` (4).
- `renderSuccess` (line ~259) changes to take the decoded config alongside the result
  (`CliOptions -> CliConfig -> ResolveResult CliConfig -> Text`); its
  `result ^. #value` uses become the passed `config`, and its report/JSON arms keep
  using `result ^. #report`.

In `examples/settei-service/src/Settei/Example/Service.hs`, mirror the same changes:
`ServiceFailure` keeps only `InputFailure`; `resolveServiceSources` (line ~277) returns
`ResolveResult ServiceConfig` directly (the `envSource` error branch keeps its current
`error` behavior; only drop the outer `Either` around `resolve`); `resolveServiceOptions`
(line ~264) wraps it in `Right`; `runServiceWithSnapshot` (line ~255) matches on
`answer` and appends the failure report for `ExplainServiceConfigurationText` (text
render) and `ExplainServiceConfigurationJson` (JSON render plus newline) after
`renderErrorsText problems`; `renderServiceSuccess` (line ~330) takes the decoded
`ServiceConfig` alongside the result.

Migrate the tests:

- `examples/settei-cli/test/Settei/Example/CliTest.hs` and
  `examples/settei-service/test/Settei/Example/ServiceTest.hs`: their
  `expectResolution :: Either a b -> IO b` helpers now unwrap two layers (the
  `Either CliFailure`/`Either ServiceFailure` from IO loading, then `answer`); keep all
  existing assertions, including the shadowed-origins list and exit-code cases, with
  unchanged expected values.
- `examples/settei-conformance/test/Settei/Example/ConformanceTest.hs`: its
  `expectResolution` and its direct `case resolve ... of Left ...` sites (lines ~80,
  ~109) migrate mechanically; all normalized-report and typed-value assertions keep
  their expected values.

Add the new behavior tests:

- CLI: a case "resolution failure in explain mode prints provenance to stderr" —
  options `["--set", "service.timeout=broken", "--explain-config"]` with
  `envSnapshot []`. Assert exit code equals `resolutionExitCode`, stdout is empty,
  stderr contains the decode-error line (it starts with `service.timeout: expected`)
  and, after it, report evidence such as `service.timeout = ` and
  `from command-line option`. Add a JSON variant with `--explain-config-json` asserting
  stderr contains `"schemaVersion":1` and `"type":"settei.resolution"`. Also assert the
  existing `--check-config` failure case's stderr does not contain `settei.resolution`
  or a `<missing>`/`<not selected>` marker — non-explain modes are unchanged.
- Service: a case "production failure explains missing password without leaking" —
  snapshot `[("HASKELL_ENV", "production")]` (no password) with `--explain-config`.
  Assert exit code `resolutionExitCode`, stderr contains
  `database.password: required value is missing` and the report line
  `database.password = <missing>`, and the existing secret-sentinel scans still find no
  sentinel in stdout or stderr for the secret-bearing failure runs.

Acceptance:
`nix develop -c cabal test all --test-show-details=direct` compiles everything and all
example and conformance tests pass. Manually observe the motivating behavior:

```bash
nix develop -c cabal run settei-example-cli -- --set service.timeout=broken --explain-config
```

Expected: exit code 4; stderr shows the decode error followed by the full report,
shaped like:

```text
service.timeout: expected a bounded integral number from command-line option --set #1, rejected "broken"
credentials.token = <not selected>
output.format = "text"
  from built-in source CLI built-in defaults
runtime.environment = "development"
  from built-in source CLI built-in defaults
service.endpoint = "https://localhost:8443"
  from built-in source CLI built-in defaults
service.timeout = "broken"
  from command-line option --set #1
  shadowed: built-in source CLI built-in defaults
```

(The exact origin spellings come from the renderer; compare against what
`--explain-config` prints on a successful run and adjust the test's substring
assertions to the true output rather than this illustrative transcript.)

### Milestone 4 — documentation, ADR amendment, and changelog

Scope: prose only. At the end, every document that shows or describes the old `resolve`
shape reflects the new one, and the design decision is durable in an ADR.

- `docs/adr/0003-resolution-provenance-and-default-semantics.md`: append a dated
  amendment section (do not rewrite existing text), for example
  `## Amendment (2026-07-19): reports for every resolution attempt`, stating: `resolve`
  now returns a total `ResolveResult` whose `answer` field carries the typed value or
  errors while the report and warnings are always produced; failure reports contain
  every evaluated node completed with not-selected placeholders; the two pre-evaluation
  validation exits produce a schema-derived report of `NotSelected` nodes with no
  origins; the default-cycle exit returns no warnings, preserving the law that cycles
  fail before any source location function is called; decode-failure nodes retain the
  rejected candidate's redacted reported value as provenance; redaction semantics are
  unchanged. Record the rejected alternative: a separate `resolveWithReport` entry
  point was rejected because two entry points would drift and the fleet would
  standardize on the lossy one.
- `docs/guides/cli-application.md`: update the `resolveCli` snippet (lines ~74–88) to
  return `ResolveResult AppConfig` without the outer `Either`; in the "Distinguish exit
  behavior" section (line ~262) document that explain modes print the failure report to
  stderr after the errors while exit codes are unchanged; extend the test checklist
  (line ~292) with "a failing explain run prints the provenance report to stderr".
- `docs/guides/kubernetes-service.md`: update the `resolveService` snippet (lines
  ~203–212) the same way; in the startup sequence and failure guidance (lines
  ~214–225), note that warnings and the report are available even when resolution
  fails; in "Expose safe diagnostics" (line ~299), note that `--explain-config` on a
  failing pod now shows the redacted provenance view, which is the intended
  crash-loop debugging workflow.
- `README.md`: update the resolve example (lines ~76–98) to the new shape:

  ```haskell
  let result = resolve defaultResolveOptions orderedSources serviceConfig
  -- result ^. #report and result ^. #warnings exist even when resolution fails.
  config <-
    either (fail . Text.unpack . renderErrorsText) pure (result ^. #answer)
  ```

  Scan the rest of README.md for any other appearance of the old signature and update
  it.
- `settei/CHANGELOG.md`: under the unreleased `0.1.0.0` entry, add a bullet: breaking
  change — `resolve` now returns `ResolveResult` unconditionally; the typed outcome
  moved to the `answer` field and the provenance report and warnings are produced for
  every resolution attempt, including failures.

Acceptance: `git grep -n "Either (NonEmpty ConfigError) (ResolveResult"` returns no
hits outside `docs/plans/` history discussion, and the full test command still passes.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/settei`.

1. Milestone 1 edits in `settei/` as specified above, then:

   ```bash
   nix develop -c cabal test settei-tests --test-show-details=direct
   ```

   Expected: output ends with all tests passing, for example:

   ```text
   All N tests passed (…s)
   Test suite settei-tests: PASS
   ```

   Iterate until green. Commit:

   ```text
   feat(settei)!: report resolution provenance and warnings on failure

   resolve now returns ResolveResult unconditionally; the typed outcome moves
   to the new answer field while the report and warnings are always produced,
   including on failure and on both pre-evaluation validation exits.

   BREAKING CHANGE: resolve :: ResolveOptions -> [Source] -> Config a ->
   ResolveResult a; ResolveResult's value field is renamed to answer and now
   carries Either (NonEmpty ConfigError) a.

   MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
   ExecPlan: docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md
   Intention: intention_01kxxdt2f0enp928nc1wbcsd2t
   ```

2. Milestone 2 edits, then run the adapter suites (use the real test-suite names from
   each `.cabal` file):

   ```bash
   nix develop -c cabal test settei-yaml settei-kdl settei-dhall settei-env settei-optparse-applicative --test-show-details=direct
   ```

   Commit:

   ```text
   test(adapters): migrate adapter suites to the total resolver result

   MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
   ExecPlan: docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md
   Intention: intention_01kxxdt2f0enp928nc1wbcsd2t
   ```

3. Milestone 3 edits, then:

   ```bash
   nix develop -c cabal test all --test-show-details=direct
   nix develop -c cabal run settei-example-cli -- --set service.timeout=broken --explain-config; echo "exit: $?"
   ```

   Expected: all suites pass; the manual run prints the decode error then the report to
   stderr and `exit: 4`. Commit:

   ```text
   feat(examples): print the failure report in explain modes

   Both reference applications match on the new answer field and, when a
   resolution fails under --explain-config or --explain-config-json, append
   the redacted provenance report to stderr after the errors. Exit codes are
   unchanged.

   MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
   ExecPlan: docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md
   Intention: intention_01kxxdt2f0enp928nc1wbcsd2t
   ```

4. Milestone 4 edits, then re-run the full suite once more:

   ```bash
   nix develop -c cabal test all --test-show-details=direct
   ```

   Commit:

   ```text
   docs: record always-available resolution reports

   Amends ADR 0003 with a dated note, updates both guides' failure handling,
   the README resolve snippet, and the settei changelog for the reshaped
   resolver result.

   MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
   ExecPlan: docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md
   Intention: intention_01kxxdt2f0enp928nc1wbcsd2t
   ```

5. Update this plan's Progress, Surprises & Discoveries, Decision Log, and Outcomes &
   Retrospective sections as you go and at completion (commit plan updates with type
   `docs(plans)` and the same three trailers). Every commit in this plan follows
   Conventional Commits and carries exactly those three trailers.

If any step reveals a semantic surprise (for example, a golden byte change you did not
expect, or laziness forcing a poisoned source), stop, record it in Surprises &
Discoveries with the failing output, decide in the Decision Log, and only then adjust
code.


## Validation and Acceptance

The change is accepted when all of the following observable behaviors hold, verified
from the repository root:

1. `nix develop -c cabal test settei-tests --test-show-details=direct` passes,
   including the new failure-path tests named in Milestone 1 and the new golden pair
   `settei/test/golden/failure-resolution.txt` / `failure-resolution.json`.
2. `nix develop -c cabal test all --test-show-details=direct` passes: every adapter
   suite, both example suites, and the conformance suite compile against the new shape
   and pass with their pre-existing expected values intact.
3. Failure provenance is visible end to end:

   ```bash
   nix develop -c cabal run settei-example-cli -- --set service.timeout=broken --explain-config
   ```

   exits 4, prints nothing to stdout, and prints to stderr the decode error followed by
   a report in which `service.timeout` shows the rejected value with its command-line
   origin and its shadowed built-in, and every other declared setting appears with its
   origin or a `<missing>`/`<not selected>` marker.
4. Non-explain failure output is byte-identical to before this change:
   `--check-config` on the same bad input prints only the error text and exits 4.
5. Pre-evaluation exits still report: the new unit tests prove a structural-conflict
   run returns every schema key as `NotSelected` plus computed warnings, and a
   default-cycle run returns the schema-only report with empty warnings while the
   poisoned source's location function is never called (the test fails with the poison
   `error` message if it is).
6. Secret safety is preserved on the failure path: the extended `redactionTest` in
   `settei/test/Settei/RenderTest.hs` renders a failing resolution's report in text and
   JSON and finds no secret sentinel; the example tests' sentinel scans over stdout and
   stderr still pass, now covering the new failure-report output.
7. The pre-existing golden files under `settei/test/golden/` are unchanged
   (`git diff --stat settei/test/golden/` shows only the two new files), and the JSON
   failure golden carries `"schemaVersion":1`.
8. Documentation is consistent: `docs/adr/0003-...md` has the dated amendment with the
   rejected `resolveWithReport` alternative; both guides and `README.md` show the new
   signature; `settei/CHANGELOG.md` records the breaking change.


## Idempotence and Recovery

Every step is an ordinary source edit validated by the test suite; all steps are safe
to re-run. `cabal test` is idempotent. No migrations, generated artifacts, or
destructive operations are involved.

Recovery points are the four milestone commits: if a later milestone goes wrong, `git
log` shows the last green state and `git restore` / `git reset --hard <commit>` returns
to it without losing earlier milestones. Do not create a branch — commit directly to
the current branch per repository convention.

Golden files: never overwrite an existing golden under `settei/test/golden/` in this
plan. If an existing golden test fails, that is a signal the change altered rendered
output it must not alter — record it in Surprises & Discoveries and fix the code, not
the golden. Only the two new `failure-resolution.*` files are created; if you generated
them from wrong output, delete and regenerate them; the test defines correctness.

Partial-compile states are expected mid-milestone (renaming `value` to `answer`
deliberately breaks every caller). If you must stop mid-milestone, note in the Progress
section exactly which files are migrated and which still fail to compile, so the next
contributor can resume from `cabal build all` errors.

Coordination with EP-9: if EP-9 lands while this plan is in flight, rebase, add the new
`ConfigError` constructor's case to any exhaustive match this plan touched, and re-run
the full suite. Never rename or remove EP-9's constructor.


## Interfaces and Dependencies

No new library dependencies are added anywhere; the change uses only what the touched
modules already import (`Data.List.NonEmpty`, `Data.Map.Strict`, generic-lens labels
via `Settei.Prelude`).

At the end of Milestone 1, `settei/src/Settei/Resolve.hs` (re-exported through
`Settei`) must export exactly:

```haskell
data UnknownKeyPolicy = WarnUnknownKeys | RejectUnknownKeys

data ResolveOptions = ResolveOptions { unknownKeyPolicy :: !UnknownKeyPolicy }

data ResolveResult a = ResolveResult
  { answer :: !(Either (NonEmpty ConfigError) a),
    report :: !ResolutionReport,
    warnings :: ![ConfigWarning]
  }

defaultResolveOptions :: ResolveOptions

resolve :: ResolveOptions -> [Source] -> Config a -> ResolveResult a
```

`Settei.Report.ResolutionReport`, `ResolutionNode`, `ResolutionOutcome`, `BranchTrace`,
and `Derivation` are unchanged. `Settei.Render.renderResolutionText` and
`renderResolutionJson` keep their signatures (`ResolutionReport -> Text`); only their
haddocks change. `Settei.Error` is untouched by this plan (EP-9 owns its evolution).

At the end of Milestone 3, the examples expose:

```haskell
-- examples/settei-cli/src/Settei/Example/Cli.hs
resolveCliOptions :: EnvSnapshot -> CliOptions -> IO (Either CliFailure (ResolveResult CliConfig))
runCliWithSnapshot :: EnvSnapshot -> CliOptions -> IO CliRun

-- examples/settei-service/src/Settei/Example/Service.hs
resolveServiceOptions :: EnvSnapshot -> ServiceOptions -> IO (Either ServiceFailure (ResolveResult ServiceConfig))
resolveServiceSources :: [Source] -> EnvSnapshot -> ResolveResult ServiceConfig
runServiceWithSnapshot :: EnvSnapshot -> ServiceOptions -> IO ServiceRun
```

where `CliFailure` and `ServiceFailure` carry only the input-loading case. These
example modules are internal (docs/adr/0007) and will be rewritten by the ergonomics
MasterPlan; the signatures above are the minimal behavior-preserving migration, not new
public API.

Downstream dependents of this plan's shape: EP-13 and EP-14 (same MasterPlan) and the
ergonomics MasterPlan consume the total `ResolveResult`; nothing in this plan may land
in a form other than the exported interface above without a Decision Log entry
explaining why.
