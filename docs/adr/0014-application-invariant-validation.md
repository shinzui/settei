---
type: Architecture Decision Record
title: Validate application invariants after typed resolution
description: Check pure application rules against declared keys and share structured failures and provenance across startup and diagnostics.
timestamp: 2026-10-21T16:36:34Z
docId: ADR-14
status: Accepted
date: 2026-10-21
generated:
  by: process:codex
  at: 2026-10-21T16:36:34Z
---

# ADR 0014: Validate application invariants after typed resolution

## Context

Individual decoders cannot express relationships between settings. Application-local
text checks can reject startup yet bypass structured errors and explanation provenance.
[ADR-2](0002-inspectable-configuration-algebra.md) requires source-free inspection;
[ADR-3](0003-resolution-provenance-and-default-semantics.md) requires early redaction
and one deterministic failure vocabulary. [ADR-10](0010-validate-environment-bindings-at-construction.md)
provides the opaque checked-collection precedent.

## Decision

Core owns `Settei.Validate`. A `Validator a` declares a stable `InvariantRule`, nonempty
setting keys, a fixed expectation, optional prerequisite identifiers, and a pure function
from the typed value to finite violations. `validators config rules` accumulates invalid
identifiers, duplicates (once at the second occurrence), empty key lists, undeclared
keys, and prerequisites that do not
name earlier rules. Shared default-cycle preflight runs before schema inspection: cycles
suppress key-membership checks but do not suppress other construction errors. Possible
conditional keys are valid references; authors handle optional values totally.

`Validator` and `Validators` export neither constructors nor `Generic` instances or
writable optics. Generic conversion would bypass construction checks even with a private
constructor. Applications construct one collection per role from shared rule values,
and test those top-level definitions. A collection must accompany the same declaration
used for resolution; the type parameter alone cannot establish declaration identity.

`validate` leaves resolution errors, reports, and warnings unchanged when no typed value
is available, recording every rule as `InvariantNotRun` without forcing its function.
On success, rules execute in declaration order and independent failures accumulate.
`requires` appends prerequisites and keeps their first occurrence. Only passed rules
satisfy prerequisites; failed or transitively skipped rules block dependents without
forcing their functions. Outcomes retain passed, failed with count, skipped with unmet
prerequisites, or not-run status in declaration order. Empty collections are valid.

Failures use `InvariantError InvariantProblem` in `ConfigError`, retaining only rule,
keys, expectation, and optional detail. They retain no raw candidate or typed record.
Expectations are fixed at declaration time; `violation` is detail-free and
`violationWithDetail` is the explicit public-label channel. **All metadata must be safe
to publish. Authors must never interpolate secret values, log the typed record, or put
multiline text into line-oriented expectations or details. Settei cannot sanitise
arbitrary author text.** Validators must be total and finite; pure evaluation cannot
catch exceptions or terminate divergence. `Validator`, `Validators`, `ValidatedResult`,
and `ValidatedDiagnostic` have no `Show` or `Eq` instances. Results and dispatch decisions
have `Generic` only, as they are data rather than checked declaration collections.

The existing text and JSON error renderers gain the `invariant` kind. A separate
`renderValidationText` renders the trace; `renderValidatedResolutionJson` adds optional
`invariants` to version-1 `settei.resolution`. The original `renderResolutionJson` stays
byte-identical. `validatedDiagnostic` checks the validated answer before check-mode
success: text explain failures append report and outcomes to errors, JSON explain
failures emit two JSON documents on stderr, and non-explain failures emit text errors
only. Success explains to stdout or prints exactly `configuration valid\n`; normal
startup receives the typed value. Applications still own streams, warning routing, and
exit codes (invariants use configuration rejection code 4).

Static schema and contract dispatch precede loading and validation. The declaration
algebra, `resolve`, and bare `ResolveResult` stay unchanged. The deployment example
migrates its existing role checks, preserving `Integer` arithmetic before doubling
concurrency and preserving acceptance of valid fixtures.

## Consequences

Applications share one rejection path while keeping domain policy local. The new
`ConfigError` constructor breaks exhaustive matches and requires the next shared PVP
major release, 0.3.0.0; release tooling owns the coordinated version and pin update.
JSON additions remain schema version 1 under ADR-3. Sentinel tests scan both an adversarial
raw secret and a unique ASCII marker because JSON and Haskell Show escape punctuation.

## Rejected Alternatives

A separate failure vocabulary would duplicate renderer and exit paths. `Monad Config`
would destroy static enumeration. Runtime key references would postpone programming
errors until startup. Automatic message sanitisation cannot establish whether arbitrary
text reveals a secret. A standalone validation document and listing rules in the schema
would widen the contract without helping this migration; validation remains a separate
post-resolution stage. Connectivity and credential verification require operational IO
and remain outside pure configuration acceptance.
