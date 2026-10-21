---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Improvement Request

- [Export a deployment configuration contract with bindings and defaults](export-a-deployment-configuration-contract.md) - Combine configuration declarations, environment bindings, default sources, and deployment requirements into a safe contract for authoring a service's first deployment.
- [Integrate application validation into structured configuration diagnostics](integrate-application-validation-into-structured-diagnostics.md) - Represent post-resolution application invariants as safe structured failures shared by startup, check mode, and text or JSON explanations.
- [Provide a reusable deployment preflight workflow using application check mode](provide-a-reusable-deployment-preflight-workflow.md) - Validate proposed container inputs with the application's own configuration checks before first deployment, with explicit handling of secrets and unresolved values.
- [Validate supplied environment variable names against declared bindings](validate-supplied-environment-variable-names.md) - Catch misspelled or unsupported application environment variables before deployment without rejecting unrelated process variables or exposing values.

