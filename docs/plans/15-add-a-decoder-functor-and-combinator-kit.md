---
id: 15
slug: add-a-decoder-functor-and-combinator-kit
title: "Add a Decoder functor and combinator kit"
kind: exec-plan
created_at: 2026-07-19T14:54:49Z
intention: "intention_01kxxdt2m8eysvxggq33jsmt2v"
master_plan: "docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md"
---

# Add a Decoder functor and combinator kit

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Settei is a Haskell configuration library about to be adopted by roughly seventy
codebases. Every adopter writes decoders — small functions that turn a raw configuration
value (text, number, array) into a typed application value. Today Settei's `Decoder` type
has no `Functor` instance and no combinators, so even the two reference applications in
this repository hand-roll identical decoders: both write a six-line `secretTextDecoder`
case expression just to wrap decoded text in a newtype, and one writes ten more lines to
decode a list of text. A fleet of seventy codebases would copy-paste the same code.

After this change, a newtype-wrapping decoder is one expression, `SecretText <$>
textDecoder`, and a list decoder is `listDecoder textDecoder`. The plan adds a lawful
`Functor` instance and five combinators (`listDecoder`, `nonEmptyDecoder`,
`parsedDecoder`, `rationalDecoder`, `doubleDecoder`) to the core module
`settei/src/Settei/Value.hs`, improves the failure message of the existing
`boundedIntegralDecoder`, documents `enumDecoder`'s case sensitivity, tests everything
(including the project's secret-safety contract: a failing decode never leaks the raw
value), and proves the ergonomic win by deleting the duplicated decoders from both
reference applications. The proof is observable: after the change, `grep -rn
secretTextDecoder examples/` finds nothing, and `nix develop -c cabal test all
--test-show-details=direct` still passes.

This is EP-15 of the parent MasterPlan
`docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md`. That
MasterPlan runs after
`docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md` completes;
before starting, confirm the correctness MasterPlan is marked Complete (or that its owner
has released EP-15 to start early — EP-15 touches only `Settei.Value` and small example
regions, so a conflict is unlikely but must be checked). Two boundaries from the
MasterPlan's Integration Points govern this plan: EP-19 (declaration sugar) must NOT add
decoder combinators — all decoding sugar belongs here — and EP-21 owns the full rewrite of
the reference applications and guides, so this plan keeps its example and guide edits
minimal and additive.


## Progress

- [ ] Milestone 1: Add `instance Functor Decoder` with a lawfulness haddock to
      `settei/src/Settei/Value.hs`.
- [ ] Milestone 1: Add `listDecoder`, `nonEmptyDecoder`, `parsedDecoder`,
      `rationalDecoder`, `doubleDecoder`, and the private `numberValue` helper, each with
      haddock, and add the five new names to the module export list.
- [ ] Milestone 1: Improve `boundedIntegralDecoder`'s failure expectation to state the
      actual accepted range; document `enumDecoder`'s exact-match case sensitivity and its
      asymmetry with `boolDecoder` in haddock.
- [ ] Milestone 1: `nix develop -c cabal build settei` succeeds with no warnings.
- [ ] Milestone 2: Add test cases to `settei/test/Settei/ValueTest.hs` covering the
      Functor instance (success and failure paths), every new combinator, the improved
      range message, and secret-sentinel safety for `listDecoder` and `parsedDecoder`.
- [ ] Milestone 2: `nix develop -c cabal test settei-tests --test-show-details=direct`
      passes with the new cases listed.
- [ ] Milestone 2: Commit milestones 1 and 2 (feat commit, then test commit, both with
      the required trailers).
- [ ] Milestone 3: Replace `secretTextDecoder` in
      `examples/settei-cli/src/Settei/Example/Cli.hs` with `SecretText <$> textDecoder`
      and delete the hand-rolled definition.
- [ ] Milestone 3: Replace `secretTextDecoder`, `textListDecoder`, and `textElement` in
      `examples/settei-service/src/Settei/Example/Service.hs` with `SecretText <$>
      textDecoder` and `listDecoder textDecoder`.
- [ ] Milestone 3: `nix develop -c cabal test all --test-show-details=direct` passes;
      commit the example refactor with trailers.
- [ ] Milestone 4: Add a "Compose decoders" section to
      `docs/guides/getting-started.md` teaching the combinator kit.
- [ ] Milestone 4: Add an Unreleased section to `settei/CHANGELOG.md`.
- [ ] Milestone 4: Amend `docs/adr/0003-resolution-provenance-and-default-semantics.md`
      with the dated parser-message-discarding redaction rule.
- [ ] Milestone 4: Final `nix develop -c cabal test all --test-show-details=direct` run;
      commit docs with trailers.
- [ ] Wrap-up: update the EP-15 rows in the MasterPlan Progress section, write the
      Outcomes & Retrospective entry here, and confirm the ADR distillation pass is done.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: `listDecoder`'s failure for a non-array input reports the expectation
  `"an array"`; a failing element reports the element decoder's own expectation wrapped
  as `"an array of <element expectation>"` (for example `"an array of text"`).
  Rationale: at failure time the only static description available is the expectation
  text inside the element's `DecodeFailure` — the `Decoder` newtype carries no standalone
  expectation description, and adding one is a larger API change out of scope here.
  Wrapping the element expectation reproduces the operator-friendly message the
  hand-rolled service decoder already used ("an array of text") whenever an element
  actually fails, tells the operator both the container shape and the element shape, and
  composes only expectation strings, which are safe by construction (they never contain
  raw values). The slight asymmetry — a plain `"an array"` when the input is not an array
  at all — is accepted because at that point no element decoder has run and inventing an
  element description would require probing the decoder with fake input.
  Date: 2026-07-19

- Decision: `parsedDecoder` discards the parser's `Left` message entirely; the resulting
  `DecodeFailure` carries only the owning `Key` and the caller-supplied expectation
  description.
  Rationale: parser libraries routinely echo the offending input in their error messages
  (for example "invalid URI: postgres://user:secret@host"). The existing `DecodeFailure`
  contract (ADR 0003) is that decode failures never retain raw values, and a
  parser-produced message is an uncontrolled channel for exactly that leak. Sanitizing
  arbitrary messages reliably is impossible, so the safe policy is total discard. The
  parser type stays `Text -> Either Text a` (rather than `Text -> Maybe a`) so
  applications can reuse the same parser functions in contexts that may display the
  message; Settei simply ignores it. This is durable redaction context, so
  `docs/adr/0003-resolution-provenance-and-default-semantics.md` gains a dated amendment
  in Milestone 4.
  Date: 2026-07-19

- Decision: `doubleDecoder` is `fromRational <$> rationalDecoder` and accepts the
  IEEE-754 round-to-nearest conversion from the exact `Rational`.
  Rationale: configuration doubles are timeouts, ratios, and sample rates, where the
  nearest representable `Double` is exactly what every other configuration system
  delivers; consumers needing exactness use `rationalDecoder` or
  `boundedIntegralDecoder`, and the haddock says so. Both numeric decoders also accept
  textual numbers (mirroring how `integralValue` accepts `RawText` for
  `boundedIntegralDecoder`) because environment variables and command-line arguments only
  carry text.
  Date: 2026-07-19

- Decision: the shared textual-number parser uses `Data.Text.Read.rational` directly,
  not wrapped in `Data.Text.Read.signed` the way `integralValue` wraps `decimal`.
  Rationale: `rational` already consumes an optional leading sign; wrapping it in
  `signed` would accept a doubled sign such as `"--1"` (signed strips one minus, rational
  strips another, yielding positive 1). `decimal` does not consume a sign, which is why
  `integralValue` needs the wrapper and `numberValue` must not copy it.
  Date: 2026-07-19

- Decision: `enumDecoder` keeps exact, case-sensitive matching and gains no
  `caseFoldEnumDecoder`; its haddock documents the case sensitivity and honestly notes
  the asymmetry with `boolDecoder`, which case-folds its textual `"true"`/`"false"`
  forms.
  Rationale: enumeration spellings are part of an application's public configuration
  vocabulary; silently accepting `"Production"` for `"production"` would make documents
  valid under one decoder and invalid under a stricter future one, and applications that
  genuinely want case-insensitivity can now write `enumDecoder` over case-folded input
  via `parsedDecoder` or normalize with the new `Functor`/combinator tools. `boolDecoder`
  predates this plan and case-folds because textual booleans from environment variables
  conventionally arrive as `TRUE`/`True`/`true`; changing it would break existing
  behavior (and a shipped test) for no adopter benefit. Documenting the asymmetry is
  cheaper and more honest than manufacturing consistency in either direction.
  Date: 2026-07-19

- Decision: `boundedIntegralDecoder`'s failure expectation changes from
  `"bounded integer"` to the concrete range, for example
  `"integer between -32768 and 32767"` for `Int16`.
  Rationale: `minBound` and `maxBound` are already in scope in the decoder body, the
  range is what an operator actually needs to fix the value, and a repository-wide search
  confirmed the literal `"bounded integer"` appears only in
  `settei/src/Settei/Value.hs` (no golden file or test asserts on it), so the change is
  safe. The full test suite run in Milestone 3 re-verifies this.
  Date: 2026-07-19

- Decision: the secret-sentinel checks are written as targeted tasty-hunit assertions,
  not property-based tests.
  Rationale: the `settei-tests` suite depends only on `tasty` and `tasty-hunit` (see
  `settei/settei.cabal`); ADR 0003's established adversarial-sentinel technique (a
  fixed sentinel containing quotes, backslashes, control characters, punctuation, and
  non-ASCII text asserted absent from rendered output) already covers the leak channels
  deterministically, and adding a QuickCheck dependency for this one concern is out of
  scope.
  Date: 2026-07-19

- Decision: example edits are strictly the three substitutions listed in Milestone 3;
  the duplicated `publicInteger` renderer helper in the service example is left alone.
  Rationale: the MasterPlan's Integration Points assign the coherent example rewrite to
  EP-21 (`docs/plans/21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md`);
  this plan only removes the decoder duplication its own API makes obsolete, keeping the
  diff minimal so EP-21's rewrite is the single large diff. `publicInteger` is renderer
  plumbing, which is EP-19/EP-21 territory, not decoding.
  Date: 2026-07-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Settei is a multi-package Haskell workspace. The core library lives in `settei/` (Cabal
package `settei`), adapters live in sibling directories (`settei-env/`, `settei-yaml/`,
`settei-kdl/`, `settei-dhall/`, `settei-optparse-applicative/`), and non-published
reference applications live under `examples/` (`examples/settei-cli`,
`examples/settei-service`, `examples/settei-conformance`). The repository root owns
`cabal.project` and the Nix flake; all build and test commands in this plan run from the
repository root inside the Nix development shell (`nix develop -c ...`).

This plan touches one core module, one core test module, two example modules, one guide,
one changelog, and one ADR. Everything else is read-only context.

The module `settei/src/Settei/Value.hs` defines three types that matter here. `RawValue`
is the parser-neutral tree that source adapters produce: constructors `RawNull`,
`RawText`, `RawBool`, `RawNumber` (holding an exact `Rational`), `RawArray`, and
`RawObject`. It deliberately has no `Show` instance because it may contain a secret.
`DecodeFailure` is a record of an owning `Key` (a validated dotted configuration path
such as `service.port`, defined in `settei/src/Settei/Key.hs`) and an `expected ::
Text` description; the rejected raw input is intentionally absent — this is the
secret-safety contract every combinator in this plan must preserve. `Decoder a` is a
newtype around `Key -> RawValue -> Either DecodeFailure a`; the key is threaded in so
failures can name the setting without the decoder author doing anything. The module
currently exports four concrete decoders (`textDecoder`, `boolDecoder`,
`boundedIntegralDecoder`, `enumDecoder`), the constructors-by-function `decoder` and
`decodeFailure`, the accessors `runDecoder` and `decodeFailureExpected`, and
`renderDecodeFailure`. Two private helpers exist at the bottom of the file: `failure`
(shorthand for `Left DecodeFailure {..}`) and `integralValue`, which is the pattern the
new `numberValue` helper mirrors — it accepts a `RawNumber` whose denominator is 1, and
also a `RawText` parsed with `Data.Text.Read.signed Data.Text.Read.decimal` requiring the
entire input to be consumed, so environment variables like `PORT=8080` decode as
integers.

The umbrella module `settei/src/Settei.hs` re-exports `module Settei.Value` (line 15 of
that file), so any name added to `Settei.Value`'s export list is automatically visible to
consumers who `import Settei`; no other export plumbing is needed. The project prelude
`settei/src/Settei/Prelude.hs` re-exports `NonEmpty (..)` from `Data.List.NonEmpty`,
`Text`, `Map`, `Generic`, base's `Prelude`, and the whole `Control.Lens` surface (hiding
lens's `Setting` alias), so `Value.hs` already has `NonEmpty`, `&`, `%~`, and `_Left` in
scope; it also already imports `Data.Generics.Labels ()`, which enables the `#expected`
label lens used below.

The duplication evidence: `examples/settei-cli/src/Settei/Example/Cli.hs` defines
`secretTextDecoder` (around line 328) as a case expression wrapping decoded text in the
example's local `newtype SecretText = SecretText Text` (line 52).
`examples/settei-service/src/Settei/Example/Service.hs` defines an identical
`secretTextDecoder` (around line 377) plus `textListDecoder` and its `textElement`
helper (lines 382–390) for decoding `["a", "b"]`-style tag arrays. Both example modules
`import Settei` wholesale, so the new combinators are in scope with no import edits.
The service module exports its `SecretText` type (module header line 8); that export
stays.

Test layout: the core suite is `settei-tests` (declared in `settei/settei.cabal`,
depends on `tasty` and `tasty-hunit` only). `settei/test/Main.hs` aggregates per-module
test trees; `settei/test/Settei/ValueTest.hs` holds the decoder tests and already
demonstrates the house style: `testCase` assertions, a `decodeSetting` helper from the
public API applied to `Setting` values, a local `validKey` partial parser, and one
secret-leak assertion using `Text.isInfixOf` against `renderDecodeFailure` output.

Relevant ADRs consulted (all under `docs/adr/`):
`docs/adr/0001-haskell-project-conventions.md` mandates GHC2024, the package-local
`common common` stanza (already present — no cabal edits are needed), strict fields,
explicit deriving strategies, lens operators for record access, and postpositive
`qualified` imports; new code must follow these. `docs/adr/0002-inspectable-configuration-algebra.md`
defines the declaration algebra and its observable laws; the law relevant here is
"Decode failures identify the validated setting key and never retain or render the
rejected raw value" — this plan extends the decoder vocabulary but must not weaken that
law, and it must not touch the `Config` algebra (no `Monad`, and per the MasterPlan no
declaration sugar — that is EP-19's territory).
`docs/adr/0003-resolution-provenance-and-default-semantics.md` defines redaction:
raw values never enter reports or structured errors, `RawValue` has no `Show`, and its
Observable Laws section names the adversarial secret-sentinel test technique this plan
reuses. Milestone 4 amends ADR 0003 with the parser-message-discarding rule. No other
ADR is relevant to this work.

One term of art: "haddock" is Haskell's in-source documentation format — comments
beginning `-- |` immediately above a definition, rendered into API docs. "Combinator"
here just means a function that builds a new `Decoder` out of existing ones or out of
plain functions.


## Plan of Work

The work is four milestones. Each is independently verifiable and each ends with the
repository compiling and its tests passing.


### Milestone 1: Functor instance and combinators in Settei.Value

Scope: all edits are inside `settei/src/Settei/Value.hs`. At the end of this milestone
the core library exposes the full combinator kit and improved messages, and
`nix develop -c cabal build settei` succeeds. Nothing else in the repository changes yet.

First, extend the export list at the top of the module. The current list is roughly
alphabetical after the three types; insert the five new names so it reads:

```haskell
module Settei.Value
  ( RawValue (..),
    DecodeFailure,
    Decoder,
    boolDecoder,
    boundedIntegralDecoder,
    doubleDecoder,
    enumDecoder,
    decodeFailure,
    decodeFailureExpected,
    decoder,
    listDecoder,
    nonEmptyDecoder,
    parsedDecoder,
    rationalDecoder,
    renderDecodeFailure,
    runDecoder,
    textDecoder,
  )
where
```

Immediately after the `Decoder` newtype declaration (around line 53), add the `Functor`
instance. It maps over the `Either` result of running the decoder, leaving the key, the
raw value, and any failure untouched. Write it explicitly (not via `deriving stock
Functor`) so the instance carries its own haddock with the one-line law argument:

```haskell
-- | Mapping transforms only a successfully decoded result; failures pass
-- through unchanged.
--
-- The instance is lawful: 'fmap' merely post-composes over the 'Either'
-- result of the wrapped function, so identity and composition follow
-- directly from the 'Functor' laws of @'Either' 'DecodeFailure'@ and of
-- functions.
instance Functor Decoder where
  fmap f (Decoder run) = Decoder (\key raw -> fmap f (run key raw))
```

Next, the combinators. Place them after `textDecoder`/`boolDecoder` alongside the other
public decoders, each with the haddock shown. `listDecoder` decodes a `RawArray` by
traversing its elements left to right with the element decoder at the same `Key`
(Settei keys have no index segments — per ADR 0003 an array is a whole value at its
exact key — so the owning key is the correct and only address for element failures).
`traverse` over `Either` stops at the first failing element. Per the Decision Log, a
failing element's expectation is wrapped as "an array of <element expectation>" using
the `_Left . #expected` lens path (both operators come from `Settei.Prelude`; the
`#expected` label works because the module imports `Data.Generics.Labels ()`), while a
non-array input reports plain "an array":

```haskell
-- | Decode an array by applying the element decoder to every element.
--
-- Elements are decoded left to right and the first failing element stops
-- decoding. An element failure keeps the owning setting key (arrays are
-- whole values at one key) and wraps the element's expectation as
-- @\"an array of \<expectation\>\"@; a non-array input fails with
-- @\"an array\"@. Failures carry only expectation text, never the
-- rejected raw value.
listDecoder :: Decoder a -> Decoder [a]
listDecoder element = Decoder $ \key -> \case
  RawArray values ->
    traverse (runDecoder element key) values
      & _Left . #expected %~ ("an array of " <>)
  _ -> failure key "an array"

-- | Decode a non-empty array with the element decoder.
--
-- An empty array — and any non-array input — fails with
-- @\"a non-empty array\"@; a failing element wraps its expectation as
-- @\"a non-empty array of \<expectation\>\"@.
nonEmptyDecoder :: Decoder a -> Decoder (NonEmpty a)
nonEmptyDecoder element = Decoder $ \key -> \case
  RawArray (firstValue : rest) ->
    traverse (runDecoder element key) (firstValue :| rest)
      & _Left . #expected %~ ("a non-empty array of " <>)
  _ -> failure key "a non-empty array"
```

Note the pattern order in `nonEmptyDecoder`: `RawArray []` falls through to the final
wildcard, which is exactly the empty-array failure required.

`parsedDecoder` is the workhorse for URIs, durations, log levels — any type with a
textual parser. It takes the safe expectation description first and the parser second.
Per the Decision Log, the parser's `Left` message is discarded because it may echo the
(possibly secret) input:

```haskell
-- | Decode a text scalar through a caller-supplied parser.
--
-- The first argument is the safe expectation description reported on any
-- failure, for example @\"an absolute URI\"@ or @\"a duration such as 30s\"@.
-- The parser's own error message is deliberately discarded: parser messages
-- routinely echo the offending input, and decode failures must never retain
-- the raw value. Non-text inputs fail with the same description.
parsedDecoder :: Text -> (Text -> Either Text a) -> Decoder a
parsedDecoder expected parse = Decoder $ \key -> \case
  RawText value -> case parse value of
    Right parsed -> Right parsed
    Left _ -> failure key expected
  _ -> failure key expected
```

The numeric decoders share a private `numberValue` helper that mirrors `integralValue`
(bottom of the file, around line 120): accept `RawNumber` directly, and accept `RawText`
for environment-variable friendliness by parsing with `Data.Text.Read.rational` and
requiring the whole input to be consumed. Do not wrap `rational` in `TextRead.signed`:
unlike `decimal`, `rational` already consumes an optional leading sign, and stacking
`signed` on top would accept a doubled sign such as `"--1"` (see Decision Log). Add
`numberValue` next to `integralValue`:

```haskell
-- | Decode an exact rational number.
--
-- Accepts a native number or, for environment-variable and command-line
-- friendliness, a textual number such as @\"2.5\"@, @\"-3\"@, or @\"1e-3\"@
-- (mirroring how 'boundedIntegralDecoder' accepts textual integers).
-- Decimal text converts exactly; no rounding occurs.
rationalDecoder :: Decoder Rational
rationalDecoder = Decoder $ \key value ->
  maybe (failure key "a number") Right (numberValue value)

-- | Decode an IEEE double-precision number.
--
-- Equivalent to @'fromRational' \<$\> 'rationalDecoder'@: the exact source
-- value is rounded to the nearest representable 'Double'. That rounding is
-- acceptable for configuration values such as timeouts and ratios; use
-- 'rationalDecoder' or 'boundedIntegralDecoder' when exactness matters.
doubleDecoder :: Decoder Double
doubleDecoder = fromRational <$> rationalDecoder
```

and the helper, beside `integralValue`:

```haskell
numberValue :: RawValue -> Maybe Rational
numberValue = \case
  RawNumber value -> Just value
  RawText value -> case TextRead.rational value of
    Right (candidate, rest)
      | Text.null rest -> Just candidate
    _ -> Nothing
  _ -> Nothing
```

(`doubleDecoder` is itself the first in-tree use of the new `Functor` instance.)

Then improve `boundedIntegralDecoder`. Replace its body so the failure names the actual
range; `minBound`/`maxBound` are already usable via the existing `forall a.` and
`TypeApplications`-style `@a` in the module:

```haskell
-- | Decode a whole number that fits the requested bounded integral type.
--
-- Accepts a native whole number or a textual integer. Failures state the
-- accepted range, for example @\"integer between -32768 and 32767\"@.
boundedIntegralDecoder :: forall a. (Bounded a, Integral a) => Decoder a
boundedIntegralDecoder = Decoder $ \key value ->
  case integralValue value of
    Just candidate
      | candidate >= lower && candidate <= upper -> Right (fromInteger candidate)
    _ -> failure key expectedRange
  where
    lower = toInteger (minBound @a)
    upper = toInteger (maxBound @a)
    expectedRange =
      "integer between "
        <> Text.pack (show lower)
        <> " and "
        <> Text.pack (show upper)
```

A repository search confirmed the old literal `"bounded integer"` appears nowhere else
(no golden file or test asserts on it), so this message change is contained; the full
`cabal test all` run in Milestone 3 is the backstop.

Finally, replace `enumDecoder`'s haddock (code unchanged):

```haskell
-- | Decode one of a finite set of exact text spellings.
--
-- Matching is case-sensitive: @\"Production\"@ does not match a declared
-- @\"production\"@ choice. This is deliberate — enumeration spellings are
-- part of an application's configuration vocabulary. Note the asymmetry
-- with 'boolDecoder', which case-folds its textual @true@/@false@ forms
-- for environment-variable convention; enumerations do not follow it.
-- Applications wanting case-insensitive enumerations can normalize input
-- via 'parsedDecoder'.
```

Acceptance for this milestone: `nix develop -c cabal build settei` from the repository
root compiles with no warnings (the project builds with `-Wall -Wcompat`).


### Milestone 2: Tests for the whole kit

Scope: all edits are inside `settei/test/Settei/ValueTest.hs`; the suite runner
`settei/test/Main.hs` and `settei/settei.cabal` already reference this module, so no
registration is needed. At the end, `nix develop -c cabal test settei-tests
--test-show-details=direct` passes and lists the new cases.

Extend the module's imports with `Data.Int (Int16)` and `Data.Ratio ((%))` (both from
`base`), then add the following cases to the existing `testGroup` list and the sentinel
definition after the existing helper definitions. The sentinel follows ADR 0003's
adversarial recipe: quotes, backslash, a control character, punctuation, and non-ASCII
text. Every new combinator gets at least one success case, one failure-message case, and
the two decoders that route attacker-controlled text through failures (`listDecoder`
wrapping element expectations, `parsedDecoder` receiving a parser that echoes its
input) get explicit sentinel-absence assertions:

```haskell
      testCase "fmap maps a successful decode" $
        runDecoder (Text.toUpper <$> textDecoder) exampleKey (RawText "hello")
          @?= Right "HELLO",
      testCase "fmap passes failures through unchanged" $
        case runDecoder (Text.toUpper <$> textDecoder) exampleKey (RawBool True) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue -> decodeFailureExpected failureValue @?= "text",
      testCase "listDecoder decodes arrays element-wise" $
        runDecoder (listDecoder textDecoder) exampleKey (RawArray [RawText "a", RawText "b"])
          @?= Right ["a", "b"],
      testCase "listDecoder rejects non-arrays" $
        case runDecoder (listDecoder textDecoder) exampleKey (RawText "a") of
          Right _ -> fail "expected decoding to fail"
          Left failureValue -> decodeFailureExpected failureValue @?= "an array",
      testCase "listDecoder wraps element expectations" $
        case runDecoder (listDecoder textDecoder) exampleKey (RawArray [RawText "a", RawBool True]) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue -> decodeFailureExpected failureValue @?= "an array of text",
      testCase "nonEmptyDecoder decodes non-empty arrays" $
        runDecoder (nonEmptyDecoder textDecoder) exampleKey (RawArray [RawText "a", RawText "b"])
          @?= Right ("a" :| ["b"]),
      testCase "nonEmptyDecoder rejects empty arrays" $
        case runDecoder (nonEmptyDecoder textDecoder) exampleKey (RawArray []) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue -> decodeFailureExpected failureValue @?= "a non-empty array",
      testCase "parsedDecoder applies the parser" $
        runDecoder portFromText exampleKey (RawText "8080") @?= Right (8080 :: Int),
      testCase "parsedDecoder reports only the caller's expectation" $
        case runDecoder portFromText exampleKey (RawText sentinel) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue ->
            decodeFailureExpected failureValue @?= "a port number",
      testCase "parsedDecoder discards parser messages that echo input" $
        case runDecoder portFromText exampleKey (RawText sentinel) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue ->
            assertBool
              "rendered failure leaked the parser input"
              (not (Text.isInfixOf sentinel (renderDecodeFailure failureValue))),
      testCase "listDecoder element failures never leak the value" $
        case runDecoder (listDecoder boolDecoder) exampleKey (RawArray [RawText sentinel]) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue ->
            assertBool
              "rendered failure leaked the array element"
              (not (Text.isInfixOf sentinel (renderDecodeFailure failureValue))),
      testCase "rationalDecoder accepts numbers and numeric text" $ do
        runDecoder rationalDecoder exampleKey (RawNumber (5 % 2)) @?= Right (5 % 2)
        runDecoder rationalDecoder exampleKey (RawText "2.5") @?= Right (5 % 2)
        runDecoder rationalDecoder exampleKey (RawText "-3") @?= Right (negate 3),
      testCase "rationalDecoder rejects trailing garbage" $
        case runDecoder rationalDecoder exampleKey (RawText "1.5x") of
          Right _ -> fail "expected decoding to fail"
          Left failureValue -> decodeFailureExpected failureValue @?= "a number",
      testCase "doubleDecoder rounds through the exact rational" $ do
        runDecoder doubleDecoder exampleKey (RawText "2.5") @?= Right 2.5
        runDecoder doubleDecoder exampleKey (RawNumber (1 % 10)) @?= Right 0.1,
      testCase "boundedIntegralDecoder reports its range" $
        case runDecoder (boundedIntegralDecoder :: Decoder Int16) exampleKey (RawNumber 100000) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue ->
            decodeFailureExpected failureValue @?= "integer between -32768 and 32767"
```

with these helpers added near the existing `exampleKey`/`validKey` definitions:

```haskell
portFromText :: Decoder Int
portFromText =
  parsedDecoder "a port number" $ \value ->
    case runDecoder (boundedIntegralDecoder :: Decoder Int) exampleKey (RawText value) of
      Right port -> Right port
      Left _ -> Left ("could not parse port from input: " <> value)

sentinel :: Text
sentinel = "s3cr3t\"\\\SOH!☃パス"
```

`portFromText`'s parser deliberately echoes its input in its `Left` message — that is
the point of the sentinel tests: the echo must never survive into the rendered failure.
(Any implementation of the parser is fine as long as the `Left` branch embeds `value`;
the version above reuses the integral decoder just to avoid new imports.)

Also update the existing "bounded integral" failure expectations if any prove to exist —
the current `ValueTest.hs` only asserts a successful integral decode, so no existing case
should change.

Acceptance: `nix develop -c cabal test settei-tests --test-show-details=direct` prints
each new case with `OK` and ends with all tests passing. Then make the two commits
described in Concrete Steps.


### Milestone 3: Delete the duplicated example decoders

Scope: two files, three substitutions, nothing else. This is the proof that the kit pays
for itself, kept minimal because EP-21 owns the full example rewrite.

In `examples/settei-cli/src/Settei/Example/Cli.hs`, change `tokenSetting` (around line
326) to use the Functor instance and delete `secretTextDecoder` entirely:

```diff
-tokenSetting = secretSetting serviceTokenKey "Service authentication token" secretTextDecoder
-
-secretTextDecoder :: Decoder SecretText
-secretTextDecoder = decoder $ \key -> \case
-  RawText value -> Right (SecretText value)
-  _ -> Left (decodeFailure key "text")
+tokenSetting =
+  secretSetting serviceTokenKey "Service authentication token" (SecretText <$> textDecoder)
```

In `examples/settei-service/src/Settei/Example/Service.hs`, make the same substitution
for `databasePasswordSetting` (around line 368), point `serviceTagsSetting` (around line
371) at `listDecoder textDecoder`, and delete `secretTextDecoder`, `textListDecoder`,
and `textElement` (lines 377–390):

```diff
-databasePasswordSetting = secretSetting databasePasswordKey "Database password" secretTextDecoder
+databasePasswordSetting =
+  secretSetting databasePasswordKey "Database password" (SecretText <$> textDecoder)

-serviceTagsSetting = publicSetting serviceTagsKey "Conformance service tags" textListDecoder
+serviceTagsSetting =
+  publicSetting serviceTagsKey "Conformance service tags" (listDecoder textDecoder)
```

Both modules `import Settei` unqualified, so the new names are already in scope; no
import edits are required. The `SecretText` newtype stays where it is in each example
(EP-21 may consolidate it later). Leave `publicInteger` and every renderer helper
untouched (Decision Log). One observable behavior change to be aware of: the service's
hand-rolled list decoder reported `"an array of text"` even for non-array input, while
`listDecoder` reports `"an array"` in that case and `"an array of text"` on element
failure; a repository search found no test or golden asserting the old message, and the
full-suite run below is the backstop.

Acceptance: `grep -rn "secretTextDecoder\|textListDecoder\|textElement"
examples/` returns nothing, and `nix develop -c cabal test all
--test-show-details=direct` passes every suite in the workspace (core, all five
adapters, and the example/conformance suites). Commit with the trailers.


### Milestone 4: Guide, changelog, and ADR amendment

Scope: `docs/guides/getting-started.md`, `settei/CHANGELOG.md`, and
`docs/adr/0003-resolution-provenance-and-default-semantics.md`.

In the guide, insert a new `## Compose decoders` section between the existing
`## Declare application types and settings` and `## Compose the declaration` sections.
Keep it compact — EP-21 does the coherent docs sweep — roughly (the outer fence below
uses four backticks so the guide's own Haskell fences can appear inside it verbatim):

````markdown
## Compose decoders

Decoders compose, so most applications never write a raw case expression.
`Decoder` is a `Functor`: wrap a decoded value in a newtype or transform it
with `<$>`:

```haskell
newtype SecretText = SecretText Text

apiTokenDecoder :: Decoder SecretText
apiTokenDecoder = SecretText <$> textDecoder
```

Decode arrays with `listDecoder` and `nonEmptyDecoder`:

```haskell
tagsDecoder :: Decoder [Text]
tagsDecoder = listDecoder textDecoder
```

Decode any type with a textual parser using `parsedDecoder`. Its first
argument is the expectation shown on failure; the parser's own error message
is discarded so a failure can never echo a (possibly secret) input value:

```haskell
listenUriDecoder :: Decoder Uri
listenUriDecoder = parsedDecoder "an absolute URI" parseAbsoluteUri
```

Numbers decode with `boundedIntegralDecoder` (whole numbers with an explicit
range in failures), `rationalDecoder` (exact), and `doubleDecoder` (rounded
to the nearest `Double`). All numeric decoders also accept textual numbers,
so the same declaration works for environment variables and file formats.
`enumDecoder` matches spellings case-sensitively.
````

In `settei/CHANGELOG.md`, add an Unreleased section above the 0.1.0.0 entry:

```markdown
## Unreleased

- Add a `Functor` instance for `Decoder`; a newtype-wrapping decoder is now
  `SecretText <$> textDecoder`.
- Add decoder combinators `listDecoder`, `nonEmptyDecoder`, `parsedDecoder`,
  `rationalDecoder`, and `doubleDecoder`, all preserving the secret-safe
  failure contract (failures carry only the setting key and an expectation).
- `boundedIntegralDecoder` failures now state the accepted range, for example
  `integer between -32768 and 32767`.
- Document `enumDecoder`'s case-sensitive matching.
```

In `docs/adr/0003-resolution-provenance-and-default-semantics.md`, the
`parsedDecoder` message-discarding policy is durable redaction context, so record it as
a dated amendment: add `Amended: 2026-07-19` beneath the `Date:` line at the top, and
append this paragraph to the end of the redaction paragraph in the Decision section (the
paragraph beginning "Redaction is applied before data enters a report or structured
error."):

```markdown
Amendment 2026-07-19: parser-backed decoding treats a parser's own error
message as potentially value-bearing, because parsers routinely echo their
input. `parsedDecoder` therefore discards the parser's message entirely; a
decode failure carries only the owning key and the caller-supplied
expectation description.
```

Acceptance: a final `nix develop -c cabal test all --test-show-details=direct` passes,
and the docs commit lands with the trailers. Then perform the wrap-up items in Progress:
tick the two EP-15 rows in the MasterPlan's Progress section (and set the EP-15 registry
row to Complete), write the Outcomes & Retrospective entry here, and confirm no further
ADR distillation is owed (the ADR 0003 amendment in this milestone is the distillation
for this plan; the remaining decisions are decoder-local API documentation already
captured in haddock).


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/settei`,
inside the Nix shell wrapper shown. Before starting, confirm the prerequisite MasterPlan
state and a clean tree:

```bash
git status --short
git log --oneline -5
```

Build after Milestone 1:

```bash
nix develop -c cabal build settei
```

Expected tail of output (module list and versions will vary):

```text
Building library for settei-0.1.0.0...
[..] Compiling Settei.Value
...
```

with no warnings. Test after Milestone 2:

```bash
nix develop -c cabal test settei-tests --test-show-details=direct
```

Expected shape of output:

```text
Settei
  Settei.Value
    text values decode:                          OK
    ...
    fmap maps a successful decode:               OK
    listDecoder decodes arrays element-wise:     OK
    parsedDecoder discards parser messages that echo input: OK
    boundedIntegralDecoder reports its range:    OK
  ...
All NN tests passed
Test suite settei-tests: PASS
```

Any `FAIL` line means an assertion mismatch; the printed expected/actual pair names the
offending case.

Full workspace test after Milestone 3 and again after Milestone 4:

```bash
nix develop -c cabal test all --test-show-details=direct
```

Every suite must end with `PASS`. Also verify the duplication is gone:

```bash
grep -rn "secretTextDecoder\|textListDecoder\|textElement" examples/ ; echo "exit: $?"
```

Expected output is only `exit: 1` (grep found nothing).

Commit protocol: every commit uses the Conventional Commits format
(`type(scope): summary`) and carries these three trailers, exactly:

```text
MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/15-add-a-decoder-functor-and-combinator-kit.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

Commit directly on the current branch (no feature branch unless the user asks). The
planned commits, one per completed unit of work:

```text
feat(value): add Decoder Functor instance and combinator kit

Add fmap over the decode result plus listDecoder, nonEmptyDecoder,
parsedDecoder, rationalDecoder, and doubleDecoder; state the accepted
range in boundedIntegralDecoder failures; document enumDecoder case
sensitivity. All failures keep the secret-safe contract: only the owning
key and an expectation description, never the raw value.

MasterPlan: docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md
ExecPlan: docs/plans/15-add-a-decoder-functor-and-combinator-kit.md
Intention: intention_01kxxdt2m8eysvxggq33jsmt2v
```

then `test(value): cover the decoder combinator kit and secret sentinels`, then
`refactor(examples): replace hand-rolled decoders with the combinator kit`, then
`docs: teach the decoder combinator kit and amend ADR 0003` — each body written in the
same style with the same three trailers. Update this plan's Progress section (and any
other living section that changed) before or with each commit; committing the plan file
updates together with the corresponding code change is preferred so the history stays
self-explaining.


## Validation and Acceptance

The change is accepted when all of the following observable behaviors hold.

First, the ergonomic win itself: in GHCi (`nix develop -c cabal repl settei`), the
one-line newtype decoder works end to end —

```haskell
ghci> import Settei.Value
ghci> import Settei.Key
ghci> newtype Wrapped = Wrapped Text deriving Show
ghci> Right key = parseKey "example.value"
ghci> runDecoder (Wrapped <$> textDecoder) key (RawText "hello")
Right (Wrapped "hello")
```

Second, the secret-safety contract: a failing decode of a sentinel-bearing raw value
never shows the sentinel. This is enforced by the two new sentinel test cases
("parsedDecoder discards parser messages that echo input" and "listDecoder element
failures never leak the value") plus the pre-existing case in `ValueTest.hs`; all must
print `OK` under:

```bash
nix develop -c cabal test settei-tests --test-show-details=direct
```

Third, failure messages are the decided ones, verified by the message-equality cases:
`"an array"`, `"an array of text"`, `"a non-empty array"`, `"a number"`, the caller's
`parsedDecoder` description verbatim, and `"integer between -32768 and 32767"` for
`Int16`.

Fourth, the fleet-facing proof: both reference applications compile and pass their
suites using only library combinators for text-wrapping and list decoding —
`grep -rn "secretTextDecoder" examples/` finds nothing, and

```bash
nix develop -c cabal test all --test-show-details=direct
```

ends with `PASS` for every suite in the workspace (this also re-validates the adapter
suites that use `boundedIntegralDecoder` against the new message, and the conformance
example that resolves the tags array through `listDecoder`).

Fifth, docs: `docs/guides/getting-started.md` contains the "Compose decoders" section,
`settei/CHANGELOG.md` has the Unreleased entries, and
`docs/adr/0003-resolution-provenance-and-default-semantics.md` carries the dated
2026-07-19 amendment. A test failing before Milestone 2's code existed and passing after
is not required here because the combinators are new API; the before/after evidence is
instead the deleted example code, whose behavior is retained by the untouched example
test suites.


## Idempotence and Recovery

Every step is an ordinary source edit followed by a build or test run, so the whole plan
is idempotent: re-running any build or test command is always safe, and re-applying an
edit that is already present is a no-op (verify with `git diff` before committing). No
migrations, generated files, or destructive operations are involved; golden files under
`settei/test/golden/` are not expected to change (they contain the expectation text
`"boolean"`, which this plan does not alter), so if a golden test fails, treat it as a
regression to investigate rather than a golden to regenerate.

If a milestone breaks the build midway, `git status` and `git diff` show exactly what
changed since the last commit; `git stash` or `git checkout -- <file>` restores the last
good state. Because each milestone ends in its own commit, recovery after a bad commit is
`git revert <sha>` — never rewrite published history. If `cabal test all` fails only in
an example or adapter suite after Milestone 3, the likely cause is an assertion on the
old failure-message text; fix the assertion to the new decided message (Decision Log)
rather than weakening the message, and record the find in Surprises & Discoveries. If
the tree at start-of-work differs from what this plan describes (for example the
correctness MasterPlan's EP work moved code in `Settei.Value`), re-read the module first,
adapt line references — the plan's anchors are names, not line numbers — and note the
drift in Surprises & Discoveries.


## Interfaces and Dependencies

No new package dependencies are added anywhere: everything uses `base`
(`Data.List.NonEmpty`, `Data.Ratio`, `Data.Int` in tests), `text`
(`Data.Text.Read.rational`), and the already-present `lens`/`generic-lens` surface
re-exported by `Settei.Prelude`. No `.cabal` file changes; no cabal.project, flake, or
Nix changes. The examples pick up the new API through their existing `settei` dependency
and wholesale `import Settei`.

At the end of Milestone 1, the module `Settei.Value` (and therefore the umbrella module
`Settei`, which re-exports it) must expose exactly these additional public names with
these signatures, plus the instance:

```haskell
instance Functor Decoder

listDecoder :: Decoder a -> Decoder [a]
nonEmptyDecoder :: Decoder a -> Decoder (NonEmpty a)
parsedDecoder :: Text -> (Text -> Either Text a) -> Decoder a
rationalDecoder :: Decoder Rational
doubleDecoder :: Decoder Double
```

`numberValue :: RawValue -> Maybe Rational` remains private to `Settei.Value`. The
existing public signatures (`textDecoder`, `boolDecoder`, `boundedIntegralDecoder`,
`enumDecoder`, `decoder`, `decodeFailure`, `decodeFailureExpected`, `runDecoder`,
`renderDecodeFailure`) are unchanged; only `boundedIntegralDecoder`'s failure text and
`enumDecoder`'s documentation change. `DecodeFailure` and `Decoder` stay abstract
(constructors unexported), and `Decoder` gains no `Applicative`, `Alternative`, or
`Monad` instance in this plan — a decoder has exactly one raw value to decode, and
richer structure is a deliberate future decision, not an accident of this kit. Downstream
plans that rely on these interfaces: EP-21
(`docs/plans/21-extend-reusable-cli-options-and-complete-the-ergonomics-docs-sweep.md`)
consumes the combinators in its full example-and-guides rewrite, and EP-19
(`docs/plans/19-add-declaration-sugar-for-conditionals-and-rendered-defaults.md`) must
not add decoder combinators of its own — any decoding-sugar need discovered there routes
back to this plan via the MasterPlan's Integration Points.
