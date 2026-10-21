# Changelog

## 0.3.0.0 — 2026-10-21

- Prepare diagnostics before input acquisition and pass the checked token through
  validation. Start resources directly inside successful `DiagnosticContinue`; static
  requests and every rejected configuration skip startup for both roles.

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
