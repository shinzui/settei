# Settei conformance example

This non-published test package loads one public configuration through the YAML, KDL,
and import-free Dhall adapters. It compares typed values and normalized explanation
structure while separately checking each adapter's honest location precision.

The suite also crosses the application boundaries exercised by the CLI and service
examples: ordered sources, malformed high-priority values, environment overrides,
Production-only Secret selection, and redacted captured output.
