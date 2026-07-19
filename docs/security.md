# Security model

Settei's security boundary is the configuration declaration. A `Setting` owns its
`Public` or `Secret` sensitivity before a raw candidate is decoded, retained in a report,
or included in a structured resolution error. Applications must classify settings
correctly; Settei cannot infer that a key is sensitive from its spelling or origin.


## Redaction guarantees

For a setting declared `Secret`:

- The resolver converts the raw candidate to an opaque redacted reported value before it
  is retained in `ResolutionNode` or a structured error.
- `renderResolutionText`, `renderResolutionJson`, and `renderErrorsText` can display the
  key and secret-safe origin metadata but render the value as `<redacted>`.
- Resolution failures retain a provenance report, and that report applies the same
  redaction before any secret candidate is retained or rendered.
- A derived secret is also represented as redacted.
- The public `ReportedValue` API can render its safe display form but cannot recover an
  underlying secret.

If one declaration names the same key as both `Public` and `Secret`, Settei treats that
key as secret everywhere: schema merging, report-node construction, and report-node
merging all use the most restrictive declaration. The conflicting public declaration
cannot weaken redaction, and resolution additionally fails with the structured
`SensitivityConflict` error instead of silently accepting the mismatch.

These guarantees apply to Settei's structured resolution path. They do not make an
application safe if it logs a raw adapter input, an environment snapshot, the resolved
typed secret, a third-party parser exception containing source excerpts, or a record with
a revealing `Show` instance. The reference service omits `Show` from every secret-bearing
type and logs a manually selected safe summary.


## Source parsing and errors

An adapter may encounter input before it knows which leaves correspond to secret
settings. Maintained adapters therefore use structured categories, paths, and concise
messages instead of retaining source excerpts or arbitrary scalar values in errors.
Applications should render the adapter's structured error and must not append the original
document “for context.”

Malformed high-priority values fail resolution; Settei does not silently fall back to a
lower valid value. This prevents an invalid credential or policy value from accidentally
activating an older configuration.

YAML and KDL reject numeric scalars whose base-10 exponent magnitude exceeds 4096 before
exact conversion. This bound is a denial-of-service protection: a hostile or corrupt file
cannot make startup spend unbounded time or memory constructing a rational number. The
YAML pure decode boundary also converts unexpected synchronous failures to a fixed,
source-free structured error while allowing asynchronous exceptions to propagate.


## Environment variables

Environment bindings are explicit and testable, but an environment value is plaintext in
the process boundary. Depending on the operating system and runtime, it may be visible to
the process, child processes, crash reporters, debuggers, or privileged inspection tools.
Redacted reports do not erase those exposures.

Use the smallest possible environment, avoid passing secret snapshots to unrelated child
processes, and configure crash/logging systems not to capture environment variables.


## Kubernetes Secrets and mounted files

A Kubernetes Secret is not encrypted merely because it is a Secret object, and both
`secretKeyRef` values and mounted Secret files become process-readable plaintext. Settei's
Kubernetes annotations record an asserted object kind, namespace, name, and key for
explanation; they do not contact the API server, validate RBAC, attest the object, rotate a
credential, or erase it from process memory.

Mount files read-only, restrict pod and node access, use an external secret-management and
rotation policy where required, and never put a real secret in the example manifests or
test fixtures.


## Dhall import policy

`settei-dhall` supports two application-selected policies:

- `NoImports` rejects every import before it is opened.
- `LocalImportsWithin canonicalRoot` permits only canonical local files beneath that
  explicit root and rejects parent, symlink, environment, remote, missing, alternative,
  raw-text, and raw-bytes escape paths that violate the policy.

Remote and environment imports are not part of the maintained adapter surface. A loaded
local graph reports its root and transitive import closure, but normalization makes exact
leaf-to-import attribution unavailable. Do not claim finer provenance in audit output.

`LocalImportsWithin` is preflight validation, not an operating-system sandbox: import
paths are canonicalized and checked before evaluation, so an actor able to mutate files
or symlinks concurrently can race the preflight and the upstream read (a
time-of-check/time-of-use race). Never treat a directory writable by untrusted actors as
a safe import root.


## Safe application practices

- Declare sensitivity at the setting, not at the source or renderer.
- Use a secret wrapper without `Show` and avoid deriving `Show` for enclosing records.
- Keep schema descriptions, source names, file paths, and annotations free of secret
  values; they remain visible by design.
- Render only Settei reports or an explicit allowlisted startup summary.
- Inject environment snapshots and sentinel secrets in tests, then scan stdout, stderr,
  text reports, JSON reports, and golden files for the sentinel.
- Keep diagnostics source-free when possible: `describe` must not load configuration.
- Treat reports as operational metadata. Even with redacted values, file paths, object
  names, keys, and service topology may be sensitive to an organization.

Report a suspected vulnerability through the repository's private security-reporting
channel when available; do not include a real credential in a public issue.
