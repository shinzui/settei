---
id: 11
slug: adopt-yaml-1-2-core-schema-boolean-scalars
title: "Adopt YAML 1.2 core-schema boolean scalars"
kind: exec-plan
created_at: 2026-07-19T14:54:42Z
intention: "intention_01kxxdt2f0enp928nc1wbcsd2t"
master_plan: "docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md"
---

# Adopt YAML 1.2 core-schema boolean scalars

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Today, an operator who writes the unquoted YAML line `country: no` into a Settei
configuration file does not get the text "no". The YAML adapter silently turns it into the
boolean `false`, and a text setting for that key then fails to decode with the message
"expected text" — an error that is loud but baffling, because the file plainly contains a
word. Worse, `enabled: on` silently type-shifts from what the operator may have intended.
This is the classic "Norway problem": YAML 1.1 defined `y`, `yes`, `on`, `n`, `no`, and
`off` as boolean spellings, so the country code `no` (Norway) becomes `false`. YAML 1.2's
core schema fixed this by restricting booleans to `true` and `false` only.

Settei's YAML adapter brands itself strict — it already rejects anchors, aliases, merge
keys, duplicate keys, multiple documents, and custom tags (see
docs/adr/0004-yaml-input-semantics.md) — yet it still recognizes the permissive YAML 1.1
boolean set. This plan closes that gap. After this change, the only untagged plain scalars
the adapter treats as booleans are `true` and `false`, compared case-insensitively.
Everything else in the old set (`y`, `yes`, `on`, `n`, `no`, `off`) becomes plain text. A
scalar explicitly tagged `!!bool` also accepts only `true`/`false`; `!!bool yes` becomes a
structured `YamlInvalidScalar` error instead of `True`.

You can see it working by running the settei-yaml test suite: a new characterization test
named for the Norway problem proves that `country: no` reaches the resolver as the text
"no", and the whole-workspace test run (including the cross-format conformance suite under
examples/) stays green. A side benefit: the YAML adapter and the core `boolDecoder` in
settei/src/Settei/Value.hs (which accepts only textual "true"/"false" case-insensitively)
finally agree on what a textual boolean is, so environment-variable booleans and YAML
booleans behave identically.

This defect was found in the 2026-07-19 API review and is item EP-11 of the MasterPlan
docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] Mark EP-11 "In Progress" in the MasterPlan registry table in docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md.
- [ ] Check whether EP-10 (docs/plans/10-bound-numeric-scalar-conversion-in-the-yaml-and-kdl-adapters.md) has landed; note the answer in Surprises & Discoveries and adapt line references if settei-yaml/src/Settei/Yaml.hs has shifted.
- [ ] Restrict `yamlBoolean` in settei-yaml/src/Settei/Yaml.hs to case-insensitive `true`/`false` only.
- [ ] Add success-path boolean scalar tests to settei-yaml/test/Settei/YamlTest.hs, including the named Norway regression test.
- [ ] Add the tagged `!!bool yes` failure test to settei-yaml/test/Settei/YamlCharacterizationTest.hs.
- [ ] Run `nix develop -c cabal test settei-yaml-tests --test-show-details=direct` and confirm all tests pass.
- [ ] Commit the code and test change (Conventional Commit with the three required trailers).
- [ ] Append a dated amendment note to docs/adr/0004-yaml-input-semantics.md recording the YAML 1.2 core-schema boolean decision and the rejected alternative.
- [ ] Rewrite the boolean paragraphs of docs/guides/yaml.md, including a short Norway-problem explanation and the note about agreement with core `boolDecoder`.
- [ ] Update the boolean sentence in settei-yaml/test/fixtures/characterization/README.md.
- [ ] Add the behavior change to settei-yaml/CHANGELOG.md.
- [ ] Commit the documentation changes (Conventional Commit with the three required trailers).
- [ ] Run `nix develop -c cabal test all --test-show-details=direct` and confirm the entire workspace, including examples/settei-conformance, stays green.
- [ ] Update the MasterPlan: tick the two EP-11 Progress boxes and set the registry status to Complete.
- [ ] Fill in Outcomes & Retrospective in this plan and perform the ADR distillation pass (the ADR 0004 amendment covers the durable context; confirm nothing else needs promotion).


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Restrict untagged plain-scalar boolean recognition in the YAML adapter to
  case-insensitive `true` and `false`, following the YAML 1.2 core schema. `y`, `yes`,
  `on`, `n`, `no`, and `off` become plain text (`RawText`).
  Rationale: The adapter's contract (docs/adr/0004-yaml-input-semantics.md) is strictness
  and deterministic meaning; the YAML 1.1 boolean set resurrects the Norway problem, where
  `country: no` becomes `RawBool False` and a text setting fails with a baffling
  "expected text" error, and `enabled: on` silently type-shifts. YAML 1.2 core schema is
  the modern standard and matches what operators expect.
  Date: 2026-07-19

- Decision: Scalars explicitly tagged `!!bool` accept the same restricted set. After this
  change, `!!bool yes` is a `YamlInvalidScalar` structured error, not `True`.
  Rationale: One consistent boolean vocabulary for the whole adapter. The `BoolTag` branch
  of `scalarValue` funnels through `parseBoolean`, which consults the same `yamlBoolean`
  helper, so consistency falls out of the single-function change. Keeping a wider set for
  tagged scalars would mean two boolean languages in one file format and would reintroduce
  the ambiguity this plan removes.
  Date: 2026-07-19

- Decision: Leave `isNull` in settei-yaml/src/Settei/Yaml.hs unchanged (case-folded
  `null`, the literal `~`, and the empty plain scalar are `RawNull`).
  Rationale: The YAML 1.2 core schema null spellings are `null`, `Null`, `NULL`, `~`, and
  empty; `Text.toCaseFold` already accepts the three capitalizations, so current behavior
  is already 1.2-core-conformant. No change, no new tests required, but the plan records
  the decision so nobody "fixes" it speculatively.
  Date: 2026-07-19

- Decision: Rejected alternative — keeping the YAML 1.1 boolean set for compatibility
  with existing files.
  Rationale: Settei is pre-release (0.1.0.0 has never shipped), so there are no existing
  adopter files to protect, and strictness is the adapter's stated contract. Compatibility
  with a footgun is not a feature. This rejection is also recorded in the dated amendment
  to docs/adr/0004-yaml-input-semantics.md.
  Date: 2026-07-19

- Decision: Treat EP-10 (docs/plans/10-bound-numeric-scalar-conversion-in-the-yaml-and-kdl-adapters.md)
  as a soft dependency only: land after it when possible, but do not block on it.
  Rationale: Both plans edit the scalar pipeline in settei-yaml/src/Settei/Yaml.hs and
  both append dated notes to docs/adr/0004-yaml-input-semantics.md; landing EP-10 first
  avoids rebasing the ADR amendment. The boolean change itself touches only `yamlBoolean`
  and is semantically independent of the numeric guard, so it compiles and is correct from
  the current tree either way. ADR amendments append dated notes rather than rewriting
  earlier ones, per the MasterPlan's integration rules.
  Date: 2026-07-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

Settei is a Haskell configuration library developed in this repository as a Cabal
multi-package workspace. The core package `settei` defines the configuration algebra:
untyped raw values (`RawValue`, with constructors `RawText`, `RawBool`, `RawNumber`,
`RawNull`, `RawArray`, `RawObject`), typed decoders, sources, and the resolver. Format
adapters live in sibling packages; this plan concerns `settei-yaml`, whose single public
module is settei-yaml/src/Settei/Yaml.hs. Reference applications and a cross-format
conformance test suite live under examples/ and are the public-API conformance boundary
per docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md:
every behavior change must leave them green or update them.

Relevant ADRs consulted (repository-relative paths):

- docs/adr/0004-yaml-input-semantics.md — the YAML adapter's contract. It commits to a
  strict marked-event subset of YAML: duplicate keys, anchors, aliases, merge keys,
  multiple documents, dotted keys, non-string keys, and custom tags all fail with a stable
  `YamlErrorCategory`, and errors never retain raw scalars. It currently says only
  "booleans are typed" without pinning the boolean vocabulary; this plan appends a dated
  amendment pinning it to the YAML 1.2 core schema.
- docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md — the
  examples under examples/ (settei-cli, settei-service, settei-conformance) are the
  conformance boundary; the full test run must stay green.
- docs/adr/0001-haskell-project-conventions.md governs code style (as it does for every
  plan in this MasterPlan); no boolean-specific content.

How the YAML scalar pipeline works today. Parsing goes through
`Text.Libyaml.decodeMarked`, producing a stream of marked events. Every scalar event
reaches `scalarValue` (settei-yaml/src/Settei/Yaml.hs, around lines 338–356). That
function branches on the libyaml tag:

- `Libyaml.StrTag` → `RawText`; `Libyaml.NullTag` → `RawNull`.
- `Libyaml.BoolTag` (a scalar explicitly tagged `!!bool`) → `parseBoolean` (around lines
  358–363), which calls `yamlBoolean` and turns `Nothing` into a `YamlInvalidScalar`
  error with the message "invalid boolean scalar".
- `Libyaml.IntTag` and `Libyaml.FloatTag` → numeric parsing.
- `Libyaml.NoTag` (an ordinary untagged scalar) with a quoted, literal, or folded style →
  always `RawText` (this is why quoting a word keeps it text). Otherwise, for a *plain*
  unquoted scalar, the branch tries `isNull`, then `yamlBoolean`, then `parseYamlNumber`,
  and finally falls through to `RawText`. This `NoTag` plain-scalar consultation of
  `yamlBoolean` is where the Norway problem lives.

The current `yamlBoolean` (around lines 392–402) case-folds the scalar and accepts the
YAML 1.1 set:

```haskell
yamlBoolean :: Text -> Maybe Bool
yamlBoolean value = case Text.toCaseFold value of
  "y" -> Just True
  "yes" -> Just True
  "on" -> Just True
  "true" -> Just True
  "n" -> Just False
  "no" -> Just False
  "off" -> Just False
  "false" -> Just False
  _ -> Nothing
```

Directly below it, `isNull` (around lines 404–405) accepts case-folded `null`, the
literal `~`, and the empty scalar. `Text.toCaseFold` already makes `Null` and `NULL`
match, which is exactly the YAML 1.2 core-schema null set, so `isNull` needs no change
(see Decision Log).

The core decoder this restores consistency with: `boolDecoder` in
settei/src/Settei/Value.hs (around lines 78–85) accepts `RawBool` directly, and for
`RawText` accepts only case-folded "true"/"false". Today the YAML adapter manufactures
`RawBool False` out of "no" before `boolDecoder` ever sees it, so the core and the
adapter disagree about the textual boolean language. After this plan, they agree.

Survey of existing tests, fixtures, and docs that mention the YAML 1.1 set (this is the
required enumeration; the search covered settei-yaml/test, examples/settei-conformance,
docs/, and the settei-yaml source for `y`, `yes`, `on`, `n`, `no`, `off`, `yamlBoolean`,
and `RawBool`):

- settei-yaml/test/Settei/YamlTest.hs — the only boolean assertion is in the test "large
  integers, decimals, booleans, and arrays retain portable meaning" (around line 45),
  which feeds `enabled: true` and expects `RawBool True`. `true` remains a boolean, so
  this test needs no change.
- settei-yaml/test/Settei/YamlCharacterizationTest.hs — currently exercises only failure
  paths (duplicates, anchors, merge keys, tags, non-string keys, syntax marks); no
  boolean coverage. New failure test added here.
- settei-yaml/test/fixtures/characterization/ — fixtures cover duplicates, multiple
  documents, aliases, merge keys, custom tags, and a nested mapping; none contains `yes`,
  `no`, `on`, `off`, `y`, or `n`. No fixture changes required. The prose in
  settei-yaml/test/fixtures/characterization/README.md says "Scalars support null,
  booleans, ..." and should gain the 1.2 core-schema qualifier (Milestone 2).
- examples/settei-conformance/test/fixtures/service.yaml (and its .kdl and .dhall
  siblings) — contain no boolean scalars at all, in either spelling set. The conformance
  suite is unaffected by this change and must simply stay green.
- settei/test/Settei/ResolveTest.hs (line 62) and settei-dhall/test/Settei/DhallTest.hs
  (lines 52 and 60) — use the string "yes" as ordinary text data in core and Dhall
  tests. They never pass through the YAML adapter and are unaffected.
- docs/guides/yaml.md — lines 177–181 document the full YAML 1.1 set ("Plain boolean
  spellings `y`, `yes`, `on`, `true`, `n`, `no`, `off`, and `false` are recognized
  case-insensitively") with a `featureLabel: "on"` quoting example. This is the main
  documentation to rewrite (Milestone 2).
- settei-yaml/CHANGELOG.md — one `0.1.0.0 — 2026-07-18` section (unreleased); gains a
  bullet.

Conclusion of the survey: no existing test or fixture *relies* on the 1.1-only spellings,
so the change is purely additive on the test side plus documentation rewrites. That is a
finding of this plan, not an assumption — if the tree has drifted when you implement,
re-run the search shown in Concrete Steps and update this section.

Coordination note: EP-10 (docs/plans/10-bound-numeric-scalar-conversion-in-the-yaml-and-kdl-adapters.md)
edits the numeric functions in the same module and appends its own dated note to the same
ADR. Prefer landing this plan after EP-10 so the ADR amendments stack in registry order,
but nothing here depends on EP-10's artifacts. The line numbers cited above are from the
pre-EP-10 tree; if EP-10 has landed, locate the functions by name (`yamlBoolean`,
`parseBoolean`, `scalarValue`, `isNull`) rather than by line.


## Plan of Work

The work is three milestones: the semantic change with its tests, the documentation trail,
and whole-workspace validation. Each is independently verifiable and separately
committed.

### Milestone 1 — Restrict the boolean set and prove it with tests

Scope: settei-yaml only. At the end of this milestone, `yamlBoolean` recognizes only
case-insensitive `true`/`false`, plain `no`/`on`/`yes`/`off`/`y`/`n` scalars decode as
text, `!!bool yes` is a structured error, and the settei-yaml test suite passes with new
named regression tests. Acceptance: `nix develop -c cabal test settei-yaml-tests
--test-show-details=direct` passes, and if you run the new tests against the unmodified
`yamlBoolean` first, the Norway regression test fails with a value mismatch — that
before/after flip is the proof the change is effective beyond compilation.

Edit settei-yaml/src/Settei/Yaml.hs. Replace the body of `yamlBoolean` so the whole
function reads:

```haskell
yamlBoolean :: Text -> Maybe Bool
yamlBoolean value = case Text.toCaseFold value of
  "true" -> Just True
  "false" -> Just False
  _ -> Nothing
```

That single edit propagates everywhere by construction. In `scalarValue`, the
`Libyaml.NoTag` plain-scalar branch guard `Just boolean <- yamlBoolean value` now fails
for "no"/"on"/etc., so those scalars fall through the numeric guard (they are not
numbers) to the final `otherwise -> Right (RawText value)` — exactly the desired text
behavior. In the `Libyaml.BoolTag` branch, `parseBoolean` gets `Nothing` back from
`yamlBoolean` for "yes" and produces its existing
`yamlError options YamlInvalidScalar ... "invalid boolean scalar"` — the desired tagged
failure. Do not touch `isNull`, `parseYamlNumber`, or anything else in the module. Do not
change any exported name; the public API surface is unchanged.

Then add tests. Success-path tests go in settei-yaml/test/Settei/YamlTest.hs because that
module already has the helpers `expectSource` (decode a YAML string or fail the test),
`expectCandidate` (look up a key's candidate in the decoded source), `candidateValue`,
and `validKey`. Add one new test case to the `testGroup` list, plus the keys it needs.
The Norway regression test must be identifiable by name. A concrete shape that fits the
file's existing style:

```haskell
      testCase "Norway regression: YAML 1.1 boolean spellings remain text" $ do
        input <-
          expectSource
            "country: no\nfeature:\n  legacy: yes\n  toggle: on\n  kill: off\n  short: y\n  tiny: n\n"
        country <- expectCandidate countryKey input
        candidateValue country @?= RawText "no"
        legacy <- expectCandidate legacyKey input
        candidateValue legacy @?= RawText "yes"
        toggle <- expectCandidate toggleKey input
        candidateValue toggle @?= RawText "on"
        kill <- expectCandidate killKey input
        candidateValue kill @?= RawText "off"
        short <- expectCandidate shortKey input
        candidateValue short @?= RawText "y"
        tiny <- expectCandidate tinyKey input
        candidateValue tiny @?= RawText "n",
      testCase "core-schema booleans parse case-insensitively and quoted true stays text" $ do
        input <-
          expectSource
            "plain: true\nupper: TRUE\nnegative: false\nquoted: \"true\"\n"
        plain <- expectCandidate plainKey input
        candidateValue plain @?= RawBool True
        upper <- expectCandidate upperKey input
        candidateValue upper @?= RawBool True
        negative <- expectCandidate negativeKey input
        candidateValue negative @?= RawBool False
        quoted <- expectCandidate quotedKey input
        candidateValue quoted @?= RawText "true",
```

Define the new keys next to the existing key definitions at the bottom of the file, in
the same style (`countryKey = validKey "country"`, `legacyKey = validKey
"feature.legacy"`, `toggleKey = validKey "feature.toggle"`, `killKey =
validKey "feature.kill"`, `shortKey = validKey "feature.short"`, `tinyKey = validKey
"feature.tiny"`, `plainKey = validKey "plain"`, `upperKey = validKey "upper"`,
`negativeKey = validKey "negative"`, `quotedKey = validKey "quoted"`), extending the
existing type-signature line that lists the keys. Note the quoted-"true" assertion is the
pre-existing SingleQuoted/DoubleQuoted style rule in `scalarValue`, restated as a
regression guard so nobody later "simplifies" the style check away.

Failure-path tests go in settei-yaml/test/Settei/YamlCharacterizationTest.hs, which has
the `expectError` helper. Add two cases to its `testGroup` list:

```haskell
      testCase "tagged !!bool with a YAML 1.1 spelling fails as an invalid scalar" $ do
        problem <- expectError "feature:\n  enabled: !!bool yes\n"
        yamlErrorCategory problem @?= YamlInvalidScalar
        yamlErrorContext problem @?= "$.feature.enabled",
      testCase "tagged !!bool true still parses" $
        case decodeYamlSource
          (withYamlSourcePath "characterization.yaml" (yamlSourceOptions "characterization"))
          (ByteString8.pack "feature:\n  enabled: !!bool true\n") of
          Left errors -> fail (show errors)
          Right _ -> pure (),
```

(The second case only needs decode success; candidate-level inspection of `RawBool True`
for the tagged form is covered by the untagged `true` assertions in YamlTest.hs and by
the shared `yamlBoolean` code path.)

Run the suite (command in Concrete Steps), then commit.

### Milestone 2 — Documentation trail: ADR amendment, guide, changelog, fixture README

Scope: documentation only; no Haskell changes. At the end of this milestone the decision
is durable project memory and every user-facing description of YAML booleans matches the
code. Acceptance: the four files below contain the described content, and
`nix develop -c cabal test settei-yaml-tests --test-show-details=direct` still passes
(docs cannot break it, but re-running confirms a clean tree before committing).

First, append a dated amendment to docs/adr/0004-yaml-input-semantics.md. Do not rewrite
the existing Decision or Rejected Alternatives prose (the MasterPlan's integration rule:
each plan appends its own dated note; EP-10 may already have appended one — leave it
untouched and add yours after it). Add a new section at the end of the file, shaped like
this:

```markdown
## Amendment 2026-07-19: YAML 1.2 core-schema booleans

The 2026-07-19 API review found that `yamlBoolean` accepted the YAML 1.1 boolean set
(`y`, `yes`, `on`, `n`, `no`, `off`, `true`, `false`), resurrecting the Norway problem:
an unquoted `country: no` became the boolean false, so a text setting failed to decode
with a baffling "expected text" error, and `enabled: on` silently type-shifted.

Untagged plain-scalar boolean recognition is now restricted to case-insensitive `true`
and `false`, per the YAML 1.2 core schema. Scalars explicitly tagged `!!bool` accept the
same restricted set, so `!!bool yes` is a `YamlInvalidScalar` error; the adapter has one
boolean vocabulary. Null spellings are unchanged: case-folded `null`, `~`, and the empty
plain scalar were already exactly the 1.2 core-schema null set. This also aligns the
adapter with core `boolDecoder`, which accepts only textual `true`/`false`.

Rejected alternative: keeping the YAML 1.1 boolean set for compatibility. Settei is
pre-release with no adopter files to protect, and strictness is this adapter's contract.
```

Adjust the amendment date if you implement on a different day, and place it after any
EP-10 amendment already present.

Second, update docs/guides/yaml.md. In the section "Understand YAML-to-Settei values",
replace the paragraph beginning "Plain boolean spellings `y`, `yes`, `on`, ..." and its
`featureLabel: "on"` example with prose that states: only `true` and `false`
(case-insensitive, so `True` and `TRUE` also work) are booleans, per the YAML 1.2 core
schema; `y`, `yes`, `on`, `n`, `no`, and `off` are ordinary text; and quoting still
forces text (`"true"` is the text true). Include a short named explanation of the Norway
problem — YAML 1.1 treated `no` as false, so `country: no` corrupted the country code
for Norway; Settei deliberately follows YAML 1.2 so that cannot happen — with a small
yaml-fenced example such as:

```yaml
country: no        # the text "no", never a boolean
feature:
  enabled: true    # a boolean
  label: "on"      # quoted: the text "on" (unquoted "on" is also text)
```

Also add one sentence noting the deliberate consistency with the core decoder: the core
`boolDecoder` (Settei.Value in the settei package) accepts only textual "true"/"false"
case-insensitively for text scalars, so a boolean written in an environment variable and
a boolean written in YAML follow the same rules. Finally, soften the "Production
checklist" bullet "Quote boolean-like or numeric-looking values that must remain text" to
mention only numeric-looking values and the two real boolean words, since `yes`/`no`/
`on`/`off` no longer need quoting.

Third, in settei-yaml/test/fixtures/characterization/README.md, amend the sentence
"Scalars support null, booleans, exact finite numbers, strings, arrays, ..." to say
booleans follow the YAML 1.2 core schema (`true`/`false` only, case-insensitive).

Fourth, add a bullet to settei-yaml/CHANGELOG.md under the existing `0.1.0.0` section
(the package has never shipped, so the initial-release section absorbs the change rather
than a new version heading):

```markdown
- Restrict boolean scalars to the YAML 1.2 core schema: only case-insensitive `true` and
  `false` are booleans, whether plain or tagged `!!bool`. The YAML 1.1 spellings `y`,
  `yes`, `on`, `n`, `no`, and `off` are now plain text, eliminating the Norway problem.
```

Commit the documentation changes.

### Milestone 3 — Whole-workspace validation and MasterPlan bookkeeping

Scope: no new edits expected. Run the full workspace test suite so the conformance
boundary of docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md
is re-proven: examples/settei-conformance fixtures contain no boolean scalars (verified
in Context and Orientation), so the suite must pass unchanged — if it does not, a fixture
or example silently depended on the 1.1 set, which is a discovery to record in Surprises
& Discoveries and fix by updating that fixture and this plan. Acceptance:
`nix develop -c cabal test all --test-show-details=direct` reports every suite passing.

Then update docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md:
tick the two EP-11 checkboxes in its Progress section ("YAML untagged booleans restricted
to true/false with characterization tests" and "ADR 0004 amendment, YAML guide, and
conformance fixtures updated" — the fixture half is satisfied vacuously and the guide
half by Milestone 2) and set row 11's Status to Complete in the Exec-Plan Registry.
Include that MasterPlan edit in the final commit, write the Outcomes & Retrospective
entry in this plan, and confirm the ADR distillation pass: the durable decision already
lives in the ADR 0004 amendment; nothing else in the Decision Log is project-level.


## Concrete Steps

All commands run from the repository root, /Users/shinzui/Keikaku/bokuno/settei. The
project is built inside its Nix development shell via `nix develop -c`.

Before editing, re-verify the survey (optional but cheap; expect only the hits enumerated
in Context and Orientation):

```bash
grep -rnE '"(y|yes|on|n|no|off)"|: *(yes|no|on|off) *$' settei-yaml/test examples/settei-conformance/test docs/guides/yaml.md
```

Optionally, to capture red/green evidence, add the Milestone 1 tests *before* changing
`yamlBoolean` and run the suite; expect the Norway test to fail like this (then apply the
code change and watch it pass):

```text
    Norway regression: YAML 1.1 boolean spellings remain text: FAIL
      expected: RawText "no"
       but got: RawBool False
```

Milestone 1 build-and-test loop:

```bash
nix develop -c cabal test settei-yaml-tests --test-show-details=direct
```

Expected tail of a successful run:

```text
All 21 tests passed (...)
Test suite settei-yaml-tests: PASS
```

(The exact count depends on how many cases exist when you implement; before this plan the
module pair had 21 cases, and this plan adds 4, so expect around 25. What matters is
`PASS` and the presence of the new test names in the `--test-show-details=direct`
listing.)

Commit Milestone 1. Every commit in this plan uses the Conventional Commits format and
carries the three trailers exactly as shown:

```bash
git add settei-yaml/src/Settei/Yaml.hs settei-yaml/test/Settei/YamlTest.hs settei-yaml/test/Settei/YamlCharacterizationTest.hs docs/plans/11-adopt-yaml-1-2-core-schema-boolean-scalars.md
git commit -m 'fix(settei-yaml)!: restrict booleans to the YAML 1.2 core schema

Only case-insensitive true/false are booleans, plain or tagged !!bool.
The YAML 1.1 spellings y/yes/on/n/no/off become plain text, eliminating
the Norway problem (country: no is now the text "no").

MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
ExecPlan: docs/plans/11-adopt-yaml-1-2-core-schema-boolean-scalars.md
Intention: intention_01kxxdt2f0enp928nc1wbcsd2t'
```

(Stage this plan file alongside each commit so its Progress section always matches the
committed state. The `!` marks a behavior change; the package is unreleased, so no
version bump is made.)

Milestone 2: make the four documentation edits described in Plan of Work, re-run the
settei-yaml suite once to confirm a clean tree, then commit:

```bash
git add docs/adr/0004-yaml-input-semantics.md docs/guides/yaml.md settei-yaml/test/fixtures/characterization/README.md settei-yaml/CHANGELOG.md docs/plans/11-adopt-yaml-1-2-core-schema-boolean-scalars.md
git commit -m 'docs(settei-yaml): record YAML 1.2 core-schema boolean semantics

Amend ADR 0004 with the dated boolean decision and rejected alternative,
rewrite the YAML guide boolean section with a Norway-problem explanation
and the boolDecoder consistency note, and update the changelog.

MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
ExecPlan: docs/plans/11-adopt-yaml-1-2-core-schema-boolean-scalars.md
Intention: intention_01kxxdt2f0enp928nc1wbcsd2t'
```

Milestone 3 validation:

```bash
nix develop -c cabal test all --test-show-details=direct
```

Expected: every test suite in the workspace, including the examples/settei-conformance
suite, ends with `PASS`. Then edit the MasterPlan bookkeeping and this plan's living
sections and commit:

```bash
git add docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md docs/plans/11-adopt-yaml-1-2-core-schema-boolean-scalars.md
git commit -m 'chore(plans): complete EP-11 YAML 1.2 boolean adoption

MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
ExecPlan: docs/plans/11-adopt-yaml-1-2-core-schema-boolean-scalars.md
Intention: intention_01kxxdt2f0enp928nc1wbcsd2t'
```


## Validation and Acceptance

Acceptance is behavioral. After implementation, all of the following hold, and each is
observable by running the named command:

1. A YAML document containing the unquoted line `country: no` decodes so the key
   `country` carries `RawText "no"`. The test named "Norway regression: YAML 1.1 boolean
   spellings remain text" in settei-yaml/test/Settei/YamlTest.hs asserts this (plus
   `yes`, `on`, `off`, `y`, `n`), and it appears as a passing line in
   `nix develop -c cabal test settei-yaml-tests --test-show-details=direct`. A practical
   consequence a human can reason about: a `textDecoder` setting for `country` now
   succeeds with "no" instead of failing with "expected text".
2. `enabled: on` yields text, not a boolean — covered by the same test.
3. Plain `true`, `TRUE`, and `false` decode as `RawBool True`/`RawBool False`, and the
   double-quoted scalar `"true"` remains `RawText "true"` — the test "core-schema
   booleans parse case-insensitively and quoted true stays text" asserts this.
4. `enabled: !!bool yes` fails to decode with `yamlErrorCategory == YamlInvalidScalar`
   and context `$.feature.enabled`, while `!!bool true` still decodes — the two new
   cases in settei-yaml/test/Settei/YamlCharacterizationTest.hs assert this.
5. Nothing else regressed: `nix develop -c cabal test all --test-show-details=direct`
   passes across the workspace, including the cross-format conformance suite under
   examples/ (whose fixtures contain no boolean scalars and therefore need no edits).
6. The documentation matches the code: docs/adr/0004-yaml-input-semantics.md ends with
   the dated 2026-07-19 amendment, docs/guides/yaml.md describes only `true`/`false` as
   booleans and explains the Norway problem and the `boolDecoder` consistency, and
   settei-yaml/CHANGELOG.md carries the behavior-change bullet.

If you captured the optional red run in Milestone 1, the failing-then-passing Norway test
is the strongest evidence that the change is effective beyond compilation; keep the
failure snippet in Surprises & Discoveries or in the commit message body if you find it
useful.


## Idempotence and Recovery

Every step is safe to repeat. The `yamlBoolean` edit is a pure function-body replacement:
applying it twice is a no-op, and re-running either test command never mutates state.
Documentation edits are plain-text and re-checkable by reading the file; if you are
unsure whether the ADR amendment was already appended, search for "Amendment 2026-07-19"
in docs/adr/0004-yaml-input-semantics.md before adding it again — there must be exactly
one such section from this plan.

If a test run fails midway, nothing needs cleanup; fix the code or test and re-run. If
you need to abandon partially staged work, `git status` shows the touched files and
`git restore <path>` reverts an individual file (never revert files owned by other
in-flight plans — this plan only touches the files listed in Concrete Steps). Because
each milestone is its own commit with the required trailers, `git revert <sha>` cleanly
undoes the behavior change or the docs independently if the MasterPlan ever requires it —
independent revertibility is the stated reason EP-11 is separate from EP-10.

If EP-10 lands between your milestones, rebase; the only plausible conflict is in
settei-yaml/src/Settei/Yaml.hs near the numeric functions (yours touches only
`yamlBoolean`) and in the ADR, where both plans append distinct dated sections — keep
both, EP-10's first.


## Interfaces and Dependencies

No new dependencies, no version bumps, and no public API surface change. The edit is
internal to the existing module settei-yaml/src/Settei/Yaml.hs; the module's export list
is untouched.

Signatures that must exist, unchanged, at the end of Milestone 1 (all private to
Settei.Yaml except where noted):

- `yamlBoolean :: Text -> Maybe Bool` — now returning `Just` only for case-folded
  "true"/"false".
- `parseBoolean :: YamlSourceOptions -> [PathPiece] -> Libyaml.MarkedEvent -> Text ->
  Either YamlSourceError RawValue` — unchanged text, now stricter via `yamlBoolean`.
- `scalarValue :: YamlSourceOptions -> [PathPiece] -> Libyaml.MarkedEvent -> ByteString
  -> Libyaml.Tag -> Libyaml.Style -> Either YamlSourceError RawValue` — unchanged.
- `isNull :: Text -> Bool` — deliberately unchanged (Decision Log).
- Public entry points `decodeYamlSource` and `readYamlSource` in Settei.Yaml — unchanged
  types; only the value-level boolean vocabulary narrows.

Libraries in play, all already dependencies of settei-yaml (see
settei-yaml/settei-yaml.cabal): `libyaml` (marked event parsing via `Text.Libyaml`),
`text` (`Data.Text.toCaseFold` does the case-insensitive comparison), `attoparsec` and
`scientific` (numeric path, untouched). The tests use the existing `tasty`/`tasty-hunit`
suite `settei-yaml-tests` defined in settei-yaml/settei-yaml.cabal with modules
Settei.YamlTest and Settei.YamlCharacterizationTest — no cabal file edit is needed
because both test modules already exist. The related core interface is `boolDecoder ::
Decoder Bool` in settei/src/Settei/Value.hs, which is read for context only and must not
be edited by this plan; its textual "true"/"false" rule is the consistency anchor that
docs/guides/yaml.md now documents.
