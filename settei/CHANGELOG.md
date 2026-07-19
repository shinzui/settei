# Changelog for settei

## Unreleased

- `Settei.Prelude` is now documented as internal to the settei package family and is
  excluded from the PVP-stable public surface; adopters should import the documented
  public modules instead. Its exports track the `lens` package and may change in any
  release.
- Add a `Functor` instance for `Decoder`; a newtype-wrapping decoder is now
  `SecretText <$> textDecoder`.
- Add decoder combinators `listDecoder`, `nonEmptyDecoder`, `parsedDecoder`,
  `rationalDecoder`, and `doubleDecoder`, all preserving the secret-safe
  failure contract (failures carry only the setting key and an expectation).
- `boundedIntegralDecoder` failures now state the accepted range, for example
  `integer between -32768 and 32767`.
- Document `enumDecoder`'s case-sensitive matching.
- Add `whenConfig`, `whenEq`, and `fallbackTo` to `Settei.Config`. Each combinator
  desugars to the existing `Functor` and `Selective` operations without changing the
  inspectable declaration algebra.
- Add `publicShowSetting` and `withRenderer` to `Settei.Setting` for concise typed-default
  rendering; secret settings continue to redact regardless of attached renderers.

## 0.1.0.0 — 2026-07-19

- Initial experimental release.
- Add inspectable Applicative and Selective configuration declarations.
- Add hierarchical resolution, ordered provenance, named defaults, secret-safe errors,
  static schemas, and versioned text and JSON reports.
- Merge duplicate setting sensitivities most-restrictively in schemas and reports, so a
  key declared `Secret` anywhere cannot be weakened by a conflicting `Public`
  declaration; add `redactReportedValue` as a one-way collapse of any retained display
  representation to the redaction marker.
- Add the structured `SensitivityConflict` resolution error for mixed-sensitivity keys,
  rendered in JSON with the additive `sensitivity-conflict` kind.
- Breaking: `resolve` now returns `ResolveResult` unconditionally. The typed outcome
  moved to its `answer` field, while the provenance report and warnings are available
  for every resolution attempt, including failures.
- Make repeated `annotateSource` calls merge source-wide annotations, with annotations
  from later calls winning on name collisions.
- Add `sourceFromPairs`, `SourceConstructionError`, and
  `sourceUnaddressableLeaves` for validated custom-source construction and inspection.
- Render exact terminating rational values as decimals in reports while retaining exact
  fraction notation for non-terminating values.
