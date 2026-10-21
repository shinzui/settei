# Bundle Update Log

## 2026-10-21
* **Bootstrap**: Establish the improvement-request bundle under the shared
  `coordination.improvementRequests` profile from
  `mori://shinzui/okf-profiles/profiles/improvement-requests`, pinned to okf-profiles
  v0.22.0. Registered the bundle in `mori.dhall`, added it to the pre-commit
  `okf-documentation-check` hook with strict validation, and linked it from the README.
  No request is recorded yet; planned behavior that lacks shipped repository evidence
  belongs here rather than in the capability catalog.
