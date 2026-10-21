# Bundle Update Log

## 2026-10-21
* **Update**: IR-3 implementation started under plan 28.
* **Update**: IR-1 completed by docs/plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md.
* **Update**: IR-4 accepted after validation against the core resolver and renderer seams and the notification-hub post-resolution checks; targetPlan set to docs/plans/29-integrate-application-validation-into-structured-configuration-diagnostics.md (planned, not yet implemented).
* **Update**: IR-3 accepted after validation against the notification-hub check paths and the Pulumi deployment library; targetPlan set to docs/plans/28-provide-a-reusable-deployment-preflight-harness-around-application-check-mode.md (planned, not yet implemented).
* **Update**: IR-1 accepted; targetPlan set to docs/plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md (planned and reviewed, not yet implemented).
* **Update**: IR-2 accepted after validation against settei-env and the notification-hub bindings; targetPlan set to docs/plans/27-validate-supplied-environment-variable-names-against-declared-bindings.md.
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
