# Settei service example

This non-published package demonstrates a service declaration with environment-dependent
HTTP and database-pool defaults and a database password selected only in Production. It
accepts one explicitly tagged mounted YAML, KDL, or import-free Dhall file followed by
explicit environment bindings.

The executable prints only a safe startup summary or Settei's redacted explanation. The
Kubernetes manifests are local examples and require no Kubernetes SDK or live cluster.
