---
title: "Kubernetes-derived environment bindings"
type: Capability
description: "Derive validated environment bindings and matching per-key provenance annotations from one ConfigMap or Secret reference without duplicating object identity by hand."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
capabilityId: CAP-13
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.2.0.0"
packages:
  - settei-kubernetes
  - settei-env
interface:
  - Settei.Kubernetes.Bindings
  - Settei.Env
requires:
  - CAP-5
evidence:
  - kind: test
    resource: settei-kubernetes/test/Settei/KubernetesTest.hs
    proves: Secret and ConfigMap constructors derive exact per-key annotations, allow one object key to feed several variables, reject binding conflicts, and merge with hand-written collections.
  - kind: example
    resource: examples/settei-service/src/Settei/Example/Service.hs
    proves: A Kubernetes-shaped service combines generated Secret bindings with ordinary environment bindings in one validated collection.
  - kind: guide
    resource: docs/guides/kubernetes-service.md
    proves: Object-key rows, binding derivation, environment loading, provenance, and trust boundaries are documented for consumers.
---

# Kubernetes-derived environment bindings

`Settei.Kubernetes.Bindings` constructs the
[explicit environment bindings (CAP-5)](explicit-environment-sources.md) for a named
ConfigMap or Secret. Each `ObjectKeyBinding` states the object data key, environment
variable, and target Settei key once. The generated binding carries a per-key
`KubernetesRef`, preventing the provenance annotation from drifting away from the data
key that feeds it.

```haskell
secretBindings =
  bindingsFromSecret
    (Just "production")
    "service-database"
    [ objectKeyBinding
        "password"
        (EnvName "DATABASE_PASSWORD")
        passwordKey
    ]
```

The result is an ordinary validated `Bindings` value that can be merged with hand-written
collections and read through `environmentSource` or `readEnvironmentSource`.

## Limits

- The derivation handles names and provenance only. Kubernetes or the deployment system
  must inject the actual environment variables before the process starts.
- References are caller-supplied assertions; the library does not contact the cluster,
  verify the referenced object, or attest that the variable came from it.
- Secret classification still belongs to the matching `Setting`. A `SecretObject`
  annotation does not automatically redact a value.
- The process-environment exposure and startup-snapshot limits of CAP-5 still apply.
