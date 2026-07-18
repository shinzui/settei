# Dhall characterization fixtures

These files preserve the input boundaries tested by `Settei.DhallTest` and shipped in the
`settei-dhall` source distribution. `direct.dhall`, `nested.dhall`, `list.dhall`,
`optional.dhall`, and `schema-default.dhall` cover JSON-compatible normalized values.
`parse-error.dhall`, `type-error.dhall`, and `unsupported-bytes.dhall` cover stable error
phases. The `local/` chain proves transitive import collection; path, symlink, cycle, and
cache cases use temporary directories because they require filesystem topology.
