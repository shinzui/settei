---
id: 18
slug: make-environment-bindings-total-and-validated
title: "Make environment bindings total and validated"
kind: exec-plan
created_at: 2026-07-19T14:54:49Z
intention: "intention_01kxxdt2m8eysvxggq33jsmt2v"
master_plan: "docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md"
---

# Make environment bindings total and validated

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Settei's environment adapter (`settei-env`) maps explicitly listed environment variables
to hierarchical configuration keys. The list of mappings — the "bindings" — is static
program data written once by the application author. Today, however, the bindings are
validated every time a source is assembled: `envSource` returns
`Either (NonEmpty EnvError) Source`, so every caller must handle an error branch that can
never fire for a correct program. The evidence is in this repository's own reference
service, `examples/settei-service/src/Settei/Example/Service.hs`, whose
`resolveServiceSources` contains the line `Left problems -> error (show problems)` — even
the reference application cannot handle the "impossible" error gracefully. The reference
CLI threads the same impossibility through an `InputFailure` wrapper, and every caller
repeats the same source label, `"environment"`.

After this change, validation happens exactly once, when the binding list is constructed.
A new opaque type `Bindings` can only be obtained through the validating smart constructor
`bindings :: [EnvBinding] -> Either (NonEmpty EnvError) Bindings` (or through
`prefixedBindings`, which already validates). Because a `Bindings` value is
valid-by-construction, `envSource` becomes a total function —
`envSource :: Text -> Bindings -> EnvSnapshot -> Source` — and application resolution code
loses its dead error branches entirely. Two convenience functions,
`environmentSource` and `readEnvironmentSource`, supply the ubiquitous `"environment"`
label. This is a deliberate breaking change to the pre-release `settei-env` API
(the package has never been published to Hackage; the MasterPlan explicitly keeps Hackage
publication out of scope).

You can see it working by running the settei-env test suite (which gains
construction-validation cases and a totality enumeration) and the full workspace suite
(which proves both reference applications and the conformance suite now assemble
environment sources with no `Either` plumbing):

```bash
nix develop -c cabal test settei-env-tests --test-show-details=direct
nix develop -c cabal test all --test-show-details=direct
```


## Progress

- [x] (2026-07-19 20:47Z) Preflight: clean tree confirmed, baseline `cabal test all`
      green, and EP-17's `renderEnvErrorsText` confirmed in `settei-env`.
- [x] (2026-07-19 20:47Z) Milestone 1: `Settei.Env` reshaped — `Bindings`, `bindings`, `bindingsList`,
      total `envSource`/`readEnvSource`, `environmentSource`/`readEnvironmentSource`,
      `prefixedBindings` returning `Bindings`, unified validation, sentinel haddock updated,
      export list updated.
- [x] (2026-07-19 20:47Z) Milestone 1: `settei-env/test/Settei/EnvTest.hs` rewritten — per-constructor
      construction-validation cases, bounded-exhaustive totality enumeration, snapshot
      behavior tests adapted, prefixed-path tests.
- [x] (2026-07-19 20:47Z) Milestone 1 validation: `nix develop -c cabal test
      settei-env-tests --test-show-details=direct` passed all 16 tests.
- [x] (2026-07-19 20:48Z) Milestone 1 committed as `a8960a7` with required trailers.
- [x] (2026-07-19 20:50Z) Milestone 2: `examples/settei-service/src/Settei/Example/Service.hs` — `error (show
      problems)` branch deleted; `environmentBindings` is a validated `Bindings` CAF.
- [x] (2026-07-19 20:50Z) Milestone 2: `examples/settei-cli/src/Settei/Example/Cli.hs` — env `InputFailure`
      plumbing deleted; `environmentBindings` is a validated `Bindings` CAF.
- [x] (2026-07-19 20:50Z) Milestone 2: `examples/settei-conformance/test/Settei/Example/ConformanceTest.hs`
      `expectEnvSource` made total; example test suites force both `Bindings` CAFs.
- [x] (2026-07-19 20:50Z) Milestone 2: the additional optparse adapter test caller was
      migrated and `nix develop -c cabal test all --test-show-details=direct` passed.
- [x] (2026-07-19 20:51Z) Milestone 2 committed as `5f967b0` with required trailers.
- [x] (2026-07-19 20:53Z) Milestone 3: `docs/guides/environment-and-cli.md` rewritten for the new API.
- [x] (2026-07-19 20:53Z) Milestone 3: `docs/guides/kubernetes-service.md` env-binding section updated;
      `fromKubernetesObject` flow verified unchanged and stated as such.
- [x] (2026-07-19 20:53Z) Milestone 3: `README.md` source-assembly snippet updated;
      `docs/guides/cli-application.md` corrected to construct `Bindings` and use the total
      default-label functions.
- [x] (2026-07-19 20:53Z) Milestone 3: `settei-env/CHANGELOG.md` gains an Unreleased breaking-change entry.
- [x] (2026-07-19 20:53Z) Milestone 3: construction-time validation recorded in
      `docs/adr/0010-validate-environment-bindings-at-construction.md`.
- [x] (2026-07-19 20:55Z) Milestone 3: MasterPlan registry row EP-18 marked Complete and
      its Progress checkboxes updated; cross-plan caller discoveries recorded.
- [x] (2026-07-19 20:55Z) Milestone 3 validation: `nix develop -c cabal test all
      --test-show-details=direct` passed; maintained guides, README, examples, and current
      tests contain no old-signature `envSource` pattern.
- [x] (2026-07-19 20:56Z) Milestone 3 committed as `829c77b` with required trailers.
- [x] (2026-07-19 20:55Z) Living sections updated; ADR distillation completed in
      `docs/adr/0010-validate-environment-bindings-at-construction.md`; plan complete.


## Surprises & Discoveries

- Observation: EP-17 landed before this plan and exports `renderEnvErrorsText`, so the
  reference applications can use the operator-readable renderer immediately and need no
  `Show` fallback or `TODO(EP-17)` marker.
  Evidence: `rg -n "renderEnvErrorsText" settei-env/src/Settei/Env.hs` matched the export
  and definition before implementation began; the baseline full workspace suite passed.

- Observation: `settei-optparse-applicative/test/Settei/OptparseTest.hs` contained one
  additional old-signature `envSource` caller that the planning-time caller inventory
  omitted. The first post-example full build exposed it before the example suites ran.
  Evidence: GHC reported that `[EnvBinding]` no longer matched `Bindings` at
  `OptparseTest.hs:117`; the helper now validates with `bindings` and calls the total
  `environmentSource`.

- Observation: `fromKubernetesObject` remained exactly the single-binding annotation
  function described by the plan; collection validation wraps the annotated result and
  does not change Kubernetes metadata semantics.
  Evidence: `Settei.Env` still declares
  `fromKubernetesObject :: KubernetesRef -> EnvBinding -> EnvBinding`.

- Observation: the plan's literal final grep commands also search checked-in historical
  plan documents, including this plan's explanation of the removed signature, so they
  cannot be expected to return no matches repository-wide. Validation scoped the stale
  API scan to maintained guides, README, examples, adapter source, and current tests.
  Evidence: `rg` found no old `[EnvBinding]` source-builder signature or `envSource`
  `Either` handling in those maintained surfaces; matches outside that scope are planning
  history that intentionally describes the migration.


## Decision Log

- Decision: Make the change breaking. `envSource` and `readEnvSource` change their
  signatures in place instead of gaining parallel `envSource2`-style variants.
  Rationale: `settei-env` is pre-release and unpublished; the MasterPlan
  (docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md) targets a
  deliberate API surface before roughly 70 codebases adopt it. Carrying a deprecated
  partial variant into the first release would defeat the plan's purpose.
  Date: 2026-07-19

- Decision: Introduce an opaque `Bindings` collection with a private constructor, a
  validating smart constructor `bindings :: [EnvBinding] -> Either (NonEmpty EnvError)
  Bindings`, and an inspection function `bindingsList :: Bindings -> [EnvBinding]`.
  Validation is exactly today's `bindingErrors` checks: invalid names, duplicate names,
  duplicate target keys, and prefix-overlapping target keys.
  Rationale: making the only path to a `Bindings` value pass through validation is what
  lets `envSource` become total without weakening any check. `bindingsList` preserves
  inspectability (the caller can count, display, or re-derive names) without allowing
  construction.
  Date: 2026-07-19

- Decision: The recommended failure idiom for static binding lists is to resolve
  `bindings` ONCE — at startup, in a top-level CAF (a constant applicative form: a
  top-level Haskell definition with no parameters, evaluated at most once), or in a unit
  test — so a failure is a fail-fast programming-error report at program start, not a
  runtime condition threaded through resolution code. The guide shows asserting the CAF in
  a test so the suite, not production startup, is the first place a bad edit fails.
  Rationale: binding lists are static program data; an invalid list is a bug, and the
  honest place to surface a bug is one startup check plus a test, not an `Either` on
  every source assembly.
  Date: 2026-07-19

- Decision: Do NOT provide `unsafeBindings :: [EnvBinding] -> Bindings`.
  Rationale (rejected alternative recorded): a documented partial constructor for
  "statically known" lists would save one `either` per program at the cost of an
  unchecked hole in the module's central invariant. The `Either` forced once at startup
  is cheap and honest, and the CAF idiom above already reduces the ceremony to one line.
  If fleet feedback later demands it, adding a partial constructor is a non-breaking
  follow-up; removing one would be breaking.
  Date: 2026-07-19

- Decision: Provide the default source label via two convenience functions,
  `environmentSource :: Bindings -> EnvSnapshot -> Source` and
  `readEnvironmentSource :: Bindings -> IO Source`, both using the label `"environment"`.
  Keep the labeled `envSource`/`readEnvSource` for multi-snapshot tests and unusual
  deployments.
  Rationale: every observed caller (both examples, the conformance suite, the guides, the
  README) passes the literal `"environment"`. The names follow the module's existing
  style: `envSource` has an effectful sibling prefixed with `read` (`readEnvSource`), so
  the convenience pair keeps the same `read` prefix pattern, and the full word
  "environment" in the name is what signals that the label is fixed to that word.
  Rejected alternatives: (a) `defaultEnvSourceLabel :: Text` plus primed variants —
  saves nothing over a literal and adds a name adopters must discover; (b) making the
  label a field of `Bindings` — conflates what the bindings ARE with how one particular
  source stack labels them, and would force rebuilding `Bindings` per label in
  multi-snapshot tests.
  Date: 2026-07-19

- Decision: `prefixedBindings :: Text -> [Key] -> Either (NonEmpty EnvError) Bindings`
  returns the validated collection directly, and its validation is unified with
  `bindingErrors` so each check exists once. A duplicate generated name is reported as
  `PrefixedNameCollision` (which carries the colliding target keys), never as the less
  informative `DuplicateEnvironmentName`; the shared validator's duplicate-name results
  are filtered out on the prefixed path because every such duplicate is by construction a
  normalization collision.
  Rationale: the function already validated; returning `[EnvBinding]` forced a second,
  redundant validation at `envSource`. One validator means the two paths cannot drift.
  Date: 2026-07-19

- Decision: Keep the `insertRawValue` sentinel `error "validated environment keys cannot
  overlap"` but rewrite its comment to state that overlap-freedom is now proven by
  `Bindings` construction, making the branch unreachable-by-construction rather than
  unreachable-by-earlier-check-in-the-same-function.
  Rationale: the alternative — encoding non-overlap in types — is far beyond this plan's
  scope; a documented sentinel on a proven-dead branch is the conventional honest form.
  Date: 2026-07-19

- Decision: Prove totality with a bounded exhaustive enumeration inside tasty-hunit (all
  64 subsequences of a six-binding pool, checking that every subset that constructs
  successfully also builds and serves a source without raising), rather than adding a
  tasty-quickcheck dependency.
  Rationale (rejected alternative recorded): no package in this workspace depends on
  QuickCheck today, and EP-20 is about to audit the dependency surface; a deterministic
  exhaustive enumeration over a designed pool gives the same "any successfully
  constructed Bindings never errors during source building" evidence with zero new
  dependencies and no flaky generators.
  Date: 2026-07-19

- Decision: Reference applications construct `Bindings` in a top-level CAF with
  `either (error . <render>) id` and each example test suite forces the CAF, keeping
  diffs minimal per the MasterPlan (EP-21,
  docs/plans/21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md,
  owns the full example rewrite). Error rendering uses `renderEnvErrorsText` if EP-17
  (docs/plans/17-add-error-renderers-to-every-source-adapter.md, a soft dependency) has
  landed, otherwise `show` with a tracked `TODO(EP-17)` comment.
  Date: 2026-07-19

- Decision: Record the construction-time validation semantics in a SHORT NEW ADR rather
  than amending docs/adr/0003-resolution-provenance-and-default-semantics.md, per the
  MasterPlan's Integration Points which allow either. The implementer picks the next free
  ADR number at implementation time: EP-16
  (docs/plans/16-provide-shared-tagged-format-configuration-loading.md) plans to claim
  docs/adr/0008 and EP-17 may claim 0009, and all three plans may land in any order, so
  this plan must not hard-code a number.
  Rationale: ADR 0003 is core-resolver territory (precedence, provenance, defaults);
  binding validation is an adapter-construction concern, and a one-page dedicated ADR is
  easier for adopters to find than a paragraph inside a long core ADR.
  Date: 2026-07-19

- Decision: Record the breaking change in `settei-env/CHANGELOG.md` under a new
  `## Unreleased` heading rather than editing the 0.1.0.0 entry or picking a version now.
  Rationale: the package is unpublished; the release process (see the repository's
  release skill and docs/plans/14-revalidate-correctness-and-update-release-collateral.md
  precedent) assigns the version at release time.
  Date: 2026-07-19

- Decision: Fix the small `envSource` snippet in `README.md` in this plan even though
  EP-21 owns the full docs sweep.
  Rationale: after this plan the snippet would show a signature that no longer exists in
  the repository; a two-line fix now avoids publishing wrong front-page documentation
  between plans. The kubernetes-service and environment-and-cli guides are in this plan's
  explicit scope for the same reason.
  Date: 2026-07-19

- Decision: Update the typed binding example in `docs/guides/cli-application.md` during
  this plan rather than leaving it for EP-21.
  Rationale: the planning-time note expected only signature-neutral prose, but the guide
  actually declared `environmentBindings :: [EnvBinding]`. Leaving it unchanged would
  make a maintained guide fail against the new public API immediately after EP-18.
  Date: 2026-07-19


## Outcomes & Retrospective

EP-18 delivered the planned breaking ergonomics change. `Settei.Env` now exposes an
opaque, smart-constructed `Bindings` collection; both explicit and prefixed construction
share one validator; `envSource` and `readEnvSource` are total; and the conventional
`"environment"` label has pure and effectful convenience functions. The focused adapter
suite grew from 13 to 16 tests, including construction coverage for every `EnvError`
category and a deterministic enumeration of all 64 subsets in the designed binding pool.

Both reference applications validate their static binding lists once, render any
programming error through EP-17's stable renderer, and have no impossible source-assembly
branch. Their tests force the CAFs, the conformance helper is total, and the one additional
optparse adapter test caller discovered during the full build was migrated. The full
workspace suite passed after the code migration and again after documentation and ADR
work.

The maintained environment, Kubernetes, and CLI guides plus the README now teach the
construction-once API; `settei-env/CHANGELOG.md` records the breaking surface. Durable
semantics were distilled into
`docs/adr/0010-validate-environment-bindings-at-construction.md`. No implementation work
remains in this ExecPlan; EP-20 can audit the finalized surface and EP-21 can perform the
broader coherent examples-and-docs sweep against it.


## Context and Orientation

Settei is a multi-package Haskell workspace. Per
docs/adr/0001-haskell-project-conventions.md, every publishable package lives in a
same-named top-level directory: the core is `settei/`, and the environment adapter this
plan reshapes is `settei-env/` (one library module, `settei-env/src/Settei/Env.hs`, and
one test suite named `settei-env-tests` — verify in `settei-env/settei-env.cabal`, which
declares `test-suite settei-env-tests` with main module `test/Main.hs` and
`test/Settei/EnvTest.hs`). Non-published reference applications live under `examples/`:
`examples/settei-cli`, `examples/settei-service`, and the cross-cutting test package
`examples/settei-conformance`. Builds and tests run through the Nix dev shell:
`nix develop -c cabal test all --test-show-details=direct` from the repository root.

Vocabulary used throughout this plan, all defined in `settei-env/src/Settei/Env.hs`
today: an *environment binding* (`EnvBinding`, a record with strict fields `name ::
EnvName`, `key :: Key`, `annotations :: Map Text Text`) maps one environment-variable
name to one structural Settei key; an `EnvSnapshot` is a pure, injectable
`Map EnvName Text` view of the process environment so tests never mutate real
environment variables; a `Source` (from the core `settei` package) is a labeled raw-value
tree that the core resolver later consumes; `EnvError` is the validation vocabulary with
five constructors — `InvalidEnvironmentName`, `DuplicateEnvironmentName`,
`DuplicateTargetKey`, `ConflictingTargetKeys` (one bound key is a structural prefix of
another, e.g. `database` and `database.host`), and `PrefixedNameCollision` (two keys
normalize to the same generated variable name). A *total* function is one that returns a
result for every well-typed input, with no error-signaling wrapper and no exception on
the documented domain. A *smart constructor* is an ordinary function that is the only
exported way to build a type, so it can enforce invariants; the type's real data
constructor stays private to the module.

The current API (all in `settei-env/src/Settei/Env.hs`; line numbers as of this writing):
`binding :: EnvName -> Key -> EnvBinding` builds one unvalidated binding (~line 57).
`envSource :: Text -> [EnvBinding] -> EnvSnapshot -> Either (NonEmpty EnvError) Source`
(~line 91) first runs the private validator `bindingErrors :: [EnvBinding] -> [EnvError]`
(~line 170, which checks invalid names, duplicate names, duplicate keys, and calls
`overlapErrors :: [Key] -> [EnvError]` ~line 181 for prefix overlaps), and only then
folds present variables into a raw tree with the private
`insertRawValue :: Key -> RawValue -> RawValue -> RawValue` (~line 235), whose impossible
branch is `error "validated environment keys cannot overlap"` (~line 247).
`readEnvSource :: Text -> [EnvBinding] -> IO (Either (NonEmpty EnvError) Source)`
(~line 124) snapshots the real environment and delegates to `envSource`.
`prefixedBindings :: Text -> [Key] -> Either (NonEmpty EnvError) [EnvBinding]`
(~line 138) derives `PREFIX_KEY_SEGMENTS` names and performs its own copy of most of the
same validation (invalid names, duplicate keys, overlaps) plus collision detection —
duplicated logic this plan unifies. `fromKubernetesObject` and `annotateBinding` decorate
a single `EnvBinding` with trusted metadata and are untouched by this plan.

The callers that prove the ergonomics gap:
`examples/settei-service/src/Settei/Example/Service.hs` defines
`environmentBindings :: [EnvBinding]` (~line 241, seven bindings) and
`resolveServiceSources` (~lines 277–283) which contains
`Left problems -> error (show problems)`.
`examples/settei-cli/src/Settei/Example/Cli.hs` defines
`environmentBindings :: [EnvBinding]` (~line 191, five bindings) and `resolveCliOptions`
(~lines 215–233) which wraps the impossible failure as
`Left (InputFailure (Text.pack (show problems)))`.
`examples/settei-conformance/test/Settei/Example/ConformanceTest.hs` has
`expectEnvSource` (~lines 308–312) with its own `error (show problems)` branch.
`examples/settei-service/test/Settei/Example/ServiceTest.hs` calls
`resolveServiceSources` in five tests and needs no signature change.

Relevant ADRs consulted (repository-relative paths):
docs/adr/0001-haskell-project-conventions.md — GHC2024, the shared `common common`
stanza, strict fields, explicit deriving strategies, lens-based record access via
`Settei.Prelude` and local `Data.Generics.Labels ()` imports, postpositive `qualified`.
New code in this plan must follow all of it.
docs/adr/0003-resolution-provenance-and-default-semantics.md — adapters only parse input
into `RawValue`, construct `Source`, and attach honest origin metadata; annotations never
carry raw candidate values; `EnvError` values contain names and keys, never environment
values. This plan moves WHEN validation happens; it must not change WHAT is validated or
what errors may contain.
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md — the
examples are the conformance boundary, which is why Milestone 2 updates them, and why the
MasterPlan instructs keeping those diffs minimal so EP-21's rewrite is the single large
diff. No existing ADR covers construction-time validation of adapter inputs; Milestone 3
adds one.

Parent MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md,
registry row EP-18 (this plan; no hard dependencies; soft dependency EP-17 for `EnvError`
rendering only). Sibling plans referenced above are placeholders at the time of writing;
this plan does not depend on their contents.


## Plan of Work

The work is three milestones, each independently verifiable and each ending in one
commit.

Milestone 1 reshapes `settei-env` itself. At the end, `Settei.Env` exports an opaque
`Bindings` type, the smart constructor `bindings`, the inspector `bindingsList`, a total
`envSource :: Text -> Bindings -> EnvSnapshot -> Source`, a total
`readEnvSource :: Text -> Bindings -> IO Source`, the conveniences
`environmentSource`/`readEnvironmentSource`, and
`prefixedBindings :: Text -> [Key] -> Either (NonEmpty EnvError) Bindings`, with all
validation living in the single `bindingErrors` function. The package's own test suite is
rewritten to cover construction-time validation of every `EnvError` constructor, a
bounded-exhaustive totality check, and unchanged snapshot behavior. Acceptance:
`nix develop -c cabal test settei-env-tests --test-show-details=direct` passes. Note that
Milestone 1 alone leaves the examples uncompilable against the new API, which is why its
commit gate is the settei-env suite only; `cabal test all` becomes the gate again at the
end of Milestone 2. Do not push between commits 1 and 2.

Milestone 2 updates the three example call sites minimally. At the end,
`Service.hs` and `Cli.hs` each define `environmentBindings :: Bindings` as a top-level
CAF (validated once, failing fast with a rendered report if a programmer edits the list
into an invalid state), the dead `Either` branches are deleted, the conformance helper is
total, and each example test suite gains one test that forces the CAF so the suite — not
production startup — is the first place a bad binding list fails. Acceptance:
`nix develop -c cabal test all --test-show-details=direct` passes.

Milestone 3 aligns the written record. At the end,
`docs/guides/environment-and-cli.md` teaches the construct-once idiom,
`docs/guides/kubernetes-service.md`'s binding section compiles against the new API and
explicitly states that the `fromKubernetesObject` flow is unchanged, `README.md`'s
snippet is correct, `settei-env/CHANGELOG.md` records the breaking change under
Unreleased, a new short ADR records the durable decision, and the MasterPlan registry and
Progress are updated. Acceptance: full suite still green, and a manual grep shows no
stale references to the old signatures in docs.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/settei` unless
stated otherwise. Every commit in this plan uses Conventional Commits and MUST carry
these three trailers (exact text, one per line, at the end of the commit message body):

```text
MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/18-make-environment-bindings-total-and-validated.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

### Step 0: Preflight

Confirm a clean tree and a green baseline, and determine the EP-17 soft-dependency
status:

```bash
git status
nix develop -c cabal test all --test-show-details=direct
grep -rn "renderEnvErrorsText" settei-env/src/
```

If the last grep prints a match, EP-17 has landed and Milestone 2 uses
`renderEnvErrorsText` for the CAF failure message; if it prints nothing, use `show` and
add the `TODO(EP-17)` comments shown below. Record which case applied in Surprises &
Discoveries.

### Step 1: Reshape `settei-env/src/Settei/Env.hs`

Edit `settei-env/src/Settei/Env.hs`. First the export list: add `Bindings` (type only —
no `(..)`, the constructor stays private), `bindings`, `bindingsList`,
`environmentSource`, and `readEnvironmentSource` to the existing alphabetical-ish export
list, keeping every current export.

Add the opaque type and its two public functions near the other type definitions
(after `EnvError`). `EnvBinding` has no `Show` instance (by design — see
docs/adr/0003), so `Bindings` derives only `Eq`; deliberately do NOT derive `Generic`,
because `GHC.Generics.to` would let outside code rebuild the constructor and bypass
validation:

```haskell
-- | A collection of bindings proven valid at construction.
--
-- The constructor is private: 'bindings' and 'prefixedBindings' are the only ways to
-- obtain a value, so every 'Bindings' is free of invalid names, duplicate names,
-- duplicate target keys, and prefix-overlapping target keys. Binding lists are static
-- program data; resolve 'bindings' once at startup (or force it in a unit test) so an
-- invalid list is a fail-fast programming-error report, not a runtime branch.
newtype Bindings = Bindings [EnvBinding]
  deriving stock (Eq)

-- | Validate a static binding list once, yielding a collection usable with the total
-- source builders.
bindings :: [EnvBinding] -> Either (NonEmpty EnvError) Bindings
bindings values =
  case NonEmpty.nonEmpty (bindingErrors values) of
    Just errors -> Left errors
    Nothing -> Right (Bindings values)

-- | Inspect the validated bindings, for example to count or display them.
bindingsList :: Bindings -> [EnvBinding]
bindingsList (Bindings values) = values
```

Make `envSource` total by replacing its signature, its validation case, and its haddock.
The body's fold and annotation logic are unchanged except that the binding list now comes
out of the `Bindings` wrapper. Because the module gains a top-level name `bindings` and
the packages compile with `-Wall` (which includes `-Wname-shadowing`), rename every local
parameter currently called `bindings` — in `envSource`, `readEnvSource`, and
`bindingErrors` — to `values` (or `boundValues` where `values` is taken, as in
`readEnvSource`):

```haskell
-- | Translate explicitly bound variables from one snapshot into a Settei source.
--
-- Total: a 'Bindings' value is valid by construction, so no error branch exists.
-- Missing variables are absent leaves. Values remain 'RawText'; target decoding and
-- sensitivity handling stay in the core declaration and resolver.
envSource :: Text -> Bindings -> EnvSnapshot -> Source
envSource sourceLabel (Bindings values) (EnvSnapshot snapshot) =
  annotateSourceAt annotationsFor (source sourceLabel EnvironmentSource root)
  where
    presentBindings =
      [ (bindingValue, rawValue)
      | bindingValue <- values,
        Just value <- [Map.lookup (bindingValue ^. #name) snapshot],
        let rawValue = RawText value
      ]
    -- root, perKeyAnnotations, annotationsFor: unchanged from the current module.
```

```haskell
-- | Snapshot the process environment once and pass it through the pure translator.
readEnvSource :: Text -> Bindings -> IO Source
readEnvSource sourceLabel validated = do
  boundValues <- Environment.getEnvironment
  pure
    ( envSource
        sourceLabel
        validated
        (envSnapshot [(Text.pack name, Text.pack value) | (name, value) <- boundValues])
    )
```

Add the default-label conveniences immediately after their labeled siblings:

```haskell
-- | 'envSource' with the conventional source label @"environment"@.
environmentSource :: Bindings -> EnvSnapshot -> Source
environmentSource = envSource "environment"

-- | 'readEnvSource' with the conventional source label @"environment"@.
readEnvironmentSource :: Bindings -> IO Source
readEnvironmentSource = readEnvSource "environment"
```

Unify `prefixedBindings` with the shared validator and return the collection directly.
Delete its private `invalidErrors` and `duplicateKeyErrors` and its call to
`overlapErrors`; those three checks now come from `bindingErrors`. Keep `groupedByName`
and `collisionErrors` exactly as they are, and filter the shared validator's
`DuplicateEnvironmentName` results because on this path every duplicate generated name IS
a normalization collision and is reported with the richer `PrefixedNameCollision`
constructor (error ordering changes slightly; the tests assert membership, not order):

```haskell
-- | Derive explicit bindings using @PREFIX_KEY_SEGMENTS@ names.
--
-- Non-alphanumeric characters become underscores and letters become uppercase. Any
-- collision introduced by that normalization is returned instead of being guessed away.
-- The successful result is already validated: pass it straight to 'envSource'.
prefixedBindings :: Text -> [Key] -> Either (NonEmpty EnvError) Bindings
prefixedBindings prefix keys =
  case NonEmpty.nonEmpty errors of
    Just found -> Left found
    Nothing -> Right (Bindings generated)
  where
    generated = fmap (\key -> binding (prefixedName prefix key) key) keys
    groupedByName =
      Map.fromListWith
        (<>)
        [ (bindingValue ^. #name, bindingValue ^. #key :| [])
        | bindingValue <- generated
        ]
    collisionErrors =
      [ PrefixedNameCollision name targetKeys
      | (name, targetKeys) <- Map.toAscList groupedByName,
        NonEmpty.length targetKeys > 1
      ]
    sharedErrors = filter (not . isDuplicateNameError) (bindingErrors generated)
    errors = sharedErrors <> collisionErrors

isDuplicateNameError :: EnvError -> Bool
isDuplicateNameError (DuplicateEnvironmentName _) = True
isDuplicateNameError _ = False
```

Finally, update the sentinel's rationale in `insertRawValue`. Keep the `error` call —
its message is a programming-error marker, and this plan proves it unreachable — but make
the comment say why it is now unreachable by construction:

```haskell
-- 'Bindings' construction rejects prefix-overlapping target keys, so by the time this
-- fold runs, no path can descend through a previously written leaf. This branch is
-- unreachable by construction and exists only to satisfy exhaustiveness honestly.
go _ _ = error "validated environment keys cannot overlap"
```

### Step 2: Rewrite `settei-env/test/Settei/EnvTest.hs`

Adapt the helpers first: `expectSourceWith` builds through the smart constructor and the
now-total `envSource` (no `Left` case remains for source building — construction is where
failure can happen), and the let-bound variable named `bindings` in the "overlapping
target keys" test must be renamed (it would shadow the new import):

```haskell
expectBindings :: [EnvBinding] -> IO Bindings
expectBindings values = either (fail . show) pure (bindings values)

expectSourceWith :: [EnvBinding] -> [(Text, Text)] -> IO Source
expectSourceWith values snapshot = do
  validated <- expectBindings values
  pure (envSource "environment" validated (envSnapshot snapshot))
```

Retarget the existing rejection tests at `bindings` instead of `envSource` — the
`assertLeftContains` helper keeps its shape, applied to
`bindings sameName`, `bindings sameKey`, and `bindings overlapping`. Add an
`InvalidEnvironmentName` case (missing today):

```haskell
testCase "invalid names are rejected at construction" $
  assertLeftContains isInvalidName (bindings [binding (EnvName "1BAD") runtimeEnvironment])
```

with `isInvalidName (InvalidEnvironmentName _) = True` and false otherwise, so every
`EnvError` constructor now has a construction-time test (`PrefixedNameCollision` keeps
its existing `prefixedBindings` test, updated only in that a successful result is now a
`Bindings`). Add a success-path test for the unified prefixed path proving the derived
names survive: `prefixedBindings "MYAPP" [validKey "service.host", validKey
"service.port"]` succeeds and `fmap bindingName . bindingsList` yields
`[EnvName "MYAPP_SERVICE_HOST", EnvName "MYAPP_SERVICE_PORT"]`.

Add the totality enumeration. The pool is designed so subsets exercise both branches:
`"a"` together with `"a.b"` or `"a.c"` overlaps (construction fails), while many other
subsets are valid:

```haskell
testCase "constructed bindings never fail during source building" $ do
  let pool =
        [ binding (EnvName "POOL_A") (validKey "a"),
          binding (EnvName "POOL_AB") (validKey "a.b"),
          binding (EnvName "POOL_AC") (validKey "a.c"),
          binding (EnvName "POOL_B") (validKey "b"),
          binding (EnvName "POOL_BCD") (validKey "b.c.d"),
          binding (EnvName "POOL_C") (validKey "c")
        ]
      snapshot =
        envSnapshot [(name, "value") | EnvName name <- fmap bindingName pool]
      outcomes =
        [ (subset, bindings subset)
        | subset <- List.subsequences pool
        ]
  assertBool "expected some subsets to fail construction" (any (isLeft . snd) outcomes)
  assertBool "expected some subsets to construct" (any (isRight . snd) outcomes)
  sequence_
    [ case lookupSource (bindingKey bound) (envSource "environment" validated snapshot) of
        Right (Just _) -> pure ()
        _ -> fail "expected every bound key to be served by the total source"
    | (subset, Right validated) <- outcomes,
      bound <- subset
    ]
```

(`List` is `Data.List qualified as List`; `isLeft`/`isRight` come from `Data.Either`.
`lookupSource` forces the built raw tree at each bound key, so if the `insertRawValue`
sentinel could ever fire for validated input, this test would raise.) The two Kubernetes
annotation tests and the missing-variable test keep their assertions unchanged — they
prove snapshot behavior (presence, absence, per-key annotations, redaction) survived the
reshaping.

### Step 3: Validate and commit Milestone 1

```bash
nix develop -c cabal test settei-env-tests --test-show-details=direct
```

Expected shape of success (test count will be higher than the current 7):

```text
Test suite settei-env-tests: RUNNING...
Settei.Env
  explicit binding records variable origin:            OK
  ...
  constructed bindings never fail during source building: OK
All N tests passed
Test suite settei-env-tests: PASS
```

Then commit (note the `!` — this is a breaking API change):

```bash
git add settei-env
git commit -m "feat(settei-env)!: validate bindings at construction and make envSource total" \
  -m "Bindings is an opaque validated collection; bindings/bindingsList are the
construction and inspection surface; envSource and readEnvSource are total;
environmentSource and readEnvironmentSource fix the conventional label;
prefixedBindings returns Bindings through the unified validator." \
  -m "MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/18-make-environment-bindings-total-and-validated.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v"
```

### Step 4: Update the reference service, CLI, and conformance suite (Milestone 2)

In `examples/settei-service/src/Settei/Example/Service.hs`, change `environmentBindings`
to a validated CAF, keeping the exact seven-entry list as the argument to `bindings`:

```haskell
-- | Explicit environment bindings, including the annotated Kubernetes Secret value.
--
-- Validated once at module level; the test suite forces this CAF so an invalid edit
-- fails in tests before it can fail at startup.
environmentBindings :: Bindings
environmentBindings =
  either (error . show) id  -- TODO(EP-17): render with renderEnvErrorsText once available.
    ( bindings
        [ binding (EnvName "HASKELL_ENV") runtimeEnvironmentKey,
          -- ... the six remaining entries, verbatim from the current list ...
        ]
    )
```

(If Step 0 found `renderEnvErrorsText`, use
`either (error . Text.unpack . renderEnvErrorsText) id` and omit the TODO.) Then delete
the dead branch by collapsing `resolveServiceSources` to a single expression — this
removes the `error (show problems)` line entirely:

```haskell
-- | Resolve already loaded file sources followed by an injected environment snapshot.
resolveServiceSources :: [Source] -> EnvSnapshot -> Either (NonEmpty ConfigError) (ResolveResult ServiceConfig)
resolveServiceSources fileSources snapshot =
  resolve
    defaultResolveOptions
    (fileSources <> [environmentSource environmentBindings snapshot])
    serviceConfig
```

(The old local variable named `environmentSource` disappears with the branch, so there is
no clash with the newly imported `Settei.Env.environmentSource`.)

In `examples/settei-cli/src/Settei/Example/Cli.hs`, apply the same CAF pattern to its
five-entry `environmentBindings`, and delete the env-error `InputFailure` plumbing inside
`resolveCliOptions` by replacing the bound `environmentSource <- case envSource ... of
...` block with a direct list element:

```haskell
resolveCliOptions :: EnvSnapshot -> CliOptions -> IO (Either CliFailure (ResolveResult CliConfig))
resolveCliOptions snapshot options = do
  loaded <- traverse loadConfigInput (options ^. #configInputs)
  pure $ do
    fileSources <- firstInputFailure loaded
    case resolve
      defaultResolveOptions
      ( [builtInSource]
          <> fileSources
          <> [environmentSource environmentBindings snapshot]
          <> cliSources "arguments" (options ^. #overrides)
      )
      cliConfig of
      Left problems -> Left (ResolveFailure problems)
      Right value -> Right value
```

`CliFailure`'s `InputFailure` constructor stays — file loading still uses it — only the
environment case disappears. Both modules keep `environmentBindings` in their export
lists (the exported name is unchanged; only its type changed from `[EnvBinding]` to
`Bindings`).

In `examples/settei-conformance/test/Settei/Example/ConformanceTest.hs`, make the helper
total:

```haskell
expectEnvSource :: Env.EnvSnapshot -> Source
expectEnvSource = Env.environmentSource Service.environmentBindings
```

Add one CAF-forcing test to each example suite so the binding lists are asserted valid by
the suite (the counts pin today's lists; update the number if a list legitimately
changes). In `examples/settei-service/test/Settei/Example/ServiceTest.hs`:

```haskell
testCase "environment bindings validate at construction" $
  length (bindingsList environmentBindings) @?= 7
```

and in `examples/settei-cli/test/Settei/Example/CliTest.hs` the same with `@?= 5`.
Import whatever is missing (`bindingsList` comes from `Settei.Env`; both test modules
already import the example modules). `examples/settei-service/test/Settei/Example/ServiceTest.hs`'s
five existing `resolveServiceSources` calls compile unchanged — its signature did not
change.

### Step 5: Validate and commit Milestone 2

```bash
nix develop -c cabal test all --test-show-details=direct
```

Every suite must report `PASS` (settei, settei-env, settei-optparse-applicative,
settei-yaml, settei-kdl, settei-dhall, both example suites, and the conformance suite).
Then:

```bash
git add examples
git commit -m "refactor(examples): adopt construction-validated environment bindings" \
  -m "environmentBindings is a Bindings CAF in both reference applications; the
impossible error branches (error (show problems) in the service, InputFailure
plumbing in the CLI, the conformance helper's Left case) are deleted; each example
suite forces the CAF. EP-21 owns the full example rewrite." \
  -m "MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/18-make-environment-bindings-total-and-validated.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v"
```

### Step 6: Documentation, changelog, ADR, MasterPlan bookkeeping (Milestone 3)

Rewrite the environment sections of `docs/guides/environment-and-cli.md`:
in "Bind environment variables explicitly", change `environmentBindings :: [EnvBinding]`
to the `Bindings` CAF form (mirroring Step 4's snippet, with the guide's four bindings),
move the validation paragraph ("rejects invalid or repeated variable names, repeated
target keys, and overlapping targets…") to describe `bindings` instead of `envSource`,
and add the test idiom with a short lead-in sentence:

```haskell
testCase "environment bindings are valid" $
  length (bindingsList environmentBindings) @?= 4
```

Change `loadEnvironment` to the total, default-labeled form
`loadEnvironment :: IO Source` / `loadEnvironment = readEnvironmentSource
environmentBindings`, and the test snippet to the total
`testEnvironment :: Source` using `envSource "test environment" environmentBindings
(envSnapshot [...])` — keeping the labeled function in exactly the multi-snapshot-test
role the Decision Log assigns it. In "Generate conventional bindings", update the type to
`Either (NonEmpty EnvError) Bindings` and state that the successful result is already
validated and goes straight to `envSource`/`environmentSource`.

In `docs/guides/kubernetes-service.md`, wrap the "Bind Kubernetes-delivered environment
variables" list in the same `bindings`-CAF form and add one sentence stating explicitly
that `fromKubernetesObject` is unchanged: it still annotates a single `EnvBinding`
before the list is validated, and neither its signature nor its metadata semantics moved
(verify by re-reading the function — it is `KubernetesRef -> EnvBinding -> EnvBinding`
and this plan never touched it). Do the same one-line verification statement in the
plan's Surprises section if anything differs. The guide's "Resolve once at startup"
section already takes a prepared `Source`, so it needs no change beyond confirming its
prose still matches. In `README.md`, replace the three-line
`environmentSource <- either (fail . show) pure (envSource "environment"
environmentBindings snapshot)` binding with the total
`let environmentSource = Settei.Env.environmentSource environmentBindings snapshot`
form (adjust to the snippet's import style). Check
`docs/guides/cli-application.md` ~lines 218–219: its prose ("Call `readEnvSource` once
after argument parsing… call the pure `envSource` instead") names no signature and
remains true; update wording only if you find otherwise.

Add to `settei-env/CHANGELOG.md`, above the 0.1.0.0 entry:

```markdown
## Unreleased

- BREAKING: environment bindings are validated once at construction. `Bindings` is an
  opaque validated collection built by `bindings` or `prefixedBindings`; `envSource`
  and `readEnvSource` take `Bindings` and are total; `environmentSource` and
  `readEnvironmentSource` provide the conventional `"environment"` label;
  `bindingsList` inspects a validated collection.
```

Create the new ADR at `docs/adr/NNNN-validate-environment-bindings-at-construction.md`,
where NNNN is the next free number in `docs/adr/` at implementation time (run
`ls docs/adr/`; EP-16 plans to claim 0008 and EP-17 may claim 0009 — take whatever is
actually free). Keep it to roughly a page with the standard Status/Date/Context/Decision/
Consequences/Rejected Alternatives shape, distilling this plan's Decision Log: static
binding lists validate once through an opaque smart-constructed collection; source
assembly is total; no unsafe constructor; default-label conveniences; the sentinel
convention for unreachable-by-construction branches; rejected alternatives
(`unsafeBindings`, label-in-Bindings, label constant, per-assembly validation).

Update the MasterPlan file
`docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md`: set the
EP-18 registry row's Status to Complete and tick its two Progress checkboxes ("validated
Bindings construction; envSource total; default label" and "examples and environment
guide updated"). Update this plan's own Progress, Decision Log (any deviations),
Surprises & Discoveries, and Outcomes & Retrospective.

### Step 7: Final validation and commit

```bash
nix develop -c cabal test all --test-show-details=direct
grep -rn "envSource \"environment\"" docs/ README.md
grep -rn "Either (NonEmpty EnvError) Source" docs/ README.md
```

The suite passes; the first grep should match only intentional labeled-call examples (if
any remain) and the second should print nothing. Then:

```bash
git add docs README.md settei-env/CHANGELOG.md
git commit -m "docs(settei-env): teach construction-validated bindings and record the ADR" \
  -m "environment-and-cli and kubernetes-service guides, README snippet, changelog
Unreleased entry, new ADR for construction-time validation, MasterPlan bookkeeping." \
  -m "MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/18-make-environment-bindings-total-and-validated.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v"
```

(If the ExecPlan/MasterPlan living-section updates were not staged in commit 3, commit
them with a final `docs(plans): ...` commit carrying the same trailers. Do not create a
feature branch; commit to the current branch per the repository's git conventions.)


## Validation and Acceptance

Acceptance is behavioral, not structural. All commands run from the repository root.

First, the library behavior. `nix develop -c cabal test settei-env-tests
--test-show-details=direct` must pass with tests demonstrating: (1) each of the five
`EnvError` constructors is produced at construction time — `InvalidEnvironmentName` from
`bindings [binding (EnvName "1BAD") …]`, `DuplicateEnvironmentName` and
`DuplicateTargetKey` from the duplicate lists, `ConflictingTargetKeys` from
`service`/`service.port`, `PrefixedNameCollision` from `prefixedBindings "MYAPP"` over
`service.http-port`/`service.http_port`; (2) the totality enumeration passes — every one
of the 64 pool subsets that constructs successfully builds a source that serves every
bound key, and the enumeration is asserted to contain both failing and succeeding
subsets so it cannot silently degenerate; (3) the pre-existing snapshot behaviors hold
unchanged — present variables produce candidates carrying the `environment.variable`
annotation, absent variables produce no candidate, the Kubernetes Secret test still
proves the secret sentinel string never reaches rendered output while Secret object
metadata does, and the ConfigMap test still shows public metadata and value.

Second, the totality is visible in the types: after Milestone 1,
`grep -n "envSource ::" settei-env/src/Settei/Env.hs` shows
`envSource :: Text -> Bindings -> EnvSnapshot -> Source` with no `Either`, and
`grep -rn "error (show problems)" examples/` prints nothing after Milestone 2.

Third, the workspace behavior. `nix develop -c cabal test all --test-show-details=direct`
must end with every suite reporting `PASS`. This proves the reference service still
resolves its five ServiceTest scenarios (unchanged `resolveServiceSources` signature),
the CLI still distinguishes real file-loading `InputFailure`s from resolution failures,
the conformance suite still validates precedence against
`Service.environmentBindings`, and the two new CAF-forcing tests pass (meaning both
shipped binding lists are valid — the fail-fast idiom demonstrated live).

Fourth, the documentation record: `docs/guides/environment-and-cli.md` and
`docs/guides/kubernetes-service.md` contain only the new signatures, the kubernetes guide
states in prose that `fromKubernetesObject` flows are unchanged, `settei-env/CHANGELOG.md`
has the Unreleased breaking entry, and a new ADR exists in `docs/adr/` describing
construction-time validation. Failure modes to recognize: a `-Wname-shadowing` warning
mentioning `bindings` means a local parameter rename from Step 1 was missed (the build
treats it as a warning, but fix it — the workspace compiles with `-Wall`); an
`ambiguous occurrence: environmentSource` error in an example means a leftover local
binding from the old `case` block was not deleted.


## Idempotence and Recovery

Every step is an ordinary edit-plus-test cycle in a git repository, so the universal
recovery tool is `git status` / `git diff` to see where you are and
`git checkout -- <path>` (or `git restore <path>`) to abandon a broken edit; nothing in
this plan touches state outside the working tree except the Nix build cache, which is
content-addressed and safe to rebuild any number of times. Re-running any test command is
always safe. The three milestones are strictly ordered — do not start Milestone 2 before
the settei-env suite is green, because the examples cannot compile against a half-edited
`Settei.Env` — but within a milestone the edits commute and can be redone in any order.

If you stop mid-milestone, update the Progress checklist in this file first, splitting
the current item into its done and remaining halves, so the next contributor (or you,
later) can restart from this document alone. If Milestone 1 is committed and Milestone 2
proves harder than expected, note that the workspace is intentionally red at `cabal test
all` between commits 1 and 2 (only `settei-env-tests` is green); that window should be
kept short and never pushed upstream mid-window — finish Milestone 2 before pushing. If a
rebase or concurrent plan (EP-15, EP-17, EP-19 touch disjoint modules, but EP-17 touches
`settei-env`) collides, the merge rule is: this plan owns the shapes of `Bindings`,
`bindings`, `bindingsList`, `envSource`, `readEnvSource`, `environmentSource`,
`readEnvironmentSource`, and `prefixedBindings`; EP-17 owns `renderEnvErrorsText`; both
can coexist in one module without semantic conflict. The ADR number is chosen at the last
moment (Step 6) precisely so that a numbering collision is recoverable by renaming the
new file before commit 3.


## Interfaces and Dependencies

This plan uses only libraries already in the workspace. `settei-env`'s library depends on
`base`, `containers`, `generic-lens`, `settei`, and `text`; its test suite adds `tasty`
and `tasty-hunit` (see `settei-env/settei-env.cabal` — no dependency changes are needed;
the totality test deliberately avoids adding QuickCheck, per the Decision Log; the test
module gains only new imports of `Data.List qualified as List` and `Data.Either`). From
the core `settei` package it continues to use `Key`, `keySegments`, `RawValue`
(`RawText`, `RawObject`), `Source`, `source`, `annotateSourceAt`, `EnvironmentSource`,
`lookupSource`, `KubernetesRef`, and `kubernetesAnnotations` — none of which change here.
Code style follows docs/adr/0001-haskell-project-conventions.md: GHC2024, strict fields,
explicit deriving strategies, lens access with generic-lens labels, postpositive
`qualified`.

At the end of Milestone 1, `settei-env/src/Settei/Env.hs` exports exactly its current
surface plus the additions, with these signatures:

```haskell
newtype Bindings                                                     -- opaque; Eq only
bindings              :: [EnvBinding] -> Either (NonEmpty EnvError) Bindings
bindingsList          :: Bindings -> [EnvBinding]
envSource             :: Text -> Bindings -> EnvSnapshot -> Source
readEnvSource         :: Text -> Bindings -> IO Source
environmentSource     :: Bindings -> EnvSnapshot -> Source
readEnvironmentSource :: Bindings -> IO Source
prefixedBindings      :: Text -> [Key] -> Either (NonEmpty EnvError) Bindings
```

Everything else (`EnvName (..)`, `EnvSnapshot (..)`, `EnvBinding` opaque, `EnvError
(..)`, `binding`, `annotateBinding`, `bindingName`, `bindingKey`, `bindingAnnotations`,
`envSnapshot`, `fromKubernetesObject`) is unchanged. At the end of Milestone 2,
`Settei.Example.Service.environmentBindings :: Bindings` and
`Settei.Example.Cli.environmentBindings :: Bindings` (names unchanged, types narrowed),
and `resolveServiceSources :: [Source] -> EnvSnapshot -> Either (NonEmpty ConfigError)
(ResolveResult ServiceConfig)` keeps its exact signature so
`examples/settei-service/test/Settei/Example/ServiceTest.hs` compiles untouched apart
from the added CAF-forcing test.

Plan-level dependencies: no hard dependency on any sibling plan. Soft dependency EP-17
(docs/plans/17-add-error-renderers-to-every-source-adapter.md) supplies
`renderEnvErrorsText` for the examples' CAF failure message; Step 0 detects whether it
has landed, and the `show`-based fallback with `TODO(EP-17)` comments is fully
acceptable — EP-17 or EP-21 will replace it. Downstream, EP-21
(docs/plans/21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md)
hard-depends on this plan and performs the full example and docs rewrite; keep Milestone
2's diffs minimal for its sake. EP-20 audits the final exposed surface this plan adds.
