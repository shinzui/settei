---
id: 10
slug: bound-numeric-scalar-conversion-in-the-yaml-and-kdl-adapters
title: "Bound numeric scalar conversion in the YAML and KDL adapters"
kind: exec-plan
created_at: 2026-07-19T14:54:42Z
intention: "intention_01kxxdt2f0enp928nc1wbcsd2t"
master_plan: "docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md"
---

# Bound numeric scalar conversion in the YAML and KDL adapters

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Today, a single numeric scalar in a configuration file can hang or out-of-memory-kill any
process that loads it through Settei's YAML or KDL adapter. A value such as
`1e1000000000` — fourteen characters of input — is parsed cheaply into a compact
scientific-notation number, but both adapters then convert it to an exact `Rational`
unconditionally, and that conversion tries to materialize an integer with one billion
decimal digits. The process either hangs computing the power or exhausts memory. This
happens at configuration-load time, before any typed decoder gets a chance to say "that is
not a valid port number." For a service deployed in Kubernetes, a typo or a hostile
ConfigMap becomes a startup denial-of-service that no application code can defend against.

After this change, both adapters reject any numeric scalar whose base-10 exponent has an
absolute value greater than 4096, using the same structured, secret-safe error machinery
they already use for every other rejected input. The YAML adapter reports category
`YamlInvalidScalar` with the fixed message "numeric scalar exponent is out of the
supported range"; the KDL adapter reports category `KdlUnsupportedValue` with the fixed
message "numeric value exponent is out of the supported range". Both errors carry the
adapter's usual source name, path, location/span, and structural context, and neither ever
echoes the offending scalar. Every legitimate configuration number — ports, timeouts,
byte sizes, scientific constants, ordinary decimals, hex and octal integers, negative
exponents — continues to convert to an exact `Rational` unchanged.

You can see it working by running the two adapter test suites: new characterization tests
feed `1e1000000000` and `1e-1000000000` to each adapter and assert a fast structured
rejection. The fact that those tests complete within normal test time at all is the
regression proof — before this fix they would hang or be OOM-killed.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] (2026-07-19 10:02 PDT) Milestone 1: add `maximumScalarExponent` and the `scalarRational` guard helper to `settei-yaml/src/Settei/Yaml.hs`
- [x] (2026-07-19 10:02 PDT) Milestone 1: route the `FloatTag`, `IntTag` (`parseTaggedInteger`), and untagged (`NoTag`) numeric paths through the guard
- [x] (2026-07-19 10:02 PDT) Milestone 1: add YAML characterization tests (fast rejection of huge positive/negative exponents, tagged-path rejection, boundary acceptance at 4096, boundary rejection at 4097, exactness of decimals/hex/octal/negative exponents, stable category/message/location)
- [x] (2026-07-19 10:02 PDT) Milestone 1: `nix develop -c cabal test settei-yaml-tests --test-show-details=direct` green (28 tests passed in 0.00s); commit
- [x] (2026-07-19 10:04 PDT) Milestone 2: add `scientific >=0.3.7 && <0.4` to the `settei-kdl` library `build-depends`
- [x] (2026-07-19 10:04 PDT) Milestone 2: add `maximumScalarExponent` and the guarded `KDL.Number` branch in `translateValue` in `settei-kdl/src/Settei/Kdl.hs`
- [x] (2026-07-19 10:04 PDT) Milestone 2: add KDL characterization tests (same matrix as YAML, minus YAML-specific tags; KDL hex literal exactness)
- [x] (2026-07-19 10:04 PDT) Milestone 2: `nix develop -c cabal test settei-kdl-tests --test-show-details=direct` green (24 tests passed in 0.01s); commit
- [x] (2026-07-19 10:07 PDT) Milestone 3: append dated 2026-07-19 amendment notes to `docs/adr/0004-yaml-input-semantics.md` and `docs/adr/0005-canonical-kdl-v2-input-semantics.md`
- [x] (2026-07-19 10:07 PDT) Milestone 3: update the number sections of `docs/guides/yaml.md` and `docs/guides/kdl.md`
- [x] (2026-07-19 10:07 PDT) Milestone 3: update `settei-yaml/CHANGELOG.md` and `settei-kdl/CHANGELOG.md`
- [x] (2026-07-19 10:07 PDT) Milestone 3: run `nix develop -c cabal test all --test-show-details=direct` from the repo root (10 suites and 162 named tests passed); commit
- [x] (2026-07-19 10:07 PDT) Update the MasterPlan registry status and Progress checkboxes for EP-10
- [x] (2026-07-19 10:07 PDT) Final: living sections of this plan updated; Outcomes & Retrospective written; ADR distillation pass confirmed complete


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- During Milestone 2 dependency verification, Mori had no registered `scientific`
  project, so the release line was checked against both Hackage and the authoritative
  upstream tags. Hackage listed 0.3.8.1 as current and `git ls-remote --tags --refs`
  returned `refs/tags/v0.3.8.1`; the planned `>=0.3.7 && <0.4` bound therefore includes
  the current release rather than relying on the local corpus alone.


## Decision Log

Record every decision made while working on the plan.

- Decision: Bound numeric conversion by the absolute base-10 exponent of the parsed
  `Scientific` value, with a named limit constant `maximumScalarExponent = 4096`, defined
  locally in each adapter.
  Rationale: `Data.Scientific.base10Exponent` is an `Int` read, so the check is O(1) and
  runs before any expensive materialization. 4096 is far above any legitimate
  configuration magnitude (ports, timeouts, byte sizes, and physical constants all live
  within a few hundred orders of magnitude of 1) yet a `Rational` with a ~4096-digit
  numerator or denominator is cheap to build (a few kilobytes, microseconds). The limit is
  a per-scalar, adapter-local input-acceptance rule, not a core semantic: `RawNumber`
  in `settei/src/Settei/Value.hs` remains an unbounded exact `Rational`, and no core
  module changes. The constant is deliberately duplicated in the two adapters rather than
  exported from core, because core has no concept of scientific notation.
  Date: 2026-07-19

- Decision: On violation, `settei-yaml` fails with the existing `YamlInvalidScalar`
  category and the fixed message "numeric scalar exponent is out of the supported range";
  `settei-kdl` fails with the existing `KdlUnsupportedValue` category and the fixed
  message "numeric value exponent is out of the supported range". Neither message ever
  contains the scalar text. Both errors carry the adapter's normal location/span and
  structural context payloads.
  Rationale: Both adapters guarantee that structured errors never retain raw scalars
  (ADR 0004 and ADR 0005); a scalar with a huge exponent could still sit next to a secret
  in the same document, and error categories are the stable API — reusing existing
  categories means no new constructors, no renderer changes, and no downstream matching
  breakage.
  Date: 2026-07-19

- Decision: An untagged YAML plain scalar that lexes as a number but exceeds the bound is
  an error, not a fallback to `RawText`.
  Rationale: The `NoTag` branch of `scalarValue` currently treats "parses as a number" as
  the decision point and falls through to text only when the scalar is not numeric at all.
  Falling back to text for out-of-range numbers would make a scalar's *type* depend on its
  *magnitude*, silently hiding exactly the typo this plan exists to surface, and would let
  the hostile input flow onward as a huge string.
  Date: 2026-07-19

- Decision: Only the exponent is bounded; a huge literal coefficient (a number written out
  with thousands of digits) is still accepted and converted.
  Rationale: For the coefficient, conversion cost is proportional to the size of the input
  text the operator actually wrote — a megabyte of digits costs about a megabyte, which is
  ordinary input-proportional work, not amplification. The attack in scope is the
  exponent's asymmetry: fourteen input characters demanding gigabytes of output. Bounding
  literal length is a document-size concern outside this plan.
  Date: 2026-07-19

- Decision: Add `scientific >=0.3.7 && <0.4` to the `settei-kdl` library `build-depends`,
  matching `settei-yaml`'s existing bounds.
  Rationale: `settei-kdl` currently receives `Scientific` values from `kdl-hs` but has no
  direct dependency on the `scientific` package (verified in
  `settei-kdl/settei-kdl.cabal`), so it cannot import `Data.Scientific.base10Exponent`.
  ADR 0001 requires packages to declare direct dependencies for modules they import and to
  express audited compatible ranges; reusing the range already audited for `settei-yaml`
  keeps the workspace on one `scientific` release line.
  Date: 2026-07-19

- Decision: This plan lands before EP-11 and EP-13 (registry order), and its ADR
  amendments append dated notes rather than rewriting earlier ADR text.
  Rationale: EP-11 (`docs/plans/11-adopt-yaml-1-2-core-schema-boolean-scalars.md`) and
  EP-13 also edit `settei-yaml/src/Settei/Yaml.hs` and amend ADR 0004; landing in registry
  order avoids rebasing shared files, and append-only dated amendments keep each plan's
  ADR change independently revertible (MasterPlan Integration Points).
  Date: 2026-07-19

- Decision: Record the change under the existing `0.1.0.0` changelog sections of both
  adapter packages rather than adding an "Unreleased" heading.
  Rationale: Per the MasterPlan, 0.1.0.0 is implementation-complete but has never shipped,
  so there is no published behavior to differentiate from; the 0.1.0.0 entries describe
  what the first release will contain.
  Date: 2026-07-19

- Decision: Implement the absolute exponent bound as the direct range comparison
  `exponent < -4096 || exponent > 4096`, rather than `abs exponent > 4096`.
  Rationale: `base10Exponent` returns a fixed-width `Int`, and `abs minBound` overflows
  back to `minBound`. The direct comparison states the same acceptance rule while staying
  total for every `Scientific` representation, including values constructed outside the
  current parsers.
  Date: 2026-07-19


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

Completed on 2026-07-19. Both file adapters now inspect a parsed `Scientific` exponent
before any exact conversion and reject values outside the inclusive -4096 through 4096
range with their established structured, secret-safe error categories. YAML covers the
float-tagged, integer-tagged, and untagged paths; KDL declares its new direct `scientific`
dependency and guards its sole finite-number translation path. Ordinary decimals, hex,
octal, large written coefficients, and both boundary exponents retain exact behavior.

The focused YAML suite passed all 28 tests, the focused KDL suite passed all 24 tests, and
the final `cabal test all` run passed 10 suites containing 162 named tests. No reference
application, conformance fixture, golden file, or unrelated adapter required a change.
The intended release collateral is current in both adapter guides and 0.1.0.0 changelogs.

The implementation reinforced two lessons. Dependency bounds need an authoritative
release check even after Mori locates the relevant corpus source, and a numeric range
guard on a fixed-width signed type is safest as direct lower/upper comparisons rather
than `abs`. The ADR distillation pass is complete: ADR 0004 and ADR 0005 now hold the
durable per-adapter exponent-bound semantics and denial-of-service rationale. The range
comparison detail and release-verification transcript remain task-local in this plan.


## Context and Orientation

Settei is a Haskell configuration library developed as a multi-package Cabal workspace at
the repository root (`cabal.project` lists the packages). The core package `settei`
defines a source-neutral raw value tree: `RawValue` in `settei/src/Settei/Value.hs`
(around line 31) has a constructor `RawNumber !Rational` — numbers are exact rationals
with no size limit, by design. Format adapters translate concrete file formats into this
tree. Two adapters matter here: `settei-yaml` (module `Settei.Yaml` in
`settei-yaml/src/Settei/Yaml.hs`) parses a strict YAML subset via `libyaml` marked
events, and `settei-kdl` (module `Settei.Kdl` in `settei-kdl/src/Settei/Kdl.hs`) parses
KDL v2 documents via the `kdl-hs` package.

Both adapters receive parsed numbers as `Scientific` values, a type from the `scientific`
package. Understanding that type is the heart of this plan. A `Scientific` is a pair of a
`coefficient :: Integer` and a `base10Exponent :: Int`, denoting the number
`coefficient * 10 ^ base10Exponent`. Parsing text into this form is cheap and safe: the
parser stores the exponent as a machine `Int`, so `1e1000000000` parses in microseconds
into coefficient 1 and exponent 1000000000. The danger is *conversion out* of this form.
`Data.Scientific.toRational` (via the `Real` instance) computes the value exactly, which
means computing `10 ^ base10Exponent` as an exact `Integer`. Memory and time for that
power are proportional to the magnitude of the exponent, not to the length of the input
text: an exponent of one billion demands an integer of roughly a billion decimal digits —
hundreds of megabytes of allocation and a long multiplication chain — before anything can
inspect the result. A large *negative* exponent is just as bad, because the exact
`Rational` needs `10 ^ 1000000000` as its denominator. The `scientific` package's own
documentation warns that its conversion functions can fill all memory when applied to
huge-exponent values and advises checking the exponent first. Equality, ordering, and
`base10Exponent` itself are safe O(1)-ish operations.

The defect (found by the 2026-07-19 API review recorded in the parent MasterPlan): both
adapters call `toRational` on parser-produced `Scientific` values with no exponent check.

In `settei-yaml/src/Settei/Yaml.hs`, the function `scalarValue` (around line 338)
dispatches on the libyaml tag. The `Libyaml.FloatTag` branch (line ~348) is
`RawNumber . toRational <$> parseNumber options context marked value`. The
`Libyaml.IntTag` branch delegates to `parseTaggedInteger` (line ~365), which calls
`parseNumber` and then `toRational` itself before checking the denominator — so the
tagged-integer path materializes the huge number too and must also be guarded. The
`Libyaml.NoTag` branch (line ~354) has the pattern guard
`| Right number <- parseYamlNumber value -> Right (RawNumber (toRational number))`.
`parseNumber` (line ~373) wraps `parseYamlNumber` (line ~379), an attoparsec parser that
accepts `0x` hexadecimal, `0o` octal, and decimal/exponent forms and returns a
`Scientific`. Errors in this module are built with the internal helper
`yamlError :: YamlSourceOptions -> YamlErrorCategory -> Maybe Libyaml.YamlMark ->
[PathPiece] -> Text -> YamlSourceError` (line ~450), which records the stable category,
source name, optional file path, one-based line and column, structural context (rendered
like `$.service.port`), and a fixed message. The category to use here,
`YamlInvalidScalar`, already exists in the `YamlErrorCategory` enumeration (line ~52) and
is already used for other bad scalars ("invalid boolean scalar", "invalid or non-finite
numeric scalar").

In `settei-kdl/src/Settei/Kdl.hs`, the function `translateValue` (line ~410) dispatches
on `valueData`, and its `KDL.Number number -> Right (RawNumber (toRational number))`
branch (line ~415) is the unguarded conversion; `KDL.Number` carries a `Scientific`
(verified in the `kdl-hs` source, `KDL/Types.hs`, `Number Scientific`). Errors use the
internal helper `kdlError :: KdlSourceOptions -> KdlErrorCategory -> Maybe KdlSpan ->
Maybe KdlSpan -> [Text] -> Text -> KdlSourceError` (line ~482), which records category,
source name, optional path, a one-based start/end span, an optional related span, the
node path context, and a fixed message. `translateValue` already produces
`KdlUnsupportedValue` errors for non-finite numbers with the value's span via
`valueLocation value` — the new guard reuses exactly that shape. Note that `settei-kdl`'s
cabal file (`settei-kdl/settei-kdl.cabal`) does *not* currently list `scientific` in
`build-depends`; the `Scientific` values arrive transitively through `kdl-hs`. Milestone 2
adds the direct dependency so the module can import `base10Exponent`.

Test layout: each adapter has a tasty suite under `test/` with a behavior module and a
characterization module. `settei-yaml/test/Settei/YamlCharacterizationTest.hs` currently
contains only failure-path tests built on an `expectError :: String -> IO
YamlSourceError` helper around `decodeYamlSource`.
`settei-kdl/test/Settei/KdlCharacterizationTest.hs` has both `expectError` and
`expectSource`/`expectValue` helpers around `decodeKdlSource`, using
`lookupSource`/`candidateValue` from the core to inspect decoded values. New tests go in
these characterization modules; the YAML module gains success-path helpers mirroring the
KDL ones.

Relevant ADRs consulted (all under `docs/adr/`):
`docs/adr/0004-yaml-input-semantics.md` promises that YAML numbers "become exact
`Rational` values through `Scientific`" and that failures carry only category, location,
context, and a fixed safe message, never a raw scalar — this plan amends it with the
exponent bound. `docs/adr/0005-canonical-kdl-v2-input-semantics.md` promises "finite
`Scientific` values convert exactly to `Rational`" with the same secret-safety rule —
also amended here. `docs/adr/0001-haskell-project-conventions.md` governs code style
(strict record fields, postpositive `qualified` imports, lens accessors, explicit direct
dependencies with audited compatible ranges) and applies to every edit in this plan.
No other ADR is relevant.

Parent MasterPlan: `docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md`
(this plan is EP-10 in its registry). Integration constraint to respect: EP-11
(`docs/plans/11-adopt-yaml-1-2-core-schema-boolean-scalars.md`) and EP-13 also edit
`settei-yaml/src/Settei/Yaml.hs`, and EP-11 and EP-13 also amend ADR 0004. This plan
lands first in registry order, and all ADR amendments are append-only dated notes so the
later plans stack their own notes without rewriting this one. This plan changes no
behavior for in-range numbers and adds no new error categories, so the reference
applications and conformance fixtures under `examples/` are not invalidated; EP-14
re-validates everything at the end regardless.

All builds and tests run inside the Nix development shell from the repository root
(`/Users/shinzui/Keikaku/bokuno/settei`), via `nix develop -c cabal ...`.


## Plan of Work

The work is three milestones: guard the YAML adapter with its tests, guard the KDL
adapter with its tests, then reconcile documentation. Each milestone is independently
verifiable with its own test command and ends in its own commit.

### Milestone 1 — Bounded conversion in settei-yaml

Scope: `settei-yaml/src/Settei/Yaml.hs` and
`settei-yaml/test/Settei/YamlCharacterizationTest.hs` only. At the end of this milestone
the YAML adapter rejects out-of-range exponents on all three numeric paths (float tag,
integer tag, untagged plain scalar) with a stable structured error, in-range numbers are
untouched, and the characterization suite proves both, fast.

First extend the `Data.Scientific` import (line ~43, currently
`import Data.Scientific (Scientific)`) to also bring in `base10Exponent`. Then, near the
existing number-parsing functions (around `parseNumber`, line ~373), add a documented
limit constant and a guard helper:

```haskell
-- | Largest absolute base-10 exponent accepted for a numeric scalar.
--
-- 'toRational' materializes @10 ^ exponent@ as an exact 'Integer', so cost grows
-- with the exponent's magnitude rather than the input's length. 4096 is far above
-- any legitimate configuration magnitude yet cheap to materialize. This is a
-- per-scalar, adapter-local acceptance bound, not a core 'RawValue' semantic.
maximumScalarExponent :: Int
maximumScalarExponent = 4096

scalarRational ::
  YamlSourceOptions ->
  [PathPiece] ->
  Libyaml.MarkedEvent ->
  Scientific ->
  Either YamlSourceError Rational
scalarRational options context marked number
  | abs (base10Exponent number) > maximumScalarExponent =
      Left
        ( yamlError
            options
            YamlInvalidScalar
            (Just (startMark marked))
            context
            "numeric scalar exponent is out of the supported range"
        )
  | otherwise = Right (toRational number)
```

The message text is fixed and must never interpolate the scalar. Now route every
`toRational` call on a parsed scalar through this helper. In `scalarValue`, the
`Libyaml.FloatTag` branch becomes:

```haskell
Libyaml.FloatTag ->
  RawNumber <$> (parseNumber options context marked value >>= scalarRational options context marked)
```

In the `Libyaml.NoTag` branch, the numeric pattern guard changes from returning
`Right (RawNumber (toRational number))` to
`RawNumber <$> scalarRational options context marked number` — meaning an untagged
scalar that lexes as a number but exceeds the bound is an error, not text (see Decision
Log). In `parseTaggedInteger`, replace `let rational = toRational number` with a bind
through the guard, keeping the existing whole-number check afterwards:

```haskell
parseTaggedInteger :: YamlSourceOptions -> [PathPiece] -> Libyaml.MarkedEvent -> Text -> Either YamlSourceError RawValue
parseTaggedInteger options context marked value = do
  number <- parseNumber options context marked value
  rational <- scalarRational options context marked number
  if Ratio.denominator rational == 1
    then Right (RawNumber rational)
    else Left (yamlError options YamlInvalidScalar (Just (startMark marked)) context "integer tag requires a whole number")
```

No export-list change: the constant and helper stay internal. The hex and octal parser
branches build integers via `fromInteger`, which yields exponent 0, so they pass the
guard automatically; their cost is proportional to literal length, which is accepted.

Then extend `settei-yaml/test/Settei/YamlCharacterizationTest.hs`. Add success-path
helpers mirroring the KDL characterization module (an `expectSource` that fails the test
on `Left`, and an `expectValue` using `lookupSource`, `validKey`/`parseKey`, and
`candidateValue` from the core — this needs `import Settei` and `import Data.Ratio ((%))`
plus `import Test.Tasty (localOption)` and the tasty `Timeout` machinery). Add a test
group of numeric-bound cases, wrapping the rejection cases in
`localOption (mkTimeout 10000000)` (ten seconds, in microseconds) so a regression fails
loudly instead of hanging CI:

- `huge: 1e1000000000` fails with category `YamlInvalidScalar`, line `Just 1`, context
  `"$.huge"`, and message exactly `"numeric scalar exponent is out of the supported
  range"` (assert all four — this is the stability contract of test requirement (d)).
- `tiny: 1e-1000000000` fails identically.
- `huge: !!float 1e1000000000` and `huge: !!int 1e1000000000` fail with the same
  category and message, proving the tagged float and tagged integer paths are guarded.
- `edge: 1e4096` succeeds and equals `RawNumber (10 ^ (4096 :: Integer) % 1)`;
  `edge: 1e-4096` succeeds and equals `RawNumber (1 % 10 ^ (4096 :: Integer))` —
  boundary values just inside the limit still convert exactly.
- `over: 1e4097` fails — the boundary is exclusive above 4096.
- Exactness regression cases: `rate: 1.5e-3` is `RawNumber (3 % 2000)`, `mask: 0x1A` is
  `RawNumber 26`, `mode: 0o17` is `RawNumber 15`, `port: 8080` is `RawNumber 8080`.

Acceptance: `nix develop -c cabal test settei-yaml-tests --test-show-details=direct`
passes with the new cases listed, completing in normal test time. Commit.

### Milestone 2 — Bounded conversion in settei-kdl

Scope: `settei-kdl/settei-kdl.cabal`, `settei-kdl/src/Settei/Kdl.hs`, and
`settei-kdl/test/Settei/KdlCharacterizationTest.hs`. At the end, the KDL adapter applies
the same bound with its own error vocabulary.

In `settei-kdl/settei-kdl.cabal`, add `scientific >=0.3.7 && <0.4` to the library
stanza's `build-depends` (alphabetical position, matching `settei-yaml`'s bounds — the
package currently gets `Scientific` only transitively via `kdl-hs` and cannot import
`Data.Scientific` without this). The test suite does not need the dependency.

In `settei-kdl/src/Settei/Kdl.hs`, add `import Data.Scientific (base10Exponent)` to the
import block, define the same documented constant `maximumScalarExponent :: Int` with
value `4096` near `translateValue` (deliberately duplicated per adapter; see Decision
Log), and replace the `KDL.Number` branch of `translateValue` (line ~415) with a guarded
pair of branches:

```haskell
KDL.Number number
  | abs (base10Exponent number) > maximumScalarExponent ->
      Left
        ( kdlError
            options
            KdlUnsupportedValue
            (Just (valueLocation value))
            Nothing
            path
            "numeric value exponent is out of the supported range"
        )
  | otherwise -> Right (RawNumber (toRational number))
```

This mirrors the adjacent non-finite-number rejection: same category
(`KdlUnsupportedValue`), same span source (`valueLocation value`), no related span, node
path as context, fixed message. No export-list change.

Extend `settei-kdl/test/Settei/KdlCharacterizationTest.hs` (helpers already exist) with a
numeric-bound group, rejection cases under `localOption (mkTimeout 10000000)`:

- `huge 1e1000000000` fails with category `KdlUnsupportedValue`, a span whose
  `kdlSpanLine` is `Just 1`, and message exactly `"numeric value exponent is out of the
  supported range"` (assert category, message, and span — requirement (d)).
- `tiny 1e-1000000000` fails identically.
- `edge 1e4096` succeeds as `RawNumber (10 ^ (4096 :: Integer) % 1)`; `edge 1e-4096`
  succeeds as `RawNumber (1 % 10 ^ (4096 :: Integer))`; `over 1e4097` fails.
- Exactness regression cases: `rate 1.5e-3` is `RawNumber (3 % 2000)`, `mask 0x1A` is
  `RawNumber 26`, and the existing exact-number test (`12345678901234567890`, `1.25`)
  keeps passing — big coefficients remain accepted.

The error-message assertion needs an accessor: use the existing exported
`kdlErrorMessage`. Acceptance: `nix develop -c cabal test settei-kdl-tests
--test-show-details=direct` passes fast. Commit.

### Milestone 3 — Documentation, changelogs, and full validation

Scope: ADRs, guides, changelogs, MasterPlan bookkeeping, and the full workspace test run.

Amend `docs/adr/0004-yaml-input-semantics.md`: add an `Amended: 2026-07-19` line under
the `Date:` header and append a new section at the end of the file (do not rewrite any
existing text — EP-11 and EP-13 will append their own notes after this one):

```markdown
## Amendment 2026-07-19: bounded numeric scalar exponents

Exact `Rational` conversion is now bounded: a numeric scalar whose parsed base-10
exponent has an absolute value greater than 4096 fails with `YamlInvalidScalar` and
the fixed message "numeric scalar exponent is out of the supported range". The
guard covers the float-tagged, integer-tagged, and untagged numeric paths, because
`toRational` materializes `10 ^ exponent` as an exact `Integer` and an unbounded
exponent lets a fourteen-character scalar hang or out-of-memory a process at load
time. The bound is per-scalar and adapter-local; core `RawNumber` remains an
unbounded exact `Rational`, and literal coefficients of any written length remain
accepted because their cost is proportional to input size.
(docs/plans/10-bound-numeric-scalar-conversion-in-the-yaml-and-kdl-adapters.md)
```

Amend `docs/adr/0005-canonical-kdl-v2-input-semantics.md` the same way (it already has
one `Amended:` line from 2026-07-18; add a second): an analogous appended section stating
that finite `Scientific` values convert exactly only when the absolute base-10 exponent
is at most 4096, and that violations fail with `KdlUnsupportedValue` and the fixed
message "numeric value exponent is out of the supported range".

Update `docs/guides/yaml.md`: the paragraph at lines ~184–187 ("Plain decimal and
exponent numbers ... become exact rational values") gains a sentence stating that numbers
whose base-10 exponent magnitude exceeds 4096 are rejected as `YamlInvalidScalar` so a
single scalar cannot exhaust memory at load time, and that this comfortably covers all
practical configuration values. Update `docs/guides/kdl.md`: the sentence at line ~144
("finite numbers become exact `RawNumber` values") gains the matching KDL note
(`KdlUnsupportedValue`, same bound).

Update `settei-yaml/CHANGELOG.md` and `settei-kdl/CHANGELOG.md`: add a bullet under each
package's existing `0.1.0.0` section (0.1.0.0 has never shipped; see Decision Log), for
example "Reject numeric scalars whose base-10 exponent magnitude exceeds 4096 instead of
attempting an unbounded exact conversion at load time."

Update the parent MasterPlan
`docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md`: set EP-10's
registry Status to Complete and tick its two Progress checkboxes (do this only when the
work is actually done and green).

Acceptance: `nix develop -c cabal test all --test-show-details=direct` from the repo root
passes every suite in the workspace. Commit. Then perform this plan's closing pass:
update Progress, write Outcomes & Retrospective, and confirm the ADR distillation is done
(for this plan, the ADR amendments above *are* the distillation of the exponent-bound
decision; verify nothing else in the Decision Log or Surprises sections is durable
project context before marking complete).


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/settei` inside
the Nix dev shell (`nix develop -c ...`). Work directly on the current branch (`master`)
per the repository's git conventions — no feature branch unless the user asks.

Every commit in this plan must follow the Conventional Commits specification and must
carry these three trailers, exactly:

```text
MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
ExecPlan: docs/plans/10-bound-numeric-scalar-conversion-in-the-yaml-and-kdl-adapters.md
Intention: intention_01kxxdt2f0enp928nc1wbcsd2t
```

Step 1 (optional but valuable evidence): write the Milestone 1 rejection tests *first*
and run them against the unfixed adapter to capture the failure mode. Because the unfixed
code hangs, the ten-second tasty timeout converts the hang into a visible test failure:

```bash
nix develop -c cabal test settei-yaml-tests --test-show-details=direct
```

Expected pre-fix output for the new case (proof the defect is real; keep a snippet in
Surprises & Discoveries):

```text
    huge positive exponents are rejected quickly:          FAIL (10.00s)
      Timed out after 10s
```

If your machine starts swapping instead, interrupt with Ctrl-C — the post-fix run is the
required proof; this pre-fix run is optional.

Step 2: make the Milestone 1 source edits to `settei-yaml/src/Settei/Yaml.hs` exactly as
described in Plan of Work (import `base10Exponent`, add `maximumScalarExponent` and
`scalarRational`, reroute the `FloatTag`, `NoTag`, and `parseTaggedInteger` paths).

Step 3: run the YAML suite and expect every case to pass quickly:

```bash
nix develop -c cabal test settei-yaml-tests --test-show-details=direct
```

Expected output shape (names will match what you wrote; total time must be seconds, not
minutes):

```text
Settei.Yaml.Characterization
  huge positive exponents are rejected quickly:            OK
  huge negative exponents are rejected quickly:            OK
  tagged numeric paths apply the exponent bound:           OK
  boundary exponents inside the limit convert exactly:     OK
  ordinary decimal, hex, and octal scalars stay exact:     OK
...
All N tests passed
```

Step 4: commit Milestone 1:

```bash
git add settei-yaml/src/Settei/Yaml.hs settei-yaml/test/Settei/YamlCharacterizationTest.hs docs/plans/10-bound-numeric-scalar-conversion-in-the-yaml-and-kdl-adapters.md
git commit -m "fix(settei-yaml): bound numeric scalar exponents before Rational conversion" -m "Reject scalars whose base-10 exponent magnitude exceeds 4096 with
YamlInvalidScalar across the float-tagged, integer-tagged, and untagged
paths, so a single scalar like 1e1000000000 can no longer hang or OOM
configuration load. In-range decimals, hex, octal, and negative
exponents still convert exactly." -m "MasterPlan: docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md
ExecPlan: docs/plans/10-bound-numeric-scalar-conversion-in-the-yaml-and-kdl-adapters.md
Intention: intention_01kxxdt2f0enp928nc1wbcsd2t"
```

(Include the plan file in each commit so its Progress checklist moves with the work.)

Step 5: make the Milestone 2 edits (`settei-kdl/settei-kdl.cabal` gains
`scientific >=0.3.7 && <0.4`; `settei-kdl/src/Settei/Kdl.hs` gains the import, constant,
and guarded `KDL.Number` branch; `settei-kdl/test/Settei/KdlCharacterizationTest.hs`
gains the test group), then run:

```bash
nix develop -c cabal test settei-kdl-tests --test-show-details=direct
```

Expect the same shape: all cases `OK`, fast. If cabal cannot resolve `scientific`, you
edited the wrong stanza — the dependency belongs in the `library` stanza's
`build-depends` of `settei-kdl/settei-kdl.cabal`.

Step 6: commit Milestone 2 with subject
`fix(settei-kdl): bound numeric value exponents before Rational conversion`, a body
noting the new direct `scientific` dependency, and the same three trailers.

Step 7: make the Milestone 3 documentation edits (ADR 0004 and 0005 appended dated
amendments, both guide number sections, both changelogs, MasterPlan registry and
Progress), then run the joint suite and the full workspace validation:

```bash
nix develop -c cabal test settei-yaml-tests settei-kdl-tests --test-show-details=direct
nix develop -c cabal test all --test-show-details=direct
```

Both must end with every suite reporting `All N tests passed` (the full run includes the
core, adapter, and example suites; none should be affected beyond the two edited
adapters).

Step 8: commit Milestone 3 with subject
`docs: record the numeric exponent bound for the YAML and KDL adapters` and the same
trailers. Update this plan's living sections (Progress complete, Outcomes &
Retrospective written) either in this commit or a final `docs(plans)` commit, also with
the trailers.


## Validation and Acceptance

The change is accepted when all of the following observable behaviors hold.

Rejection is fast and structured. Decoding the YAML document `huge: 1e1000000000` through
`decodeYamlSource` returns `Left` with one error whose `yamlErrorCategory` is
`YamlInvalidScalar`, `yamlErrorLine` is `Just 1`, `yamlErrorContext` is `"$.huge"`, and
`yamlErrorMessage` is exactly `"numeric scalar exponent is out of the supported range"`.
Decoding the KDL document `huge 1e1000000000` through `decodeKdlSource` returns `Left`
with one error whose `kdlErrorCategory` is `KdlUnsupportedValue`, whose `kdlErrorSpan`
starts at line 1, and whose `kdlErrorMessage` is exactly `"numeric value exponent is out
of the supported range"`. The same holds for `1e-1000000000` in both formats and for the
YAML `!!float`/`!!int` tagged forms. The characterization tests encode all of this, and
their completion within the ten-second tasty timeout is itself the denial-of-service
regression proof: before the fix these inputs hang or exhaust memory, after the fix the
whole suite finishes in seconds. Neither error string contains the digits of the
offending scalar (the fixed messages make this true by construction; the assertions on
exact message text enforce it).

In-range behavior is unchanged and exact. `edge: 1e4096` (YAML) and `edge 1e4096` (KDL)
decode to `RawNumber (10 ^ 4096 % 1)`; the `1e-4096` forms decode to
`RawNumber (1 % 10 ^ 4096)`; `1e4097` is rejected in both. `1.5e-3` decodes to
`RawNumber (3 % 2000)`, YAML `0x1A` and KDL `0x1A` to `RawNumber 26`, YAML `0o17` to
`RawNumber 15`, and the existing huge-coefficient literal test
(`12345678901234567890`) still passes, demonstrating that only the exponent — not the
written length of the number — is bounded.

Test commands and expected results, from `/Users/shinzui/Keikaku/bokuno/settei`:

```bash
nix develop -c cabal test settei-yaml-tests settei-kdl-tests --test-show-details=direct
nix develop -c cabal test all --test-show-details=direct
```

Every suite prints `All N tests passed` and exits zero. A hang, a timeout failure, an
unexpected category/message, or an inexact rational in the boundary cases is a failure.

Documentation acceptance: ADR 0004 and ADR 0005 each carry an appended
`## Amendment 2026-07-19` section describing the bound (earlier text untouched);
`docs/guides/yaml.md` and `docs/guides/kdl.md` number sections mention the 4096 bound and
the error category; both adapter changelogs mention the rejection under `0.1.0.0`; the
MasterPlan registry row for EP-10 reads Complete with its Progress boxes ticked.


## Idempotence and Recovery

Every step is safe to repeat. The source edits are plain-text changes tracked by git:
re-running a test command is always safe, and re-applying an edit that is already present
is a no-op you will notice immediately (the Edit will fail to find the pre-edit text, or
the diff will be empty). Nothing in this plan migrates data, touches state outside the
repository, or is destructive.

If a run of the new rejection tests hangs (a sign the guard is missing or misrouted on
some path), the tasty timeout turns it into a failure after ten seconds; if you ran
without the timeout and the process is consuming memory, interrupt it with Ctrl-C —
nothing is corrupted, fix the guard and rerun. If you find yourself mid-milestone after an
interruption, `git status` and `git diff` show exactly what is staged, and this plan's
Progress checklist records the last completed step; split any half-done checklist entry
into "done" and "remaining" halves before stopping. To abandon an in-progress milestone
cleanly, `git checkout -- <file>` restores any edited file, and completed milestones are
each an independent commit that can be reverted with `git revert <sha>` without
disturbing the others (this independent revertibility is why YAML and KDL land as
separate commits).

The cabal dependency addition in Milestone 2 is additive; if the solver misbehaves,
reverting the single cabal line restores the previous build plan. The ADR amendments are
append-only, so re-running Milestone 3 can at worst duplicate an appended section —
check the end of each ADR before appending.


## Interfaces and Dependencies

Packages and libraries. `scientific` (release line `>=0.3.7 && <0.4`) provides
`Data.Scientific.Scientific`, its safe O(1) inspector `base10Exponent :: Scientific ->
Int`, and the dangerous exact conversion `toRational` (via `Real`) that this plan fences.
`settei-yaml` already depends on it; Milestone 2 adds it to the `settei-kdl` library
stanza in `settei-kdl/settei-kdl.cabal` with those same bounds, per ADR 0001's
direct-dependency and audited-range rules. `libyaml` (YAML events and tags) and `kdl-hs`
(`KDL.Types`, where `ValueData` has `Number Scientific`) are unchanged. `tasty` provides
`localOption` and `mkTimeout` (microseconds) for the timeout-guarded rejection tests;
both test suites already depend on `tasty` and `tasty-hunit`. The core `settei` package
is not modified: `RawNumber !Rational` in `settei/src/Settei/Value.hs` stays unbounded.

Module-level interfaces that must exist at the end of each milestone, all internal (no
export-list changes anywhere):

After Milestone 1, `Settei.Yaml` (in `settei-yaml/src/Settei/Yaml.hs`) contains
`maximumScalarExponent :: Int` equal to 4096 and
`scalarRational :: YamlSourceOptions -> [PathPiece] -> Libyaml.MarkedEvent -> Scientific
-> Either YamlSourceError Rational`, and every path that converts a parsed scalar to
`Rational` — the `Libyaml.FloatTag` branch of `scalarValue`, the numeric guard of its
`Libyaml.NoTag` branch, and `parseTaggedInteger` — goes through `scalarRational`. The
public API (`YamlErrorCategory`, `decodeYamlSource`, accessors) is unchanged.

After Milestone 2, `Settei.Kdl` (in `settei-kdl/src/Settei/Kdl.hs`) contains its own
`maximumScalarExponent :: Int` equal to 4096, and the `KDL.Number` branch of
`translateValue :: KdlSourceOptions -> [Text] -> KDL.Value -> Either KdlSourceError
RawValue` checks `abs (base10Exponent number) > maximumScalarExponent` before
`toRational`, failing with `KdlUnsupportedValue` at `valueLocation value`. The public API
is unchanged.

After Milestone 3, no code interfaces change; the deliverables are the appended dated
amendment sections in `docs/adr/0004-yaml-input-semantics.md` and
`docs/adr/0005-canonical-kdl-v2-input-semantics.md`, the updated number sections in
`docs/guides/yaml.md` and `docs/guides/kdl.md`, the `0.1.0.0` changelog bullets in
`settei-yaml/CHANGELOG.md` and `settei-kdl/CHANGELOG.md`, and the MasterPlan bookkeeping.

Coordination interfaces with sibling plans: EP-11 and EP-13 edit
`settei-yaml/src/Settei/Yaml.hs` after this plan; the new `scalarRational` helper sits
beside `parseNumber` and does not touch `yamlBoolean` or the decode boundary those plans
own. All three plans append dated notes to ADR 0004 in landing order. EP-14 re-runs the
full release validation after everything lands and is the final owner of any golden or
fixture drift (this plan expects none).
