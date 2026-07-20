# ADR 0011: Map Kubernetes mounted directories through explicit file bindings

Status: Accepted

Date: 2026-07-19


## Context

Kubernetes commonly exposes a ConfigMap or Secret to a process as a directory with one
file per object key. Kubelet's atomic writer does not keep those visible entries as
ordinary files: each visible name is a symbolic link through a hidden `..data` link to a
hidden timestamped payload directory. A configuration adapter must follow the visible
links when reading while avoiding the writer's hidden and stale implementation entries
when inspecting the directory.

Kubernetes data keys commonly contain dots, such as `application.yaml`, `tls.crt`, and
`ca.pem`. Settei dots describe structural key segments, so deriving configuration keys
from mounted names would be ambiguous. Mounted Secret content can also contain arbitrary
bytes, while Settei's existing scalar text decoders operate on Unicode text and errors
must never retain potentially secret content.


## Decision

The `settei-kubernetes` package maps mounted files only through an explicit validated
`FileBindings` collection. A file name remains an opaque visible directory entry and the
caller independently supplies its structural Settei `Key`. Construction rejects empty,
path-containing, NUL-containing, dot, and `..`-prefixed names, duplicate file names,
duplicate target keys, and prefix-overlapping target keys.

`readMountedDirectorySource` checks the mount root as a directory, opens each bound
visible entry by name, and lets the operating system follow its symbolic-link chain. It
does not enumerate or descend into hidden payload directories and does not cache a
directory listing. `unboundMountedFiles` is a separate diagnostic helper: it lists only
visible entries, filters every `..`-prefixed atomic-writer name, and reports entries that
have no binding. Unbound files do not become source leaves or source-construction
warnings.

A bound file that does not exist, including a dangling visible atomic-writer link, is an
absent leaf. Requiredness stays in the core resolver, so a required declaration reports
the missing setting and an optional declaration resolves to `Nothing`. Other I/O
failures accumulate as categorized source errors.

Mounted values must be valid UTF-8. Invalid input produces `KubernetesInvalidUtf8` with a
fixed message that retains no bytes or decoder detail. By default the adapter removes
exactly one final line-feed character after decoding; `keepTrailingNewline` preserves the
text verbatim. It does not base64-decode mounted Secret data because Kubernetes has
already decoded that representation before exposing the file.

The resulting source kind is `CustomSource "kubernetes-mounted-directory"`. Every
present leaf retains the full visible file path plus object-kind, namespace, object-name,
and per-file object-key annotations. Core rendering can consequently produce an origin
such as `kubernetes-mounted-directory source app-secrets from Kubernetes Secret
prod/app-credentials key password` without a Kubernetes client or cluster lookup.


## Consequences

Projected ConfigMap and Secret volumes compose as ordinary ordered Settei sources while
retaining honest per-file provenance. The adapter handles kubelet's atomic replacement
layout without depending on the timestamp directory's spelling or observing stale
payloads through enumeration. Static binding mistakes fail once at construction, and
missing values retain the same resolver semantics as unset environment variables.

Binary Secret values are outside this text adapter's contract. Applications that need a
binary keystore or certificate bundle must read it through a domain-specific binary path
rather than translate it to `RawText`. Reloading or watching projected volumes also
remains outside the adapter; applications re-read on startup and deployments restart to
adopt changes.


## Rejected Alternatives

Deriving Settei keys from file names, including splitting or sanitizing dots, was
rejected because it guesses structure from legal opaque Kubernetes names. Automatically
reading every visible file was rejected because explicit bindings make the accepted
configuration surface reviewable and keep unbound-file diagnostics separate from core
unknown-key policy.

Enumerating hidden payload directories or resolving links to cache their targets was
rejected because it exposes atomic-writer implementation details and can observe stale
generations. Rejecting every missing bound file during source construction was rejected
because adapters do not own requiredness. Keeping all trailing newlines by default was
rejected because accidental line feeds from editors and `echo` are a common operational
failure for file-per-value secrets; the opt-in preservation mode covers significant
newlines without weakening the default.
