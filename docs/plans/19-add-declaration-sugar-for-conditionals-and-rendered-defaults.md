---
id: 19
slug: add-declaration-sugar-for-conditionals-and-rendered-defaults
title: "Add declaration sugar for conditionals and rendered defaults"
kind: exec-plan
created_at: 2026-07-19T14:54:49Z
intention: "intention_01kxxdt2m8eysvxggq33jsmt2v"
master_plan: "docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md"
---

# Add declaration sugar for conditionals and rendered defaults

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Settei is a Haskell library for typed, layered, explainable application configuration. A
program builds one value of type `Config a` (a "declaration") that names every setting it
may read, and Settei can both statically list those settings (`describe`) and resolve them
against ordered sources (files, environment variables, command-line flags) with a full
provenance report.

A 2026-07-19 API review found two ergonomics gaps that roughly 50 microservices and 20
applications would otherwise each work around by hand:

Gap A: declaring "require this setting only under some condition" — the canonical case
being "require the database password only in the Production environment" — currently needs
a raw `Control.Selective.select` call with an inside-out `Either` encoding
(`Left ()` means "evaluate the branch", `Right Nothing` means "skip it"). It is
boilerplate-heavy and easy to invert silently.

Gap B: a typed default value (for example the integer `8080`) shows up in provenance
reports as the placeholder `<derived>` unless the author remembered to use
`publicSettingWithRenderer` and supply a rendering function. Both reference applications
independently hand-rolled the same `Text.pack . show` plumbing to avoid this.

After this plan is implemented, an application author writes:

```haskell
productionPassword :: Config (Maybe SecretText)
productionPassword =
  whenEq (required environmentSetting) Production (required databasePasswordSetting)
```

instead of five lines of `select` encoding, and writes:

```haskell
httpPortSetting :: Setting Int
httpPortSetting = publicShowSetting httpPortKey "HTTP bind port" boundedIntegralDecoder
```

to get a report that says `8080` instead of `<derived>`. Two further combinators round out
the surface: `whenConfig` (condition as a `Config Bool`) and `fallbackTo` (try an optional
declaration, fall back to another — the key-migration/alias pattern the fleet needs when
renaming configuration keys). All sugar desugars to the existing `Functor` + `Selective`
operations, so static inspection via `describe` remains complete and the deliberate
absence of a `Monad` instance (docs/adr/0002) is untouched. Success is visible by running
the test suite (`nix develop -c cabal test settei-tests --test-show-details=direct`) and
by reading the rewritten `productionPassword` in
examples/settei-service/src/Settei/Example/Service.hs.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] (2026-07-19) Milestone 1: add `whenConfig`, `whenEq`, `fallbackTo` to settei/src/Settei/Config.hs with schema-footprint haddocks; rewrite the module haddock example to teach `whenEq` first while keeping `select` documented.
- [x] (2026-07-19) Milestone 1: add `publicShowSetting` and `withRenderer` to settei/src/Settei/Setting.hs with haddocks covering the Show-renderer caveat and secret-setting behavior.
- [x] (2026-07-19) Milestone 1: library compiles warning-clean (`nix develop -c cabal build settei`).
- [x] (2026-07-19) Milestone 2: describe-level tests in settei/test/Settei/ConfigTest.hs (schema possible/necessary/condition rows for all three combinators, plus agreement with the raw `select` encoding) and runConfig-level tests for both branch outcomes.
- [x] (2026-07-19) Milestone 2: resolution-report tests in settei/test/Settei/ResolveTest.hs (selected / not-selected outcomes and `BranchTrace` rows for `whenEq` and `fallbackTo`; rendered-default tests for `publicShowSetting`, `withRenderer`, and secret redaction).
- [x] (2026-07-19) Milestone 2: `nix develop -c cabal test settei-tests --test-show-details=direct` passes (102 tests).
- [ ] Milestone 3: examples/settei-service/src/Settei/Example/Service.hs uses `whenEq` for `productionPassword` and `publicShowSetting` instead of the hand-rolled `publicInteger`; examples/settei-cli/src/Settei/Example/Cli.hs uses `publicShowSetting` for `timeoutSetting`. Diffs kept minimal.
- [ ] Milestone 3: `nix develop -c cabal test all --test-show-details=direct` passes.
- [ ] Milestone 4: docs/guides/kubernetes-service.md conditional section teaches `whenEq`; docs/guides/getting-started.md gains a short conditional-declaration and rendered-default passage; README.md checked (updated only if it shows a raw `select` conditional).
- [ ] Milestone 4: settei/CHANGELOG.md entry added; dated amendment appended to docs/adr/0002-inspectable-configuration-algebra.md.
- [ ] Milestone 5: final full validation, MasterPlan registry/progress updated, this plan's living sections completed, ADR distillation pass done.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: All three conditional combinators are plain functions defined with `fmap` and
  the existing `select`; no new constructor is added to the private `Config` GADT in
  settei/src/Settei/Internal/Config.hs.
  Rationale: Verified against the source during planning. `SelectConfig` already gives the
  needed runtime semantics (`runConfig` evaluates the selector first and evaluates the
  branch only for `Left`, Internal/Config.hs lines 120-126) and the needed static
  semantics (`describeConfig` maps `SelectConfig` to `conditionalSchema selector branch`,
  lines 153-154, which produces exactly the Conditional presence and `Condition` rows the
  sugar must report). Adding constructors would force changes to both interpreters for
  zero new expressive power and would enlarge the surface ADR 0002 keeps deliberately
  small. If implementation reveals a report-quality reason to add a node (for example a
  named branch label), stop, record it here, and amend ADR 0002 first.
  Date: 2026-07-19

- Decision: Final public names are `whenConfig`, `whenEq`, and `fallbackTo`, all exported
  from `Settei.Config` (and therefore re-exported by the umbrella module
  settei/src/Settei.hs).
  Rationale: A bare `when` would shadow `Control.Monad.when` in consumer code, and `whenS`
  collides with `Control.Selective.whenS` (type `f Bool -> f () -> f ()`), which guide
  readers import unqualified. `whenConfig` follows the codebase's existing pattern of
  suffixing with the produced type where a bare verb is taken (compare `constantDefault`,
  `caseDefault` producing `Default`). `whenEq` has no clash. `fallbackTo` was chosen over
  the suggested `orElseConfig` because `Control.Selective` already exports an `orElse`
  with different (`Semigroup`-accumulating `Either`) semantics, and because `fallbackTo`
  reads correctly infix: ``optional newSetting `fallbackTo` required oldSetting``.
  Date: 2026-07-19

- Decision: Add `publicShowSetting :: Show a => Key -> Text -> Decoder a -> Setting a`
  whose renderer is `Text.pack . show`. A `Show`-based renderer is acceptable for report
  display.
  Rationale: The renderer affects only how a typed default value is displayed in
  provenance reports; it is never parsed back and never touches secrets.
  `defaultReportedValue` in settei/src/Settei/Resolve.hs (around line 313) consults the
  renderer only for `Public` settings and unconditionally stores a redaction marker for
  `Secret` ones, so a `Show`-based renderer can be ugly (a derived `Show` of a rich record
  prints Haskell syntax) but never unsafe. The haddock must state this caveat and
  recommend `publicShowSetting` for primitive and enum-like types, with
  `publicSettingWithRenderer` for bespoke display (the examples keep their
  operator-friendly lowercase enum renderers such as `renderEnvironment` for this reason).
  Date: 2026-07-19

- Decision: Also add `withRenderer :: (a -> Text) -> Setting a -> Setting a` as a post-hoc
  modifier on any already-constructed setting.
  Rationale: It composes with helper functions an application may already have (wrap an
  existing `publicSetting` without re-stating key, description, and decoder), and it makes
  the renderer decision separable from the construction site. Applying it to a secret
  setting is defined and harmless: the renderer is stored but ignored, because
  `defaultReportedValue` checks sensitivity before consulting the renderer. The haddock
  states this explicitly.
  Date: 2026-07-19

- Decision: Rejected alternative — making `withDefault` require a renderer (for example
  `withDefault :: Setting a -> (a -> Text) -> Default a -> Config a`).
  Rationale: It would break the legitimate rendererless flow of secret settings (which
  must never render defaults) by demanding a function that is then ignored, and it adds
  mandatory noise for public settings whose authors never inspect reports. Opt-in
  rendering with an easy `publicShowSetting` spelling fixes the observed forgetfulness
  without changing `withDefault`'s type.
  Date: 2026-07-19

- Decision: This plan adds no decoder combinators and no `Decoder` instances.
  Rationale: The parent MasterPlan assigns decoder composition to EP-15
  (docs/plans/15-add-a-decoder-functor-and-combinator-kit.md). `publicShowSetting` only
  wraps an existing `Decoder` argument; it does not build or transform decoders.
  Date: 2026-07-19

- Decision: Example edits stay minimal (rewrite `productionPassword`, replace the
  hand-rolled integer-setting helpers, nothing else).
  Rationale: EP-21
  (docs/plans/21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md)
  owns the coherent full rewrite of both reference applications; the MasterPlan directs
  each child plan to keep example diffs small to avoid conflicts.
  Date: 2026-07-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

The repository root is /Users/shinzui/Keikaku/bokuno/settei. It is a multi-package Cabal
workspace built through Nix; every build or test command in this plan is run from the
repository root as `nix develop -c cabal ...`. The core library lives in the `settei/`
subdirectory; its test suite is named `settei-tests` (see settei/settei.cabal). Reference
applications live under `examples/` (they are the public-API conformance boundary per
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md).

Terms used in this plan, defined once:

- A *setting* (`Setting a`, settei/src/Settei/Setting.hs) is metadata for one logical
  configuration value: a dotted `Key` such as `database.password`, a human description, a
  `Sensitivity` (`Public` or `Secret`), a `Decoder a` that turns a raw source value into
  the typed value, and an optional *renderer* `Maybe (a -> Text)` used only to display
  typed default values in reports. The record constructor is private; callers use
  `publicSetting`, `publicSettingWithRenderer`, or `secretSetting`.
- A *declaration* (`Config a`) composes settings. `Config` is a private GADT
  (settei/src/Settei/Internal/Config.hs) with constructors for pure values, `fmap`,
  applicative application, setting requests, defaults, and `SelectConfig` — the node
  behind the `Selective` type class's `select`. The public module
  settei/src/Settei/Config.hs exposes only `Config`, `describe`, `required`, `optional`,
  and `withDefault`; the `Functor`/`Applicative`/`Selective` instances come from the
  internal module. Per docs/adr/0002-inspectable-configuration-algebra.md, `Config`
  deliberately has no `Monad` instance and must never gain bind-equivalent power, because
  bind could build new keys from resolved values and destroy complete static inspection.
- *Selective* is the type class from the `selective` package.
  `select :: f (Either a b) -> f (a -> b) -> f b` runs the second ("branch") effect only
  when the first ("selector") produces `Left`. The runtime interpreter `runConfig`
  (Internal/Config.hs, lines 120-126) implements exactly that short-circuit; the static
  interpreter `describeConfig` (lines 153-154) conservatively records the branch.
- A *schema* (`Schema`, settei/src/Settei/Schema.hs) is the result of `describe`. A
  setting in it is *possible* (occurs anywhere), *necessary* (evaluated on every path), or
  *conditional* (on the effectful side of a selective branch, may be skipped). A
  `Condition` row records a branch: `conditionDependencies` (the selector's possible
  keys) and `conditionSettings` (the branch's possible keys, the ones "activated" by the
  branch). Test accessors: `schemaPossible`, `schemaNecessary`, `schemaConditions`,
  `schemaSettingKey`, `schemaSettingRequirement`.
- A *resolution report* (`ResolutionReport`, settei/src/Settei/Report.hs) describes one
  actual run: per-key `ResolutionNode`s whose `outcome` is `Resolved`, an error, or
  `NotSelected` (the branch was skipped), plus `BranchTrace` rows
  (`dependencies`, `settings`, `selected :: Bool`) — one per evaluated selective node.
- A *reported value* (`ReportedValue`, settei/src/Settei/Provenance.hs) is the only value
  representation reports may hold: visible text, `<redacted>` for secrets, or `<derived>`
  when a public typed default has no renderer. `defaultReportedValue` in
  settei/src/Settei/Resolve.hs (around line 313) is where the renderer decision happens:
  Secret always redacts; Public uses the renderer if present, else `<derived>`.

Relevant ADRs consulted (repository-relative): docs/adr/0002-inspectable-configuration-algebra.md
(the algebra this plan extends; no-Monad rule; conservative schema; this plan appends an
amendment), docs/adr/0003-resolution-provenance-and-default-semantics.md (default
semantics; the renderer opt-in for public typed defaults; secret settings always store a
redaction marker — the new constructors must preserve all of it), and
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md (why the
examples must adopt the sugar, and why the edits stay minimal for EP-21). No other ADR is
relevant.

The parent MasterPlan is
docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md (this is its
EP-19; no hard dependencies, implementable immediately). Cross-MasterPlan constraint: the
correctness initiative docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
lands first. If, when you start, resolver signatures differ slightly from the excerpts in
this plan (for example `resolve`'s result shape), adapt the test snippets to the current
signatures; the combinator design is unaffected. EP-15 owns all decoder combinators — do
not add any here.

The two gaps, as they exist in the tree today:

Gap A. examples/settei-service/src/Settei/Example/Service.hs lines 207-213:

```haskell
productionPassword :: Config (Maybe SecretText)
productionPassword = select selector branch
  where
    selector =
      (\environment -> if environment == Production then Left () else Right Nothing)
        <$> required environmentSetting
    branch = (\password _ -> Just password) <$> required databasePasswordSetting
```

The same shape appears in the module haddock of settei/src/Settei/Config.hs (lines
10-20), in docs/guides/kubernetes-service.md (lines 120-137), in
settei/test/Settei/ConfigTest.hs (`productionOnly`), and in
settei/test/Settei/ResolveTest.hs. Note the trap: swapping `Left`/`Right` type-checks but
silently inverts the condition.

Gap B. examples/settei-service/src/Settei/Example/Service.hs lines 373-375 defines a
hand-rolled helper:

```haskell
publicInteger :: Key -> Text -> Setting Int
publicInteger key description =
  publicSettingWithRenderer key description boundedIntegralDecoder (Text.pack . show)
```

and examples/settei-cli/src/Settei/Example/Cli.hs line 313-315 inlines the same
`Text.pack . show` renderer for `timeoutSetting`. Without that plumbing, a defaulted port
reports as `<derived>`.

Files this plan touches: settei/src/Settei/Config.hs, settei/src/Settei/Setting.hs,
settei/test/Settei/ConfigTest.hs, settei/test/Settei/ResolveTest.hs,
examples/settei-service/src/Settei/Example/Service.hs,
examples/settei-cli/src/Settei/Example/Cli.hs, docs/guides/kubernetes-service.md,
docs/guides/getting-started.md, README.md (verification only, edit only if needed),
settei/CHANGELOG.md, docs/adr/0002-inspectable-configuration-algebra.md, this plan, and
the MasterPlan's registry/progress. No cabal file changes are needed: no new modules, no
new dependencies (`selective`, `text`, and `lens` are already dependencies of `settei`),
and `Settei.Config`/`Settei.Setting` are already exposed and re-exported by
settei/src/Settei.hs.


## Plan of Work

Milestone 1 — core combinators and constructors. At the end of this milestone the library
exports three conditional combinators and two renderer-aware setting constructors, the
`Settei.Config` module haddock teaches `whenEq` before `select`, and
`nix develop -c cabal build settei` succeeds warning-clean. Everything is additive.

In settei/src/Settei/Config.hs: add `whenConfig`, `whenEq`, and `fallbackTo` to the export
list (keep alphabetical-ish grouping with the existing exports) and add
`import Control.Selective (select)` (the module currently uses the implicit Prelude,
which supplies `<$>`, `maybe`, `const`, `Eq`, and `Bool`; no other import is needed).
Definitions, exactly these desugarings:

```haskell
-- | Evaluate a declaration only when a condition is 'True'.
--
-- Desugars to 'Control.Selective.select'; no new syntax is introduced. Schema
-- footprint: every setting inside the condition keeps its presence (a 'required'
-- condition setting stays necessary); every setting inside the branch becomes
-- conditional; one 'Condition' row is recorded whose dependencies are the
-- condition's possible keys and whose activated settings are the branch's
-- possible keys. At resolution time a 'False' condition reports the branch's
-- settings as not selected rather than missing.
whenConfig :: Config Bool -> Config a -> Config (Maybe a)
whenConfig condition branch =
  select
    ((\flag -> if flag then Left () else Right Nothing) <$> condition)
    ((\value () -> Just value) <$> branch)

-- | Evaluate a declaration only when a scrutinee equals an expected value.
--
-- @'whenEq' (required environmentSetting) Production (required passwordSetting)@
-- requires the password only when the resolved environment is @Production@.
-- Schema footprint is identical to 'whenConfig': scrutinee settings keep their
-- presence, branch settings become conditional, and one 'Condition' row links
-- them.
whenEq :: (Eq d) => Config d -> d -> Config a -> Config (Maybe a)
whenEq scrutinee expected = whenConfig ((== expected) <$> scrutinee)

-- | Use the first declaration's value when present; otherwise evaluate the
-- fallback. This is the key-migration idiom:
-- @optional newSetting \`fallbackTo\` required oldSetting@ reads a renamed key
-- and consults the old key only when no source supplies the new one.
--
-- Desugars to 'Control.Selective.select'. Schema footprint: the primary
-- declaration's settings keep their presence; the fallback's settings become
-- conditional; one 'Condition' row records the primary's possible keys as
-- dependencies and the fallback's possible keys as activated settings. Caveat:
-- the alias is declaration-level, not per-source — a value for the primary key
-- in any source, however low its precedence, suppresses the fallback entirely.
fallbackTo :: Config (Maybe a) -> Config a -> Config a
fallbackTo primary fallback =
  select
    (maybe (Left ()) Right <$> primary)
    (const <$> fallback)
```

Why no new GADT constructor is needed (analysis, recorded per the Decision Log): each
combinator is `fmap` around one `select`. `runConfig` already evaluates `SelectConfig`
selectors first and branches only on `Left`, so `whenConfig` with a `False` condition
never requests the branch's settings, and `fallbackTo` with a present primary never
requests the fallback's. `describeConfig` already maps `SelectConfig` to
`conditionalSchema`, which is precisely the documented schema footprint. The resolver
(settei/src/Settei/Resolve.hs, around lines 185-205) already emits one `BranchTrace` per
evaluated selective node and `NotSelected` placeholder nodes for skipped possible
settings, so reports need no changes either.

Rewrite the module haddock of settei/src/Settei/Config.hs: keep the opening two
paragraphs, replace the `productionPassword` example with the `whenEq` spelling shown in
Purpose, keep the `describe`/`schemaNecessary` inspection snippet (it still prints
`["runtime.environment"]`), and add one sentence plus a small code block showing the raw
`select` desugaring so full Selective generality stays documented. Keep the closing
no-Monad paragraph verbatim.

In settei/src/Settei/Setting.hs: add `publicShowSetting` and `withRenderer` to the export
list and add `import Data.Text qualified as Text` (the module's `Settei.Prelude` exports
the `Text` type but not `pack`). Definitions:

```haskell
-- | Declare a public setting whose typed default values render via 'show'.
--
-- Equivalent to 'publicSettingWithRenderer' with @Text.pack . show@. Best for
-- primitive and enum-like types; a derived 'Show' of a rich type may be ugly in
-- reports but is never unsafe, because renderers only affect display of typed
-- defaults and secret settings always redact regardless of any renderer.
publicShowSetting :: (Show a) => Key -> Text -> Decoder a -> Setting a
publicShowSetting key description decoder =
  publicSettingWithRenderer key description decoder (Text.pack . show)

-- | Attach or replace the typed-default renderer of an existing setting.
--
-- On a secret setting this is harmless: the stored renderer is ignored and
-- reports keep showing the redaction marker (see 'Settei.Resolve').
withRenderer :: (a -> Text) -> Setting a -> Setting a
withRenderer renderValue settingSpec = settingSpec & #renderer ?~ renderValue
```

(`&`, `?~`, and the `#renderer` label come from `Settei.Prelude`'s lens re-export plus the
`Data.Generics.Labels` import already in the module.)

Milestone 2 — tests that pin the contract. At the end of this milestone
`nix develop -c cabal test settei-tests --test-show-details=direct` passes with new cases
covering schema shape, runtime shape, and report rendering. The new tests demonstrate
behavior beyond compilation: the schema assertions would fail if a desugaring inverted
`Left`/`Right`, and the report assertions would fail if renderers leaked into secret
display.

In settei/test/Settei/ConfigTest.hs add, alongside the existing `productionOnly` cases
(keep those — they pin the raw encoding): a `whenEq`-based declaration
`sugaredProductionOnly = whenEq (required environmentSetting) "production" (required passwordSetting)`
and cases asserting (a) its `schemaPossible` key set is
`{runtime.environment, database.password}`, its `schemaNecessary` is
`{runtime.environment}`, and it has exactly one `Condition` with dependencies
`{runtime.environment}` and settings `{database.password}` — byte-for-byte the same
assertions as the existing raw-select test, proving the sugar and the manual encoding
agree; (b) a `whenConfig` case using
`whenConfig ((== "production") <$> required environmentSetting) (required passwordSetting)`
with the same schema assertions (this exercises the `Config Bool` entry point without
needing a Bool decoder); (c) a `fallbackTo` case: with two text settings `newSetting`
(key `service.endpoint`) and `oldSetting` (key `service.url`), the schema of
``optional newSetting `fallbackTo` required oldSetting`` has possible keys
`{service.endpoint, service.url}`, necessary keys `{service.endpoint}`, and one
`Condition` with dependencies `{service.endpoint}` and settings `{service.url}`; and (d)
runtime cases via the file's existing pure `interpret` helper: `whenEq` under
`developmentValues` yields `Right Nothing`, under `productionValues` yields
`Left (Missing passwordKey)`, and under production-plus-password yields
`Right (Just "...")`; `fallbackTo` yields the primary's value when the new key is
present, the fallback's value when only the old key is present, and
`Left (Missing oldKey)` when neither is.

In settei/test/Settei/ResolveTest.hs add a small group mirroring the file's existing
selective cases but built with the sugar (reuse its `environmentSource`, `source`, and
key-constant helpers): (a) resolving a `whenEq`-based `productionPassword` against a
development source yields value `Nothing`, a `database.password` node with outcome
`NotSelected`, and exactly one `BranchTrace` with `selected = False`; against a
production source it fails with the password's missing-requirement error; (b) resolving
``optional newSetting `fallbackTo` required oldSetting`` against a source supplying the
new key yields the new value, an old-key node with outcome `NotSelected`, and a
`BranchTrace` with `selected = False`; against a source supplying only the old key it
yields the old value with a `BranchTrace` `selected = True`; (c) rendered defaults:
`withDefault (publicShowSetting portKey "Port" boundedIntegralDecoder) (constantDefault (RuleName "built-in-port") "Built-in" 8080)`
resolved with no sources produces a node whose outcome is `Resolved v` with
`renderReportedValue v == "8080"`, while the same declaration with plain `publicSetting`
renders `"<derived>"`; (d) `withRenderer (Text.pack . show)` applied to a public setting
renders the default visibly, and applied to a `secretSetting` still renders
`"<redacted>"` (this pins the `defaultReportedValue` sensitivity-first rule from
settei/src/Settei/Resolve.hs). Follow the file's existing assertion style (`^. #outcome`,
`^. #branches`, `renderReportedValue`, `expectSuccess`); add
`import Data.Text qualified as Text` if the file lacks it.

Milestone 3 — minimal example adoption. At the end of this milestone both reference
applications use the sugar and `nix develop -c cabal test all --test-show-details=direct`
passes. In examples/settei-service/src/Settei/Example/Service.hs replace the
`productionPassword` body (lines 207-213) with the one-line `whenEq` form and delete the
now-unused `import Control.Selective (select)` (line 32) if nothing else uses it; delete
the `publicInteger` helper (lines 373-375) and change its three call sites
(`httpPortSetting`, `databasePortSetting`, `databasePoolSizeSetting`) to
`publicShowSetting ... boundedIntegralDecoder`. In
examples/settei-cli/src/Settei/Example/Cli.hs change `timeoutSetting` (lines 313-315) to
`publicShowSetting serviceTimeoutKey "Request timeout in seconds" boundedIntegralDecoder`.
Do not touch the enum settings that use bespoke lowercase renderers
(`environmentSetting`, `outputFormatSetting`) — derived `Show` would print `Production`
where operators expect `production`. Fix any resulting unused-import warnings
(`Data.Text qualified as Text` may become unused in one file; check compiler output).
Nothing else changes — EP-21 owns the full rewrite.

Milestone 4 — documentation, changelog, ADR amendment. At the end of this milestone every
document that taught the raw encoding teaches the sugar. In
docs/guides/kubernetes-service.md replace the `select`-based `productionPassword` snippet
(lines 120-137) with the `whenEq` form, adjust the surrounding sentence ("express the
condition with `whenEq`; the general `select` from the `selective` package remains
available for arbitrary branch shapes"), and remove the now-unneeded
`import Control.Selective (select)` from the guide's import block (line 39) and the
`selective` entry from its build-depends listing (line 26) if the guide's code no longer
needs them. In docs/guides/getting-started.md, after the combinator-behavior table
(around line 140), add a short paragraph plus one fenced `haskell` block introducing
`whenEq` (production-only credential) and `fallbackTo` (key migration), and one sentence
in the settings-declaration part recommending `publicShowSetting` for numeric settings so
reports show real values instead of `<derived>`. Check README.md with
`grep -n "select\|productionPassword" README.md`; as of planning it contains no raw
conditional snippet (its lines 100-121 show `caseDefault`), so expect no edit — update
only if the post-correctness tree changed that. In settei/CHANGELOG.md add (create the
section if absent) under a `## Unreleased` heading above `## 0.1.0.0`: added `whenConfig`,
`whenEq`, `fallbackTo` to `Settei.Config` and `publicShowSetting`, `withRenderer` to
`Settei.Setting`; all Selective-expressible, no semantics changes. (Version numbering is
owned by the release process / EP-20; do not bump the `.cabal` version here.) Append to
docs/adr/0002-inspectable-configuration-algebra.md a final section headed
`## Amendment: declaration sugar combinators (YYYY-MM-DD)` (use the real date) stating:
`whenConfig`, `whenEq`, and `fallbackTo` are definitionally expressible via the existing
`Functor` and `Selective` operations and introduce no new syntax nodes; they therefore
inherit the algebra's complete static inspection; the no-Monad rule is unaffected and
remains binding on any future sugar, which must likewise desugar to
Functor/Applicative/Selective.

Milestone 5 — closure. Re-run both validation commands, update the MasterPlan
(docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md): set EP-19's
registry row to Complete and tick its two Progress boxes. Update this plan's Progress,
Decision Log (any deviations), Surprises & Discoveries, and write the Outcomes &
Retrospective entry. Perform the ADR distillation pass (the ADR 0002 amendment from
Milestone 4 is the expected distillation; verify nothing else durable emerged).


## Concrete Steps

All commands run from the repository root /Users/shinzui/Keikaku/bokuno/settei. Before
starting, confirm the correctness MasterPlan has landed
(`grep -n "Status" docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md`
and check its Progress section); if it has not, pause this plan.

Step 1. Edit settei/src/Settei/Config.hs and settei/src/Settei/Setting.hs as specified in
Milestone 1 (exports, imports, definitions, haddocks, module-haddock rewrite). Build:

```bash
nix develop -c cabal build settei
```

Expected: compiles with no warnings (the package uses `-Wall -Wcompat`). A failure like
`Variable not in scope: select` means the `Control.Selective` import is missing; a
`pack` scope error means the qualified `Data.Text` import is missing in Setting.hs.

Step 2. Commit Milestone 1. Every commit in this plan uses Conventional Commits and
carries the three trailers shown here, exactly:

```text
feat(settei): add whenConfig, whenEq, fallbackTo and renderer sugar

Add Selective-expressible conditional combinators to Settei.Config and
Show-based renderer constructors to Settei.Setting; teach whenEq first
in the Settei.Config module haddock.

MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/19-add-declaration-sugar-for-conditionals-and-rendered-defaults.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

Commit on the current branch (repository convention: no feature branches unless asked).
Update the Progress checklist in this plan file in the same commit or a `docs(plans)`
follow-up — the plan must always reflect actual state.

Step 3. Add the Milestone 2 tests to settei/test/Settei/ConfigTest.hs and
settei/test/Settei/ResolveTest.hs, then run:

```bash
nix develop -c cabal test settei-tests --test-show-details=direct
```

Expected: all tests pass, with output ending like:

```text
All N tests passed (0.0Xs)
Test suite settei-tests: PASS
```

where N exceeds the previous count by the number of added cases. If a schema assertion
fails with the necessary set containing `database.password`, the desugaring's
`Left`/`Right` orientation is inverted — fix the combinator, not the test. Commit:

```text
test(settei): pin schema and report contracts of the declaration sugar

MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/19-add-declaration-sugar-for-conditionals-and-rendered-defaults.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

Step 4. Apply the Milestone 3 example edits, then run the full workspace:

```bash
nix develop -c cabal test all --test-show-details=direct
```

Expected: every package's suite passes (the conformance and example suites exercise the
rewritten declarations; the service example's own tests assert the same
production/development branch behavior, so they prove `whenEq` is drop-in). Commit:

```text
refactor(examples): adopt whenEq and publicShowSetting in reference apps

MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/19-add-declaration-sugar-for-conditionals-and-rendered-defaults.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

Step 5. Apply the Milestone 4 documentation, changelog, and ADR edits. Verify no stale
teaching remains:

```bash
grep -rn "if environment == " docs/guides README.md settei/src/Settei/Config.hs
```

Expected: no hits outside historical plan documents (the raw encoding may legitimately
remain in settei/test/Settei/ConfigTest.hs and ResolveTest.hs as the pinned desugaring
oracle, and in this plan). Commit:

```text
docs(settei): teach conditional sugar; changelog and ADR 0002 amendment

MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/19-add-declaration-sugar-for-conditionals-and-rendered-defaults.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

Step 6. Milestone 5 closure: re-run both commands from Steps 3 and 4, update the
MasterPlan registry row and Progress boxes for EP-19, complete this plan's living
sections, and commit:

```text
docs(plans): complete EP-19 and update master plan status

MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/19-add-declaration-sugar-for-conditionals-and-rendered-defaults.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```


## Validation and Acceptance

Primary commands, in order, from the repository root:

```bash
nix develop -c cabal test settei-tests --test-show-details=direct
nix develop -c cabal test all --test-show-details=direct
```

Acceptance is behavioral:

1. Conditional sugar, schema side: `describe` of
   `whenEq (required environmentSetting) "production" (required passwordSetting)` lists
   both keys as possible, only `runtime.environment` as necessary, and exactly one
   `Condition` whose dependencies are `{runtime.environment}` and whose activated
   settings are `{database.password}` — identical to the raw `select` encoding's schema.
   The new ConfigTest cases assert exactly this via `schemaPossible`, `schemaNecessary`,
   and `schemaConditions`.
2. Conditional sugar, runtime side: resolving that declaration against a development
   source succeeds with value `Nothing`, reports the password node as `NotSelected`, and
   records one `BranchTrace` with `selected = False`; against a production source it
   fails with the password's missing-requirement error. The new ResolveTest cases assert
   this.
3. `fallbackTo`: with the new key present the old key is `NotSelected`
   (`selected = False` trace); with only the old key present the value comes from the
   fallback (`selected = True` trace); the schema marks the old key conditional with the
   documented `Condition` row.
4. Rendered defaults: a defaulted `publicShowSetting` port reports `8080`; the identical
   declaration with `publicSetting` reports `<derived>`; a secret setting reports
   `<redacted>` even with `withRenderer` applied. Asserted via `renderReportedValue`.
5. Examples: `productionPassword` in
   examples/settei-service/src/Settei/Example/Service.hs is the one-line `whenEq` form,
   neither example defines a `Text.pack . show` renderer by hand, and the full workspace
   suite passes — proving the sugar is a drop-in replacement for the reference
   applications' behavior.
6. Documentation: the module haddock of settei/src/Settei/Config.hs and
   docs/guides/kubernetes-service.md teach `whenEq` first; `select` remains documented;
   settei/CHANGELOG.md lists the five new exports; docs/adr/0002 carries the dated
   amendment.

Failure signatures to recognize: `expected one condition, found 0` in ConfigTest means a
desugaring lost its selective node (probably rewrote `select` away);
`Right Nothing` where `Left (Missing ...)` was expected (or vice versa) means the
`Left`/`Right` orientation is inverted; `"<derived>"` where `"8080"` was expected means
the renderer was not attached; any test printing a raw secret is a release blocker —
stop and re-read docs/adr/0003.


## Idempotence and Recovery

Every step is additive and repeatable. Re-running any build or test command is always
safe. The edits are guarded by uniqueness of the code being replaced: if an edit's
anchor text is not found, the step was already applied — verify with `git log --oneline`
and `git diff`, then continue with the next step. No migrations, no generated files, no
golden-file changes are expected (the new tests use programmatic assertions, not
goldens; if a golden test elsewhere fails, you changed behavior rather than adding
surface — revert and re-read Milestone 1, whose changes must not alter any existing
output). To abandon a partial milestone, `git checkout -- <file>` restores any touched
file; commits are per-milestone so `git revert <sha>` unwinds cleanly. If the
`Settei.Config` haddock rewrite conflicts with concurrent work from another ExecPlan,
re-apply only the example swap (whenEq first, select second) on top of the current text
and record the conflict in Surprises & Discoveries.


## Interfaces and Dependencies

No new package dependencies. The `settei` library already depends on `selective >=0.7`
(provides `Control.Selective.select`), `text`, `lens`, and `generic-lens`
(settei/settei.cabal); the sugar uses only these. No cabal file edits; no new modules;
no version bump in this plan.

At the end of Milestone 1 the following must exist, with exactly these signatures:

```haskell
-- settei/src/Settei/Config.hs (exported; re-exported via Settei)
whenConfig :: Config Bool -> Config a -> Config (Maybe a)
whenEq     :: (Eq d) => Config d -> d -> Config a -> Config (Maybe a)
fallbackTo :: Config (Maybe a) -> Config a -> Config a

-- settei/src/Settei/Setting.hs (exported; re-exported via Settei)
publicShowSetting :: (Show a) => Key -> Text -> Decoder a -> Setting a
withRenderer      :: (a -> Text) -> Setting a -> Setting a
```

All five flow through the umbrella module settei/src/Settei.hs automatically (it
re-exports `Settei.Config` and `Settei.Setting` wholesale), so downstream packages and
the examples need no import changes beyond deleting now-unused ones. Internal interfaces
consumed but not modified: `Control.Selective.select` (the only Selective operation
used), `Settei.Internal.Config.SelectConfig` semantics via `runConfig`/`describeConfig`
(unchanged), `Settei.Resolve.defaultReportedValue` (unchanged renderer/sensitivity
rule), and the test accessors `schemaPossible`, `schemaNecessary`, `schemaConditions`,
`reportBranches`/`#branches`, `NotSelected`, `BranchTrace`, and `renderReportedValue`.
Explicit non-interfaces: no `Monad Config`, no bind-equivalent operation, no `Decoder`
combinators (EP-15), no changes to `withDefault`'s type.
