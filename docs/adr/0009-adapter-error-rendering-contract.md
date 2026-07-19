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
