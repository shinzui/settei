---
title: Deployment preflight harness
type: Capability
description: Run application-owned checks against explicitly proposed deployment inputs with controlled secret channels and honest coverage verdicts.
generated:
  by: process:codex
  at: 2026-10-21T15:13:00Z
capabilityId: CAP-15
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.3.0.0"
packages:
  - settei-preflight
interface:
  - Settei.Preflight
  - Settei.Preflight.Request
requires:
  - CAP-7
evidence:
  - kind: test
    resource: settei-preflight/test/Settei/PreflightTest.hs
    proves: Isolation, every coverage classification, execution failures, timeout and pipe cleanup, secret redaction, and deterministic reports.
  - kind: example
    resource: examples/settei-deployment/test/Settei/Example/Deployment/PreflightTest.hs
    proves: Real server and worker precedence, extracted-input mutations, secret channels, and configuration-only startup boundaries.
  - kind: guide
    resource: docs/guides/deployment-preflight.md
    proves: Strict tooling requests, runnable first-deployment checks, extraction assumptions, gate outcomes, and readiness limits.
---

# Deployment preflight harness

`Settei.Preflight` materializes proposed environment and files, runs the application's
check command with a timeout, redacts known secrets, verifies temporary cleanup, and
reports pass, inconclusive, or fail. Only pass passes a gate. Synthetic, unresolved,
unavailable, and unenumerated inputs prevent complete coverage. The strict request
format carries real secrets by environment/file reference. The executable supports text
or version 1 JSON reports and gate exit codes.

Implemented for the next shared 0.3.0.0 release; absent from released 0.2.0.0.
See the [guide](../guides/deployment-preflight.md) and
[ADR-13](../adr/0013-deployment-preflight-harness-semantics.md).

## Limits

- The harness executes a caller-selected command and is not a sandbox. Only tested
  application check paths establish that resource acquisition is skipped.
- Complete proposed-input acceptance does not prove deployed-image identity, actual
  credentials, connectivity, or readiness. Follow with real-input gates and live checks.
- Exact-value redaction requires correctly classified nonempty secrets; transformed,
  partial, or unmarked credentials cannot be recognized. Metadata must be credential-free.
- SIGTERM-resistant children and descendants are not force-killed. Captured output is
  retained in memory. Reports reveal names and topology.
- The reference extractor consumes an already normalized JSON List, not live Kubernetes
  or Pulumi state. Unsupported inputs remain limitations; image entrypoint equivalence
  and supplied-name validation remain separate caller duties.
- Supported execution platforms are Linux and macOS; the POSIX contract does not claim
  Windows support.
