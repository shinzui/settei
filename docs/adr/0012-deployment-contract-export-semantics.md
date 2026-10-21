---
type: Architecture Decision Record
title: Export deployment contracts from declarations and explicit default sources
description: Define source-free deployment contract inspection with occurrence-aware input verdicts, deferred computations, and redaction before retention.
timestamp: 2026-10-21T14:30:00Z
docId: ADR-12
status: Accepted
date: 2026-10-21
generated:
  by: process:codex
  at: 2026-10-21T14:30:00Z
---

# ADR 0012: Export deployment contracts from declarations and explicit default sources

## Context

A required declaration can be satisfied by an application's built-in source. The static
schema cannot tell a deployment author which external inputs remain necessary, and a
resolution report needs runtime inputs first. Deployment discovery also needs environment
bindings and explicit production policies, while keeping default secrets out of reports.

[ADR-2](0002-inspectable-configuration-algebra.md) gives core an inspectable private
algebra. [ADR-3](0003-resolution-provenance-and-default-semantics.md) defines source
ordering, default syntax, and early redaction. [ADR-10](0010-validate-environment-bindings-at-construction.md)
provides safe binding inspection. A deployment contract joins these existing definitions
without adding configuration syntax or a second application schema.

## Decision

Core owns `Settei.Contract`, re-exported by `Settei`. It is a pure interpreter of the
private algebra. Adapters contribute neutral `InputBinding` metadata; `Settei.Env.inputBindings`
converts validated environment bindings with the same trusted annotation precedence as
`envSource`. Kubernetes mounted-file conversion is deferred; `CustomInput` can identify
future channels without importing an adapter into core.

Applications explicitly pass default sources in lowest-to-highest precedence order. No
source name or kind implies default status. No runtime file or environment is read. Only
the winning default-source candidate is decoded, once per request occurrence, to determine
validity; decoded values are discarded. Losing origins remain highest losing precedence
first. Structural conflicts and unknown leaves use the resolver's path rules.

Constant declaration defaults can display through a public renderer. Public constants
without a renderer are unrenderable; secrets are redacted without calling the renderer.
Derived and case defaults retain dependency keys, alternative counts, and fallback
presence, without applying functions, selecting alternatives, or evaluating their values.
Declaration fallback coverage does not guarantee successful computation, available
dependencies, or complete case coverage. Runtime checks remain necessary.

External-input verdicts track individual request occurrences. Presence is propagated
through the syntax: branches and default dependencies are conditional; target requests
inherit their enclosing presence. The merged schema fields remain independently visible
and cannot substitute for occurrence-level analysis. Verdict precedence is:

1. An explicit deployment-profile requirement requires input despite any default.
2. With a winning source default, a necessary decoder rejection requires input. If only
   conditional decoders reject, input is conditional. If all accept, source coverage
   defaults the setting. The aggregate validity records the first rejection in traversal
   order, but every rejecting occurrence can affect the verdict.
3. Without a candidate, a necessary required occurrence requires input; otherwise a
   conditional required occurrence makes input conditional. A separate declaration
   default never satisfies another required request for the same key.
4. Only with no required occurrence may declaration defaults provide fallback coverage;
   otherwise the setting is optional.

Profiles are application-supplied names and key/reason maps. They express deployment
policy as metadata, independently of runtime environment selection or resolution. Export
is discovery, not enforcement of provider or deployment constraints.

Cycle validation runs first, before schema traversal or any source hook, and returns
existing `DefaultCycle` errors. The shared private validator lives in
`Settei.Internal.DefaultValidation`, which imports the algebra and error types. The
algebra cannot import `Settei.Error`: the existing Error -> Default -> Internal.Config
path would create a module cycle. All other inconsistencies are contract diagnostics in
stable order: mixed sensitivities, structural conflicts, unknown leaves, unknown binding
keys, unknown profile keys.

Effective sensitivity is most restrictive across the entire declaration. Mixed public
and secret requests produce a diagnostic and a secret contract setting. Both typed and
source default values are redacted before entering the contract; safe output types may
have `Eq` and `Show`. `ContractInputs` and decoder-bearing private occurrence records
have neither instance because they retain raw sources or functions. Metadata follows the
existing convention: descriptions, names, annotations, explanations, and reasons must
never contain secret values.

`settei.contract` is a separate deterministic JSON document with `schemaVersion: 1`.
Existing schema and resolution documents stay unchanged. The new diagnostic flags join
the mutually exclusive Diagnostics group. Applications dispatch schema and contract
modes before executing their environment reader or opening sources; tests inject a
failing reader into the same wrapper used by each executable. Exhaustive matches on the
extended `DiagnosticMode` need a major PVP update.

## Consequences

Deployment authors can discover environment names, safe public defaults, redacted default
availability, and explicit overrides without obtaining credentials. They must still run
application check mode and validate credentials, connectivity, Kubernetes resources,
cross-setting invariants, and deployment wiring separately. The reference server/worker
workflow and public conformance fixtures demonstrate that boundary.

Tests preserve branch-local decoder semantics, prove non-evaluation with poison defaults,
scan safe outputs for secret sentinels, and pin deterministic contract renderings while
retaining the existing schema golden.

## Rejected alternatives

Extending `settei.schema` was rejected to preserve its existing meaning and consumers.
Inferring defaults from `BuiltInSource` labels was rejected because applications own source
roles. Evaluating constant-only derivations was rejected because the function remains
opaque. Failing on every inconsistency was rejected because a useful diagnostic-bearing
contract can still be produced. Inferring required input from merged schema fields was
rejected because a necessary optional request can merge with a conditional required one.
