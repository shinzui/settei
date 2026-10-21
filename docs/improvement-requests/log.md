# Bundle Update Log

## 2026-10-21
* **Add**: IR-2 requests validation of explicitly supplied application environment
  names against declared bindings, with scoped allowances and value-free diagnostics.
* **Add**: IR-3 requests a reusable deployment preflight workflow that runs the actual
  application check mode on proposed container inputs and reports unresolved values
  and unavailable secrets honestly.
* **Add**: IR-4 requests structured post-resolution application validation shared by
  startup, check mode, and text or JSON explanations, preserving safe failure metadata
  and resolution provenance.
* **Add**: IR-1 requests a deployment configuration contract that combines declarations,
  environment bindings, default availability and safe values, and explicit deployment
  requirements. The originating use case is the first Pulumi deployment of
  `mori://tan/notification-hub`; acceptance includes source-based defaults, honest
  uncertainty, secret redaction, and check-mode validation of proposed inputs.
* **Bootstrap**: Establish the improvement-request bundle under the shared
  `coordination.improvementRequests` profile from
  `mori://shinzui/okf-profiles/profiles/improvement-requests`, pinned to okf-profiles
  v0.22.0. Registered the bundle in `mori.dhall`, added it to the pre-commit
  `okf-documentation-check` hook with strict validation, and linked it from the README.
  No request is recorded yet; planned behavior that lacks shipped repository evidence
  belongs here rather than in the capability catalog.
