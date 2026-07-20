---
id: 22
slug: create-the-settei-kubernetes-mounted-directory-source-adapter
title: "Create the settei-kubernetes mounted-directory source adapter"
kind: exec-plan
created_at: 2026-07-19T15:20:08Z
intention: "intention_01kxxfcw4ke5fbb2kas9ghvv9a"
master_plan: "docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md"
---

# Create the settei-kubernetes mounted-directory source adapter

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

The most common way Kubernetes delivers a ConfigMap or Secret to a container is not a
single YAML document and not environment variables — it is a projected volume: the object
is mounted as a directory, and each data key inside the object becomes one file whose
content is that key's value. A Secret named `app-credentials` with keys `password` and
`api-token`, mounted at `/etc/app-secrets`, appears to the process as the two files
`/etc/app-secrets/password` and `/etc/app-secrets/api-token`. Settei today has no source
adapter for that shape. It can read a whole YAML, KDL, or Dhall document from one file
(settei-yaml, settei-kdl, settei-dhall) and it can read explicitly bound environment
variables (settei-env), so teams who use projected volumes today either write glue that
copies file contents into environment variables — losing the file-level provenance Settei
exists to provide — or abandon the mounted-directory idiom entirely. The 2026-07-19 API
review identified this as the largest gap in Settei's Kubernetes story.

After this plan is implemented, a new publishable package `settei-kubernetes` exists as a
top-level sibling directory, exposing one module `Settei.Kubernetes`. An application
declares explicit bindings from file names to Settei keys, asserts which Kubernetes object
the directory came from, and calls `readMountedDirectorySource` to obtain an ordinary
Settei `Source` that composes with every other source by list position. Each resolved
value carries an origin whose location is the exact file path and whose annotations name
the Kubernetes object and the data key, so `--explain-config`-style reports read, for
example:

```text
kubernetes-mounted-directory source app-secrets from Kubernetes Secret prod/app-credentials key password
```

You can see it working by running the new package's test suite, which builds a faithful
simulation of the kubelet's atomic-writer symlink layout in a temporary directory and
resolves configuration through the core resolver:

```bash
nix develop -c cabal test settei-kubernetes-tests --test-show-details=direct
```

This plan is EP-22 of the MasterPlan
docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md.
It has no dependencies on the other plans in that MasterPlan and unblocks EP-23 (which
extends this same package with ref-derived environment bindings and freshness
annotations), EP-24 (the namespace cookbook), and EP-25 (reference-service integration and
release collateral).


## Progress

Milestone 1 — package scaffold and workspace registration:

- [x] 2026-07-19 Preflight: tree contained only this plan's MasterPlan status update;
      baseline `nix develop -c cabal test all` green;
      reconciliation check performed (see Context and Orientation: does settei-yaml export
      `renderYamlErrorText` from EP-17? does settei-env export an opaque `Bindings` from
      EP-18? what is the highest number in docs/adr/?). Findings recorded in Surprises &
      Discoveries.
- [x] 2026-07-19 `settei-kubernetes/` directory created with `settei-kubernetes.cabal` (canonical
      common stanza, version 0.1.0.0, metadata matching siblings), `LICENSE` copied from a
      sibling package, initial `CHANGELOG.md`, and a stub `src/Settei/Kubernetes.hs` that
      compiles.
- [x] 2026-07-19 `cabal.project` gains the package entry and `tests: True` block.
- [x] 2026-07-19 `nix/haskell.nix` gains `setteiKubernetesPackage` and `packages.settei-kubernetes`.
- [x] 2026-07-19 `mori.dhall` gains the `settei-kubernetes` package entry.
- [x] 2026-07-19 `nix develop -c cabal build settei-kubernetes` succeeds; commit 1 with required
      trailers.

Milestone 2 — bindings, options, errors, and the mounted-directory reader:

- [x] 2026-07-19 `FileBinding` type, `fileBinding`, `annotateFileBinding`, and accessor functions in
      `settei-kubernetes/src/Settei/Kubernetes.hs`.
- [x] 2026-07-19 `KubernetesErrorCategory` and `KubernetesSourceError` defined with accessors.
- [x] 2026-07-19 Opaque `FileBindings` collection with validating constructor `fileBindings`
      (empty/invalid/reserved file names, duplicate file names, duplicate target keys,
      prefix-overlapping target keys) and `fileBindingsList`.
- [x] 2026-07-19 `MountedDirectoryOptions` with `mountedDirectoryOptions`,
      `annotateMountedDirectoryOptions`, `keepTrailingNewline`, and accessors.
- [x] 2026-07-19 `readMountedDirectorySource` implemented: directory check, per-binding symlink-safe
      file reads, absent-file-is-absent-leaf, UTF-8 decoding, trailing-newline policy,
      tree building, per-key locations and annotations, error accumulation.
- [x] 2026-07-19 `unboundMountedFiles` implemented with the `..`-prefix filter.
- [x] 2026-07-19 Module compiles with complete haddocks and a sorted export list; commit 2 with
      required trailers.

Milestone 3 — error renderers per the EP-17 contract:

- [x] 2026-07-19 `renderKubernetesErrorText` and `renderKubernetesErrorsText` implemented and
      exported, one line per problem, graceful omission of absent name/path, never
      echoing file content.
- [x] 2026-07-19 Commit 3 folded into the Milestone 4 test commit, with required trailers (as
      renderers and their tests land together).

Milestone 4 — test suite:

- [x] 2026-07-19 `settei-kubernetes/test/Main.hs` and `settei-kubernetes/test/Settei/KubernetesTest.hs`
      created; test suite wired in the cabal file with `tasty`, `tasty-hunit`,
      `temporary`, `directory`, `filepath`, `bytestring` dependencies.
- [x] 2026-07-19 Atomic-writer fixture helper: temp directory with `..TIMESTAMP` payload directory,
      `..data` directory symlink, and per-key file symlinks.
- [x] 2026-07-19 Reading-through-symlinks test and hidden-entry-skipping test
      (`unboundMountedFiles` never lists `..data` or the timestamped directory).
- [x] 2026-07-19 Binding-validation tests: one per error category produced by `fileBindings`.
- [x] 2026-07-19 Absent-bound-file test: resolution through core `resolve` reports the key missing.
- [x] 2026-07-19 Invalid-UTF-8 test: error carries `KubernetesInvalidUtf8`, message contains no
      bytes from the file.
- [x] 2026-07-19 Trailing-newline tests: default strips exactly one `\n`; `keepTrailingNewline`
      preserves it; two trailing newlines lose only one.
- [x] 2026-07-19 Provenance tests: origin kind is `CustomSource "kubernetes-mounted-directory"`,
      location path is the full file path, `kubernetes.*` annotations present with
      `kubernetes.object-key` equal to the file name, binding annotations merged; report
      text contains the expected rendered origin line.
- [x] 2026-07-19 Renderer string tests pinning exact output for every error category.
- [x] 2026-07-19 `nix develop -c cabal test settei-kubernetes-tests --test-show-details=direct`
      green; commit 4 with required trailers.

Milestone 5 — documentation, collateral, and closure:

- [ ] Haddocks reviewed for every export; module header describes the projected-volume
      shape and the atomic-writer convention in one paragraph.
- [ ] `settei-kubernetes/CHANGELOG.md` initial entry finalized.
- [ ] Mounted-directory mapping-semantics ADR drafted at the next free number (see
      Decision Log for the numbering coordination rule).
- [ ] MasterPlan registry row EP-22 set to Complete; its Progress checkboxes for EP-22
      updated.
- [ ] Full validation: `nix develop -c cabal test all` and `nix flake check` green.
- [ ] Living sections of this plan updated; Outcomes & Retrospective written; ADR
      distillation pass performed; final commit with required trailers.


## Surprises & Discoveries

- 2026-07-19: The baseline `nix develop -c cabal test all` passed. EP-17's renderer
  convention has landed (`renderYamlErrorText` exists), settei-env has the opaque
  validated `Bindings` collection, and the highest ADR is 0010. The mapping-semantics
  ADR for this plan will therefore be 0011 unless another change lands first.
- 2026-07-19: On the validated aarch64-darwin platform, opening a dangling visible
  symlink raises the same does-not-exist condition as a missing regular entry. The
  reader therefore treats it as an absent leaf, preserving the plan's stated acceptable
  behavior. A bound directory entry independently exercises `KubernetesIoError`.


## Decision Log

- Decision: The adapter maps files to keys only through explicit per-file bindings; it
  never derives a Settei key from a file name.
  Rationale: This is fixed by the parent MasterPlan's Decision Log
  (docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md).
  ConfigMap and Secret data keys legally match `[-._a-zA-Z0-9]+` and very commonly
  contain dots (`application.yaml`, `tls.crt`, `ca.pem`), which collide with Settei's
  dotted key syntax. Splitting or sanitizing file names would be the same guessing trap
  ADR 0003 rejected for environment variables. The design mirrors settei-env's
  `EnvBinding` philosophy exactly: a file name is an opaque label, a `Key` is structural,
  and only the caller may connect them.
  Date: 2026-07-19

- Decision: The source kind is `CustomSource "kubernetes-mounted-directory"`, not
  `FileSource "KubernetesMountedDirectory"`.
  Rationale: `originDescription` in settei/src/Settei/Render.hs renders
  `FileSource formatName` as `file source NAME (FORMAT)` — the format slot is for parsed
  document formats like YAML or KDL, and a mounted directory is not a parsed file format.
  `CustomSource customKind` renders as `customKind <> " source " <> name`, giving
  `kubernetes-mounted-directory source app-secrets`. The `kubernetesSuffix` in the same
  file keys off the `kubernetes.object-kind`/`kubernetes.object-name` annotations, not
  the source kind, so it still appends the object identity; the full expected line is
  `kubernetes-mounted-directory source app-secrets from Kubernetes Secret
  prod/app-credentials key password`. A provenance test pins this rendered line.
  Date: 2026-07-19

- Decision: By default the adapter strips exactly one trailing `'\n'` from each file's
  decoded text; `keepTrailingNewline` on `MountedDirectoryOptions` preserves content
  verbatim. Only `'\n'` is treated specially — `"\r\n"` loses only the `'\n'` and CRLF
  is not otherwise special-cased. Exactly one newline is stripped: `"value\n\n"` becomes
  `"value\n"`.
  Rationale: `kubectl create secret generic --from-literal` stores the value with no
  trailing newline, but humans who create values with `echo` (instead of `echo -n`) or
  from edited files routinely introduce one, and a password that silently gained a
  newline is a notorious operational failure. Stripping one newline by default matches
  what operators expect a "file-per-value" mount to mean; the option keeps byte-faithful
  behavior available for values where the newline is significant. The rejected
  alternative — keep bytes verbatim by default and offer an opt-in strip — was rejected
  because it optimizes for the rare case and turns the common case into a debugging
  session.
  Date: 2026-07-19

- Decision: A bound file that is absent from the directory produces an absent leaf, not
  an error. Whether a missing value is a problem stays a core/resolver concern
  (`MissingRequired` at resolution time, or nothing at all if the setting is optional),
  exactly mirroring `envSource` in settei-env/src/Settei/Env.hs where an unset variable
  is simply not a leaf.
  Rationale: Adapters translate input into `RawValue` trees and honest metadata; they do
  not decide requiredness (ADR 0003, Consequences). An optional Secret key that a
  namespace does not define must not fail source construction.
  Date: 2026-07-19

- Decision: Files present in the directory but not bound are simply not part of the
  `Source` — they produce no leaves, no warnings, and no errors from
  `readMountedDirectorySource`. A separate inspection helper
  `unboundMountedFiles :: FileBindings -> FilePath -> IO [Text]` lists them so EP-24's
  cookbook can teach an explicit startup warning. The helper lets `IOException`
  propagate (documented in its haddock) because it is a diagnostic called deliberately
  at startup, not part of source construction.
  Rationale: The core already has an unknown-key policy for leaves that exist in a
  source; inventing a second unknown-file channel inside one adapter would duplicate
  that machinery with different semantics. Keeping the reader silent and the inspection
  explicit preserves the "mixed documents are useful" stance of ADR 0003 while still
  giving operators a typo detector.
  Date: 2026-07-19

- Decision: Bindings are validated once at construction through an opaque collection:
  `fileBindings :: [FileBinding] -> Either (NonEmpty KubernetesSourceError) FileBindings`,
  mirroring the post-EP-18 validated-`Bindings` idiom from
  docs/plans/18-make-environment-bindings-total-and-validated.md. Validation rejects:
  empty file names; file names containing `'/'` or the NUL character (path traversal —
  a bound name must address exactly one entry inside the mount directory); the reserved
  names `"."` and `".."` and any name beginning with `".."` (reserved by the kubelet's
  atomic writer, see Context and Orientation); duplicate file names; duplicate target
  keys; and prefix-overlapping target keys. The overlap rule, restated from settei-env:
  two bound keys conflict when the segment list of one is a strict prefix of the segment
  list of the other — binding both `database` and `database.host` is an error because a
  scalar leaf at `database` would block structural traversal to `database.host`.
  Because a `FileBindings` value is valid by construction, the tree-building step inside
  `readMountedDirectorySource` is total.
  Rationale: Binding lists are static program data; an invalid list is a bug best
  reported once at startup or in a unit test, and validity-by-construction is what makes
  the insert helper's impossible-overlap branch genuinely impossible. This also keeps
  the API shape consistent with what settei-env looks like after the ergonomics
  MasterPlan, which this initiative runs after.
  Date: 2026-07-19

- Decision: `KubernetesSourceError` follows the family error shape — a record of a
  stable category enum plus locating fields plus a message — with
  `name :: Maybe Text` (the source name, absent for binding-construction errors, which
  happen before any source name exists) and `path :: Maybe FilePath` (the full file or
  directory path, absent for binding-construction errors). Categories:
  `KubernetesInvalidFileName`, `KubernetesDuplicateFileName`,
  `KubernetesDuplicateTargetKey`, `KubernetesConflictingTargetKeys`,
  `KubernetesNotADirectory`, `KubernetesIoError`, `KubernetesInvalidUtf8`. The message
  is sentence-form, names the offending file name or keys, and never contains file
  content. `renderKubernetesErrorText`/`renderKubernetesErrorsText` ship in this plan,
  from day one, per the EP-17 contract
  (docs/plans/17-add-error-renderers-to-every-source-adapter.md): the plural composes
  the singular with `Text.unlines`, and the singular is one line leading with the most
  locating information present — `NAME (PATH): message`, dropping the parenthetical when
  the path is unknown and falling back to the literal prefix `file bindings: ` when the
  name is also unknown.
  Rationale: settei-yaml's `YamlSourceError` (category + name + path + message) is the
  family precedent for read-time failures, and settei-env's constructor-per-problem
  messages are the precedent for binding validation; one record with a category enum and
  optional locating fields covers both without two error types. Constructor names carry
  the `Kubernetes` prefix so unqualified imports never clash with settei-env's
  `DuplicateTargetKey`/`ConflictingTargetKeys`.
  Date: 2026-07-19

- Decision: The per-key annotations for each present leaf are
  `kubernetesAnnotations` of the asserted `KubernetesRef` with its object-key field
  replaced by that leaf's file name, merged with the binding's caller annotations
  (adapter-owned names win on collision, matching settei-env's precedence comment).
  `MountedDirectoryOptions` carries the ref whole so every candidate asserts the same
  object identity; any `key` already present in the caller's ref is ignored and
  overwritten per file, and the haddock says so.
  Rationale: This is what makes an explain report say which key of which Secret supplied
  a value — the review's core provenance ask. Reusing core's `kubernetesRef` /
  `kubernetesAnnotations` (settei/src/Settei/Origin.hs) rather than writing annotation
  names by hand keeps the vocabulary single-sourced and the `kubernetesSuffix` renderer
  working unchanged.
  Date: 2026-07-19

- Decision: This plan adds no freshness or identity annotations
  (`kubernetes.mount-path`, `kubernetes.file-modified`, and friends). Those belong to
  EP-23 per the MasterPlan's freshness-via-annotations decision; this adapter records
  only the object identity and the exact file path.
  Rationale: EP-23 owns the annotation-vocabulary extension and the decision on whether
  the core renderer displays it; duplicating a partial version here would force EP-23 to
  reconcile two vocabularies.
  Date: 2026-07-19

- Decision: The mounted-directory mapping semantics (explicit bindings, atomic-writer
  handling, UTF-8 and trailing-newline policy, absent/unbound semantics) become a new
  ADR written during Milestone 5, at the next free number in docs/adr/. Coordination
  rule: the ergonomics MasterPlan's plans are expected to have created 0008 and 0009 by
  the time this plan runs; at implementation time list docs/adr/, take the highest
  existing number plus one (expected 0010), and record the actual number here.
  Rationale: ADR numbers are allocated by landing order across initiatives; hard-coding
  one now would collide if the ergonomics plans add or renumber.
  Date: 2026-07-19

- Decision: Documentation scope in this plan is haddocks plus the CHANGELOG plus the new
  ADR only. No docs/guides/ page is written here; guide coverage (including the cookbook
  section that teaches `unboundMountedFiles` as a startup warning) belongs to EP-24 and
  EP-25, and registration of the package in docs/compatibility.md belongs to EP-25's
  release-collateral pass. The module haddock header serves as the interim usage
  documentation and includes one complete end-to-end example.
  Rationale: The MasterPlan assigns the cookbook and the collateral reconciliation to
  those plans; writing a guide stub here would create a page EP-24 immediately rewrites.
  Date: 2026-07-19

- Decision: In `nix/haskell.nix` the new derivation is
  `haskellPackages.callCabal2nix "settei-kubernetes" ../settei-kubernetes { settei =
  setteiPackage; }` with tests enabled (no `dontCheck`).
  Rationale: The only `dontCheck` exceptions in that file exist because the nixpkgs
  `tasty` closure embeds optparse-applicative 0.18 while some packages need the pinned
  0.19; settei-kubernetes depends on neither optparse-applicative nor dhall, so — like
  settei-yaml and settei-env — its tests can run in both Cabal and Nix.
  Date: 2026-07-19

- Decision: This plan assumes the correctness MasterPlan
  (docs/masterplans/2-harden-settei-correctness-before-fleet-wide-adoption.md) and the
  ergonomics MasterPlan
  (docs/masterplans/3-improve-settei-api-ergonomics-for-fleet-wide-adoption.md) have
  landed first. Reconciliation rule if the working tree differs at implementation time:
  (a) if EP-17's renderers do not yet exist in the sibling adapters, this package still
  ships `renderKubernetesErrorText`/`renderKubernetesErrorsText` with the names and
  one-line format fixed by EP-17's Decision Log — the contract is defined there even
  before it is implemented elsewhere; (b) if EP-18's opaque `Bindings` does not yet
  exist in settei-env, `FileBindings` still uses the validated-collection idiom
  described here, since it stands alone; (c) if EP-12 has changed the `resolve` result
  shape, adapt only the test code that inspects reports — the adapter itself never calls
  the resolver; (d) verify the canonical common stanza and dependency bounds against the
  actual settei-yaml.cabal in the tree rather than against the copies in this plan, and
  note any drift in Surprises & Discoveries.
  Date: 2026-07-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### The repository in one paragraph

Settei is a Haskell configuration library split into a core package and per-format
adapter packages, each in a same-named top-level directory: `settei/` (the core:
declaration algebra, resolver, provenance, reporting), `settei-env/`,
`settei-optparse-applicative/`, `settei-yaml/`, `settei-kdl/`, and `settei-dhall/`.
Reference applications live under `examples/` and are the public-API conformance
boundary. The workspace is driven by `cabal.project` at the root, Nix wiring in
`flake.nix` plus `nix/haskell.nix`, and a Mori registry manifest `mori.dhall`. All
commands in this plan run from the repository root inside `nix develop`. This plan adds a
seventh publishable package, `settei-kubernetes/`, following the identical structure.

### Relevant ADRs

- docs/adr/0001-haskell-project-conventions.md — every package is a top-level sibling
  directory owning its `.cabal` file, `src/`, `test/`, `LICENSE`, and `CHANGELOG.md`.
  Each `.cabal` file repeats the canonical `common common` stanza
  (`default-language: GHC2024`; extensions `DeriveAnyClass`, `DuplicateRecordFields`,
  `OverloadedLabels`, `OverloadedStrings`; `ghc-options: -Wall -Wcompat`) because common
  stanzas do not cross package files. Records use strict unprefixed fields with explicit
  deriving strategies; field access uses lens operators with generic-lens `#label`
  syntax, which requires each module using labels to import `Data.Generics.Labels ()`
  and each such package to declare `generic-lens` directly. Qualified imports use
  postpositive `qualified`. Dependency research starts from Mori but release freshness
  is verified against Hackage independently.
- docs/adr/0003-resolution-provenance-and-default-semantics.md — adapters only parse
  input into `RawValue`, construct a `Source`, and attach honest origin metadata; they
  never merge layers or decode application values. Origins carry a source kind, stable
  name, key, optional exact location, and ordered annotations; core supplies the shared
  Kubernetes annotation vocabulary (`kubernetes.object-kind`, `kubernetes.object-name`,
  `kubernetes.namespace`, `kubernetes.object-key`) which the text renderer appends to
  origin descriptions. Annotations must never copy raw candidate values; potentially
  secret content lives only in `RawValue`, which has no `Show`.
- docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md — the
  examples prove the process boundary only: configuration delivery is visible to a
  process as files and environment variables, and no Kubernetes API client is part of
  Settei. This plan honors that boundary absolutely: the adapter reads a local
  directory; it asserts, and never verifies, cluster identity.

The parent MasterPlan's Decision Log adds three constraints binding on this plan:
process-boundary only (no cluster client, no watch/reload); explicit per-file key
bindings (no filename-derived keys); and freshness/identity annotations belong to EP-23,
not here.

### The core APIs this adapter builds on

`settei/src/Settei/Source.hs` — `source :: Text -> SourceKind -> RawValue -> Source`
constructs a source; `locateSource :: (Key -> Maybe SourceLocation) -> Source -> Source`
attaches exact-key locations; `annotateSource :: Map Text Text -> Source -> Source`
attaches source-wide annotations; `annotateSourceAt :: (Key -> Map Text Text) -> Source
-> Source` attaches per-key annotations, and per-key entries take precedence over
source-wide entries with the same name.

`settei/src/Settei/Origin.hs` — `SourceKind` includes `CustomSource !Text` precisely for
new kinds like this one. `SourceLocation` is a record of `path :: Text` plus optional
line and column; for a mounted file the path is the file's full path and line/column stay
`Nothing`. `KubernetesRef` (constructed by `kubernetesRef :: KubernetesObjectKind ->
Maybe Text -> Text -> Maybe Text -> KubernetesRef`, where the fields are object kind,
optional namespace, object name, optional data key) and `kubernetesAnnotations ::
KubernetesRef -> Map Text Text` produce the shared annotation vocabulary. The renderer's
`kubernetesSuffix` (settei/src/Settei/Render.hs) appends
`" from Kubernetes KIND NAMESPACE/NAME key KEY"` to any origin description whose
annotations carry the object kind and name — regardless of source kind, so it composes
with `CustomSource`.

`settei-env/src/Settei/Env.hs` is the template for this module's shape — it is the
explicit-bindings philosophy this adapter transplants from environment variables to
files. Study these parts before writing code: `EnvBinding` (a record of name, key,
caller annotations), `binding` and `annotateBinding` constructors, `envSource`'s
validate-then-build structure, the private `overlapErrors`/`duplicates` validation
helpers, the private `insertRawValue` tree builder (which folds each bound value into a
`RawObject` tree along its key segments and whose impossible branch is justified by
prior overlap validation), and the `annotateSourceAt` per-key annotation map keyed by
`Key`. All of those helpers are private to `Settei.Env`, so `Settei.Kubernetes`
replicates them locally; do not try to import them.

`settei-yaml/src/Settei/Yaml.hs` is the template for the error type and the IO boundary:
`YamlSourceError` is a record of category enum, source name, optional path, positions,
and a message that never echoes content; `readYamlSource` wraps the file read in
`try @IOException` and converts the exception's `displayException` text into an
`IoError`-category value. `readMountedDirectorySource` follows the same pattern per
file.

`settei-env` and `settei-yaml` already export `fromKubernetesObject` and
`fromKubernetesMountedFile` respectively — helpers that annotate a whole env binding or
a whole mounted document with a Kubernetes ref. They cover the "one file, one document"
and "env var projected from an object" cases. This plan covers the third and most common
delivery: a directory of one-file-per-key. Say this in the module haddock so readers pick
the right tool.

### Kubernetes domain knowledge the implementer needs

A projected volume (also created by plain `configMap:`/`secret:` volumes; "projected" is
the general mechanism) mounts a ConfigMap or Secret as a directory. Each data key of the
object becomes one regular-file-shaped entry in that directory whose content is the
value: Secret `app-credentials` with data keys `password` and `api-token` mounted at
`/etc/app-secrets` yields `/etc/app-secrets/password` and `/etc/app-secrets/api-token`.

The kubelet updates these mounts atomically using a symlink convention you must handle.
The actual data lives in a hidden timestamped directory such as
`..2024_01_01_12_00_00.123456/` inside the mount; a hidden symlink `..data` points at
that directory; and each visible key entry is itself a symlink through it, for example
`password -> ..data/password`. On update, the kubelet writes a complete new timestamped
directory and atomically swaps the `..data` symlink to point at it. Three consequences
for this adapter: when enumerating the mount directory (only `unboundMountedFiles` does
this), skip every entry whose name starts with `..` and never descend into the hidden
directories, or every key would be seen twice and stale payload directories would be
read; when reading a bound file, open it by its visible name and let the operating
system follow the symlink chain (Haskell's `Data.ByteString.readFile` does this
naturally — do not use symlink-avoiding APIs); and do not cache directory listings
across reads, since the whole tree can be swapped between calls. A pod can also mount a
single key as a single file using `subPath`; that shape has no symlink dance and is
already served by the existing one-file adapters (settei-yaml et al.) or by a one-file
binding through this adapter, and the module haddock should note that this adapter
targets the directory shape.

Data-key naming: ConfigMap and Secret data keys must match `[-._a-zA-Z0-9]+`. Dots are
extremely common (`application.yaml`, `tls.crt`, `ca.pem`, `tls.key`). This is exactly
why the MasterPlan mandates explicit bindings: a file name is never split on dots and
never guessed into a `Key`. A key may not be `.` or `..`, and the kubelet reserves
`..`-prefixed names for its atomic writer, which is why `fileBindings` rejects them.

Values: in the Kubernetes API a Secret's data is base64-encoded, but the mounted files
contain the already-decoded raw bytes — the adapter must not base64-decode anything.
Content is usually UTF-8 text without a trailing newline (`kubectl create secret
--from-literal` appends none), but values created by humans via `echo` or edited files
often carry one; hence the trailing-newline decision in the Decision Log. Binary values
(a keystore, a `.p12` bundle) are legal Kubernetes but out of scope for a text
configuration value: invalid UTF-8 is a categorized error that never echoes the bytes.

### Sequencing assumption

This MasterPlan runs after the correctness MasterPlan (docs/masterplans/2) and the
ergonomics MasterPlan (docs/masterplans/3). Concretely, this plan is written assuming
EP-12's resolver result shape, EP-17's adapter renderer contract, and EP-18's validated
`Bindings` idiom are already in the tree. If the tree differs when you start, apply the
reconciliation rule recorded in the Decision Log (renderers ship regardless;
`FileBindings` stands alone; only test code depends on the resolver's report shape;
audit the canonical stanza and bounds from the live settei-yaml.cabal). Do not
contradict EP-18: its `Bindings` type is settei-env's concern and EP-23 — not this plan
— is what later derives environment bindings from a `KubernetesRef`.


## Plan of Work

### Milestone 1 — package scaffold and workspace registration

Scope: create the `settei-kubernetes/` package directory with a compiling stub module and
register it everywhere the workspace tracks packages. At the end, `nix develop -c cabal
build settei-kubernetes` succeeds and the package is visible to Cabal, Nix, and Mori.

Create `settei-kubernetes/settei-kubernetes.cabal`. Copy the metadata style of
`settei-yaml/settei-yaml.cabal` and the dependency bound spellings exactly as they appear
in the sibling cabal files (audit them in the live tree first; the spellings below were
read from settei-yaml.cabal, settei-env.cabal, and settei-dhall.cabal on 2026-07-19):

```cabal
cabal-version:   3.8
name:            settei-kubernetes
version:         0.1.0.0
synopsis:        Kubernetes mounted-directory sources for Settei
description:
  Translate a projected ConfigMap or Secret volume - a directory with one file
  per data key - into a provenance-aware Settei source through explicit
  per-file key bindings, handling the kubelet's atomic-writer symlink layout.

homepage:        https://github.com/shinzui/settei
bug-reports:     https://github.com/shinzui/settei/issues
license:         BSD-3-Clause
license-file:    LICENSE
author:          shinzui
maintainer:      shinzui
category:        Configuration
build-type:      Simple
tested-with:     GHC ==9.12.4
extra-doc-files: CHANGELOG.md

source-repository head
  type:     git
  location: https://github.com/shinzui/settei.git

common common
  default-language:   GHC2024
  default-extensions:
    DeriveAnyClass
    DuplicateRecordFields
    OverloadedLabels
    OverloadedStrings

  ghc-options:        -Wall -Wcompat

library
  import:          common
  hs-source-dirs:  src
  exposed-modules: Settei.Kubernetes
  build-depends:
    , base          >=4.21    && <5
    , bytestring    >=0.12    && <0.13
    , containers    >=0.6.8   && <0.8
    , directory     >=1.3.8   && <1.4
    , filepath      >=1.5.4   && <1.6
    , generic-lens  >=2.2     && <2.4
    , settei        ==0.1.0.0
    , text          >=2.1     && <2.2

test-suite settei-kubernetes-tests
  import:         common
  type:           exitcode-stdio-1.0
  hs-source-dirs: test
  main-is:        Main.hs
  other-modules:  Settei.KubernetesTest
  build-depends:
    , base               >=4.21    && <5
    , bytestring         >=0.12    && <0.13
    , containers         >=0.6.8   && <0.8
    , directory          >=1.3.8   && <1.4
    , filepath           >=1.5.4   && <1.6
    , generic-lens       >=2.2     && <2.4
    , settei             ==0.1.0.0
    , settei-kubernetes  ==0.1.0.0
    , tasty              >=1.5     && <1.6
    , tasty-hunit        >=0.10.2  && <0.11
    , temporary          >=1.3     && <1.4
    , text               >=2.1     && <2.2
```

Copy `LICENSE` verbatim from `settei-yaml/LICENSE` (BSD-3-Clause; every sibling package
carries its own copy). Create `settei-kubernetes/CHANGELOG.md` in the family's style:

```markdown
# Changelog for settei-kubernetes

## 0.1.0.0 — Unreleased

- Initial experimental release.
- Add a mounted-directory source for projected ConfigMap and Secret volumes with
  explicit per-file key bindings, atomic-writer symlink handling, per-file
  provenance, and secret-safe categorized errors with text renderers.
```

Create a stub `settei-kubernetes/src/Settei/Kubernetes.hs` (module header haddock plus an
empty export list is enough to compile) so the registration edits can be validated before
the real module lands.

Register the package in three places, each modeled on how settei-yaml is registered:

1. `cabal.project`: add `  settei-kubernetes` to the `packages:` list between
   `settei-kdl` and `settei-optparse-applicative` (the list is alphabetical), and add a
   `package settei-kubernetes` block with `  tests: True` alongside the existing per-
   package blocks.
2. `nix/haskell.nix`: in the `let` block, after `setteiKdlPackage`, add

   ```nix
   setteiKubernetesPackage =
     haskellPackages.callCabal2nix "settei-kubernetes" ../settei-kubernetes {
       settei = setteiPackage;
     };
   ```

   and in the outputs add `packages.settei-kubernetes = setteiKubernetesPackage;` next to
   the other `packages.settei-*` lines. No `dontCheck` (see Decision Log). `flake.nix`
   itself needs no edit — it only imports this module; verify that by grepping `flake.nix`
   for `settei-yaml` (it does not appear there).
3. `mori.dhall`: add a package entry alongside the other adapters:

   ```dhall
   , Schema.Package::{
     , name = "settei-kubernetes"
     , type = Schema.PackageType.Library
     , language = Schema.Language.Haskell
     , path = Some "settei-kubernetes"
     , description = Some "Kubernetes mounted-directory (projected volume) sources for Settei"
     , dependencies = [ Schema.Dependency.ByName "settei" ]
     }
   ```

Acceptance: `nix develop -c cabal build settei-kubernetes` compiles the stub;
`nix flake check` still passes.

### Milestone 2 — the Settei.Kubernetes module

Scope: implement the full library surface in
`settei-kubernetes/src/Settei/Kubernetes.hs`. At the end the module exports everything
listed in Interfaces and Dependencies, compiles warning-free, and every export has a
haddock. Follow `Settei.Env` for structure and idiom (strict fields, `Generic` deriving
with explicit strategies, `Data.Generics.Labels ()` import, lens access, postpositive
qualified imports).

First the binding types. `FileBinding` is a record of `fileName :: !Text` (the visible
entry name inside the mount directory — an opaque label, never parsed), `key :: !Key`
(the structural Settei target), and `annotations :: !(Map Text Text)` (trusted caller
metadata merged into that leaf's per-key annotations). `fileBinding :: Text -> Key ->
FileBinding` constructs one with empty annotations; `annotateFileBinding :: Map Text
Text -> FileBinding -> FileBinding` merges caller metadata with adapter-owned names
taking precedence (same `%~ (annotations <>)` shape and haddock caveat as
`annotateBinding` in Settei.Env). Provide accessors `fileBindingName`,
`fileBindingKey`, `fileBindingAnnotations`.

Then the error type, because validation returns it. `KubernetesErrorCategory` is a
seven-constructor enum (`KubernetesInvalidFileName`, `KubernetesDuplicateFileName`,
`KubernetesDuplicateTargetKey`, `KubernetesConflictingTargetKeys`,
`KubernetesNotADirectory`, `KubernetesIoError`, `KubernetesInvalidUtf8`) deriving
`stock (Generic, Eq, Ord, Show)`. `KubernetesSourceError` is a record of
`category :: !KubernetesErrorCategory`, `name :: !(Maybe Text)` (source name when the
error came from reading; `Nothing` from `fileBindings`), `path :: !(Maybe FilePath)`
(full file path for per-file read errors, the directory path for
`KubernetesNotADirectory`, `Nothing` from `fileBindings`), and `message :: !Text`
(sentence-form, names the offending file name or keys via `renderKey`, never contains
file content or `displayException`-carried content — `displayException` of an
`IOException` contains the path and errno text only, which is safe). Accessors:
`kubernetesErrorCategory`, `kubernetesErrorName`, `kubernetesErrorPath`,
`kubernetesErrorMessage`.

Then the validated collection. `FileBindings` is an opaque newtype over `[FileBinding]`
with no exported constructor. `fileBindings :: [FileBinding] -> Either (NonEmpty
KubernetesSourceError) FileBindings` accumulates, in this order: one
`KubernetesInvalidFileName` per binding whose name is empty, contains `'/'` or `'\NUL'`,
equals `"."` or `".."`, or has `".."` as a prefix; one `KubernetesDuplicateFileName` per
name bound more than once; one `KubernetesDuplicateTargetKey` per key targeted more than
once; and one `KubernetesConflictingTargetKeys` per pair of distinct keys where one's
segment list is a strict prefix of the other's. Replicate the `duplicates` and
`overlapErrors` helpers from `Settei.Env` (they are private there). `fileBindingsList ::
FileBindings -> [FileBinding]` allows inspection without construction. An empty binding
list is valid — it yields a source with no leaves — matching `envSource`.

Then the options. `MountedDirectoryOptions` is a record of `name :: !Text` (the stable
source name shown in reports, e.g. `"app-secrets"`), `ref :: !KubernetesRef` (the
asserted object identity; its `key` field is ignored and replaced per file — say so in
the haddock), `annotations :: !(Map Text Text)` (source-wide caller annotations applied
via `annotateSource`), and `keepsTrailingNewline :: !Bool` (default `False`; the field
is named differently from the exported setter `keepTrailingNewline` so the generated
field selector and the top-level function cannot collide in the defining module).
`mountedDirectoryOptions :: Text -> KubernetesRef -> MountedDirectoryOptions` constructs
the defaults; `annotateMountedDirectoryOptions :: Map Text Text ->
MountedDirectoryOptions -> MountedDirectoryOptions` merges caller metadata;
`keepTrailingNewline :: MountedDirectoryOptions -> MountedDirectoryOptions` sets the
flag. Provide accessors `mountedDirectoryName`, `mountedDirectoryRef`,
`mountedDirectoryAnnotations`, `mountedDirectoryKeepsTrailingNewline`.

Finally the reader. `readMountedDirectorySource :: MountedDirectoryOptions ->
FileBindings -> FilePath -> IO (Either (NonEmpty KubernetesSourceError) Source)`
proceeds as follows. First check `System.Directory.doesDirectoryExist` on the mount path
(`doesDirectoryExist` follows symlinks, which is correct — a symlinked mount root is
fine); if false, return a single `KubernetesNotADirectory` error whose path is the
directory and whose message is `"mounted path is not a directory"`. Then for each
binding in order, attempt `try @IOException (Data.ByteString.readFile (directory </>
fileName))` — note `readFile` follows the kubelet's symlink chain automatically, which
is the required behavior. Classify the outcome per binding: an exception satisfying
`System.IO.Error.isDoesNotExistError` means the bound file is absent, which is not an
error — the binding simply contributes no leaf (missing-vs-present stays a core/resolver
concern, mirroring `envSource`); any other `IOException` becomes a
`KubernetesIoError` with the file's full path and the `displayException` text; on
success, decode with `Data.Text.Encoding.decodeUtf8'`, and a `Left` becomes
`KubernetesInvalidUtf8` with the file's full path and the fixed message `"file content
is not valid UTF-8"` (never include the decoding exception's detail, which can echo
bytes). Apply the trailing-newline policy: unless `keepTrailingNewline` is set, strip
exactly one trailing `'\n'` if present (use `Text.stripSuffix "\n"` with `fromMaybe`).
Accumulate all per-file errors across all bindings; if any exist, return them all as the
`NonEmpty` — do not stop at the first, matching the accumulation style of `fileBindings`
and of core resolution. If none exist, build the source: fold the present `(binding,
RawText value)` pairs into a `RawObject` tree with a local `insertRawValue` replica
(total because `FileBindings` validation excluded overlaps); construct `source (options
name) (CustomSource "kubernetes-mounted-directory") root`; attach per-key locations with
`locateSource` from a `Map Key SourceLocation` where each present binding's location is
`SourceLocation { path = Text.pack (directory </> fileName), line = Nothing, column =
Nothing }`; attach per-key annotations with `annotateSourceAt` from a `Map Key (Map Text
Text)` where each present binding's entry is `kubernetesAnnotations (ref & #key .~ Just
fileName) <> bindingAnnotations` (adapter identity wins over caller names, mirroring
Settei.Env's precedence); and attach the options' source-wide annotations with
`annotateSource`. Absent bindings get no location and no annotation entry — they have no
leaf for the resolver to find.

And the inspection helper. `unboundMountedFiles :: FileBindings -> FilePath -> IO
[Text]` calls `System.Directory.listDirectory` (which already omits `.` and `..` but
does list `..data` and the `..TIMESTAMP` payload directory), converts entries to `Text`,
drops every entry with `".." `as a prefix (`Text.isPrefixOf ".."`), drops entries whose
name is bound, never stats or descends into anything, and returns the remainder sorted.
Its haddock states that `IOException` propagates and that the intended use is a startup
diagnostic (EP-24's cookbook will teach logging a warning from it).

The module haddock header explains, in one short paragraph each: the projected-volume
directory shape; the atomic-writer symlink convention and that this module handles it;
that keys are bound explicitly because data keys commonly contain dots; the
trailing-newline default; that single-file `subPath` mounts are served by the one-file
adapters or a one-file binding; and one complete example — declaring bindings, options
with a `kubernetesRef`, and a `readMountedDirectorySource` call.

Acceptance: `nix develop -c cabal build settei-kubernetes` compiles warning-free.

### Milestone 3 — error renderers per the EP-17 contract

Scope: `renderKubernetesErrorText :: KubernetesSourceError -> Text` and
`renderKubernetesErrorsText :: NonEmpty KubernetesSourceError -> Text`, exported from
`Settei.Kubernetes`, shipped in the package's first release per the contract of
docs/plans/17-add-error-renderers-to-every-source-adapter.md.

The plural composes the singular with `Text.unlines` over `NonEmpty.toList`, exactly like
the core's `renderErrorsText`. The singular emits one line: when both name and path are
present, `NAME (PATH): message`; when only the name is present, `NAME: message`; when
neither is present (binding-construction errors), `file bindings: message`. Expected
outputs, which the Milestone 4 tests pin exactly:

```text
app-secrets (/etc/app-secrets/password): file content is not valid UTF-8
app-secrets (/etc/app-secrets): mounted path is not a directory
file bindings: file name "tls.crt" is bound more than once
file bindings: file name "a/b" contains a path separator or is reserved
file bindings: target key database is bound more than once
file bindings: target keys database and database.host overlap
```

(The exact message wording is fixed at implementation time; whatever is chosen must name
the offending file name or rendered keys, must never echo file content, and the tests
must pin the final strings verbatim.)

Acceptance: renderer unit tests in Milestone 4 pass.

### Milestone 4 — test suite

Scope: `settei-kubernetes/test/Main.hs` (a `defaultMain (testGroup "settei-kubernetes"
[KubernetesTest.tests])` shell mirroring `settei-yaml/test/Main.hs`) and
`settei-kubernetes/test/Settei/KubernetesTest.hs`. Fixtures are created by the tests
themselves inside `withSystemTempDirectory` (from the `temporary` package, precedent in
settei-dhall's tests) — no checked-in fixture directories, because symlinks in a source
distribution are fragile.

Write a fixture helper that simulates the kubelet's atomic writer faithfully:

```haskell
-- Build a projected-volume mount at root with the given (fileName, bytes) entries:
--   root/..2026_07_19_12_00_00.123/<name>   (regular files with the payload)
--   root/..data -> ..2026_07_19_12_00_00.123 (directory symlink)
--   root/<name> -> ..data/<name>             (per-key file symlinks)
atomicWriterFixture :: FilePath -> [(FilePath, ByteString)] -> IO ()
atomicWriterFixture root entries = do
  let payload = root </> "..2026_07_19_12_00_00.123"
  createDirectory payload
  mapM_ (\(name, bytes) -> ByteString.writeFile (payload </> name) bytes) entries
  createDirectoryLink payload (root </> "..data")
  mapM_ (\(name, _) -> createFileLink ("..data" </> name) (root </> name)) entries
```

`createDirectoryLink` and `createFileLink` come from `System.Directory`. Portability
note, stated honestly: release validation runs on `aarch64-darwin` per
docs/compatibility.md, and POSIX symbolic links work identically there and on Linux, so
these tests are portable across the systems this repository validates; Windows is not a
validated platform for this workspace and no accommodation is made.

Test cases, each phrased as observable behavior:

1. Symlinked keys read correctly: build the fixture with `password` and `http-host`
   entries, bind both, read the source, resolve two required text settings through core
   `resolve` (`Settei.Resolve.resolve` with default options, one source), and assert the
   typed values equal the file contents.
2. Hidden entries are skipped: on the same fixture, `unboundMountedFiles` with a binding
   list covering only `password` returns exactly `["http-host"]` — never `..data`, never
   the timestamped directory. Add an unbound extra file to prove positive listing.
3. Binding validation: one assertion per category from `fileBindings` — empty name;
   name containing `/`; name `".."` (reserved); duplicate file name; duplicate target
   key; overlapping keys `database` and `database.host` (restating that a scalar at the
   shorter key would structurally block the longer). Each asserts the category and that
   valid bindings alongside invalid ones still surface every error (accumulation).
4. Absent bound file is an absent leaf: bind a file that the fixture does not contain;
   `readMountedDirectorySource` returns `Right`; resolving a required setting at that
   key fails with the core's missing-required error at that key, and resolving an
   optional setting succeeds with `Nothing` — proving missing-ness stayed a resolver
   concern.
5. Invalid UTF-8: write bytes `"\xff\xfe\x01"` as a bound file's payload; the read
   returns `Left` with category `KubernetesInvalidUtf8`, the file's full path, and a
   message that contains neither `\xff` nor any hex rendering of the content.
6. Trailing-newline policy: payload `"s3cr3t\n"` resolves to `"s3cr3t"` by default;
   with `keepTrailingNewline` it resolves to `"s3cr3t\n"`; payload `"s3cr3t\n\n"`
   resolves to `"s3cr3t\n"` by default (exactly one stripped); payload without a
   newline is unchanged either way.
7. Provenance: build options with `kubernetesRef SecretObject (Just "prod")
   "app-credentials" Nothing`, resolve, and inspect the report's chosen origin for the
   bound key: kind is `CustomSource "kubernetes-mounted-directory"`; location's path is
   the full file path with line and column `Nothing`; annotations contain
   `kubernetes.object-kind = "Secret"`, `kubernetes.namespace = "prod"`,
   `kubernetes.object-name = "app-credentials"`, and `kubernetes.object-key` equal to
   the file name; a caller annotation added via `annotateFileBinding` is present too.
   Additionally render the resolution report with the core's `renderResolutionText` and
   assert it contains the line fragment `kubernetes-mounted-directory source app-secrets
   from Kubernetes Secret prod/app-credentials key password`.
8. Not-a-directory: point the reader at a regular file; `Left` with
   `KubernetesNotADirectory` and the directory path.
9. Other IO error: point the reader at a directory containing a bound entry that is a
   dangling symlink (create `broken -> ..data/missing`); the failed read is classified
   (dangling symlink surfaces as does-not-exist on open — assert the actual behavior
   and record it in Surprises & Discoveries; if it reads as absent, that is acceptable
   and the test documents it as such).
10. Renderer strings: one exact-string assertion per error category through
    `renderKubernetesErrorText`, plus one `renderKubernetesErrorsText` assertion showing
    one line per problem.

Acceptance: `nix develop -c cabal test settei-kubernetes-tests
--test-show-details=direct` prints every group green and exits zero.

### Milestone 5 — documentation, ADR, collateral, closure

Scope: finish haddocks, finalize `settei-kubernetes/CHANGELOG.md`, draft the ADR, update
the MasterPlan bookkeeping, run full validation, and close the plan.

The new ADR (next free number per the coordination rule in the Decision Log; expected
docs/adr/0010) records the mounted-directory mapping semantics as durable context:
explicit per-file bindings with the dotted-key rationale; the atomic-writer handling
contract (skip `..`-prefixed entries when enumerating, follow symlinks when reading,
never descend); absent-bound-file-is-absent-leaf; unbound files surfaced only through
the inspection helper; UTF-8-only values with categorized non-echoing failure; the
strip-one-trailing-newline default and its rejected verbatim alternative; and the
`CustomSource "kubernetes-mounted-directory"` kind with the rendered-origin example.
Keep it in the family style of docs/adr/0004 (input-semantics ADRs): Context, Decision,
Consequences, Rejected Alternatives.

Guide coverage is deliberately not here: EP-24 writes the cookbook that teaches this
adapter (including the `unboundMountedFiles` startup warning) and EP-25 updates
docs/compatibility.md, the README family table, and any guide cross-links. This plan's
public documentation is the module haddock. Update the MasterPlan
(docs/masterplans/4-...) registry row for EP-22 to Complete and tick its EP-22 Progress
boxes.

Acceptance: `nix develop -c cabal test all` and `nix flake check` both green; ADR file
exists; MasterPlan updated; this plan's living sections complete.


## Concrete Steps

All commands run from the repository root, `/…/settei` (the directory containing
`cabal.project`). Every commit message follows Conventional Commits
(type(scope): summary) and carries these trailers exactly:

```text
MasterPlan: docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md
ExecPlan: docs/plans/22-create-the-settei-kubernetes-mounted-directory-source-adapter.md
Intention: intention_01kxxfcw4ke5fbb2kas9ghvv9a
```

Step 1 — preflight. Confirm a clean tree and a green baseline, and perform the
reconciliation check:

```bash
git status --short
nix develop -c cabal test all --test-show-details=direct
grep -n "renderYamlErrorText" settei-yaml/src/Settei/Yaml.hs   # EP-17 landed?
grep -n "^bindings ::" settei-env/src/Settei/Env.hs            # EP-18 landed?
ls docs/adr/                                                    # next free ADR number
```

Record the findings in Surprises & Discoveries. If either grep finds nothing, apply the
reconciliation rule from the Decision Log and note it.

Step 2 — scaffold (Milestone 1). Create the directory and files described in Plan of
Work Milestone 1, edit `cabal.project`, `nix/haskell.nix`, and `mori.dhall`, then:

```bash
cp settei-yaml/LICENSE settei-kubernetes/LICENSE
nix develop -c cabal build settei-kubernetes
nix flake check
```

Expected: the build reports `settei-kubernetes-0.1.0.0` compiled; flake check passes.
Commit:

```text
feat(kubernetes): scaffold the settei-kubernetes package

Register the new mounted-directory adapter package in cabal.project,
nix/haskell.nix, and mori.dhall with a compiling stub module.
```

(plus the three trailers).

Step 3 — implement the module (Milestone 2), then:

```bash
nix develop -c cabal build settei-kubernetes
```

Expected: compiles with no warnings (`-Wall -Wcompat` are on). Commit:

```text
feat(kubernetes): add the mounted-directory source with explicit file bindings
```

Step 4 — renderers (Milestone 3) and tests (Milestone 4). Implement, then:

```bash
nix develop -c cabal test settei-kubernetes-tests --test-show-details=direct
```

Expected transcript shape (names indicative):

```text
settei-kubernetes
  atomic writer layout
    reads bound keys through the ..data symlinks:            OK
    unboundMountedFiles skips ..-prefixed entries:           OK
  binding validation
    rejects reserved and traversal file names:               OK
    ...
All N tests passed (…s)
```

Commit (one or two commits at the implementer's discretion, each with trailers):

```text
feat(kubernetes): render mounted-directory errors as diagnostic lines
test(kubernetes): cover symlink layout, validation, provenance, and renderers
```

Step 5 — docs and closure (Milestone 5). Finish haddocks and the CHANGELOG, write the
ADR, update the MasterPlan and this plan's living sections, then run the full gate:

```bash
nix develop -c cabal build settei-kubernetes
nix develop -c cabal test settei-kubernetes-tests --test-show-details=direct
nix develop -c cabal test all --test-show-details=direct
nix flake check
```

Commit:

```text
docs(kubernetes): record mounted-directory mapping semantics and close EP-22
```

Each step is a stopping point: update the Progress checklist before and after each
commit.


## Validation and Acceptance

The change is accepted when the following behaviors are observable, not merely when code
compiles.

Build and test gates, from the repository root:

```bash
nix develop -c cabal build settei-kubernetes
nix develop -c cabal test settei-kubernetes-tests --test-show-details=direct
nix develop -c cabal test all --test-show-details=direct
nix flake check
```

All four must exit zero. The second prints one line per test case and a final
`All N tests passed`. The third proves no existing package regressed (this plan touches
no existing Haskell source, so a regression would indicate a workspace-registration
mistake). The fourth proves the Nix registration is coherent on the validated system.

Behavioral acceptance, all demonstrated inside the test suite:

- Given a temp directory laid out exactly like a kubelet projected volume (hidden
  timestamped payload directory, `..data` directory symlink, per-key file symlinks),
  binding `password` to key `database.password` and resolving a required text setting
  yields the file's content with the trailing newline stripped, and the resolution
  report's rendered text contains `kubernetes-mounted-directory source app-secrets from
  Kubernetes Secret prod/app-credentials key password`.
- `unboundMountedFiles` on that directory never returns a name beginning with `..`.
- `fileBindings` rejects, with accumulated categorized errors, every invalid shape:
  empty names, `/` or NUL in names, `.`/`..`/`..`-prefixed names, duplicate names,
  duplicate keys, and prefix-overlapping keys.
- A bound-but-absent file yields a `Right` source whose resolution reports the key
  missing only if the declaration requires it.
- A bound file containing invalid UTF-8 yields a `Left` whose message and rendered line
  contain no bytes from the file.
- Every `KubernetesSourceError` category has a pinned one-line rendering through
  `renderKubernetesErrorText`.

Success versus failure reading: a failed assertion prints the tasty-hunit expected/actual
diff and the suite exits non-zero; `cabal build` failures are compile errors naming
`settei-kubernetes/src/Settei/Kubernetes.hs`; a `nix flake check` failure after only
registration edits points at `nix/haskell.nix` (most commonly a missing `settei =
setteiPackage;` override or a typo in the path `../settei-kubernetes`).


## Idempotence and Recovery

Every step is additive and repeatable. Creating the package directory, re-editing the
three registration files, and re-running any build or test command are all safe to
repeat; Cabal and Nix builds are incremental and side-effect free. The test suite
creates all fixtures under `withSystemTempDirectory`, which removes them afterward even
on failure, so no state accumulates between runs and tests can never damage the working
tree.

If a step fails midway: registration edits can be reverted with `git checkout --
cabal.project nix/haskell.nix mori.dhall` without touching the new directory; the whole
package can be removed by deleting `settei-kubernetes/` and reverting those three files,
returning the workspace exactly to baseline (nothing else in the repository references
the package until EP-23/EP-25). If a commit was made prematurely, prefer a follow-up
`fix:` commit over history rewriting. If `cabal test all` fails in an unrelated package,
first re-run it on a clean baseline (`git stash`) to distinguish a pre-existing failure
from one introduced here, and record the finding in Surprises & Discoveries.

The dangling-symlink test (case 9) intentionally observes platform behavior rather than
prescribing it; if darwin and Linux ever disagree, keep the assertion on the validated
platform's behavior and document the divergence in Surprises & Discoveries and the ADR.


## Interfaces and Dependencies

Dependencies (library): `base >=4.21 && <5`, `bytestring >=0.12 && <0.13` (raw file
reads), `containers >=0.6.8 && <0.8` (maps for trees and annotations), `directory
>=1.3.8 && <1.4` (`doesDirectoryExist`, `listDirectory`), `filepath >=1.5.4 && <1.6`
(`</>`), `generic-lens >=2.2 && <2.4` (label access per ADR 0001), `settei ==0.1.0.0`
(core types), `text >=2.1 && <2.2`. Test suite adds `settei-kubernetes ==0.1.0.0`,
`tasty >=1.5 && <1.6`, `tasty-hunit >=0.10.2 && <0.11`, and `temporary >=1.3 && <1.4`
(plus `directory`'s `createFileLink`/`createDirectoryLink` for fixtures). Audit these
spellings against the live sibling cabal files at implementation time per the
reconciliation rule. No new flake inputs and no Kubernetes client library of any kind.

At the end of Milestone 2 the module `Settei.Kubernetes` (in
`settei-kubernetes/src/Settei/Kubernetes.hs`) exports exactly this surface, alphabetized
in the export list per family style:

```haskell
module Settei.Kubernetes
  ( FileBinding,
    FileBindings,
    KubernetesErrorCategory (..),
    KubernetesSourceError,
    MountedDirectoryOptions,
    annotateFileBinding,
    annotateMountedDirectoryOptions,
    fileBinding,
    fileBindingAnnotations,
    fileBindingKey,
    fileBindingName,
    fileBindings,
    fileBindingsList,
    keepTrailingNewline,
    kubernetesErrorCategory,
    kubernetesErrorMessage,
    kubernetesErrorName,
    kubernetesErrorPath,
    mountedDirectoryAnnotations,
    mountedDirectoryKeepsTrailingNewline,
    mountedDirectoryName,
    mountedDirectoryRef,
    readMountedDirectorySource,
    renderKubernetesErrorText,   -- Milestone 3
    renderKubernetesErrorsText,  -- Milestone 3
    unboundMountedFiles,
  )
where
```

with these signatures:

```haskell
fileBinding :: Text -> Key -> FileBinding
annotateFileBinding :: Map Text Text -> FileBinding -> FileBinding
fileBindingName :: FileBinding -> Text
fileBindingKey :: FileBinding -> Key
fileBindingAnnotations :: FileBinding -> Map Text Text

fileBindings :: [FileBinding] -> Either (NonEmpty KubernetesSourceError) FileBindings
fileBindingsList :: FileBindings -> [FileBinding]

mountedDirectoryOptions :: Text -> KubernetesRef -> MountedDirectoryOptions
annotateMountedDirectoryOptions :: Map Text Text -> MountedDirectoryOptions -> MountedDirectoryOptions
keepTrailingNewline :: MountedDirectoryOptions -> MountedDirectoryOptions
mountedDirectoryName :: MountedDirectoryOptions -> Text
mountedDirectoryRef :: MountedDirectoryOptions -> KubernetesRef
mountedDirectoryAnnotations :: MountedDirectoryOptions -> Map Text Text
mountedDirectoryKeepsTrailingNewline :: MountedDirectoryOptions -> Bool

kubernetesErrorCategory :: KubernetesSourceError -> KubernetesErrorCategory
kubernetesErrorName :: KubernetesSourceError -> Maybe Text
kubernetesErrorPath :: KubernetesSourceError -> Maybe FilePath
kubernetesErrorMessage :: KubernetesSourceError -> Text

readMountedDirectorySource ::
  MountedDirectoryOptions ->
  FileBindings ->
  FilePath ->
  IO (Either (NonEmpty KubernetesSourceError) Source)

unboundMountedFiles :: FileBindings -> FilePath -> IO [Text]

renderKubernetesErrorText :: KubernetesSourceError -> Text
renderKubernetesErrorsText :: NonEmpty KubernetesSourceError -> Text
```

Types consumed from the core (`settei` package, imported via the `Settei` umbrella and
`Settei.Prelude` per family convention): `Key`, `Source`, `SourceLocation`,
`SourceKind (CustomSource)`, `RawValue (RawObject, RawText)`, `KubernetesRef`,
`KubernetesObjectKind`, `kubernetesRef`, `kubernetesAnnotations`, `source`,
`locateSource`, `annotateSource`, `annotateSourceAt`, `keySegments`, `renderKey`.
Dependency direction per the MasterPlan: `settei-kubernetes` depends only on `settei`
(EP-23 may later add `settei-env`); nothing in the existing family depends on
`settei-kubernetes`.
