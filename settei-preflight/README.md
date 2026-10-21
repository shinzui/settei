# settei-preflight

Unreleased, targeting the shared 0.3.0.0 family release. Its workspace version remains
0.2.0.0 until the coordinated bump; this package was not part of that release.

Run an application's own configuration check against explicitly proposed inputs.
`Settei.Preflight` isolates the environment, materializes files in a private directory,
redacts exact known secrets, and reports `pass`, `inconclusive`, or `fail`.
Only `pass` passes a gate; partial coverage is never deployment validation.
Reports have private constructors; use `preflightVerdict`, `preflightOutcome`,
`preflightCoverage`, `preflightExecution`, and the summary accessors to inspect them
without a lens dependency.
Supported execution platforms: Linux and macOS. The harness is not a sandbox.

`Settei.Preflight.Request` parses strict `settei.preflight-request` version 1 JSON.
Unknown fields and conflicting forms fail. Each environment/file entry has a name
and exactly one of `value` (public), `secretFromEnvironment`, `secretFromFile`,
`synthetic` with `reason` and optional `sensitivity`, `unresolved`, or `unavailableSecret`.
Secret files are read as strict UTF-8 without trimming. Request references are resolved
from the harness process; they never mean inheritance into the checked process.

Run `settei-preflight --request request.json [--json]`. Exit codes: 0 pass,
1 inconclusive, 2 CLI usage, 3 harness failure, 4 application rejection.
The child receives only proposed present inputs plus the explicit inherited allowlist
(default `PATH`, `LANG`, `LC_ALL`, `LC_CTYPE`; `inherit: []` disables it).
The timeout covers child completion and both output streams. SIGTERM-resistant children
and descendants are not force-killed. Temporary input directories use mode 0700;
failed cleanup blocks the gate. Output is captured in memory, so use a trusted,
bounded-output configuration check.

See [the deployment preflight guide](../docs/guides/deployment-preflight.md) in the
repository for the request schema, reference extraction workflow, and limitations.
