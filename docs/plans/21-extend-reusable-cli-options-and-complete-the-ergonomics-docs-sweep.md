---
id: 21
slug: extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep
title: "Extend reusable CLI options and complete the ergonomics docs sweep"
kind: exec-plan
created_at: 2026-07-19T14:54:49Z
intention: "intention_01kxxdt2m8eysvxggq33jsmt2v"
master_plan: "docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md"
---

# Extend reusable CLI options and complete the ergonomics docs sweep

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Settei is a Haskell configuration library about to be adopted by roughly 50 microservices
and 20 applications. This plan is the capstone of the ergonomics MasterPlan
(docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md): every other
child plan added an API, and this plan makes those APIs the *only* way the project's own
reference applications and guides do things.

After this plan is complete, an adopter gains three concrete things. First, the reusable
command-line options in `Settei.Optparse` (package `settei-optparse-applicative`) cover
the diagnostic modes real services need — today they offer only text/JSON explanation
flags, while both reference applications had to hand-roll richer parsers to get
`--check-config` and `--describe-config`. After this plan, `setteiOptions` parses a full
`DiagnosticMode` (no diagnostic, explain as text, explain as JSON, check-only, describe
schema as text, describe schema as JSON), and a helper interprets that mode so an
application's `main` is a few lines. Second, the two reference applications under
`examples/` become canonical adopter templates: they use the decoder kit (EP-15), the
`settei-formats` tagged-format loader (EP-16), the adapter error renderers (EP-17), the
validated environment bindings (EP-18), and the declaration sugar (EP-19), they print
resolver warnings to stderr (today warnings are silently discarded — the API review's
headline finding), and they contain zero `Text.pack . show` error formatting. Third,
every guide under `docs/guides/`, the top-level `README.md`, `docs/compatibility.md`, and
the package changelogs teach exactly this final API, including a new explicit "null is
not unset" section that documents a subtle layering semantic adopters will otherwise
trip over.

You can see it working by running, from the repository root:

```bash
nix develop -c cabal run settei-example-cli -- --describe-config
nix develop -c cabal run settei-example-cli -- --check-config --config yaml:examples/settei-cli/test/fixtures/application.yaml
```

and observing the schema description and a `configuration valid` confirmation, with any
resolver warnings rendered on stderr, and by running the full test suite green.


## Progress

- [ ] M1: Read the completed EP-15..EP-20 plan documents and the shipped modules; record the reconciled API names (decoder kit, settei-formats types, renderer names, Bindings constructor, sugar helpers, post-EP-12 resolve shape) in this plan's Context section.
- [ ] M1: Replace `ExplainMode` with `DiagnosticMode` in settei-optparse-applicative/src/Settei/Optparse.hs (six constructors, `diagnosticModeOptions`, updated `SetteiOptions` and `setteiOptions`).
- [ ] M1: Add the diagnostic interpretation helpers (`schemaDiagnostic`, `resolutionDiagnostic`) reconciled against the post-EP-12 `ResolveResult` shape.
- [ ] M1: Update settei-optparse-applicative/test/Settei/OptparseTest.hs for the new mode set, mutual exclusion, defaulting, and helper outputs.
- [ ] M1: `cabal build settei-optparse-applicative && cabal test settei-optparse-applicative` green; commit.
- [ ] M2: Rewrite examples/settei-cli/src/Settei/Example/Cli.hs on the new APIs (settei-formats inputs and loader, shared DiagnosticMode, renderers, validated bindings, decoder kit, warnings to stderr, DescribeConfigJson).
- [ ] M2: Rewrite examples/settei-service/src/Settei/Example/Service.hs on the new APIs (single tagged input via settei-formats, shared DiagnosticMode, renderers, validated bindings, whenEq sugar, show-renderer sugar, list decoder from the kit, warnings to stderr).
- [ ] M2: Update both example cabal files to depend on settei-formats and drop now-unused direct adapter dependencies where the loader replaces them.
- [ ] M2: Update examples/settei-cli/test/Settei/Example/CliTest.hs and examples/settei-service/test/Settei/Example/ServiceTest.hs; add warning-rendering and describe-json test cases; verify examples/settei-conformance still passes unchanged.
- [ ] M2: Assert no `Text.pack . show`, `error (show`, or raw `show` on adapter errors remains under examples/ (grep transcript recorded in this plan).
- [ ] M2: `cabal test all` green; commit.
- [ ] M3: docs/guides/getting-started.md — decoder kit, sugar, a warnings subsection, and the new "null is not unset" subsection with the YAML example.
- [ ] M3: docs/guides/environment-and-cli.md — validated Bindings construction, new DiagnosticMode flags and helpers.
- [ ] M3: docs/guides/yaml.md, kdl.md, dhall.md — error-handling snippets use the EP-17 renderers.
- [ ] M3: docs/guides/cli-application.md — rewritten around the new example code.
- [ ] M3: docs/guides/kubernetes-service.md — rewritten around the new example code, plus the readiness/initContainer `--check-config` recipe and the `RejectUnknownKeys` recommendation.
- [ ] M3: docs/guides/README.md index updated (formats guide from EP-16 linked; descriptions match new capabilities).
- [ ] M3: README.md feature snippets updated where the API changed.
- [ ] M3: docs/compatibility.md adoption surface includes settei-formats and all new public modules, reconciled with EP-20's PVP wording.
- [ ] M3: CHANGELOG entries for settei-optparse-applicative and every touched package; EP-15..EP-19 changelog lines read coherently together.
- [ ] M3: commit.
- [ ] M4: `nix develop -c cabal test all --test-show-details=direct` green from a clean state.
- [ ] M4: Manual smoke transcripts for --describe-config, --describe-config-json, --check-config, and a failure-with-warnings run captured in this plan.
- [ ] M4: MasterPlan registry row EP-21 marked Complete; MasterPlan Progress checkboxes for EP-21 checked; MasterPlan Outcomes & Retrospective filled.
- [ ] M4: ADR distillation pass — verify the EP-16/EP-17/EP-18 ADRs and the ADR 0001/0002/0003 amendments are coherent; promote any leftover durable context; fill this plan's Outcomes & Retrospective.
- [ ] M4: final commit.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Replace `ExplainMode` outright with a new `DiagnosticMode` sum type instead of
  keeping `ExplainMode` alongside it or deprecating it gradually.
  Rationale: `settei-optparse-applicative` is version 0.1.0.0 and unpublished; there are no
  external consumers, and the two reference applications — the only in-repo consumers via
  their hand-rolled parsers — are rewritten in this same plan. Carrying two overlapping
  mode types into the fleet-adoption release would make the worse API permanent. The
  break is recorded in the package changelog as a major change.
  Date: 2026-07-19

- Decision: Include `DescribeConfigJson` in `DiagnosticMode` (a `--describe-config-json`
  flag), not just the text describe mode.
  Rationale: The core already ships `renderSchemaJson :: Schema -> Text` in
  settei/src/Settei/Render.hs, so the mode costs one constructor and one line of
  interpretation, and machine-readable schema output is exactly what fleet tooling (CI
  checks, documentation generators) will want. Omitting it would push the first adopter
  who needs it back into hand-rolled flag parsing, recreating the problem this plan fixes.
  Date: 2026-07-19

- Decision: Do not provide a `diagnosticModeOptionsWith` variant taking caller-supplied
  flag metadata, even though the old `explainModeOptionsWith` had one.
  Rationale: With six modes the `With` variant would take five `Mod FlagFields` arguments,
  which is unreadable at call sites. Callers who need custom flag names can compose
  `Options.flag'` alternatives directly, exactly as `Settei.Optparse` itself does; the
  guides show the default-named parser only. If a real consumer demand appears
  post-release, a record-of-modifiers variant can be added compatibly.
  Date: 2026-07-19

- Decision: After successful resolution, both reference applications render non-empty
  warnings to stderr via `renderWarningsText` and keep exit code 0. The rejected
  alternative was a `--strict-config-warnings` flag that turns warnings into a non-zero
  exit.
  Rationale: Warnings (today, unknown-key warnings) are advisory by design; a strict flag
  duplicates a policy the resolver already owns — `ResolveOptions` with
  `RejectUnknownKeys` turns the same condition into a hard resolution error with exit
  code 4 and a proper rendered error. Adding a second, CLI-level strictness knob would
  create two subtly different failure paths for one condition. Services that want
  failure should set `RejectUnknownKeys`; the kubernetes-service guide will recommend
  considering exactly that. Exit code 0 with stderr warnings preserves the documented
  exit-code contract (0 success, 2 usage, 3 source, 4 resolution) unchanged.
  Date: 2026-07-19

- Decision: `SetteiOptions` changes shape (field `explainMode :: ExplainMode` becomes
  `diagnosticMode :: DiagnosticMode`); this breaking change is accepted without a
  compatibility shim.
  Rationale: Same pre-release, no-external-consumers argument as the `ExplainMode`
  replacement; a shim would only preserve an API nobody depends on.
  Date: 2026-07-19

- Decision: Split the diagnostic interpretation helper into a source-free half
  (`schemaDiagnostic :: DiagnosticMode -> Schema -> Maybe Text`) and a post-resolution
  half (`resolutionDiagnostic`), rather than one function taking both a `Schema` and a
  `ResolveResult`.
  Rationale: ADR 0007 requires that static description load no sources. A single
  combined helper would force callers to resolve (and therefore load files and read the
  environment) before they could answer `--describe-config`, silently violating that
  contract. Two functions make the "describe short-circuits before loading" pattern the
  path of least resistance. The exact type carried by the post-resolution half must be
  reconciled with what EP-12 shipped (see Context and Orientation).
  Date: 2026-07-19

- Decision: The service keeps its single-file `FORMAT:PATH` option (an optional, single
  tagged input via settei-formats' single-input parser), while the CLI keeps its ordered
  list of tagged inputs (the repeatable list parser). Neither example switches to the
  untagged `configPathOptions`.
  Rationale: The examples' explicit format tags are a documented design point (no format
  sniffing, per ADR 0007 and the guides); the Kubernetes service deliberately models
  exactly one mounted file while the CLI models ordered layering. Both shapes are what
  settei-formats (EP-16) exists to serve.
  Date: 2026-07-19

- Decision: Both examples adopt the shared `DiagnosticMode`, which gives the service
  describe modes it previously lacked (its old `ServiceDiagnosticMode` had no
  describe constructor).
  Rationale: A Kubernetes service benefits from `--describe-config` (source-free schema
  output for operators and CI) at least as much as a CLI does, and diverging from the
  shared type solely to preserve the old four-mode surface would keep a hand-rolled
  parser alive — the opposite of this plan's purpose. Service tests gain cases for the
  new modes.
  Date: 2026-07-19

- Decision: This plan is written before its hard dependencies (EP-15 through EP-19) are
  implemented; all names it uses for their deliverables are the MasterPlan's stated
  intent plus this plan's recommendations, and Milestone 1 begins with a mandatory
  reconciliation step against the completed sibling plans and shipped source.
  Rationale: The MasterPlan fixes the concepts (decoder kit, settei-formats package,
  `render<Adapter>ErrorText` contract, validated bindings, declaration sugar) but the
  sibling ExecPlans are still skeletons today, so exact identifiers may differ when they
  ship. Freezing guesses as requirements would make this plan wrong; freezing the
  reconciliation procedure makes it robust.
  Date: 2026-07-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Settei is a multi-package Haskell workspace built with Cabal inside a Nix dev shell. The
packages live in top-level sibling directories: `settei` (the core declaration and
resolution engine), `settei-env`, `settei-optparse-applicative`, `settei-yaml`,
`settei-kdl`, `settei-dhall` (source adapters), and — after EP-16 — `settei-formats`
(tagged multi-format loading). Three internal, unpublished packages live under
`examples/`: `examples/settei-cli` (a layered command-line application),
`examples/settei-service` (a Kubernetes-shaped service), and `examples/settei-conformance`
(cross-format conformance tests). Per
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md, these
examples are the public-API conformance boundary: they are the evidence that the public
modules compose into realistic applications, and this plan is the deliberate final pass
over them.

Core vocabulary, defined here so no prior reading is required. A *declaration*
(`Config a`, from `settei`) describes typed settings applicatively; a *source* is an
ordered bundle of raw values (files, environment, command line) with provenance; *resolve*
(`Settei.Resolve.resolve`) interprets a declaration against sources ordered lowest to
highest precedence. Today `resolve` returns
`Either (NonEmpty ConfigError) (ResolveResult a)` where `ResolveResult` (in
settei/src/Settei/Resolve.hs) has fields `value :: a`, `report :: ResolutionReport`, and
`warnings :: [ConfigWarning]`. `ResolveOptions` carries an `UnknownKeyPolicy` —
`WarnUnknownKeys` (default; unknown source keys become warnings) or `RejectUnknownKeys`
(they become hard errors). Renderers live in settei/src/Settei/Render.hs:
`renderErrorsText`, `renderResolutionText`, `renderResolutionJson`,
`renderWarningsText :: [ConfigWarning] -> Text`, `renderSchemaText`, and
`renderSchemaJson :: Schema -> Text`. A `Schema` is the source-free description obtained
with `describe :: Config a -> Schema`.

Two constraints from other plans shape this one:

*Cross-MasterPlan constraint.* The correctness MasterPlan
(docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md) lands before
this initiative, and its EP-12
(docs/plans/12-report-resolution-provenance-and-warnings-on-failure.md) owns a change to
the shape returned by `resolve` — making the report and warnings available on failure,
not only on success. This plan starts from the post-correctness tree. Before writing any
code, read settei/src/Settei/Resolve.hs *as it exists then* and adjust the signatures in
Milestone 1 (particularly `resolutionDiagnostic`) and the example failure paths to the
shipped shape. The type names used in this plan reflect today's tree and are the
fallback if EP-12 kept the same names.

*Sibling-plan reconciliation.* This plan hard-depends on EP-15 through EP-19 and
soft-depends on EP-20 (all under docs/plans/, numbers 15–20). At the time this plan was
authored those documents were unfilled skeletons, so every identifier this plan uses for
their deliverables is provisional. Milestone 1 step one is: read each completed sibling
plan and the shipped modules, and rewrite the provisional names in this plan (updating
this section and the Interfaces section, with a revision note) to the real ones. The
concepts are fixed by the MasterPlan even though the spellings are not:

- EP-15 (decoder kit): `Decoder` gains a `Functor` instance and combinators in
  `settei`'s `Settei.Value` surface, so a newtype decoder is written
  `SecretText <$> textDecoder` and list decoding comes from a combinator (something like
  `listDecoder :: Decoder a -> Decoder [a]`) instead of a hand-written case expression.
- EP-16 (settei-formats): a package exposing a tagged-input type (a format tag — YAML,
  KDL, or Dhall — paired with a `FilePath`), optparse-applicative parsers for it (this
  plan calls them `configInputOption` for one optional input and `configInputOptions`
  for a repeatable ordered list, both reading `FORMAT:PATH` spellings `yaml:`, `kdl:`,
  `dhall:`), and a loader that dispatches to the right adapter and returns a `Source`
  or a rendered error.
- EP-17 (renderers): every adapter error type (`YamlSourceError`, `KdlSourceError`,
  `DhallSourceError`, `EnvError`) has a text renderer in the
  `render<Adapter>ErrorText` naming style, secret-safe and operator-readable, matching
  the tone of settei/src/Settei/Render.hs.
- EP-18 (validated bindings): environment bindings are validated once at construction
  into an opaque validated collection (this plan calls it `Bindings`), making
  `envSource`-style assembly total — no unreachable `Left` branch in application code.
- EP-19 (sugar): declaration helpers this plan calls `whenEq` (a conditional-requirement
  helper replacing raw `Control.Selective.select` encodings, as used by the service's
  Production-only password) and `publicShowSetting` (a public setting whose renderer is
  derived from `Show`, replacing `publicSettingWithRenderer key desc dec (Text.pack . show)`).
- EP-20 (surface hygiene, soft dep): final authority on exposed-module lists and the PVP
  wording in docs/compatibility.md. If EP-20 is complete, reconcile Milestone 3's
  compatibility edits with its wording; if not, write the settei-formats and new-module
  additions in the matrix's current style and leave EP-20 to restate policy.

The file this plan changes most is
settei-optparse-applicative/src/Settei/Optparse.hs. Today it exports `CliOverride` (an
opaque `--set KEY=VALUE` override whose `spelling` never contains the value, so origins
stay secret-safe), `cliOverride`/`cliOverrideKey`/`cliOverrideValue`/`cliOverrideSpelling`,
`overrideOptions` (+`With`), `cliSources` (turns overrides into ordered `Source`
fragments with occurrence provenance), `namedOption` (one named flag as a source),
`configPathOptions` (+`With`, untagged `--config PATH` occurrences),
`ExplainMode = NoExplain | ExplainText | ExplainJson` with `explainModeOptions`
(+`With`), and `SetteiOptions { configPaths :: [FilePath], overrides :: [CliOverride],
explainMode :: ExplainMode }` assembled by `setteiOptions`, which groups flags under
"Configuration" and "Diagnostics" headings using optparse-applicative 0.19's
`Options.parserOptionGroup`. Its tests live in
settei-optparse-applicative/test/Settei/OptparseTest.hs (driver test/Main.hs).

The evidence that motivated this plan sits in the two example modules, each read in
full before starting. examples/settei-cli/src/Settei/Example/Cli.hs hand-rolls: a
five-mode `DiagnosticMode` (`RunExample | DescribeConfiguration |
ExplainConfigurationText | ExplainConfigurationJson | CheckConfiguration`) with its own
flag parser; a `ConfigFormat`/`ConfigInput` pair with a `configInputReader` `ReadM`
parsing `FORMAT:PATH`; a three-way `loadConfigInput` dispatcher whose every branch
formats adapter errors with `Text.pack . show`; an `envSource` call whose `Left` branch
also does `Text.pack (show problems)`; and a hand-written `secretTextDecoder` case
expression. examples/settei-service/src/Settei/Example/Service.hs duplicates the
`ReadM` reader and three-way dispatcher (with Kubernetes mounted-file annotations), has
a four-mode `ServiceDiagnosticMode` (no describe mode), encodes the Production-only
password with raw `Control.Selective.select`, defines a `publicInteger` helper around
`Text.pack . show`, hand-rolls `textListDecoder`, and — worst — handles `envSource`
problems with `error (show problems)`. In both applications, `renderSuccess` /
`renderServiceSuccess` read only `value` and `report` from the `ResolveResult`; the
`warnings` field is never printed anywhere. Both share the exit-code contract: 0
success, 2 usage (`usageExitCode`, wired via `Options.failureCode`), 3 source IO/parse
failure (`sourceExitCode`), 4 typed resolution failure (`resolutionExitCode`). The
executables (examples/settei-cli/app/Main.hs, examples/settei-service/app/Main.hs)
print a captured run's `standardOutput` to stdout and `standardError` to stderr, so
warning output slots into the existing `CliRun`/`ServiceRun` records without touching
`main`.

Tests that must keep passing (with updated expectations): examples/settei-cli/test/Main.hs
and examples/settei-cli/test/Settei/Example/CliTest.hs (cases: precedence ordering,
describe-without-sources, help grouping, distinct source/resolution exit codes, JSON
redaction, usage exit code) with fixture
examples/settei-cli/test/fixtures/application.yaml; examples/settei-service/test/Main.hs
and examples/settei-service/test/Settei/Example/ServiceTest.hs (cases: development
defaults without password, production requires annotated password, mounted ConfigMap
provenance, safe startup summary) with fixture
examples/settei-service/test/fixtures/application.yaml; and the conformance package
under examples/settei-conformance, which consumes `serviceConformanceConfig` — keep that
export and its `(ServiceConfig, [Text])` shape stable.

The documentation surface swept in Milestone 3: docs/guides/README.md (index table),
getting-started.md, environment-and-cli.md, yaml.md, kdl.md, dhall.md,
cli-application.md, kubernetes-service.md; the top-level README.md (sections "Declare
configuration once", "Assemble ordered sources", "Explain derived defaults", "Guides and
examples"); docs/compatibility.md (its "Public modules" section lists the supported
adoption surface — today core modules plus `Settei.Env`, `Settei.Optparse`,
`Settei.Yaml`, `Settei.Kdl`, `Settei.Dhall`, with no settei-formats); and each touched
package's CHANGELOG.md (entry style: a `## <version> — <date>` heading with bullet
lines, as in settei-optparse-applicative/CHANGELOG.md).

Relevant ADRs consulted: docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md
(this plan's authority: examples are conformance evidence; static description loads no
sources; distinct usage/source/resolution exit codes; no password-bearing rendering),
docs/adr/0001-haskell-project-conventions.md (lens/`Settei.Prelude` conventions the new
code follows; EP-20 may amend it), docs/adr/0002-inspectable-configuration-algebra.md (the
declaration algebra is Applicative+Selective; nothing here may introduce a Monad),
docs/adr/0003-resolution-provenance-and-default-semantics.md (redaction and renderer
rules all diagnostic output must preserve: secret values never appear in explanations,
warnings, or schema output), and docs/adr/0004/0005/0006 (YAML, KDL, Dhall input
semantics; the null-handling documented in Milestone 3 must agree with them — note that
`RawValue` in settei/src/Settei/Value.hs has an explicit `RawNull` constructor, which is
what makes "null is present, not absent" true). During Milestone 4 also read the ADRs
created by EP-16/EP-17/EP-18 and the amendments those plans made, whatever numbers they
received.


## Plan of Work

The work is four milestones, strictly ordered. Milestone 1 changes the reusable options
library; Milestone 2 rewrites both reference applications on top of it plus the EP-15..19
APIs; Milestone 3 sweeps every document; Milestone 4 validates end-to-end and closes the
MasterPlan. Each milestone ends with the whole workspace compiling and its tests green,
so the plan can pause safely at any milestone boundary.


### Milestone 1 — extend the reusable CLI options in Settei.Optparse

Scope: settei-optparse-applicative only. At the end, `Settei.Optparse` offers the full
diagnostic mode set both examples need, plus helpers that interpret a mode, and its test
suite covers them; `ExplainMode` no longer exists. The examples still compile at this
point only if their hand-rolled types don't reference the removed names — they don't
(they import `Settei.Optparse` for `CliOverride`, `overrideOptions`, and `cliSources`
only), so the workspace stays green.

Begin with reconciliation: read docs/plans/15- through 20- as completed documents, read
settei/src/Settei/Resolve.hs and settei/src/Settei/Value.hs, the settei-formats source,
the four adapter error modules, settei-env/src/Settei/Env.hs, and the EP-19 additions in
settei's declaration modules. Update this plan's provisional names to the shipped ones
(revision note at the bottom). Do not skip this; every subsequent step depends on it.

Then edit settei-optparse-applicative/src/Settei/Optparse.hs. Delete `ExplainMode`,
`explainModeOptions`, and `explainModeOptionsWith`. Add the new sum type — the
constructor names below are the plan's chosen spellings:

```haskell
-- | Which configuration diagnostic, if any, an application should perform.
data DiagnosticMode
  = NoDiagnostic
  | ExplainText
  | ExplainJson
  | CheckConfig
  | DescribeConfigText
  | DescribeConfigJson
  deriving stock (Generic, Eq, Ord, Show)
```

Add `diagnosticModeOptions :: Parser DiagnosticMode` parsing five mutually exclusive
flags via `Options.flag'` chained with `<|>`, defaulting to `pure NoDiagnostic`:
`--explain-config` (ExplainText, help "Explain the resolved configuration as text"),
`--explain-config-json` (ExplainJson), `--check-config` (CheckConfig, help "Validate
configuration and exit"), `--describe-config` (DescribeConfigText, help "Print the
static configuration schema"), `--describe-config-json` (DescribeConfigJson, help
"Print the static configuration schema as JSON"). Mutual exclusion falls out of
`flag'`+`<|>`: passing two diagnostic flags is a usage error. There is deliberately no
`diagnosticModeOptionsWith` (see Decision Log). Change `SetteiOptions`'s `explainMode`
field to `diagnosticMode :: !DiagnosticMode`, update the internal `DiagnosticOptions`
record and `setteiOptions` assembly accordingly, keeping the "Diagnostics"
`parserOptionGroup` so `--help` groups the five flags under one heading and keeping
"Configuration" for paths and overrides.

Add the two interpretation helpers to the same module (they need only `settei` core
imports, which the package already depends on):

```haskell
-- | Render the source-free diagnostic, if the mode is one that must not load sources.
schemaDiagnostic :: DiagnosticMode -> Schema -> Maybe Text

-- | Render the post-resolution diagnostic, if the mode has one.
resolutionDiagnostic :: DiagnosticMode -> ResolveResult a -> Maybe Text
```

`schemaDiagnostic` returns `Just (renderSchemaText schema)` for `DescribeConfigText`,
`Just (renderSchemaJson schema <> "\n")` for `DescribeConfigJson` (match the existing
convention that JSON renderers get a trailing newline appended, as the examples do for
`renderResolutionJson`), and `Nothing` otherwise. `resolutionDiagnostic` returns
`Just (renderResolutionText (result ^. #report))` for `ExplainText`,
`Just (renderResolutionJson (result ^. #report) <> "\n")` for `ExplainJson`,
`Just "configuration valid\n"` for `CheckConfig`, and `Nothing` for `NoDiagnostic` and
the describe modes (the application should have short-circuited on `schemaDiagnostic`
before resolving). The intended calling pattern, which the guides will show:
`case schemaDiagnostic mode (describe config) of Just out -> print it and exit 0;
Nothing -> load sources, resolve, then case resolutionDiagnostic mode result of ...`.
Reconcile `resolutionDiagnostic`'s argument type with the post-EP-12 shape by reading
settei/src/Settei/Resolve.hs at implementation time: if EP-12 replaced
`ResolveResult`/the `Either` failure with a richer type that carries the report and
warnings on failure too, take whatever type carries the success report, and consider an
additional failure-side helper only if the examples need one to preserve their rendered
failure output. Record the reconciled signatures here.

Update settei-optparse-applicative/test/Settei/OptparseTest.hs: replace the
`ExplainMode` cases with cases asserting each flag parses to its constructor, no flag
defaults to `NoDiagnostic`, two diagnostic flags together fail to parse, `--help` output
groups the five flags under "Diagnostics", and `schemaDiagnostic`/`resolutionDiagnostic`
return the expected renderer outputs (and `Nothing` where specified). Update
settei-optparse-applicative/CHANGELOG.md with an entry recording the breaking
replacement and the new helpers.

Acceptance: from the repository root,
`nix develop -c cabal test settei-optparse-applicative --test-show-details=direct`
passes, and `nix develop -c cabal build all` still succeeds (examples untouched but
recompiled against the changed package).


### Milestone 2 — rewrite both reference applications as canonical adopter templates

Scope: examples/settei-cli and examples/settei-service (sources, cabal files, tests),
leaving examples/settei-conformance passing unchanged. At the end, the examples contain
no hand-rolled format readers, no three-way adapter dispatchers, no `Show`-formatted
errors, no raw `select`, no hand-written decoder case expressions that the kit covers,
and they print resolver warnings — while preserving the exit-code contract and the
module exports the tests and conformance package rely on.

Rewrite examples/settei-cli/src/Settei/Example/Cli.hs as follows. Delete the local
`ConfigFormat`, `ConfigInput`, `configInputReader`, and `loadConfigInput`; import the
tagged-input type, `configInputOptions` (repeatable ordered list), and the loader from
settei-formats, re-exporting from the example module whatever the existing tests and
executable need (keep exported accessors equivalent to `configInputFormat` /
`configInputPath` or update the tests to the settei-formats accessors — prefer updating
the tests, since the example should demonstrate the public API, not wrap it). Delete
the local `DiagnosticMode` and its parser; use `Settei.Optparse.DiagnosticMode` and
`diagnosticModeOptions` (the old `RunExample` constructor's role is played by
`NoDiagnostic`). `CliOptions` keeps its three fields (tagged inputs, overrides,
diagnostic mode) — it cannot use `SetteiOptions` wholesale because its inputs are
tagged, not plain paths; say so in a comment, since adopters will ask. In
`runCliWithSnapshot`, short-circuit on `schemaDiagnostic` before loading anything
(preserving ADR 0007's "static description loads no sources", which the existing
"describe works without loading sources" test asserts), then resolve and use
`resolutionDiagnostic`; the `NoDiagnostic` fallback renders the existing example-action
output. Replace the `envSource` `Left` branch by constructing the validated EP-18
`Bindings` once at the top level, making assembly total. Replace `secretTextDecoder`
with `SecretText <$> textDecoder`. Route all source-loading failures through the
settei-formats loader's rendered errors (which internally use the EP-17 renderers) so
no `Text.pack . show` remains, still exiting with `sourceExitCode` (3). Finally, print
warnings: after successful resolution, when `result ^. #warnings` is non-empty, put
`renderWarningsText (result ^. #warnings)` on `standardError` while `standardOutput`
and exit code 0 are unchanged — `successfulRun` gains the stderr text as a parameter.

Rewrite examples/settei-service/src/Settei/Example/Service.hs symmetrically: delete
`ServiceFileFormat`, `ServiceInput`, `serviceInputReader`, `loadServiceInput`, and
`ServiceDiagnosticMode`; use settei-formats' single optional tagged input
(`configInputOption` under `Applicative.optional` semantics) and the shared
`DiagnosticMode`. Keep the Kubernetes mounted-file annotation: the loader must still
attach `kubernetesRef ConfigMapObject Nothing "settei-example-service" (Just
"application.yaml")` provenance — use whatever annotation hook EP-16 shipped for this
(it exists because the mounted-file story is a MasterPlan integration point); if EP-16
shipped none, keep a thin local wrapper over the loader that applies
`fromKubernetesMountedFile`-style options, and record that gap in Surprises &
Discoveries for EP-16 follow-up. Replace `error (show problems)` in
`resolveServiceSources` with validated `Bindings` construction (this deletes the
function's only partial branch; keep its export and
`Either (NonEmpty ConfigError) (ResolveResult ServiceConfig)` shape for the conformance
package, reconciled with EP-12). Replace `productionPassword`'s raw `select` with
EP-19's `whenEq`-style helper; replace `publicInteger` with `publicShowSetting` (or the
shipped spelling); replace `textListDecoder`/`textElement` with the kit's list
decoder over `textDecoder`; replace `secretTextDecoder` with `SecretText <$>
textDecoder`. Render warnings to stderr on success exactly as the CLI does. The
service gains describe modes via the shared type; wire them through the same
`schemaDiagnostic` short-circuit against `describe serviceConfig`.

Update both cabal files (examples/settei-cli/settei-example-cli.cabal,
examples/settei-service/settei-example-service.cabal): add `settei-formats`; remove
direct `settei-yaml`/`settei-kdl`/`settei-dhall` dependencies if nothing else uses them
after the dispatchers are gone (the service still needs whatever package hosts the
Kubernetes annotation helpers — check imports before cutting).

Update tests. examples/settei-cli/test/Settei/Example/CliTest.hs: adjust constructor
names (`RunExample` → `NoDiagnostic` etc.) and any `ConfigInput` construction to the
settei-formats API; the help-grouping case's expected "Diagnostics" listing gains
`--describe-config-json`; add a case asserting a successful resolution with an unknown
key in a fixture prints the warning on stderr and still exits 0; add a
`--describe-config-json` case asserting `renderSchemaJson` output and that no sources
are read (mirror the existing describe test's technique). The "source and resolution
failures use distinct exit codes" case's expected stderr text changes from `Show`
output to the rendered adapter error — update the expectation to the renderer's text.
examples/settei-service/test/Settei/Example/ServiceTest.hs: same constructor renames,
plus new cases for the service's describe modes and warning rendering. Add or extend
fixtures under both test/fixtures/ directories as needed (for the warning case, a YAML
fixture with one undeclared key). Run the conformance suite unchanged; if it fails,
the example rewrite broke an exported shape — fix the example, not the conformance
test.

Then assert the boilerplate is really gone, from the repository root:

```bash
grep -rn "Text.pack . show\|Text.pack (show\|error (show" examples/ --include='*.hs'
```

Expected output: no matches in examples/settei-cli/src or examples/settei-service/src.
(`Text.pack (show occurrence)` style number formatting may legitimately remain in
settei-optparse-applicative; the assertion is scoped to examples/. If a match remains
under examples/, it is unfinished work, with one allowed exception: the `validKey`
helpers' `either (error . show) id` on literal keys, which is a startup-time assertion
on constants, not error rendering — keep or replace it with EP-19's key sugar if one
shipped, and record which.)

Acceptance: `nix develop -c cabal test all --test-show-details=direct` passes; the grep
transcript above is captured in this plan; running the CLI example with an
unknown-keyed config prints the warning to stderr and exits 0.


### Milestone 3 — documentation sweep

Scope: docs/guides/ (all eight files), README.md, docs/compatibility.md, and the
changelogs. At the end, no guide teaches a pre-initiative API, and a reader following
any guide writes code identical in style to the rewritten examples.

docs/guides/getting-started.md: switch decoder examples to the kit (`Functor` mapping,
list decoding, parser-backed decoding as EP-15 shipped them); use EP-19 sugar where the
guide declares conditionals or rendered defaults; extend "Use the typed result and
diagnostics" with a short warnings subsection — what `warnings` contains, that
applications should render non-empty warnings with `renderWarningsText` to stderr, and
that `RejectUnknownKeys` upgrades them to errors. Add a new subsection under the source
ordering material titled exactly "Null is not unset", containing in substance: an
explicit null in any source is a *present* value (`RawNull` in the core value model),
not an absence; a higher-precedence source therefore cannot un-set a lower-precedence
value by writing null — the null wins the precedence contest and is then handed to the
setting's decoder, which for most decoders fails with a type error at that key; to make
a setting absent, omit the key from the higher source. Include this example:

```yaml
# base.yaml (lower precedence)
service:
  timeout: 30

# override.yaml (higher precedence)
service:
  timeout: null
```

and state the observed behavior: resolution fails with a decode error at
`service.timeout` pointing at override.yaml — it does not fall back to 30. (Verify the
exact rendered error text by running it once and paste the real output into the guide.)
This documents a 2026-07-19 review finding.

docs/guides/environment-and-cli.md: the "Bind environment variables explicitly" section
teaches validated `Bindings` construction (validation errors surface once, at
construction, with the EP-17 `EnvError` renderer); "Parse reusable command-line
options" and "Render diagnostics" teach `DiagnosticMode`, `diagnosticModeOptions`, the
five flags, and the `schemaDiagnostic`/`resolutionDiagnostic` calling pattern.

docs/guides/yaml.md ("Render YAML errors"), kdl.md ("Render KDL errors and
locations"), dhall.md ("Render Dhall errors"): replace any `Show`-based error-handling
snippet with the EP-17 renderer for that adapter, keeping each guide's location/
provenance material intact.

docs/guides/cli-application.md and docs/guides/kubernetes-service.md mirror the
examples, so rewrite their code excerpts from the post-Milestone-2 modules ("Parse
configuration options", "Load each file explicitly" — now the settei-formats loader —
"Add diagnostics that match user intent", "Distinguish exit behavior" in the CLI
guide; the corresponding load/resolve/diagnostics sections in the service guide). The
kubernetes-service guide additionally gets a readiness/initContainer recipe: a short
subsection showing an initContainer (or startup probe command) running the service
binary with `--check-config` against the mounted file, so a bad ConfigMap fails the
rollout before traffic arrives, with a YAML Deployment fragment invoking
`--check-config` and an explanation of exit codes 0/3/4 in that context; and a
paragraph recommending services consider `RejectUnknownKeys` so typo'd keys fail fast
instead of warning. docs/guides/README.md: add the settei-formats guide row if EP-16
added a guide file and it is missing from the index; refresh the cli/service row
descriptions if their capabilities changed.

README.md: update the feature snippets where the API changed (decoder declarations,
source assembly, diagnostics flags) so they compile against the final API; mention
warnings rendering and check/describe flags wherever the README currently advertises
diagnostics. docs/compatibility.md: in "Public modules", add settei-formats' module(s)
and any other new public modules EP-15..19 introduced; if EP-20 is complete, match its
PVP wording exactly and only append what it missed; also add settei-formats to the
"Libraries and adapters" and "Input contracts" tables as applicable.

Changelogs: add an entry to every package touched by this plan
(settei-optparse-applicative certainly; settei-formats and others if this plan changed
them). Then read the EP-15..EP-19 entries across all changelogs in one sitting and edit
for coherence: consistent tense, consistent naming of the new APIs, no entry describing
an API a later plan renamed.

Acceptance: every fenced Haskell snippet in the swept documents type-checks against the
final API when transplanted into a scratch module (spot-check the nontrivial ones by
compiling them in a scratch file under the scratchpad directory, not committed);
`grep -rn "ExplainMode\|explainModeOptions" docs/ README.md` returns only historical
plan/masterplan documents, never guides or README.


### Milestone 4 — final validation and MasterPlan closure

Scope: no new features; prove everything works, then close the initiative per the
MasterPlan protocol. This milestone may edit the MasterPlan and ADRs — that is part of
its scope.

Run the full suite from a clean state and capture the tail of the transcript in this
plan. Then produce smoke transcripts of the example CLI (Concrete Steps lists the exact
commands): `--describe-config` (schema text, exit 0, no fixture needed),
`--describe-config-json` (JSON schema), `--check-config` with a valid fixture
(`configuration valid`, exit 0), `--check-config` with an unknown extra key (warning on
stderr, exit 0), and a resolution failure (exit 4 with rendered errors — post-EP-12,
confirm whether the failure output also carries report/warnings and show it). Paste the
real outputs into this plan's Validation section, replacing the expected sketches.

Close the MasterPlan: in
docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md, set the
EP-21 registry row Status to Complete, check the two EP-21 Progress items, and write
the MasterPlan's Outcomes & Retrospective (this is the final child plan, so the
initiative-level retrospective happens here: compare the Vision & Scope bullets against
reality, one by one).

Perform the ADR distillation pass: re-read this plan's Decision Log and Surprises &
Discoveries; read the ADRs created or amended by EP-16, EP-17, and EP-18 (expected in
the docs/adr/0008+ range) and the EP-20 amendments to docs/adr/0001, plus 0002/0003 —
verify they are mutually coherent and still true after this plan's changes (in
particular: does an ADR record the warnings-are-advisory / RejectUnknownKeys-for-strict
policy and the DiagnosticMode surface? If no existing ADR covers the diagnostic-mode
and warning-rendering contract, promote it — either as an amendment to
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md,
which already documents the exit-code discipline, or as a new ADR). Leave task-local
notes here. Finally fill this plan's Outcomes & Retrospective and mark every Progress
item.

Acceptance: suite green from clean; transcripts captured; MasterPlan closed; ADRs
coherent; this plan's living sections complete.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/settei` unless
stated otherwise. The toolchain comes from the Nix dev shell — prefix cabal commands
with `nix develop -c` (the host GHC cannot build this workspace; see
docs/compatibility.md).

Every commit in this plan uses the Conventional Commits format (`feat:`, `fix:`,
`docs:`, `test:`, `chore:`, with an optional scope and `!` for breaking changes) and
carries these three trailers, exactly:

```text
MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

Commit directly to the current branch (no feature branch unless the user asks).

Step 1 (reconciliation). Read docs/plans/15- through 20- and the shipped modules named
in Context and Orientation. Edit this plan file to replace provisional identifiers with
shipped ones; add a revision note at the bottom. Commit:

```text
docs(plans): reconcile EP-21 against shipped EP-15..EP-20 interfaces
```

Step 2 (Milestone 1 code). Edit settei-optparse-applicative/src/Settei/Optparse.hs,
test/Settei/OptparseTest.hs, and CHANGELOG.md as specified. Then:

```bash
nix develop -c cabal build settei-optparse-applicative
nix develop -c cabal test settei-optparse-applicative --test-show-details=direct
nix develop -c cabal build all
```

Expected: the test binary reports all cases passing, ending in a line like

```text
All N tests passed (0.02s)
```

Commit (note the breaking-change marker):

```text
feat(optparse)!: replace ExplainMode with a six-mode DiagnosticMode and diagnostic helpers
```

Step 3 (Milestone 2, CLI example). Rewrite examples/settei-cli/src/Settei/Example/Cli.hs,
its cabal file, tests, and fixtures. Build and test just it first:

```bash
nix develop -c cabal test settei-example-cli --test-show-details=direct
```

Commit: `feat(examples/cli): adopt the ergonomics APIs and render resolver warnings`.

Step 4 (Milestone 2, service example). Same for examples/settei-service and the
conformance package check:

```bash
nix develop -c cabal test settei-example-service --test-show-details=direct
nix develop -c cabal test settei-conformance --test-show-details=direct
```

(If the conformance package's cabal target name differs, list targets with
`nix develop -c cabal build all --dry-run` and use the real name.) Commit:
`feat(examples/service): adopt the ergonomics APIs and render resolver warnings`.

Step 5 (Milestone 2 assertion). Run the boilerplate grep and paste its (empty for
examples/src) output into this plan:

```bash
grep -rn "Text.pack . show\|Text.pack (show\|error (show" examples/ --include='*.hs'
nix develop -c cabal test all --test-show-details=direct
```

Step 6 (Milestone 3). Edit the eight guides, README.md, docs/compatibility.md, and
changelogs as specified. Spot-check nontrivial snippets by compiling them in a scratch
module under the session scratchpad directory (do not commit scratch files). Verify:

```bash
grep -rn "ExplainMode\|explainModeOptions" docs/guides README.md
```

Expected output: no matches. Commit:
`docs(guides): teach the final ergonomics API and document null-is-not-unset`.

Step 7 (Milestone 4 validation). From a clean state:

```bash
nix develop -c cabal clean
nix develop -c cabal test all --test-show-details=direct
```

Then produce the smoke transcripts (fixture paths may differ if Step 3/4 added
fixtures; adjust):

```bash
nix develop -c cabal run settei-example-cli -- --describe-config
nix develop -c cabal run settei-example-cli -- --describe-config-json
nix develop -c cabal run settei-example-cli -- --check-config --config yaml:examples/settei-cli/test/fixtures/application.yaml
nix develop -c cabal run settei-example-cli -- --check-config --config yaml:examples/settei-cli/test/fixtures/unknown-key.yaml; echo "exit=$?"
nix develop -c cabal run settei-example-cli -- --config yaml:examples/settei-cli/test/fixtures/broken.yaml; echo "exit=$?"
```

Expected shapes (replace with real output when run): the first prints the schema text
listing every declared key with its description and sensitivity; the second prints one
JSON document; the third prints `configuration valid` and exits 0; the fourth prints
`configuration valid` on stdout, an unknown-key warning line on stderr, `exit=0`; the
fifth prints rendered resolution/source errors on stderr and a non-zero `exit=3` or
`exit=4` depending on the failure class exercised.

Step 8 (Milestone 4 closure). Edit the MasterPlan (registry row, Progress, Outcomes &
Retrospective), perform the ADR distillation pass, fill this plan's living sections.
Commit: `docs: close the ergonomics MasterPlan and distill EP-21 ADR context`.

After every stopping point, update this plan's Progress section in the same commit as
the work it describes.


## Validation and Acceptance

The change is accepted when all of the following observable behaviors hold.

Library behavior: in a GHCi session or test,
`Options.execParserPure` over `setteiOptions` maps `--explain-config`,
`--explain-config-json`, `--check-config`, `--describe-config`, and
`--describe-config-json` to the five non-default `DiagnosticMode` constructors; no flag
yields `NoDiagnostic`; two diagnostic flags together produce a parse failure (which the
examples surface as exit code 2 via `Options.failureCode`); `--help` output shows the
five flags under a "Diagnostics" heading. `schemaDiagnostic DescribeConfigText`
equals `renderSchemaText` of the same schema; `resolutionDiagnostic CheckConfig`
equals `Just "configuration valid\n"`. These are asserted by
settei-optparse-applicative/test and verified by
`nix develop -c cabal test settei-optparse-applicative --test-show-details=direct`
ending in `All N tests passed`.

Example behavior: `nix develop -c cabal run settei-example-cli -- --describe-config`
prints the schema and exits 0 without reading any file or environment variable (the
existing "describe works without loading sources" test guards this). A run whose
sources contain a key not present in the declaration prints, on stderr, the
`renderWarningsText` rendering of the unknown-key warning while stdout and the exit
code are exactly what they would be without the warning. Source failures exit 3 with a
renderer-formatted (not `Show`-formatted) message; resolution failures exit 4 with
`renderErrorsText` output; usage failures exit 2. The service example behaves
identically for its single mounted file and additionally still refuses to print any
password-bearing value in any mode (existing redaction tests guard this). The
boilerplate grep from Concrete Steps Step 5 finds no `Show`-based error formatting
under examples/*/src.

Documentation: `grep -rn "ExplainMode" docs/guides README.md` is empty;
docs/guides/getting-started.md contains a "Null is not unset" heading whose YAML
example matches the actually-observed failure output; docs/guides/kubernetes-service.md
contains the `--check-config` initContainer/readiness recipe and a `RejectUnknownKeys`
recommendation; docs/compatibility.md lists the settei-formats module(s) in its public
adoption surface.

Full-suite: `nix develop -c cabal test all --test-show-details=direct` from a clean
tree passes every package's suite. Transcripts proving the above are pasted into this
plan during Milestone 4.


## Idempotence and Recovery

Every step is an ordinary edit-build-test cycle on a git working tree, safe to repeat:
re-running any build, test, grep, or smoke command is side-effect free, and re-applying
an edit that is already present is a no-op. There are no migrations, no destructive
operations, and no generated files to drift.

Recovery between milestones: each milestone ends with the whole workspace green and
committed, so `git log` plus this plan's Progress section always identify the last good
state; to retry a broken step, `git diff` against the last commit and either fix
forward or `git checkout -- <file>` the affected files. Milestone 1 removes
`ExplainMode` before Milestone 2 rewrites the examples — this is safe because the
examples do not import the removed names (verified in Context and Orientation); if an
unexpected consumer of `ExplainMode` surfaces, the build break is immediate and local,
and the fix is to migrate that consumer in the same commit, not to restore the old
type. If Milestone 2 must pause with one example rewritten and the other not, the
workspace still builds (the examples are independent packages); record the split in
Progress. Documentation edits (Milestone 3) can be committed guide-by-guide. The
MasterPlan and ADR edits in Milestone 4 are plain text edits, revertible like any
other; make them only after the validation steps pass so a revert never orphans a
"Complete" status.


## Interfaces and Dependencies

This plan consumes, and must not redesign, the deliverables of the earlier plans; the
names below are provisional until Step 1's reconciliation (see Decision Log) and this
section must be updated with the shipped spellings.

From `settei` (core): `Config`, `describe`, `Schema`, `resolve`, `ResolveOptions`,
`defaultResolveOptions`, `UnknownKeyPolicy (WarnUnknownKeys | RejectUnknownKeys)`, the
post-EP-12 resolve result carrying `value`, `report`, and `warnings :: [ConfigWarning]`
(today `Settei.Resolve.ResolveResult`; reconcile), and the renderers in
`Settei.Render`: `renderErrorsText`, `renderResolutionText`, `renderResolutionJson`,
`renderWarningsText`, `renderSchemaText`, `renderSchemaJson`. From EP-15, the decoder
kit in the `Settei.Value` surface: the `Decoder` `Functor` instance, `textDecoder`,
and a list-decoding combinator. From EP-19: the conditional helper (provisionally
`whenEq`) replacing raw `select`, and the `Show`-renderer setting helper (provisionally
`publicShowSetting`).

From `settei-formats` (EP-16): the tagged-input type (format tag + `FilePath`), the
single-input parser (provisionally `configInputOption :: ... -> Parser ConfigInput`,
used under `optional` by the service), the repeatable parser (provisionally
`configInputOptions :: Parser [ConfigInput]`, used by the CLI), the loader
(`ConfigInput -> IO (Either <rendered-or-renderable error> Source)` in whatever exact
shape shipped), and its Kubernetes mounted-file annotation hook if one exists. From
EP-17: `render<Adapter>ErrorText` for `YamlSourceError`, `KdlSourceError`,
`DhallSourceError`, and `EnvError`. From `settei-env` post-EP-18: the validated
`Bindings` collection, its constructor that fails once at construction with renderable
problems, and the total source-assembly function replacing today's
`envSource :: Text -> [EnvBinding] -> EnvSnapshot -> Either ... Source`; plus the
unchanged `EnvSnapshot`/`envSnapshot`, `EnvName`, `binding`, `fromKubernetesObject`,
`kubernetesRef`.

At the end of Milestone 1, `settei-optparse-applicative`'s `Settei.Optparse` must
export: everything it exports today except `ExplainMode`, `explainModeOptions`, and
`explainModeOptionsWith`; plus

```haskell
data DiagnosticMode
  = NoDiagnostic | ExplainText | ExplainJson
  | CheckConfig | DescribeConfigText | DescribeConfigJson

diagnosticModeOptions :: Parser DiagnosticMode
schemaDiagnostic :: DiagnosticMode -> Schema -> Maybe Text
resolutionDiagnostic :: DiagnosticMode -> ResolveResult a -> Maybe Text  -- reconcile with EP-12

data SetteiOptions = SetteiOptions
  { configPaths :: ![FilePath],
    overrides :: ![CliOverride],
    diagnosticMode :: !DiagnosticMode
  }

setteiOptions :: Parser SetteiOptions
```

At the end of Milestone 2, `Settei.Example.Cli` must still export the run/exit/accessor
surface its tests and executable use (`cliParserInfo`, `runCliWithSnapshot`,
`resolveCliOptions`, `cliExitCode`, `cliStandardOutput`, `cliStandardError`,
`usageExitCode`, `sourceExitCode`, `resolutionExitCode`, `cliConfig`,
`environmentBindings` in its validated form), and `Settei.Example.Service` must still
export `serviceConfig`, `serviceConformanceConfig :: Config (ServiceConfig, [Text])`,
`resolveServiceSources`, `runServiceWithSnapshot`, `safeStartupSummary`, the exit
codes, and `environmentBindings` in its validated form — `serviceConformanceConfig`
and `resolveServiceSources` are load-bearing for examples/settei-conformance.

External libraries: optparse-applicative `>=0.19 && <0.20` (for
`Options.parserOptionGroup` and `Options.flag'`), tasty/tasty-hunit for tests, and the
already-pinned adapter dependencies — no new external dependency is introduced by this
plan. Toolchain: GHC 9.12.4 and Cabal via `nix develop`, per docs/compatibility.md.
