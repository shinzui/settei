# settei-preflight

Run an application's own configuration check against explicitly proposed inputs.
`Settei.Preflight` isolates the environment, materializes files in a private directory,
redacts exact known secrets, and reports `pass`, `inconclusive`, or `fail`.
Only `pass` passes a gate; partial coverage is never deployment validation.
Supported execution platforms: Linux and macOS. The harness is not a sandbox.
