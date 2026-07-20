# Settei service example

This non-published package demonstrates a service declaration with environment-dependent
HTTP and database-pool defaults and a database password selected only in Production. It
accepts one explicitly tagged mounted YAML, KDL, or import-free Dhall file followed by
explicit environment bindings.

The executable prints only a safe startup summary or Settei's redacted explanation. The
checked-in [namespace deployment manifests](deploy/) accompany the
[Kubernetes cookbook](../../docs/guides/kubernetes-cookbook.md). They are rendered and
validated client-side and require no Kubernetes SDK or live cluster.
