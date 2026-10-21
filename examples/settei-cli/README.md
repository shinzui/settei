# Settei CLI example

This non-published package demonstrates ordered YAML, KDL, and import-free Dhall files
below explicitly mapped environment variables and repeated command-line overrides.

Run `settei-example-cli --help` to see the Configuration and Diagnostics option groups.
`--describe-config` inspects the declaration without opening files, while explanation
modes render only Settei's secret-safe report.

Repeat `--supplied-env NAME` to check exactly the names a deployment intends to supply
against the application's bindings and allowances before any file is loaded. Unsupported
or duplicated names exit 3; omitted bound variables may still use defaults or another
source. `HTTPS_PROXY` is a representative allowance labelled `http-client`: the example
does not open a network connection. `--explain-config-json` appends a versioned
`settei.supplied-names` document to stderr after the text errors when this check fails.


The runner uses `prepareDiagnostic` before environment or file acquisition and passes
its checked `RuntimeDiagnosticMode` to the runtime helper. Only successful
`DiagnosticContinue` starts normal work. Schema and contract requests finish before
runtime effects; diagnostic output, warning routing, and exit codes remain application
policy. See the [migration example](../../docs/guides/cli-application.md#add-diagnostics-that-match-user-intent).
