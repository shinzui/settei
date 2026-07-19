---
id: 17
slug: add-error-renderers-to-every-source-adapter
title: "Add error renderers to every source adapter"
kind: exec-plan
created_at: 2026-07-19T14:54:49Z
intention: "intention_01kxxdt2m8eysvxggq33jsmt2v"
master_plan: "docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md"
---

# Add error renderers to every source adapter

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Settei's core package ships `renderErrorsText` and `renderErrorsJson` in
`settei/src/Settei/Render.hs`, so typed configuration failures print as clean,
operator-readable lines such as `service.port: expected a bounded integer from file source
application.yaml (YAML)`. But the four source-adapter packages — settei-yaml, settei-kdl,
settei-dhall, and settei-env — export structured error types with no renderer at all.
Consequently both reference applications fall back on Haskell's derived `Show` instance:
`examples/settei-cli/src/Settei/Example/Cli.hs` (around lines 242–257) and
`examples/settei-service/src/Settei/Example/Service.hs` (around lines 289–317) wrap
adapter failures with `either (Left . Text.pack . show) Right`, and the service even calls
`error (show problems)` for environment binding failures (line 281). An operator reading a
crashed pod's log therefore sees raw record syntax like
`YamlSourceError {category = YamlDuplicateKey, name = "application.yaml", ...}` instead of a
diagnostic line. A 2026-07-19 API review of the whole package family confirmed this gap and
predicted that every one of the roughly 50 adopting services would copy the same `show`
hack.

After this plan is implemented, each adapter exports a pair of text renderers —
`renderYamlErrorText`/`renderYamlErrorsText`, `renderKdlErrorText`/`renderKdlErrorsText`,
`renderDhallErrorText`/`renderDhallErrorsText`, and
`renderEnvErrorText`/`renderEnvErrorsText` — matching the tone of the core's
`renderErrorsText`: one line per problem, leading with the most locating information the
error carries, never containing a raw configuration value. Both reference applications use
them instead of `show`, all four adapter guides teach them, and per-adapter unit tests pin
the exact rendered strings for every error category and constructor. You can see the change
working by running the adapter test suites (commands in Validation and Acceptance) and by
pointing the example CLI at a YAML file with a duplicate key: the stderr line becomes
`application.yaml (application.yaml:3:3) at $.service: duplicate mapping key` instead of a
`Show` dump.

This plan is owned by the MasterPlan
docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md, whose
Integration Points section names this plan (EP-17) the owner of the renderer naming and
formatting contract that EP-16 (docs/plans/16-provide-shared-tagged-format-configuration-loading.md)
and EP-18 (docs/plans/18-make-environment-bindings-total-and-validated.md) consume.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] (2026-07-19T20:19:40Z) Confirm preconditions: `DhallSourceError` has optional one-based `line` and
      `column` fields from EP-13, EP-16 owns ADR 0008, and ADR 0009 is free.
- [x] (2026-07-19T20:22:20Z) Milestone 1: add `renderYamlErrorText`/`renderYamlErrorsText` to
      settei-yaml/src/Settei/Yaml.hs with haddock and export-list entries.
- [x] (2026-07-19T20:22:20Z) Milestone 1: renderer unit tests in settei-yaml/test/Settei/YamlTest.hs
      cover all nine `YamlErrorCategory` values plus no-path and no-position omission;
      all 45 `settei-yaml-tests` pass.
- [x] (2026-07-19T20:25:41Z) Milestone 2: add `renderKdlErrorText`/`renderKdlErrorsText` to
      settei-kdl/src/Settei/Kdl.hs with haddock and export-list entries.
- [x] (2026-07-19T20:25:41Z) Milestone 2: renderer unit tests in
      settei-kdl/test/Settei/KdlTest.hs cover all eight `KdlErrorCategory` values plus
      related-span and omission behavior; all 34 `settei-kdl-tests` pass.
- [x] (2026-07-19T20:27:27Z) Milestone 3: add
      `renderDhallErrorText`/`renderDhallErrorsText` to settei-dhall/src/Settei/Dhall.hs
      with haddock and export-list entries, including EP-13's optional positions.
- [x] (2026-07-19T20:27:27Z) Milestone 3: renderer unit tests in
      settei-dhall/test/Settei/DhallTest.hs cover all eight `DhallErrorCategory` values
      plus no-path omission; all 26 `settei-dhall-tests` pass.
- [x] (2026-07-19T20:28:48Z) Milestone 4: add
      `renderEnvErrorText`/`renderEnvErrorsText` to settei-env/src/Settei/Env.hs with
      haddock and export-list entries.
- [x] (2026-07-19T20:28:48Z) Milestone 4: renderer unit tests in
      settei-env/test/Settei/EnvTest.hs pin exact strings for all five `EnvError`
      constructors; all 13 `settei-env-tests` pass.
- [x] (2026-07-19T20:31:59Z) Milestone 5: replace adapter-error `Show` rendering with
      the exported renderers in examples/settei-cli/src/Settei/Example/Cli.hs,
      examples/settei-service/src/Settei/Example/Service.hs, and EP-16's
      settei-formats/src/Settei/Formats.hs delegation stub.
- [x] (2026-07-19T20:31:59Z) Milestone 5: `cabal build all` and `cabal test all` pass;
      the strengthened `settei-formats-tests` delegation coverage also passes all 15 tests.
- [x] (2026-07-19T20:34:14Z) Milestone 6: update the error-rendering snippets in
      docs/guides/yaml.md, docs/guides/kdl.md, docs/guides/dhall.md, and
      docs/guides/environment-and-cli.md to use the exported renderers.
- [x] (2026-07-19T20:34:14Z) Milestone 6: add an Unreleased renderer entry to the YAML,
      KDL, Dhall, and environment adapter changelogs.
- [x] (2026-07-19T20:34:14Z) Milestone 6: record the durable cross-adapter contract in
      docs/adr/0009-adapter-error-rendering-contract.md.
- [x] (2026-07-19T20:37:05Z) Final: update the MasterPlan's EP-17 registry and Progress
      rows; `nix fmt`, `cabal build all`, the four adapter suites, `cabal test all`, and
      `nix flake check` pass; write this retrospective and complete ADR distillation.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Observation: EP-16 landed before this plan and left an explicit `TODO(EP-17)` in
  `Settei.Formats.renderFormatLoadErrorText`; fleet adoption therefore included that
  umbrella loader in addition to the two examples named by this plan. Directly testing
  all three branches required adding `settei-kdl` to the settei-formats test component's
  dependencies, matching its existing direct YAML and Dhall test dependencies.
  Evidence: the first targeted build rejected the hidden `Settei.Kdl` module; after the
  test-only dependency was added, all 15 `settei-formats-tests` passed.


## Decision Log

Record every decision made while working on the plan.

- Decision: The uniform contract is a pair of exported functions per adapter:
  `render<X>ErrorText :: <X>Error -> Text` for one failure and
  `render<X>ErrorsText :: NonEmpty <X>Error -> Text` for a batch, where the plural
  composes the singular with `Text.unlines`, exactly mirroring the core's
  `renderErrorsText = Text.unlines . fmap renderErrorText . NonEmpty.toList` in
  settei/src/Settei/Render.hs. Exact names: `renderYamlErrorText`/`renderYamlErrorsText`
  in `Settei.Yaml`, `renderKdlErrorText`/`renderKdlErrorsText` in `Settei.Kdl`,
  `renderDhallErrorText`/`renderDhallErrorsText` in `Settei.Dhall`, and
  `renderEnvErrorText`/`renderEnvErrorsText` in `Settei.Env`.
  Rationale: The MasterPlan's Integration Points section makes this plan the owner of the
  naming and formatting convention that EP-16 and EP-18 consume, so the names must be
  fixed here, before either consumer starts. Mirroring the core keeps one mental model:
  a plural renderer always ends each problem line with a newline via `Text.unlines`.
  Date: 2026-07-19

- Decision: The formatting convention is one line per problem, leading with the most
  locating information the error carries. YAML: `NAME (PATH:LINE:COLUMN) at $ctx: message`
  with graceful omission of absent path/line/column (the parenthetical is the
  colon-joined present pieces and is dropped entirely when none are present). KDL: the
  same shape using the primary span's start line and column, appending
  `; also at LINE:COLUMN` when a related span exists (property/child collisions and
  duplicate properties carry one). Dhall: `NAME (PATH): message`, dropping the
  parenthetical when no path is known; if EP-13 of the correctness MasterPlan has added
  optional position fields to `DhallSourceError` by implementation time, they join the
  parenthetical with the same colon rule. Env: sentence-form text per constructor naming
  the variable or keys involved (exact strings in Plan of Work, Milestone 4).
  Rationale: This matches the tone of `renderErrorText` in settei/src/Settei/Render.hs
  ("key: expected X from <origin description>"): terse, locating, colon-separated, no
  prose paragraphs. Operators grep logs; a single line per problem with the file position
  first is the most useful shape.
  Date: 2026-07-19

- Decision: Text renderers only; no `render<X>ErrorsJson` in this plan.
  Rationale: The core's JSON error documents (`renderErrorsJson`) exist for the
  resolver's structured, versioned diagnostic documents that tooling consumes. Adapter
  errors are load-time, operator-facing failures printed to stderr before any structured
  reporting pipeline exists; every observed consumer need (both reference applications,
  the guides, EP-16's loader, EP-18's env path) is text. Rejected alternative: adding
  versioned JSON documents per adapter now — rejected because it would quadruple the
  golden-test surface for a consumer that does not exist, and because JSON renderers can
  be added later purely additively (new exports, no changes to the text contract) if a
  need appears.
  Date: 2026-07-19

- Decision: Secret-safety is inherited, not added: all four error types already retain no
  raw configuration values by construction, and the renderers concatenate only the fields
  those types already expose plus fixed punctuation.
  Rationale: Verified against the types and their ADRs. `YamlSourceError` holds only
  category, source name, optional path, optional one-based line/column, structural
  context text, and a fixed message (docs/adr/0004: failures "never retain a raw scalar
  or source excerpt"). `KdlSourceError` holds category, name, optional path, optional
  spans, context, fixed message (docs/adr/0005: the parser's rendered excerpt is
  discarded "because parsing precedes sensitivity classification"). `DhallSourceError`
  holds only category, name, optional safe path and position, fixed message (docs/adr/0006: "without
  source snippets or retained upstream exceptions"). `EnvError` constructors hold only
  `EnvName` and `Key` values, never environment values. Renderers must not introduce any
  new data source, and the tests reuse the existing secret-sentinel discipline where
  applicable.
  Date: 2026-07-19

- Decision: Example updates in this plan are the minimal mechanical substitution of
  `Text.pack . show` (and `show problems`) with the new renderers; the coherent example
  rewrite belongs to EP-21
  (docs/plans/21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md).
  The `error (show problems)` line in examples/settei-service/src/Settei/Example/Service.hs
  (line 281) is being redesigned away by EP-18
  (docs/plans/18-make-environment-bindings-total-and-validated.md), which makes `envSource`
  total; this plan touches that line only if EP-18 has not landed yet, replacing it with
  `error (Text.unpack (renderEnvErrorsText problems))` so even the interim panic is
  operator-readable. If EP-18 has landed first, the branch no longer exists and this plan
  changes nothing there.
  Rationale: The MasterPlan's Decision Log mandates minimal per-plan example edits so
  EP-21's rewrite is the single large diff; the ordering contingency keeps both plans
  landable in either order.
  Date: 2026-07-19

- Decision: Record the contract in a new short ADR, expected as
  docs/adr/0009-adapter-error-rendering-contract.md, rather than amending
  docs/adr/0003-resolution-provenance-and-default-semantics.md.
  Rationale: The MasterPlan allows either. ADR 0003 governs core resolution rendering and
  redaction; the adapter renderer contract spans four other packages and has its own
  rejected alternatives (JSON now, a shared typeclass), so a dedicated short ADR is
  clearer. Number 0008 is presumptively reserved for EP-16's umbrella-package-boundary
  ADR (the MasterPlan's "Cross-plan decisions that should become ADRs" paragraph lists
  EP-16's ADR first). As of 2026-07-19, docs/adr/ ends at 0007 and
  docs/plans/16-provide-shared-tagged-format-configuration-loading.md is still a skeleton
  that names no number, so the implementer must check docs/adr/ at implementation time
  and take the next free number if 0009 is taken or 0008 is still free and EP-16 is
  cancelled.
  Date: 2026-07-19

- Decision: Renderers live inside the existing adapter modules (`Settei.Yaml`,
  `Settei.Kdl`, `Settei.Dhall`, `Settei.Env`), not in new modules and not in core.
  Rationale: The error types are abstract in three of the four packages (only `EnvError`
  exports constructors), so rendering must live where the fields are visible; core cannot
  see adapter types without inverting the dependency direction; and a shared typeclass
  across four packages would need a fifth common package for one method — needless
  coupling for four small functions. This rejected-typeclass reasoning goes into the ADR.
  Date: 2026-07-19

- Decision: Include Dhall's optional line and column in the same colon-joined
  parenthetical as its safe path, and use
  `docs/adr/0009-adapter-error-rendering-contract.md` for the durable contract.
  Rationale: The implementation preflight found EP-13's `line :: Maybe Int` and
  `column :: Maybe Int` fields in `DhallSourceError`, so positioned parse failures can
  render as `NAME (PATH:LINE:COLUMN): message` while position-free failures omit absent
  pieces. EP-16 completed first and created ADR 0008, leaving 0009 as the next free ADR.
  Date: 2026-07-19


## Outcomes & Retrospective

EP-17 delivered the fixed singular/plural renderer pair in all four source adapters.
Golden tests cover every YAML, KDL, Dhall, and environment error category, available and
missing locations, KDL related spans, IO-safe prefixes, and the plural trailing-newline
contract. Both reference applications and the `settei-formats` umbrella loader now use
those APIs instead of derived `Show`, satisfying EP-16's soft integration dependency and
leaving stable names for EP-18 and EP-21.

The original purpose is met without a shared error type, a new common dependency, or any
new retained source data. Each adapter preserves its honest diagnostic precision, and
the examples, four guides, and four changelogs teach the same operator-facing path. The
umbrella loader gained direct delegation tests for YAML, KDL, and Dhall; its test-only KDL
dependency was the sole implementation-time adjustment beyond the planned consumers.

Final validation passed on 2026-07-19: `nix fmt`, `cabal build all`, all four focused
adapter suites (45 YAML, 34 KDL, 26 Dhall, and 13 environment tests), the complete Cabal
test suite, and `nix flake check`. ADR 0009 distills the durable naming, formatting,
omission, newline, dependency-boundary, and secret-safety decisions. The remaining
Surprises & Discoveries entry is task-local test-component bookkeeping and needs no
additional ADR. No planned gap remains.


## Context and Orientation

Settei is a Haskell configuration library organized as a Cabal multi-package workspace at
the repository root (`cabal.project` lists the packages; a Nix flake provides the
toolchain, so every build/test command in this plan is prefixed with `nix develop -c` and
run from the repository root). The core package `settei/` defines the declaration algebra,
resolver, provenance reporting, and the renderers for *resolution* failures. Four adapter
packages turn external inputs into core `Source` values:

- `settei-yaml/` (module `Settei.Yaml` in settei-yaml/src/Settei/Yaml.hs) parses a strict
  YAML subset. Its failure type `YamlSourceError` (around line 65) is an abstract record —
  the constructor is not exported — with fields reachable through accessor functions:
  `yamlErrorCategory :: YamlSourceError -> YamlErrorCategory`, `yamlErrorName` (the stable
  source name, `Text`), `yamlErrorPath` (`Maybe FilePath`), `yamlErrorLine` and
  `yamlErrorColumn` (`Maybe Int`, one-based), `yamlErrorContext` (a structural path
  rendered like `$.service.ports[0]`; it is always at least `"$"`), and
  `yamlErrorMessage` (a fixed secret-safe message). `YamlErrorCategory` (around line 52)
  has nine values: `YamlSyntaxError`, `YamlIoError`, `YamlMultipleDocuments`,
  `YamlDuplicateKey`, `YamlNonStringKey`, `YamlDottedKey`, `YamlUnsupportedFeature`,
  `YamlInvalidScalar`, `YamlTopLevelType`.
- `settei-kdl/` (module `Settei.Kdl` in settei-kdl/src/Settei/Kdl.hs) parses KDL v2. Its
  `KdlSourceError` (around line 71) is likewise abstract, with accessors
  `kdlErrorCategory`, `kdlErrorName`, `kdlErrorPath` (`Maybe FilePath`), `kdlErrorSpan`
  and `kdlErrorRelatedSpan` (`Maybe KdlSpan`; a `KdlSpan` carries one-based `line`,
  `column`, `endLine`, `endColumn` reachable via `kdlSpanLine`, `kdlSpanColumn`,
  `kdlSpanEndLine`, `kdlSpanEndColumn`), `kdlErrorContext` (rendered like `$.service.port`,
  always at least `"$"`), and `kdlErrorMessage`. `KdlErrorCategory` (around line 50) has
  eight values: `KdlSyntaxError`, `KdlIoError`, `KdlDuplicateProperty`, `KdlInvalidName`,
  `KdlUnsupportedAnnotation`, `KdlUnsupportedValue`, `KdlMixedNodeShape`,
  `KdlPropertyChildCollision`.
- `settei-dhall/` (module `Settei.Dhall` in settei-dhall/src/Settei/Dhall.hs) evaluates
  Dhall under explicit import policies. Its abstract `DhallSourceError` (around line 138)
  carries `dhallErrorCategory`, `dhallErrorName`, `dhallErrorPath`
  (`Maybe FilePath`), `dhallErrorLine` and `dhallErrorColumn` (`Maybe Int`, one-based),
  and `dhallErrorMessage`. `DhallErrorCategory` (around line 122) has
  eight values: `DhallIoError`, `DhallParseError`, `DhallImportPolicyError`,
  `DhallImportError`, `DhallTypeError`, `DhallConversionError`, `DhallInvalidKey`,
  `DhallTopLevelType`.
- `settei-env/` (module `Settei.Env` in settei-env/src/Settei/Env.hs) maps explicitly
  bound environment variables to keys. Its `EnvError` (around line 48) **does** export
  constructors: `InvalidEnvironmentName !EnvName`, `DuplicateEnvironmentName !EnvName`,
  `DuplicateTargetKey !Key`, `ConflictingTargetKeys !Key !Key` (one key is a structural
  prefix of the other), and `PrefixedNameCollision !EnvName !(NonEmpty Key)` (prefix
  normalization mapped several keys onto one variable name). `EnvName` is a newtype over
  `Text`; the module-internal `renderEnvName` (around line 221) unwraps it. `Key` values
  render with `renderKey` from the core (`Settei.Key`, re-exported by the umbrella module
  `Settei`, which every adapter already imports), producing dotted text like
  `service.port`.

The rendering style to match lives in settei/src/Settei/Render.hs. `renderErrorsText`
(around line 167) is `Text.unlines . fmap renderErrorText . NonEmpty.toList`, and
`renderErrorText` produces exactly one line per problem in the shape
`key: expected X from <origin description>` — terse, colon-separated, locating information
first, never a raw secret. Note that `Text.unlines` appends a newline after every element,
so a plural renderer's output always ends with `\n`; the adapter renderers deliberately
share that property.

The evidence of the gap: `loadConfigInput` in
examples/settei-cli/src/Settei/Example/Cli.hs (lines 242–257) converts every adapter
failure with `either (Left . Text.pack . show) Right`, and line 222 does the same for
`EnvError` values via `Text.pack (show problems)`. `loadServiceInput` in
examples/settei-service/src/Settei/Example/Service.hs (lines 289–317) repeats the pattern
for all three file formats, and `resolveServiceSources` (line 281) calls
`error (show problems)` on the `EnvError` branch.

Relevant ADRs consulted (all under docs/adr/):

- docs/adr/0003-resolution-provenance-and-default-semantics.md — redaction is applied
  before data enters a report or structured error; renderers can only ever see already-safe
  data. The adapter renderers preserve this: they add no data.
- docs/adr/0004-yaml-input-semantics.md — YAML failures carry "only source name, optional
  path, one-based mark, structural key/index context, and a fixed safe message".
- docs/adr/0005-canonical-kdl-v2-input-semantics.md — KDL parse diagnostics keep only the
  line/column header; the parser's rendered source excerpt is discarded.
- docs/adr/0006-dhall-input-import-and-provenance-semantics.md — Dhall failures "use
  stable adapter categories and fixed messages without source snippets or retained
  upstream exceptions".
- docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md — the
  examples must exercise the public API, which is why they must adopt the renderers.
- docs/adr/0001-haskell-project-conventions.md — house style (lens-style field access via
  `#field` labels, ImportQualifiedPost, fourmolu formatting) that the new code follows.

Cross-plan context: the correctness MasterPlan
(docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md) lands before
this initiative, and its EP-13
(docs/plans/13-harden-source-construction-and-adapter-diagnostics.md) gives Dhall parse
failures a source position. As of 2026-07-19 both that plan file and
docs/plans/16-provide-shared-tagged-format-configuration-loading.md are unfilled
skeletons, so the exact Dhall field names and EP-16's ADR-number claim are not yet
knowable; the Concrete Steps below start with a precondition check that resolves both.


## Plan of Work

The work proceeds in six milestones. Milestones 1–4 are the same recipe applied to four
packages, each independently verifiable by its own test suite; Milestone 5 wires the
renderers into both reference applications; Milestone 6 updates guides, changelogs, and
writes the ADR. All new code follows house style: `{-# LANGUAGE ImportQualifiedPost #-}`
is already active, fields are read with generic-lens labels (`problem ^. #name`), and
`fourmolu` (configured by fourmolu.yaml at the repository root) formats everything.

Milestone 1 — YAML renderers. At the end of this milestone, `Settei.Yaml` exports the two
renderers, and `settei-yaml-tests` proves the rendered string for every category. In
settei-yaml/src/Settei/Yaml.hs, insert the following two definitions immediately after
`yamlErrorMessage` (around line 146), and add `renderYamlErrorText` and
`renderYamlErrorsText` to the module's alphabetically sorted export list (they slot in
after `readYamlSource`):

```haskell
-- | Render one YAML input failure as a single operator-readable line.
--
-- The line leads with the stable source name, then a parenthetical built from the
-- colon-joined available location pieces (path, one-based line, one-based column),
-- then the structural context, then the fixed secret-safe message:
-- @application.yaml (config/application.yaml:3:5) at $.service.name: ...@.
-- Absent pieces are omitted; when no piece is known the parenthetical disappears.
-- No raw configuration value can appear because 'YamlSourceError' retains none.
renderYamlErrorText :: YamlSourceError -> Text
renderYamlErrorText problem =
  problem ^. #name
    <> locationText
    <> " at "
    <> problem ^. #context
    <> ": "
    <> problem ^. #message
  where
    locationText = case locationPieces of
      [] -> ""
      pieces -> " (" <> Text.intercalate ":" pieces <> ")"
    locationPieces =
      maybe [] (pure . Text.pack) (problem ^. #path)
        <> maybe [] (pure . Text.pack . show) (problem ^. #line)
        <> maybe [] (pure . Text.pack . show) (problem ^. #column)

-- | Render every YAML input failure, one line per problem, matching
-- 'Settei.Render.renderErrorsText' in shape and trailing newline.
renderYamlErrorsText :: NonEmpty YamlSourceError -> Text
renderYamlErrorsText = Text.unlines . fmap renderYamlErrorText . NonEmpty.toList
```

Because the renderer lives inside the defining module it reads the private record fields
directly with labels; the public accessors stay untouched. `Data.Text`,
`Data.List.NonEmpty`, and the label machinery are already imported.

Tests go into the existing settei-yaml/test/Settei/YamlTest.hs as a new
`testGroup "error rendering"` inside `tests`. `YamlSourceError` is abstract, so every
test error is produced by feeding a crafted document to `decodeYamlSource` (the file
already has an `expectError` helper around line 140 that does exactly this) or, for
`YamlIoError`, by calling `readYamlSource` on a path that does not exist. Cover every
category — the existing tests in that file and in
settei-yaml/test/Settei/YamlCharacterizationTest.hs already contain a triggering input
for each (duplicate key, non-string key, dotted key, alias for unsupported-feature,
invalid scalar, multiple documents, top-level sequence, malformed syntax); reuse those
inputs. Assert the exact rendered string with `@?=` for every category except
`YamlIoError`, whose message embeds the operating system's `IOException` text; for that
one assert the stable prefix (`name`, path parenthetical, ` at $: `) with
`Text.isPrefixOf`. Add two omission tests: an in-memory decode without
`withYamlSourcePath` (path absent, line/column present — parenthetical is `(LINE:COLUMN)`)
and the missing-file IO error (path present, no line/column — parenthetical is `(PATH)`).
Add one plural test asserting `renderYamlErrorsText` of a one-element `NonEmpty` equals
the singular rendering plus `"\n"`. To pin an exact expected string the first time, write
the assertion with a deliberately wrong expected value, run the suite, and copy the actual
string from the failure diff into the test — then re-run and confirm green. This is safe
precisely because every message is a fixed constant in the module.

Milestone 2 — KDL renderers. Same recipe in settei-kdl/src/Settei/Kdl.hs: insert after
`kdlSpanEndColumn` (around line 165), and add `renderKdlErrorText` and
`renderKdlErrorsText` to the alphabetical export list (after `readKdlSource`):

```haskell
-- | Render one KDL input failure as a single operator-readable line.
--
-- The line leads with the stable source name, then a parenthetical of the
-- colon-joined available pieces (path, primary span start line, start column),
-- then the structural context and fixed message. When a second trustworthy span
-- exists (duplicate properties and property\/child collisions), it is appended as
-- @; also at LINE:COLUMN@. No raw configuration value can appear because
-- 'KdlSourceError' retains none.
renderKdlErrorText :: KdlSourceError -> Text
renderKdlErrorText problem =
  problem ^. #name
    <> locationText
    <> " at "
    <> problem ^. #context
    <> ": "
    <> problem ^. #message
    <> relatedText
  where
    locationText = case locationPieces of
      [] -> ""
      pieces -> " (" <> Text.intercalate ":" pieces <> ")"
    locationPieces =
      maybe [] (pure . Text.pack) (problem ^. #path)
        <> maybe [] spanPieces (problem ^. #location)
    spanPieces spanValue =
      [ Text.pack (show (spanValue ^. #line)),
        Text.pack (show (spanValue ^. #column))
      ]
    relatedText =
      maybe
        ""
        ( \spanValue ->
            "; also at "
              <> Text.pack (show (spanValue ^. #line))
              <> ":"
              <> Text.pack (show (spanValue ^. #column))
        )
        (problem ^. #relatedLocation)

-- | Render every KDL input failure, one line per problem, matching
-- 'Settei.Render.renderErrorsText' in shape and trailing newline.
renderKdlErrorsText :: NonEmpty KdlSourceError -> Text
renderKdlErrorsText = Text.unlines . fmap renderKdlErrorText . NonEmpty.toList
```

Tests go into settei-kdl/test/Settei/KdlTest.hs as a `testGroup "error rendering"`,
triggering each of the eight categories through `decodeKdlSource` (existing tests contain
inputs for duplicate properties, invalid/dotted names, type annotations, `#inf`/`#nan`,
mixed shapes, and collisions) and `readKdlSource` on a missing path for `KdlIoError`
(prefix assertion, as with YAML). Include one test asserting the `; also at LINE:COLUMN`
suffix appears for a `KdlPropertyChildCollision` (or `KdlDuplicateProperty`) error whose
`kdlErrorRelatedSpan` is present, and omission tests for a syntax error (span may be
present but path absent without `withKdlSourcePath`) and the IO error (path, no span).
Add the plural-equals-singular-plus-newline test.

Milestone 3 — Dhall renderers. In settei-dhall/src/Settei/Dhall.hs insert after
`dhallErrorMessage` (around line 192), and add both names to the alphabetical export list
(between `loadDhallSource`/`loadDhallSourceDetailed` and the rest — keep sorted order):

```haskell
-- | Render one Dhall input failure as a single operator-readable line:
-- @NAME (PATH): message@, or @NAME: message@ when no safe path is known.
-- No raw configuration value can appear because 'DhallSourceError' retains none.
renderDhallErrorText :: DhallSourceError -> Text
renderDhallErrorText problem =
  problem ^. #name
    <> maybe "" (\path -> " (" <> Text.pack path <> ")") (problem ^. #path)
    <> ": "
    <> problem ^. #message

-- | Render every Dhall input failure, one line per problem, matching
-- 'Settei.Render.renderErrorsText' in shape and trailing newline.
renderDhallErrorsText :: NonEmpty DhallSourceError -> Text
renderDhallErrorsText = Text.unlines . fmap renderDhallErrorText . NonEmpty.toList
```

Position contingency: the correctness MasterPlan's EP-13
(docs/plans/13-harden-source-construction-and-adapter-diagnostics.md) gives Dhall parse
failures a source position, and that MasterPlan lands before this one. At implementation
time, re-read `DhallSourceError` in settei-dhall/src/Settei/Dhall.hs. If optional line and
column (or a location record) fields exist, the renderer must tolerate their absence and
use them when present, folding them into the parenthetical with the same colon-joined
rule as YAML — `NAME (PATH:LINE:COLUMN): message` — and the tests must cover both the
positioned parse error and position-free categories. If the fields do not exist, ship the
name/path/message form above; it composes with a later position field additively. Record
whichever branch was taken in this plan's Decision Log.

Tests go into settei-dhall/test/Settei/DhallTest.hs as a `testGroup "error rendering"`,
triggering the eight categories through `loadDhallSource` / `loadDhallSourceDetailed`:
a nonexistent `DhallFile` path (`DhallIoError`, prefix assertion), syntactically invalid
expression text (`DhallParseError`), an expression containing `env:HOME as Text` or a
remote import under `NoImports` (`DhallImportPolicyError`), a local import escaping a
`LocalImportsWithin` root or a missing local import (`DhallImportError`), an ill-typed
expression (`DhallTypeError`), a value with no JSON representation such as a function
(`DhallConversionError`), a record label that is not a valid key segment
(`DhallInvalidKey`), and a non-record top level (`DhallTopLevelType`). The existing
DhallTest.hs already triggers these categories — reuse its inputs, and keep its
`XDG_CACHE_HOME` isolation discipline (no test may touch the real cache, network, or
environment imports; see docs/adr/0006). Add the no-path omission test using an in-memory
`dhallExpression` root and the plural test.

Milestone 4 — Env renderers. In settei-env/src/Settei/Env.hs insert after
`bindingAnnotations` (around line 77) or after `renderEnvName` — either location is fine;
keep the two functions adjacent — and add `renderEnvErrorText` and `renderEnvErrorsText`
to the alphabetical export list (after `prefixedBindings`):

```haskell
-- | Render one binding-validation failure as a single operator-readable sentence.
-- Only variable names and structural keys appear; environment values are never
-- retained by 'EnvError' and therefore cannot leak.
renderEnvErrorText :: EnvError -> Text
renderEnvErrorText = \case
  InvalidEnvironmentName name ->
    "environment binding " <> renderEnvName name <> ": invalid variable name"
  DuplicateEnvironmentName name ->
    "environment binding " <> renderEnvName name <> ": variable bound more than once"
  DuplicateTargetKey key ->
    "bindings target the same key " <> renderKey key <> " twice"
  ConflictingTargetKeys lower higher ->
    "bindings target overlapping keys " <> renderKey lower <> " and " <> renderKey higher
  PrefixedNameCollision name keys ->
    "environment binding "
      <> renderEnvName name
      <> ": normalized name collides for keys "
      <> Text.intercalate ", " (fmap renderKey (NonEmpty.toList keys))

-- | Render every binding-validation failure, one line per problem, matching
-- 'Settei.Render.renderErrorsText' in shape and trailing newline.
renderEnvErrorsText :: NonEmpty EnvError -> Text
renderEnvErrorsText = Text.unlines . fmap renderEnvErrorText . NonEmpty.toList
```

`renderKey` is in scope through the existing `import Settei`, and `renderEnvName` is a
private helper in the same module. Because `EnvError` exports its constructors, the tests
in settei-env/test/Settei/EnvTest.hs construct each of the five constructors directly and
assert exact strings, for example:

```haskell
renderEnvErrorText (InvalidEnvironmentName (EnvName "http port"))
  @?= "environment binding http port: invalid variable name"
renderEnvErrorText (DuplicateTargetKey (validKey "http.port"))
  @?= "bindings target the same key http.port twice"
```

(the test file already defines a `validKey` helper). Cover all five constructors,
including a `PrefixedNameCollision` with two keys asserting the comma-joined key list,
plus the plural test. EP-18 note: if EP-18 has already landed and changed the `EnvError`
vocabulary, this milestone renders whatever constructors exist at that time with the same
sentence-form convention and records the divergence in the Decision Log; the exported
renderer names are fixed regardless.

Milestone 5 — minimal example adoption. At the end of this milestone neither reference
application mentions `show` for adapter errors. In
examples/settei-cli/src/Settei/Example/Cli.hs, `loadConfigInput` (lines 242–257): replace
each `either (Left . Text.pack . show) Right` with
`either (Left . Yaml.renderYamlErrorsText) Right`,
`either (Left . Kdl.renderKdlErrorsText) Right`, and
`either (Left . Dhall.renderDhallErrorsText) Right` respectively (the modules are already
imported qualified under those names). At line 222 replace
`Left (InputFailure (Text.pack (show problems)))` with
`Left (InputFailure (renderEnvErrorsText problems))` (`Settei.Env` is imported
unqualified there). In examples/settei-service/src/Settei/Example/Service.hs,
`loadServiceInput` (lines 289–317): the same three substitutions. Line 281's
`error (show problems)` follows the EP-18 contingency recorded in the Decision Log: only
if EP-18 has not landed, change it to `error (Text.unpack (renderEnvErrorsText problems))`
(add `Text.unpack` via the existing qualified `Data.Text` import). Make no other example
change — no restructuring, no new failure types; EP-21 owns the rewrite. Note the plural
renderers end with a newline where the old `show` text did not; if an example or
conformance test asserted the old `Show` text or exact stderr equality, update that
assertion to the new rendered form (record any such fix in Surprises & Discoveries — a
scan on 2026-07-19 found the example tests assert with `Text.isInfixOf` on substrings, so
breakage is expected to be minor or absent).

Milestone 6 — docs, changelogs, ADR. Each of the four adapter guides currently teaches a
hand-rolled renderer that this plan obsoletes. In docs/guides/yaml.md, the "Render YAML
errors" section (around lines 214–235) defines `renderYamlErrors`/`renderYamlError` by
hand and an earlier snippet (around line 129) calls `first renderYamlErrors loaded`:
delete the hand-rolled definitions, show the exported `renderYamlErrorsText` instead with
one sample output line in a `text` fence, keep the paragraph documenting the accessor
functions for applications that need custom layouts, and change the load snippet to
`first renderYamlErrorsText loaded`. Apply the same treatment to docs/guides/kdl.md
(`renderKdlErrors` around lines 229–241, load snippet around line 119) and
docs/guides/dhall.md (`renderDhallErrors` around lines 258–266, load snippet around line
146). In docs/guides/environment-and-cli.md, the binding-validation discussion (around
lines 122–167) explains `EnvError` values; add a sentence and short `haskell` snippet
showing `renderEnvErrorsText` as the way to print them. Then add a changelog entry at the
top of each of settei-yaml/CHANGELOG.md, settei-kdl/CHANGELOG.md,
settei-dhall/CHANGELOG.md, and settei-env/CHANGELOG.md, above the existing `## 0.1.0.0`
heading, in the existing style:

```markdown
## Unreleased

- Add `renderYamlErrorText` and `renderYamlErrorsText`: operator-readable, secret-safe
  text renderers for `YamlSourceError`, matching the core `renderErrorsText` tone.
```

(adjust names per package). Finally write the ADR, expected path
docs/adr/0009-adapter-error-rendering-contract.md (after verifying the number per the
Decision Log). Outline: **Context** — core renders resolution failures but the four
adapter error types had no renderers, so applications printed derived `Show` output; the
ergonomics MasterPlan makes EP-17 the contract owner with EP-16 and EP-18 as consumers.
**Decision** — every source adapter exports `render<X>ErrorText :: <X>Error -> Text` and
`render<X>ErrorsText :: NonEmpty <X>Error -> Text`; the plural is `Text.unlines` of the
singular; one line per problem leading with the most locating information available
(source name, then path:line:column parenthetical with graceful omission, then structural
context where the type has one, then the fixed message; env errors are sentence-form
naming variables and keys); renderers add no data beyond the error's existing secret-safe
fields, so redaction remains by construction; text only. **Consequences** — no adopting
service needs `Show` for operator output; future position fields (EP-13) join the
parenthetical additively; JSON renderers remain possible as additive exports.
**Rejected Alternatives** — per-adapter JSON documents now (no consumer, quadruples
golden surface); a shared rendering typeclass or core-owned rendering (dependency
direction and abstract types forbid it); amending ADR 0003 instead of a new ADR (the
contract spans four non-core packages).


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/settei`. Enter
the development shell implicitly by prefixing every cabal command with `nix develop -c`.

First, the precondition check (Progress item 1). Read the current
`DhallSourceError` definition and the ADR directory:

```bash
grep -n "data DhallSourceError" -A 10 settei-dhall/src/Settei/Dhall.hs
ls docs/adr/
grep -n -i "adr\|0008\|0009" docs/plans/16-provide-shared-tagged-format-configuration-loading.md
```

Record in the Decision Log which Dhall fields exist and which ADR number is free, then
proceed. For each of Milestones 1–4: edit the adapter module and its test file as
specified in Plan of Work, format, and run that package's suite. The four suite names
below were verified against the cabal files on 2026-07-19 (`test-suite settei-yaml-tests`,
`settei-kdl-tests`, `settei-dhall-tests` — settei-dhall also has a separate
`settei-dhall-prototype-tests` suite this plan does not touch — and
`settei-env-tests`):

```bash
nix develop -c fourmolu -i settei-yaml/src/Settei/Yaml.hs settei-yaml/test/Settei/YamlTest.hs
nix develop -c cabal test settei-yaml-tests --test-show-details=direct
```

Expected tail of the output (test counts will differ; what matters is the final line):

```text
All N tests passed (0.42s)
Test suite settei-yaml-tests: PASS
```

A failing exact-string assertion prints an HUnit diff like `expected: "..." but got:
"..."`; on the first run of a new assertion, copy the actual string into the test if and
only if it matches the format contract in the Decision Log, then re-run. Repeat the
pattern for the other packages:

```bash
nix develop -c cabal test settei-kdl-tests --test-show-details=direct
nix develop -c cabal test settei-dhall-tests --test-show-details=direct
nix develop -c cabal test settei-env-tests --test-show-details=direct
```

Commit after each milestone. Every commit message must follow Conventional Commits and
must carry the three trailers below (exactly these values). Example for Milestone 1:

```text
feat(settei-yaml): add operator-readable YAML error renderers

Export renderYamlErrorText and renderYamlErrorsText so applications stop
printing Show output for YamlSourceError, with exact-string tests for
every YamlErrorCategory and location-omission behavior.

MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/17-add-error-renderers-to-every-source-adapter.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

Use the same shape with scopes `settei-kdl`, `settei-dhall`, `settei-env` for Milestones
2–4; `feat(examples): render adapter errors instead of Show output` for Milestone 5;
and `docs: teach adapter error renderers and record the rendering contract` for
Milestone 6 (guides, changelogs, and the ADR can be one commit or two — keep the ADR
with the guide changes so the contract and its teaching land together). Commit directly
to the current branch; do not create a feature branch. Update this plan's Progress
section (and Decision Log or Surprises where applicable) in the same commit as the work
it describes.

For Milestone 5, after the example edits:

```bash
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
```

For Milestone 6, after guides, changelogs, and the ADR, re-run the full suite one final
time (documentation cannot break tests, but the final green run is the completion
evidence) and perform the end-of-plan bookkeeping: mark the two EP-17 rows in
docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md Progress as
done and set the EP-17 registry row to Complete, write this plan's Outcomes &
Retrospective, and confirm the ADR distillation pass (the contract ADR written in
Milestone 6 is that pass; verify nothing else in the Decision Log or Surprises deserves
promotion).


## Validation and Acceptance

Adapter-level acceptance: the four suites pass —

```bash
nix develop -c cabal test settei-yaml-tests settei-kdl-tests settei-dhall-tests settei-env-tests --test-show-details=direct
```

— and each suite contains an "error rendering" group whose assertions pin the exact
single-line output for every enumerated case: all nine `YamlErrorCategory` values, all
eight `KdlErrorCategory` values (including one related-span case rendering
`; also at LINE:COLUMN`), all eight `DhallErrorCategory` values, and all five `EnvError`
constructors, plus the omission cases (no path, no line/column) and the
plural-is-unlines-of-singular property. IO-error cases assert the stable prefix rather
than the OS-dependent message tail. These tests fail before the renderers exist (the
functions are not in scope), which demonstrates the change is effective beyond
compilation.

Workspace-level acceptance: the complete suite passes —

```bash
nix develop -c cabal test all --test-show-details=direct
```

Behavioral acceptance, observable by a human: `grep -rn "Text.pack . show" examples/`
no longer matches any adapter-error site in
examples/settei-cli/src/Settei/Example/Cli.hs or
examples/settei-service/src/Settei/Example/Service.hs, and running the example CLI
against a YAML file containing a duplicate mapping key, for example

```bash
printf 'service:\n  port: 1\n  port: 2\n' > /tmp/dup.yaml
nix develop -c cabal run settei-example-cli -- --config /tmp/dup.yaml
```

prints to stderr a single diagnostic line in the contract shape — source name, then
`(path:line:column)`, then ` at $.service: `, then the adapter's fixed duplicate-key
message — instead of a `YamlSourceError {...}` record dump, and exits nonzero. (Check
the CLI's actual flag spelling in examples/settei-cli before running; the assertion is
about the stderr shape, not the flag.) Documentation acceptance: the four guides named in
Milestone 6 contain no hand-rolled `renderYamlErrors`/`renderKdlErrors`/
`renderDhallErrors` definitions, each shows the exported renderer, each adapter changelog
has the Unreleased entry, and the contract ADR exists in docs/adr/.


## Idempotence and Recovery

Every step is additive and safely repeatable. Adding an already-present export or
function is a compile error, not corruption; re-running any test command is free of side
effects (the Dhall tests isolate `XDG_CACHE_HOME` to a temporary directory, per
docs/adr/0006, and no test touches the network or the real process environment). If a
milestone is interrupted, `git status` shows the touched files; either finish the edit or
`git checkout -- <file>` to return to the last commit and restart that milestone from its
Plan of Work paragraph. Because each milestone is one package plus its tests (or docs
only), a failed milestone never leaves another package broken: the previously committed
milestones keep `cabal test all` meaningful. The exact-string bootstrap technique
(deliberately wrong expected value, copy the actual from the diff) is self-correcting —
an incorrectly copied string simply fails again. If EP-18 lands mid-implementation and
removes the `EnvError` `Left` branch from `envSource`, drop the Service.hs line-281 edit
from Milestone 5 and note it in the Decision Log; nothing else in this plan depends on
it. If a rebase conflict arises against EP-15/16/18/19 work (they touch disjoint modules,
so this is unlikely outside the examples), the examples are the only shared surface —
re-apply the mechanical substitutions of Milestone 5, which are order-independent.


## Interfaces and Dependencies

No new package, no new dependency, no cabal `build-depends` change: every renderer uses
only `Data.Text` and `Data.List.NonEmpty`, both already imported by all four modules, and
the tests use the already-configured tasty/tasty-hunit harnesses. The contract this plan
owns, which EP-16 (loader failure surfacing), EP-18 (env failure surfacing), and EP-21
(examples and guides sweep) may consume by exact name, is the following export set, all
present at the end of Milestones 1–4:

```haskell
-- module Settei.Yaml (settei-yaml/src/Settei/Yaml.hs)
renderYamlErrorText :: YamlSourceError -> Text
renderYamlErrorsText :: NonEmpty YamlSourceError -> Text

-- module Settei.Kdl (settei-kdl/src/Settei/Kdl.hs)
renderKdlErrorText :: KdlSourceError -> Text
renderKdlErrorsText :: NonEmpty KdlSourceError -> Text

-- module Settei.Dhall (settei-dhall/src/Settei/Dhall.hs)
renderDhallErrorText :: DhallSourceError -> Text
renderDhallErrorsText :: NonEmpty DhallSourceError -> Text

-- module Settei.Env (settei-env/src/Settei/Env.hs)
renderEnvErrorText :: EnvError -> Text
renderEnvErrorsText :: NonEmpty EnvError -> Text
```

Behavioral guarantees attached to the contract: every plural renderer is exactly
`Text.unlines . fmap <singular> . NonEmpty.toList` (so output ends with a newline and
each problem is one line); every singular renderer emits locating information before the
message with graceful omission of absent pieces; and no renderer introduces data beyond
the fields its error type already retains, preserving the secret-safety established by
docs/adr/0004, docs/adr/0005, docs/adr/0006, and the `EnvError` design. The consuming
modules changed by this plan are `Settei.Example.Cli`
(examples/settei-cli/src/Settei/Example/Cli.hs) and `Settei.Example.Service`
(examples/settei-service/src/Settei/Example/Service.hs); the documentation surfaces are
docs/guides/yaml.md, docs/guides/kdl.md, docs/guides/dhall.md,
docs/guides/environment-and-cli.md, the four adapter CHANGELOG.md files, and the new
contract ADR in docs/adr/. Core `Settei.Render` is read for tone but not modified.
