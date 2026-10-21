---
type: Guide
title: Preflight-checking proposed deployment inputs
description: Run application-owned configuration checks on proposed container inputs with honest coverage and controlled secret channels.
docId: DOC-12
tags: [settei, deployment, preflight]
generated:
  by: process:codex
  at: 2026-10-21T15:13:00Z
---

# Preflight-checking proposed deployment inputs

Use `settei-preflight` before provisioning to run the application's own check command on
exactly the environment, files, and overrides you intend to deploy. The harness owns no
application decoders, defaults, or cross-setting rules. The application resolves its
normal ordered sources and exits from `--check-config` before acquiring resources.
The [deployment contract](deployment-contract.md) helps discover what to supply; the
harness exercises the actual configuration path.

`Settei.Preflight` is the Haskell library. `Settei.Preflight.Request` is the strict JSON
interface for deployment tooling; `settei-preflight --request PATH [--json]` runs it.
This capability targets the next shared 0.3.0.0 release and is absent from released 0.2.0.0.

## Describe proposed inputs

A request names a role, host executable, check arguments, and every proposed environment
variable and file. For example, save this as `request.json` and replace the executable:

```json
{
  "schemaVersion": 1,
  "type": "settei.preflight-request",
  "role": "server",
  "command": {
    "executable": "/absolute/path/to/application",
    "arguments": [
      {"literal": "--config"},
      {"file": "etc/application.yaml"},
      {"literal": "--check-config"}
    ]
  },
  "environment": [
    {"name": "ENVIRONMENT", "value": "production"},
    {"name": "DATABASE_URL", "secretFromEnvironment": "PREFLIGHT_DATABASE_URL"},
    {"name": "WEBHOOK_SECRET", "secretFromFile": "./private/webhook-secret"},
    {"name": "POD_NAMESPACE", "synthetic": "production", "reason": "downward API namespace"},
    {"name": "CREDENTIAL", "synthetic": "fake-credential", "reason": "shape check only", "sensitivity": "secret"},
    {"name": "GENERATED_ENDPOINT", "unresolved": "resource does not exist yet"},
    {"name": "EMAIL_CREDENTIALS_JSON", "unavailableSecret": "not provisioned"}
  ],
  "files": [
    {"name": "etc/application.yaml", "value": "server:\n  host: 0.0.0.0\n"}
  ],
  "inherit": ["PATH", "LANG", "LC_ALL", "LC_CTYPE"],
  "timeoutSeconds": 60,
  "exitCodes": {"accepted": 0, "usage": [2], "sourceFailure": [3], "rejected": [4]},
  "notes": []
}
```

Each entry has `name` and exactly one value form. `value` means supplied public text;
real secrets can only use `secretFromEnvironment` or `secretFromFile`. Synthetic material
is fake, inline, public unless `sensitivity: "secret"`, and always partial coverage.
`unresolved` and `unavailableSecret` carry reasons and are omitted from the child, so its
own missing-required diagnostics remain visible. Metadata and values labeled public must
contain no credentials. The parser cannot recognize a mislabeled secret.

Secret environment references are read from the harness process. Secret file references
are relative to its working directory, strictly UTF-8, and never trimmed. An unreadable
or invalid UTF-8 secret is unavailable. A reference does not cause the provisioning
variable itself to be inherited by the child.

All request fields are closed: unknown keys, wrong types, conflicting forms, inline
secret sensitivity on `value`, and unsupported versions fail safely. `files` and `notes`
default to empty, timeout to 60 seconds, and exit-code mapping to the example above.
`inherit` defaults to `PATH`, `LANG`, `LC_ALL`, `LC_CTYPE`; a supplied list replaces it
entirely. Use `inherit: []` for an empty context. An inherited name cannot also be a
proposed input. If your application binds locale or PATH as configuration, remove those
names from inheritance and propose them explicitly. Inheritance is execution context,
not deployment-input coverage. macOS runtimes can synthesize their own process variables.

Arguments may be `literal`, `file`, `directory`, or `parts` containing a sequence of those
single-form objects, for example `{"parts":[{"literal":"yaml:"},{"file":"etc/application.yaml"}]}`.
Files use canonical relative slash-separated names, without empty, dot, parent, NUL,
or backslash segments; duplicates and file/parent collisions fail. File references must
name declared files; directory references must contain at least one declared file.
The directory is created even if its proposed child files are omitted. The report keeps
symbolic `{file:NAME}` and `{dir:NAME}` references rather than ephemeral paths.

The harness resolves bare executable names on its own PATH and explicit relative paths
against its working directory before entering the private input directory. It invokes
no shell. A fully assembled argument or executable containing a known nonempty secret
fails before spawn. Timeout must be positive and fit microsecond conversion; exit-code
mapping entries must be disjoint integers in 0..255. CLI parse failures exit 2; request
read, parse, execution, and cleanup failures exit 3 with fixed safe errors.

## Extract a rendered container specification

The internal [deployment example](../../examples/settei-deployment/README.md) includes a
normalized Kubernetes JSON `List`: a ConfigMap, a Secret with fake placeholders, and
server/worker Deployments with `check-config` init containers. Kustomize normally emits
YAML; Pulumi does not automatically emit this aggregate List. Collect and normalize
those outputs before using this reference extractor. It has no Pulumi SDK or cluster client.

From the repository root:

```bash
nix develop -c cabal build settei-example-deployment settei-preflight
nix develop -c cabal run -v0 settei-example-deployment-preflight -- \
  --manifest examples/settei-deployment/test/fixtures/rendered-production.json \
  --deployment settei-example-deployment-server --role server \
  --executable "$(nix develop -c cabal list-bin settei-example-deployment-server)" \
  --synthetic POD_NAMESPACE=production > /tmp/server-request.json
SETTEI_PREFLIGHT_SECRET_SETTEI_EXAMPLE_DEPLOYMENT_SECRETS_DATABASE_URL='postgres://preflight.invalid/notification' \
SETTEI_PREFLIGHT_SECRET_SETTEI_EXAMPLE_DEPLOYMENT_SECRETS_WEBHOOK_SECRET='preflight-stand-in-webhook-secret' \
  nix develop -c cabal run -v0 settei-preflight -- --request /tmp/server-request.json
```

The first command writes a request with secret references, never Secret manifest values.
The second exits 4 and includes `email.credentials: required value is missing` in the
redacted stderr block. Add the following fake credential to the harness environment and
repeat the second command:

```bash
export SETTEI_PREFLIGHT_SECRET_SETTEI_EXAMPLE_DEPLOYMENT_SECRETS_EMAIL_CREDENTIALS_JSON='{}'
```

Now it exits 1. Its first lines and stdout block are:

```text
preflight server: inconclusive (accepted with partial coverage; not a deployment validation)
coverage: partial
  POD_NAMESPACE: synthetic stand-in (downward API fieldPath metadata.namespace)
```

```text
stdout:
  configuration valid
stderr:
  (empty)
```

Select `settei-example-deployment-worker` for both deployment and executable and
`--role worker` to check that role. Its projected mount adds this exact note:

```text
unsupported mounted volume (projected/downwardAPI/csi/emptyDir/persistentVolumeClaim)
```

The extractor resolves one unambiguous Deployment and one named container across init
and regular containers (`--container` defaults to `check-config`). Referenced resources
are resolved in the Deployment namespace, with absent namespace meaning `default`.
Duplicate same-kind/name/namespace objects fail. It expands envFrom in order, applying
prefixes with later values winning, then applies explicit env entries in order with
later duplicates winning. It emits one entry per effective name.

Handled inputs are literal env values; same-namespace ConfigMap key references;
Secret key references; unresolved fieldRef values; envFrom ConfigMaps and enumerated
Secret keys; ConfigMap and Secret mounts with explicit items or all keys; and mounted
file/directory paths embedded in container args. Only Secret key names are inspected,
including the union of `data` and `stringData`. Generated reference names are
`PREFIX + sanitize(secretName) + "_" + sanitize(key)`, default prefix
`SETTEI_PREFLIGHT_SECRET_`, with uppercase ASCII letters/digits preserved and other
characters replaced by underscores. Sanitization collisions fail extraction.
`--secret-prefix` changes the prefix. Missing ConfigMap values become unresolved;
optional missing key references are omitted with a note. Missing envFrom objects add
notes because their names cannot be enumerated.

`--synthetic NAME=VALUE` applies only to unresolved public values;
`--synthetic-secret NAME=VALUE` applies only to secret references or unavailable secrets.
They accept fake material only. Unknown names, conflicting substitutions, and public
substitution of secrets fail. File substitutions are outside this example interface.

Unsupported inputs remain visible: unknown valueFrom/envFrom forms, resourceFieldRef,
projected/downwardAPI/csi/emptyDir/PVC mounted volumes, subPath/subPathExpr, binaryData,
optional-volume semantics, nonempty container command overrides, unexpanded `$(VAR)`,
and absolute argument paths outside supported mounts. Unknown valueFrom also emits the
named unresolved input. Examples of fixed notes include:

```text
unsupported env.valueFrom input
subPath/subPathExpr mounts are unsupported
ConfigMap binaryData is unsupported
optional volume semantics are unsupported
container command override is unsupported; host executable equivalence is unverified
argument expansion is unsupported
argument contains an absolute path outside supported mounts
```

Every note becomes an extraction limitation and prevents `pass`. Paths use full boundaries
and longest matches; `/etc/config` cannot rewrite `/etc/config2`. Traversal, duplicate
files, and file/parent collisions fail. Container args are applied to the explicitly
supplied host executable; the caller must establish its equivalence to the deployed
image's entrypoint. The extractor does not inspect or attest images.

## Read the report and gate honestly

Reports name the role, verdict, coverage limitations, every input's classification and
whether it was passed, inherited-variable presence, symbolic command, notes, and redacted
stdout/stderr. `passed` means supplied to a successfully spawned child; omitted or
pre-spawn-failure inputs are false. Inputs sort by channel then name, with extraction
limitations identified by zero-based note index. `--json` emits deterministic compact
`settei.preflight` schema version 1, including `verdictExplanation`, structured outcome,
coverage, inputs, inherited presence, notes, command, and optional execution fields
`exitCode`, `timedOut`, `stdout`, and `stderr`.

| Result | Meaning | CLI exit | Passes gate |
| --- | --- | --- | --- |
| pass | Application accepted; every proposed value is supplied and no extraction notes remain. | 0 | Yes |
| inconclusive | Application accepted with synthetic, unresolved, unavailable, or unenumerated inputs; not a deployment validation. | 1 | No |
| fail, application rejected | Child exit categorized as usage, source failure, configuration rejection, or unknown. | 4 | No |
| fail, harness error | Invalid request, missing executable, spawn/materialization/capture/cleanup error, or timeout. | 3 | No |
| CLI usage | Invalid harness invocation. | 2 | No |

The default child mapping is 0 accepted, 2 usage, 3 source-loading failure, 4
configuration rejected, and other codes unknown. Override it for another application's
convention. A child rejection wins over partial coverage; missing credentials do not
become inconclusive merely because the harness could not supply them.

Adding or changing request fields or forms requires a new schemaVersion; unknown keys
are rejected, so they cannot be treated as ignorable additions. Version 1 notes are all
coverage limitations. The request and report use fixed field ordering and byte-identical
goldens. They are tooling documents encoded with Aeson outside the core document encoder.

## Secret channels and the later deployment checks

Files are UTF-8 beneath a fresh 0700 temporary directory, removed before success returns.
Cleanup failure is a harness failure; the temporary-library bracket is fallback cleanup.
The child receives secrets only through proposed environment or files. Exact known
nonempty secret appearances are redacted across complete captured streams, longest first,
before any report is retained. Roles, names, notes, reasons, commands, and invalid-request
problems are sanitized too. This does not recognize transformed/encoded/partial secrets,
empty strings, or unmarked credentials. The application must still use safe diagnostics.
Reports reveal input names and topology and should be treated as operational metadata.

The timeout includes child completion and draining both pipes, including a retained pipe
after the immediate child exits. Readers are cancelled and joined before handles close.
Timeout requests SIGTERM; a resistant child or descendants are not force-killed. Captured
output is held in memory; run a trusted, bounded-output check. The harness is not a sandbox
and cannot establish that an arbitrary caller-selected command has no effects.

Both tested deployment roles run with unreachable database URLs and a startup action
instrumented to fail if entered. Check mode prints exactly `configuration valid` and
skips startup; non-check controls trigger the action. These are configuration-only checks,
without cluster, database, or provider access. They do not prove connectivity, credentials,
deployed image identity, or readiness. A renamed unbound variable such as `HASKELL_ENV`
can also remain invisible; supplied-name validation from plan 27 is the complementary
check, not a feature the harness automatically invokes.

After provisioning, use the [init-container check gate](kubernetes-cookbook.md#6-gate-rollouts-with---check-config)
with actual mounted files and secrets. Then use live authentication, connectivity, image
identity verification, and readiness probes. Synthetic pre-provisioning checks remain
partial even when that later workflow is planned.
