---
type: Architecture Decision Record
title: Run deployment preflight through application-owned check commands
description: Define controlled preflight execution, strict secret references, honest coverage verdicts, cleanup, and tooling document compatibility.
timestamp: 2026-10-21T15:13:00Z
docId: ADR-13
status: Accepted
date: 2026-10-21
generated:
  by: process:codex
  at: 2026-10-21T15:13:00Z
---

# ADR 0013: Run deployment preflight through application-owned check commands

## Context

Deployment tooling assembles literal values, secret references, generated values, files,
and overrides before provisioning. Reimplementing application rules in infrastructure
would drift. The [deployment contract](0012-deployment-contract-export-semantics.md)
helps discover inputs, while actual acceptance belongs to the application's normal
configuration path. The [reference application boundary](0007-reference-applications-are-the-public-api-conformance-boundary.md)
proves check mode exits before resource acquisition.

## Decision

Ship `settei-preflight` as a sibling package depending only on core and environment
packages within the family. `Settei.Preflight` runs a chosen executable and check args;
it contains no configuration decoder, default, or application invariant. The deployment
example converts a normalized rendered Kubernetes JSON List into that generic interface,
with no Kubernetes client or Pulumi SDK.

Every proposed value is supplied public/secret, synthetic public/secret, unresolved, or
unavailable secret. Only supplied and synthetic values reach the child. Each omitted
input and every extraction note remains a coverage limitation. An accepted child yields
`pass` only with complete supplied coverage and no notes; otherwise `inconclusive`,
explicitly not a deployment validation. Any child rejection or harness failure yields
`fail`. Only pass gates successfully. The default child exit mapping is 0 accepted,
2 usage, 3 source failure, 4 configuration rejected, others unknown; callers may replace
it with disjoint codes. Harness CLI exits are 0 pass, 1 inconclusive, 2 usage,
3 harness failure, and 4 application rejection.

`Settei.Preflight.Request` owns strict `settei.preflight-request` version 1. Real secrets
use references to harness environment or files; inline values are public and inline
synthetic credentials must be fake. Unknown keys, conflicting forms, and unsafe options
fail with fixed messages and schema paths. Neither parser exceptions nor secret-file
read errors retain upstream diagnostic text. Raw request, input, and captured-output
types have no Show. Metadata must contain no unclassified credentials.

The child's environment starts empty and includes present proposed entries plus an
explicit inherited allowlist. Defaults are PATH and three locale names; a supplied
allowlist replaces them. Proposed/inherited overlap is invalid. Runtime-added variables,
such as macOS CoreFoundation's own encoding variable, are outside the spawn contract.
Bare executables resolve on the harness PATH and relative executables in its working
directory before entering the private input directory. No shell is invoked.

Proposed files are untrimmed UTF-8 in a 0700 temporary directory. Reject traversal,
file/parent conflicts, and undeclared references. Create referenced directories even when
all their files are omitted. Explicitly remove and verify absence before returning
success; cleanup failure blocks the gate, with temporary-library cleanup as fallback.
The executable and fully assembled arguments cannot contain known nonempty secrets.

Read stdout and stderr concurrently as bytes, decode lenient UTF-8, and redact exact
known nonempty secrets before constructing reports, including metadata and error fields.
Match longest first with stable ties, across chunks, without rescanning inserted markers;
secret-bearing input names use numeric markers. Private captured output has no Show.
This cannot recognize transformed or mislabeled secrets. Reports reveal names/topology.

Timeout covers process completion and both pipe drains. Scope reader threads within the
process bracket, cancel and join them before closing handles, and observe reader failures
without waiting indefinitely for child exit. Request termination through process cleanup's
SIGTERM and report timeout; do not claim resistant children or descendants are killed.
A private process seam supports deterministic failure injection and a retained-pipe test
that explicitly reaps its controlled retainer. It is not public API.

The request and `settei.preflight` report are tooling formats encoded with Aeson in fixed
pair order, pinned by byte-identical goldens on both supported Aeson lines. They are
outside the core's no-parser-dependency serialization rule in
[ADR-3](0003-resolution-provenance-and-default-semantics.md). Closed request schemas require
a new version for added or changed fields/forms; version 1 has no ignorable note field.

## Consequences

The deployment example proves file/environment/CLI precedence, equal in-process and
subprocess results, role-specific rejection, extraction mutation failures, and startup
instrumentation. Unsupported extraction remains visible and cannot pass a gate. Host
executable/image entrypoint equivalence remains a caller obligation. The harness is not
a sandbox; it cannot vouch for arbitrary commands, connectivity, authentication, image
identity, or readiness. Check supplied names separately; an unbound renamed variable can
remain invisible. Follow pre-provisioning checks with actual-input init-container gating
and live readiness/integration checks. Linux and macOS are the supported execution targets;
POSIX permissions/signals do not establish Windows support. Captured output stays in
memory, so check commands must be trusted and have bounded output.

## Rejected alternatives

A Haskell-only interface would leave deployment tooling without an interchange document.
Inline real secrets with warnings would put credentials into retained request artifacts.
Inheriting the full environment would let ambient application variables fill omissions.
Parsing application diagnostics before structured validation exists would couple the
harness to application output. Force-killing descendants would add a process-supervision
guarantee beyond this harness. Pulumi/Kubernetes SDKs would put deployment-specific
extraction in the generic package. Suppressed temporary-library deletion errors cannot
justify pass, so cleanup is explicitly verified. Reader threads outside process cleanup
were rejected because handle locks can deadlock during cancellation.
