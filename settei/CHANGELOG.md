# Changelog for settei

## 0.1.0.0 — 2026-07-18

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
