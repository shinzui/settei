---
type: Architecture Decision Record
title: Give every source adapter an operator-readable error renderer
description: Give every source adapter a shared operator-readable error rendering contract.
timestamp: 2026-10-21T16:08:03Z
docId: ADR-9
status: Accepted
date: 2026-07-19
generated:
  by: human:nadeem
  at: 2026-07-19T00:00:00Z
---

# ADR 0009: Give every source adapter an operator-readable error renderer

Status: Accepted

Date: 2026-07-19


## Context

YAML, KDL, Dhall, and environment loading already returned structured, secret-safe error
types, but applications had to assemble operator-facing text themselves. The reference
applications used derived `Show` output, while the guides each demonstrated a different
hand-written formatter. Fleet-wide adoption would multiply those choices and make error
messages depend on record representation rather than an intentional public contract.

The adapters retain different honest location information. YAML has a structural context
and optional path, line, and column. KDL additionally has primary and related spans. Dhall
has an optional safe path and optional parse position. Environment validation has variable
names and structural keys but no file location. A useful contract must preserve those
differences without inventing a shared error type or exposing raw configuration values.


## Decision

Each adapter module exports a singular and plural text renderer:

- `Settei.Yaml`: `renderYamlErrorText` and `renderYamlErrorsText`;
- `Settei.Kdl`: `renderKdlErrorText` and `renderKdlErrorsText`;
- `Settei.Dhall`: `renderDhallErrorText` and `renderDhallErrorsText`; and
- `Settei.Env`: `renderEnvErrorText` and `renderEnvErrorsText`.

Every singular renderer emits one operator-readable line. YAML and KDL lead with the
source name, colon-joined available path and position, structural context, and fixed
message. KDL appends a related start position when one exists. Dhall uses the same
colon-joined location rule without structural context. Environment failures use fixed
sentences containing only the variable names and keys carried by `EnvError`.

Missing location fields are omitted; an empty location removes the parenthetical
entirely. Every plural renderer is the singular renderer mapped over `NonEmpty` and joined
with `Text.unlines`, so each problem occupies one line and the result has a trailing
newline. Adapter error rendering is text-only. The core's versioned JSON diagnostics
remain reserved for resolution reports and errors.

The renderers concatenate only fields already retained by their structured error types.
They do not read source input, process environment values, or upstream exception text.
Applications and the `settei-formats` umbrella loader use these renderers instead of
derived `Show` output.


## Consequences

Applications have one stable, grep-friendly rendering path per adapter, and a fleet can
share error-handling code without depending on private record layout. Golden tests pin
all adapter error categories, omission behavior, KDL related spans, and plural newline
semantics.

Format-specific detail remains visible and truthful. Consumers that need structured UI
or telemetry can continue using the public accessors rather than parsing rendered text.
Adding a new retained location field can extend an adapter's output, but changing fixed
phrasing or punctuation requires treating the renderer as a compatibility surface.

The plural trailing newline is convenient for stderr and log output. Code embedding the
text inside another sentence must account for it or use the singular renderer.


## Rejected Alternatives

Derived `Show` was rejected because it exposes representation details, produces noisy
constructor syntax, and is not an operator contract. Repeating formatters in every
application was rejected because wording, location handling, and secret-safety discipline
would drift across adopters.

A shared error type or rendering typeclass was rejected because the four packages do not
share the same diagnostic fields and must not gain a new common dependency for one small
method. Moving the functions into core was rejected because core deliberately has no
dependency on concrete adapters. Per-adapter JSON renderers were deferred because no
load-time tooling consumer requires them; they can be added later without changing the
text contract.


## Amendment 2026-10-21: supplied-name diagnostics and the first adapter JSON document

`Settei.Env` adds `renderSuppliedNameErrorText` and `renderSuppliedNameErrorsText`
for runtime `SuppliedNameError` values under the unchanged singular/plural text contract.
Portable names appear verbatim. Other names are enclosed in double quotes with JSON
string escapes, additionally escaping U+007F–U+009F, U+2028, and U+2029 as four-digit
lowercase `\u` escapes. This preserves exactly one physical line per error even when
supplied names contain newlines or terminal controls. Comparison and structured errors
retain original names; there is no normalization or value retention.

`renderSuppliedNameErrorsJson` is the first adapter JSON renderer, admitted because
IR-2's deployment tooling is the load-time consumer anticipated by the original deferral.
That deferral is superseded for supplied-name errors, independently of IR-3. `EnvError`
and other adapters' errors remain text-only until a consumer requires otherwise.

The document has `schemaVersion` 1 and type `settei.supplied-names`. Top-level keys are
`schemaVersion`, `type`, and `errors` in that order. Each error has ordered `kind` and
`name` fields, with kinds `unsupported-supplied-name` and `duplicate-supplied-name`.
The array retains diagnostic order. Encoding is compact with no trailing newline and
uses the core's string-escaping rules on original names, independently of text display:
quote and backslash escapes, short escapes for backspace, form feed, newline, carriage
return and tab, lowercase four-digit `\u` escapes for other characters below U+0020,
and all other characters verbatim. One consumer can therefore read core and adapter
documents alike. Changing a field name or document type requires a new schema version;
additional kinds can be handled by consumers that ignore unknown kinds.

The small encoder stays private to `settei-env`; exposing core internals or adding Aeson
for this closed document would unnecessarily widen the dependency or public API surface.
The reference CLI prints text lines then one JSON document on stderr in JSON explain
mode, with empty stdout and exit 3. Success reports remain on stdout as before.
