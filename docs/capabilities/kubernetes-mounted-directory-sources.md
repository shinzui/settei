---
title: "Kubernetes mounted-directory sources"
type: Capability
description: "Read explicitly bound UTF-8 files from projected ConfigMap or Secret directories, including kubelet atomic-writer symlinks, into provenance- and freshness-aware sources."
generated:
  by: openai/codex
  at: "2026-09-21T03:07:17Z"
capabilityId: CAP-12
provider: mori://shinzui/settei
status: shipped
stability: experimental
since: "0.2.0.0"
packages:
  - settei-kubernetes
interface:
  - Settei.Kubernetes
requires:
  - CAP-2
evidence:
  - kind: test
    resource: settei-kubernetes/test/Settei/KubernetesTest.hs
    proves: Explicit file bindings validate, atomic-writer symlinks load, absent and invalid files follow the documented categories, annotations and freshness survive, and rendered failures contain no bytes.
  - kind: example
    resource: examples/settei-service/test/Settei/Example/ServiceTest.hs
    proves: A service resolves mounted ConfigMap and Secret values at the documented precedence and safely handles source and resolution failures.
  - kind: guide
    resource: docs/guides/kubernetes-service.md
    proves: Mounted-directory construction, explicit bindings, source ordering, diagnostics, and restart semantics are documented end to end.
---

# Kubernetes mounted-directory sources

`settei-kubernetes` reads a projected ConfigMap or Secret directory with one visible
file per bound object key, including kubelet's `..data` atomic-writer symlink layout.
Validated `FileBindings` map each visible filename explicitly to a structural Settei
key. Present files become text candidates for
[layered resolution (CAP-2)](layered-resolution-and-provenance.md) with exact paths,
asserted object identity, object keys, mount path, read time, and per-file modification
time.

```haskell
bindings <- fileBindings [fileBinding "password" passwordKey]
let options = mountedDirectoryOptions "app-secrets" secretReference
loaded <- readMountedDirectorySource options bindings "/etc/app-secrets"
```

The adapter accumulates independent I/O and UTF-8 failures without retaining file
contents. `unboundMountedFiles` supports an explicit startup check while ignoring hidden
atomic-writer entries.

## Limits

- This is filesystem integration, not cluster access. The caller-supplied Kubernetes
  reference is explanatory metadata and is not compared with an API object, RBAC policy,
  or volume specification.
- Files are read eagerly. Running processes do not watch projected-volume updates; adopt
  a changed ConfigMap or Secret by restarting the process.
- Bound absent files contribute no candidate and remain a declaration/resolution concern.
  Other read failures fail source construction.
- Values must be UTF-8. By default one trailing newline is removed; callers needing
  byte-faithful text must opt into `keepTrailingNewline`.
- Freshness timestamps are process/node-clock observations for incident triage, not proof
  that every pod saw a rotation.
