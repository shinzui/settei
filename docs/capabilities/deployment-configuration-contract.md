---
title: Deployment configuration contract
type: Capability
description: Export deterministic deployment input bindings, safe default metadata, and explicit profile requirements before reading runtime inputs.
generated:
  by: process:codex
  at: 2026-10-21T20:02:35Z
capabilityId: CAP-14
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.3.0.0"
packages:
  - settei
  - settei-env
  - settei-optparse-applicative
interface:
  - Settei.Contract
  - Settei.Env
  - Settei.Optparse
requires:
  - CAP-1
  - CAP-3
  - CAP-5
  - CAP-7
evidence:
  - kind: test
    resource: settei/test/Settei/ContractTest.hs
    proves: Occurrence-aware verdicts, source precedence and validity, deferred default computations, deterministic rendering, cycle preflight, and secret redaction.
  - kind: example
    resource: examples/settei-deployment/test/Settei/Example/DeploymentTest.hs
    proves: Source-free contract export followed by server and worker checks for incomplete, invalid, and complete proposed production inputs.
  - kind: guide
    resource: docs/guides/deployment-contract.md
    proves: A first-deployment workflow and explicit uncertainty, compatibility, and operational validation boundaries.
---

# Deployment configuration contract

`deploymentContract` joins an existing `Config`, adapter-neutral `InputBinding` values,
explicitly supplied default sources, and an optional `DeploymentProfile`. Text and version
1 `settei.contract` JSON distinguish required, conditional, defaulted, and optional external
inputs independently of merged schema requiredness and presence. Each key retains all its
bindings, default origins and validity, deferred dependency information, and profile reason.

`Settei.Env.inputBindings` exports validated binding metadata. `Settei.Optparse` provides
`--deployment-contract` and `--deployment-contract-json`. Complete application dispatch
uses `prepareDiagnostic mode schema (Just contract)` before all runtime acquisition;
`Nothing` support explicitly rejects either mode. `contractDiagnostic` remains a partial
rendering selector, whose `Nothing` never permits startup. Existing schema and resolution JSON remain unchanged.

This capability was added in the shared 0.3.0.0 release;
0.2.0.0 does not include it. Secret values are redacted before retention. Pure decoders
check winning source defaults, while derived and case computations remain deferred.
Structural inconsistencies are diagnostics; recursive defaults return existing cycle errors.

## Limits

Declaration fallback coverage does not prove that dependencies, computation, or case
selection will succeed. Conditional input may be needed on a selected path. Deployment
profiles describe explicit policy and do not enforce runtime input origin. Application
check mode and operator validation remain responsible for credentials, connectivity,
Kubernetes resources, cross-setting invariants, and wiring. Metadata itself must not
contain secrets. See the [guide](../guides/deployment-contract.md) and
[ADR-12](../adr/0012-deployment-contract-export-semantics.md).
