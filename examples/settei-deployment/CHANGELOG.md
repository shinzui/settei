# Changelog

## Unreleased

- Replace application-local text checks with shared rule declarations and role-specific
  `Validators`; consume `validatedDiagnostic` in every dynamic mode. Successful values,
  acceptance outcomes, source exit 3, and configuration exit 4 are unchanged.
- Rejection wording changes from `workers.visibilityTimeoutSeconds: must be at least
  twice workers.concurrency` to `workers.visibilityTimeoutSeconds, workers.concurrency:
  invariant worker-visibility-covers-concurrency failed: workers.visibilityTimeoutSeconds
  must be at least twice workers.concurrency`.
- JSON explain failures now emit two JSON stderr documents (errors, then resolution with
  invariant outcomes), including on base resolution failures, replacing mixed text/JSON.
  Text explain failures retain winning-source provenance and append the rule trace.
