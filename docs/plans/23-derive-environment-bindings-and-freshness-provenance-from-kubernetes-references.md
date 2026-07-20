---
id: 23
slug: derive-environment-bindings-and-freshness-provenance-from-kubernetes-references
title: "Derive environment bindings and freshness provenance from Kubernetes references"
kind: exec-plan
created_at: 2026-07-19T15:20:08Z
intention: "intention_01kxxfcw4ke5fbb2kas9ghvv9a"
master_plan: "docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md"
---

# Derive environment bindings and freshness provenance from Kubernetes references

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

The 2026-07-19 API review of Settei's Kubernetes support found two provenance gaps that
matter during incidents. First, a `KubernetesRef` (the cluster-independent record naming a
ConfigMap or Secret, defined in settei/src/Settei/Origin.hs) and the environment binding
it decorates are assembled independently by hand. The reference service's binding list in
examples/settei-service/src/Settei/Example/Service.hs (around line 249) shows the pattern:
the user writes `kubernetesRef SecretObject Nothing "settei-example-service-database"
(Just "password")` in one expression and `binding (EnvName "DATABASE_PASSWORD")
databasePasswordKey` in another, and nothing ties the Secret data key `"password"` to the
variable `DATABASE_PASSWORD`. If either side is edited, the provenance annotation silently
lies about which Secret key actually feeds which variable — the worst kind of incident
documentation, because it looks authoritative. Second, origins from mounted Kubernetes
volumes carry no freshness or identity metadata: a `--explain-config` report cannot say
which directory a value was read from or when that file last changed, so during an
incident an operator cannot distinguish a stale mount from a current one.

After this plan is implemented, both gaps are closed without touching any core type.
A user writes one atomic construction —

```haskell
bindingsFromSecret
  Nothing
  "settei-example-service-database"
  [objectKeyBinding "password" (EnvName "DATABASE_PASSWORD") databasePasswordKey]
```

— and receives the validated `Bindings` collection from settei-env in which every
generated binding already carries the Kubernetes annotations of a per-key reference whose
`kubernetes.object-key` IS the data key it was constructed from. The annotation cannot
drift from the binding because there is no seam between them. Separately, the
mounted-directory source created by EP-22
(docs/plans/22-create-the-settei-kubernetes-mounted-directory-source-adapter.md) gains
three new descriptive annotations — `kubernetes.mount-path`, `kubernetes.file-modified`,
and `kubernetes.read-at` — so every origin from a projected volume answers "read from
which directory, file last modified when, snapshot taken when". The core text renderer
learns one minimal addition: when `kubernetes.file-modified` is present, the existing
"from Kubernetes …" suffix appends the modification time. You can see all of it working by
running the settei-kubernetes, settei-env, and settei test suites (commands in Validation
and Acceptance), and by reading a temp-directory fixture through the mounted source and
rendering its resolution report: the report line ends with something like
`from Kubernetes ConfigMap payments/service-config key host (modified
2026-07-19T15:20:08Z)`.


## Progress

- [x] (2026-07-20T02:05:46Z) Step 0 preflight: EP-22, EP-18, and EP-17 landing status verified against the
      working tree; actual `settei-kubernetes` module layout, source-reader name, error
      type, and test-suite name recorded in Surprises & Discoveries; actual post-EP-18
      `Settei.Env` surface (`Bindings`, `bindings`, `bindingsList`) confirmed; baseline
      `cabal test all` green.
- [x] (2026-07-20T02:07:46Z) Milestone 1: `mergeBindings` added to settei-env/src/Settei/Env.hs with haddock and
      export-list entry; merge tests (valid merge, cross-collection duplicate name,
      cross-collection overlapping keys, empty list) in
      settei-env/test/Settei/EnvTest.hs; settei-env/CHANGELOG.md Unreleased entry;
      `settei-env-tests` green; commit 1 with required trailers.
- [x] (2026-07-20T02:11:33Z) Milestone 2: new module `Settei.Kubernetes.Bindings` in settei-kubernetes with
      `ObjectKeyBinding`, `objectKeyBinding`, `bindingsFromSecret`,
      `bindingsFromConfigMap`; exposed-modules entry in
      settei-kubernetes/settei-kubernetes.cabal (plus settei-env/time build-depends as
      needed).
- [x] (2026-07-20T02:11:33Z) Milestone 2: derivation tests — exact equivalence with the hand-written reference
      service Secret entry (annotation maps equal), ConfigMap analog, namespace handling,
      invalid-list rejection, merge with a manual collection; settei-kubernetes suite
      green; settei-kubernetes/CHANGELOG.md entry; commit 2 with required trailers.
- [x] (2026-07-20T02:17:37Z) Milestone 3: freshness annotations wired into EP-22's mounted-directory reader —
      `kubernetes.mount-path` and `kubernetes.read-at` source-wide via `annotateSource`,
      `kubernetes.file-modified` per key via `annotateSourceAt`; temp-dir fixture tests
      asserting presence and ISO-8601 parseability; settei-kubernetes suite green;
      changelog entry; commit 3 with required trailers.
- [ ] Milestone 4: core `kubernetesSuffix` in settei/src/Settei/Render.hs appends
      `(modified TIME)` when present; unit tests in settei/test/Settei/RenderTest.hs for
      both the extended and unchanged suffix; golden-file impact check done
      (settei/test/golden/); settei/CHANGELOG.md entry; `settei-tests` and full suite
      green; commit 4 with required trailers.
- [ ] Milestone 5: shared settei-kubernetes ADR extended (or standalone ADR written per
      the recorded contingency) with the freshness/identity vocabulary; dated amendment
      note added to docs/adr/0003; MasterPlan registry row EP-23 and Progress checkboxes
      updated; this plan's living sections updated; final full suite green; commit 5 with
      required trailers.
- [ ] ADR distillation pass performed; plan marked complete.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- EP-22 landed with the provisional public surface intact: module
  `Settei.Kubernetes`, opaque `FileBindings`, smart constructors `fileBindings` and
  `mountedDirectoryOptions`, reader `readMountedDirectorySource`, error type
  `KubernetesSourceError`, source kind `CustomSource
  "kubernetes-mounted-directory"`, and test suite `settei-kubernetes-tests`. Its
  durable semantics are recorded in
  docs/adr/0011-kubernetes-mounted-directory-input-semantics.md.
  Evidence: the preflight `rg` found the reader at
  settei-kubernetes/src/Settei/Kubernetes.hs:217 and the suite at
  settei-kubernetes/settei-kubernetes.cabal:49.

- EP-18 and EP-17 landed with the names assumed by this plan: `Bindings`, `bindings`,
  `bindingsList`, and `renderEnvErrorsText` are exported by
  settei-env/src/Settei/Env.hs. No existing `mergeBindings` definition was found, so
  Milestone 1 remains necessary.

- The 2026-07-20 preflight full-suite baseline passed before implementation: 102 core
  tests, 26 settei-kubernetes tests, 16 settei-env tests, and every other workspace
  suite reported `PASS`. This establishes that later failures are changes introduced
  under EP-23 rather than inherited breakage.

- Dependency lookup found `haskell/time` in Mori, with the required `getCurrentTime`,
  `formatTime`, and `parseTimeM` APIs present in its source; Mori had no registered
  projects for `directory` or `temporary`. Those two dependencies and their bounds
  already belonged to EP-22, so EP-23 introduced no guess or compatibility change for
  them. The authoritative Hackage package index and upstream tag list both reported
  `time-1.16`, while the GHC 9.12.4 dev shell provides `time-1.14`.


## Decision Log

- Decision: The derivation constructors live in a NEW module,
  `Settei.Kubernetes.Bindings`, inside the settei-kubernetes package, not in EP-22's
  source-adapter module and not in settei-env.
  Rationale: The MasterPlan's Integration Points assign EP-23 "the bindings-derivation
  and freshness modules" within settei-kubernetes, and the dependency direction
  (settei-kubernetes may depend on settei and settei-env; nothing depends on
  settei-kubernetes) makes it the only package that can see both `KubernetesRef` and
  `Bindings`. A separate module keeps the mounted-directory source module free of
  settei-env vocabulary for adopters who use only mounted files, and it avoids edit
  collisions with EP-22's module. Contingency: as of authoring (2026-07-19) EP-22's plan
  file is an unfilled skeleton, so if EP-22 lands with a different module convention
  (for example a single `Settei.Kubernetes` public module that re-exports everything),
  put the new definitions in `Settei.Kubernetes.Bindings` anyway and add re-exports to
  match EP-22's convention; record the reconciliation here.
  Date: 2026-07-19

- Decision: The record is `data ObjectKeyBinding = ObjectKeyBinding { objectKey :: Text,
  envName :: EnvName, targetKey :: Key }` with strict fields, `stock (Generic, Eq,
  Show)` deriving, and a total constructor function `objectKeyBinding :: Text -> EnvName
  -> Key -> ObjectKeyBinding`. The role-specific field names (rather than ADR 0001's
  generic `name`/`key` labels) are deliberate: the record contains three key-like things
  — a Kubernetes data key, a variable name, and a Settei structural key — and generic
  labels would make call sites ambiguous to human readers even though
  `DuplicateRecordFields` would compile. `Show` is safe because the record holds only
  names and keys, never values.
  Date: 2026-07-19

- Decision: The derivation functions are `bindingsFromSecret :: Maybe Text -> Text ->
  [ObjectKeyBinding] -> Either (NonEmpty EnvError) Bindings` and `bindingsFromConfigMap`
  with the same shape (arguments: optional namespace, object name, key triples), both
  thin wrappers over one private helper taking `KubernetesObjectKind`. They reuse
  settei-env's `EnvError` unchanged — no new error type and no wrapper — because every
  possible failure is a binding-list validation failure (invalid variable name, duplicate
  name, duplicate or overlapping target keys), which is exactly `EnvError`'s vocabulary,
  and the caller merges the result with other `Bindings` values whose errors are also
  `EnvError`. Each generated `EnvBinding` is annotated with `kubernetesAnnotations` of a
  per-key ref built as `kubernetesRef kind namespace objectName (Just objectKey)`, so
  `kubernetes.object-key` is definitionally the data key the binding was constructed
  from. Duplicate `objectKey` values across triples are legal (Kubernetes allows one
  Secret key to feed several variables); duplicate `envName` or conflicting `targetKey`
  values are rejected by the shared validation.
  Date: 2026-07-19

- Decision: Composition with hand-written bindings goes through a new ADDITIVE settei-env
  function `mergeBindings :: [Bindings] -> Either (NonEmpty EnvError) Bindings`,
  implemented as re-validation of the concatenated lists
  (`bindings . concatMap bindingsList`). EP-18
  (docs/plans/18-make-environment-bindings-total-and-validated.md) planned no merge
  operation, so this plan adds one; it is a justified settei-env edit because merging is
  a property of the `Bindings` abstraction, not of Kubernetes, and settei-kubernetes
  cannot implement it without settei-env exposing internals. Rejected alternative: a
  `Semigroup Bindings` instance — rejected because merging two individually valid
  collections can produce an invalid combination (duplicate variable names, overlapping
  target keys across the two), and a lawful total `Semigroup` cannot fail; an `error`
  inside `<>` would reintroduce exactly the partiality EP-18 removed. Rejected
  alternative: making the derivation functions accept mixed raw lists — rejected because
  it forces every derived collection back to unvalidated `[EnvBinding]` and duplicates
  the merge decision in every adapter. The list-typed signature covers the common
  three-way case (derived Secret + derived ConfigMap + manual) in one call; the empty
  list yields the valid empty collection.
  Date: 2026-07-19

- Decision: This plan OWNS three new annotation names in the shared `kubernetes.*`
  vocabulary of docs/adr/0003: `kubernetes.mount-path` (the directory the mounted source
  was read from, as given to the reader), `kubernetes.file-modified` (per-key file
  modification time of the actual file read, after any Kubernetes atomic-writer symlink
  resolution), and `kubernetes.read-at` (source-wide wall-clock time at which the
  directory snapshot was taken). `kubernetes.read-at` IS included — during an incident it
  directly answers "how stale is what this pod loaded" by comparison with
  `kubernetes.file-modified` and with the incident timeline — with a recorded clock-trust
  caveat: both timestamps come from the node's clock as seen by the container (file
  mtimes are written by the kubelet's atomic writer), so cross-machine comparisons are
  only as good as the cluster's clock discipline; the annotations are triage evidence,
  not proof. Timestamps are ISO-8601 UTC at whole-second precision with a trailing `Z`
  (format string `%Y-%m-%dT%H:%M:%SZ`): deterministic width, greppable, and sub-second
  precision has no triage value while some filesystems do not provide it. All three are
  descriptive only and never affect precedence — restating docs/adr/0003's rule that
  annotations are descriptive and precedence belongs exclusively to list position.
  Captured in IO at read time inside EP-22's directory reader; never captured lazily.
  Date: 2026-07-19

- Decision: The core text renderer's `kubernetesSuffix`
  (settei/src/Settei/Render.hs, lines 152–164) is extended minimally: when
  `kubernetes.file-modified` is present it appends ` (modified TIME)` after the existing
  kind/namespace/name/key text; `kubernetes.mount-path` and `kubernetes.read-at` are NOT
  rendered in the text suffix. Weighing: text reports are read line-by-line during
  incidents, and the modification time is the single freshness fact worth the line
  length; the mount path duplicates what the origin's source name and `SourceLocation`
  already convey for mounted sources, and `read-at` is source-wide triage data rather
  than per-value provenance. JSON output needs no change at all — `originJson` already
  emits the complete ordered annotation map, so all three names appear there
  automatically. Because the suffix is driven purely by annotations (not by
  `SourceKind`), this works regardless of which `SourceKind` EP-22 chose for the mounted
  source. This is a small additive core change; the golden files under
  settei/test/golden/ were grepped on 2026-07-19 and contain no `from Kubernetes` text,
  so no existing golden should change — Milestone 4 still performs the check.
  Date: 2026-07-19

- Decision: The freshness/identity vocabulary is recorded by EXTENDING the shared
  settei-kubernetes semantics ADR that EP-22 creates (one ADR for the package's
  mounted-directory mapping and its annotation vocabulary), not by a new standalone ADR.
  The MasterPlan's Integration Points explicitly leave "same or separate ADR" to this
  plan; one shared ADR keeps the package's whole provenance story in one document that
  EP-24's cookbook can cite. Contingency: EP-22 is a hard dependency and should have
  written that ADR before this plan runs; if preflight finds no settei-kubernetes ADR in
  docs/adr/, write a standalone one at the next free number (0008/0009 are presumptively
  claimed by the ergonomics initiative's EP-16/EP-17 — check `ls docs/adr/` at
  implementation time) and record the deviation here. Separately, because the CORE
  renderer sentence in docs/adr/0003 ("the text renderer recognizes core's Kubernetes
  annotation vocabulary and appends the asserted object kind, namespace, name, and key")
  changes meaning, docs/adr/0003 gets a dated amendment note in the same commit as the
  renderer change.
  Date: 2026-07-19

- Decision: Hard assumption — the derivation functions return the validated `Bindings`
  collection from post-EP-18 settei-env, constructed via the smart constructor
  `bindings :: [EnvBinding] -> Either (NonEmpty EnvError) Bindings` and inspected via
  `bindingsList :: Bindings -> [EnvBinding]`. As of authoring, EP-18 is fully planned but
  not yet implemented (settei-env/src/Settei/Env.hs still has the pre-EP-18 partial
  `envSource`). Reconciliation step: at implementation time read
  settei-env/src/Settei/Env.hs; if EP-18's final shape differs from its plan (different
  names, a richer collection type), adapt this plan's signatures to whatever actually
  landed and record the adaptation here. If EP-18 has NOT landed at all, stop: this plan
  must not proceed against the partial API (the MasterPlan orders this initiative after
  the ergonomics MasterPlan for exactly this reason).
  Date: 2026-07-19

- Decision: No reference-application or guide edits in this plan. The equivalence with
  the reference service's hand-written Secret entry is proven by a settei-kubernetes
  TEST that replicates that entry, not by editing
  examples/settei-service/src/Settei/Example/Service.hs. EP-25 owns wiring the reference
  service to the new constructors; EP-24/EP-25 own guide and cookbook coverage. This
  follows the MasterPlan's convention that EP-22/EP-23 keep example edits minimal.
  Date: 2026-07-19

- Decision: Bound the new settei-kubernetes `time` dependency as `>=1.14 && <1.17`.
  Rationale: 1.14 is the version shipped by this repository's GHC 9.12.4 development
  environment, the source APIs used by Milestone 3 are present there and in Mori's
  1.16 corpus, and both Hackage's live package index and the upstream repository tag
  1.16 as the current release. The next minor boundary is excluded under PVP.
  Date: 2026-07-20


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Settei is a multi-package Haskell configuration library. Per
docs/adr/0001-haskell-project-conventions.md, every publishable package lives in a
same-named top-level directory (`settei/` core, `settei-env/`, `settei-yaml/`,
`settei-kdl/`, `settei-dhall/`, `settei-optparse-applicative/`, and — after EP-22 —
`settei-kubernetes/`), each with its own `.cabal` file repeating the canonical
`common common` stanza (`default-language: GHC2024`, extensions `DeriveAnyClass`,
`DuplicateRecordFields`, `OverloadedLabels`, `OverloadedStrings`). House style: strict
record fields without type-name prefixes, explicit deriving strategies, lens-style field
access through `Settei.Prelude` plus a local `import Data.Generics.Labels ()` in modules
that use `#label` syntax, postpositive `qualified` imports, fourmolu formatting
(fourmolu.yaml at the root). Reference applications live under `examples/` and are the
public-API conformance boundary per
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md; they
never contact a cluster. All builds and tests run from the repository root
(/Users/shinzui/Keikaku/bokuno/settei) through the Nix dev shell:
`nix develop -c cabal test all --test-show-details=direct`.

Vocabulary. A *Source* (settei/src/Settei/Source.hs) is a named raw-value tree; an
application passes a list of sources from lowest to highest precedence and the core
resolver picks, per declared key, the rightmost present candidate. An *Origin*
(settei/src/Settei/Origin.hs) is the structured provenance attached to each candidate: a
`SourceKind`, a stable name, the logical `Key`, an optional `SourceLocation`, and an
ordered `annotations :: Map Text Text`. *Annotations* are descriptive string metadata that
never affect precedence — this is the load-bearing rule of
docs/adr/0003-resolution-provenance-and-default-semantics.md, and everything in this plan
rides annotations precisely so no core type changes. `Source` supports source-wide
annotations via `annotateSource :: Map Text Text -> Source -> Source` and composable
per-key annotations via `annotateSourceAt :: (Key -> Map Text Text) -> Source -> Source`
(both in settei/src/Settei/Source.hs, lines 56–67); when names overlap, per-key entries
win over source-wide entries (see `originFor`, line 130, which builds the origin map as
`annotationsAt key <> annotations` — left-biased `Map` union).

The Kubernetes vocabulary today. `KubernetesRef` (settei/src/Settei/Origin.hs, line 59)
is a cluster-independent record — object kind (`ConfigMapObject` or `SecretObject`),
optional namespace, object name, optional data key — built by `kubernetesRef` and
flattened to annotations by `kubernetesAnnotations` (line 88), which emits
`kubernetes.object-kind`, `kubernetes.object-name`, and optionally
`kubernetes.namespace` and `kubernetes.object-key`. The core text renderer's
`kubernetesSuffix` (settei/src/Settei/Render.hs, lines 152–164) recognizes exactly those
four names and appends text like ` from Kubernetes Secret payments/payments-database key
password` to an origin description; the JSON renderer (`originJson`, line 277) emits the
whole annotation map and needs no per-name knowledge.

The environment adapter. settei-env/src/Settei/Env.hs defines `EnvName` (a newtype over
`Text`), `EnvBinding` (strict fields `name :: EnvName`, `key :: Key`, `annotations :: Map
Text Text`; constructors private, built by `binding :: EnvName -> Key -> EnvBinding`),
`annotateBinding :: Map Text Text -> EnvBinding -> EnvBinding`, and
`fromKubernetesObject :: KubernetesRef -> EnvBinding -> EnvBinding` (line 166), which is
just `annotateBinding . kubernetesAnnotations` — the manual pairing this plan makes
atomic. `EnvError` is the validation vocabulary: `InvalidEnvironmentName`,
`DuplicateEnvironmentName`, `DuplicateTargetKey`, `ConflictingTargetKeys` (one target key
is a structural prefix of another), `PrefixedNameCollision`. After EP-18
(docs/plans/18-make-environment-bindings-total-and-validated.md — fully planned, read it
for the complete design), the module additionally exports the opaque validated collection
`Bindings`, the smart constructor `bindings :: [EnvBinding] -> Either (NonEmpty EnvError)
Bindings`, the inspector `bindingsList :: Bindings -> [EnvBinding]`, and total source
builders `envSource :: Text -> Bindings -> EnvSnapshot -> Source` /
`environmentSource :: Bindings -> EnvSnapshot -> Source`. EP-18 deliberately provides no
way to combine two `Bindings` values; Milestone 1 adds one. After EP-17
(docs/plans/17-add-error-renderers-to-every-source-adapter.md), the module also exports
`renderEnvErrorsText :: NonEmpty EnvError -> Text`, which callers of this plan's
derivation functions can use to print failures.

The motivating call site. examples/settei-service/src/Settei/Example/Service.hs defines
`environmentBindings` (around line 241 pre-EP-18; a `Bindings` CAF post-EP-18) whose last
entry is the hand-assembled pair this plan makes atomic:

```haskell
fromKubernetesObject
  (kubernetesRef SecretObject Nothing "settei-example-service-database" (Just "password"))
  (binding (EnvName "DATABASE_PASSWORD") databasePasswordKey)
```

Nothing checks that `"password"` and `DATABASE_PASSWORD` belong together; a later edit to
either expression leaves a well-typed lie.

The mounted-directory source. EP-22
(docs/plans/22-create-the-settei-kubernetes-mounted-directory-source-adapter.md) creates
the settei-kubernetes package: a source adapter that reads a projected ConfigMap or
Secret volume — the standard Kubernetes mount shape where each object data key becomes
one file in a directory, with the kubelet's atomic-writer symlink layout (`..data`
indirection) — as an ordinary `Source` with explicit per-file key bindings mirroring
settei-env's philosophy, plus an error type and text renderer following EP-17's
`render<X>ErrorText`/`render<X>ErrorsText` contract. This plan HARD-DEPENDS on EP-22.
Important authoring-time caveat: on 2026-07-19 EP-22's plan file is still an unfilled
skeleton and the settei-kubernetes directory does not exist, so the exact names EP-22
will choose — the public module name (assumed `Settei.Kubernetes`), the reader function
(assumed `readMountedDirectorySource`, per the MasterPlan's wording), the file-bindings
structure mapping data-key files to Settei `Key`s, the error type, the chosen
`SourceKind`, and the test-suite name (assumed `settei-kubernetes-tests` by the family
convention `<package>-tests`) — are assumptions. Step 0 verifies every one of them
against the landed EP-22 and records corrections in Surprises & Discoveries. Two design
choices in this plan are deliberately insensitive to EP-22's decisions: the renderer
extension keys on annotations rather than `SourceKind`, and the freshness annotations
attach through the generic `annotateSource`/`annotateSourceAt` combinators that every
`Source` supports.

Relevant ADRs consulted (repository-relative paths):
docs/adr/0001-haskell-project-conventions.md (layout, stanza, style — governs all new
code here); docs/adr/0003-resolution-provenance-and-default-semantics.md (annotations are
descriptive and never affect precedence; core owns the four `kubernetes.*` names above;
adapters may add annotation names without introducing format cases into the resolver;
adapter annotations must never copy raw candidate values — mount paths and timestamps are
metadata, never values, so the new names comply; the renderer sentence this plan amends);
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md (why this
plan adds tests instead of example edits). docs/adr/0004/0005/0006 are format-adapter
ADRs not directly relevant. The ergonomics initiative's ADRs (numbers 0008/0009 expected
from EP-16/EP-17, plus EP-18's construction-validation ADR and EP-22's settei-kubernetes
ADR) will exist by implementation time; read whichever of them exist for the renderer
contract and the shared-ADR extension point.

Parent MasterPlan:
docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md,
registry row EP-23 (hard dependency EP-22; no soft dependencies). Its binding decisions
for this plan: freshness/identity ride the annotation vocabulary, NOT a `KubernetesRef`
record change; EP-23 owns the new annotation names and the renderer decision; any core
change is minimal and additive.


## Plan of Work

The work is five milestones plus a preflight. Milestone 1 (settei-env merge) and
Milestones 2–3 (settei-kubernetes) could in principle be reordered, but Milestone 2's
merge test consumes Milestone 1's function, so do them in order. Milestone 4 (core
renderer) is independent of 1–3 at the code level but is sequenced after them so the
freshness tests exist to demonstrate the rendered output end to end. Milestone 5 is the
written record.

Step 0 — preflight. Confirm a clean tree and green baseline, then verify the three
upstream plans actually landed with the shapes this plan assumes: EP-18's `Bindings`
surface in settei-env/src/Settei/Env.hs, EP-17's `renderEnvErrorsText`, and EP-22's
settei-kubernetes package (module layout, reader name and signature, file-bindings
structure, error type, `SourceKind`, test-suite name in
settei-kubernetes/settei-kubernetes.cabal, and whether EP-22's ADR exists in docs/adr/).
Record every confirmed or corrected name in Surprises & Discoveries before writing code.
If EP-18 or EP-22 has not landed, stop and surface that — this plan cannot proceed.

Milestone 1 — an explicit merge for validated bindings, in settei-env. Scope: one
additive function plus tests and a changelog line. At the end, two independently
validated `Bindings` collections can be combined into one, with cross-collection
conflicts (a variable name bound in both, or target keys that collide across the two)
rejected through the same `EnvError` vocabulary as construction. In
settei-env/src/Settei/Env.hs, add to the export list (alphabetically, near `bindings`)
and define next to `bindings`:

```haskell
-- | Merge validated collections into one, re-validating cross-collection conflicts.
--
-- Two individually valid collections can still collide with each other (a variable
-- name bound in both, or target keys that overlap across them), so merging returns
-- the same 'EnvError' vocabulary as 'bindings'. The empty list yields the valid
-- empty collection. Order is preserved: earlier collections contribute earlier
-- bindings.
mergeBindings :: [Bindings] -> Either (NonEmpty EnvError) Bindings
mergeBindings = bindings . concatMap bindingsList
```

(Adapt the exact identifiers to whatever EP-18 landed; the semantics — concatenate then
re-validate through the one shared validator — are the contract.) Tests in
settei-env/test/Settei/EnvTest.hs, in a new `testGroup "merging validated bindings"`:
merging two disjoint valid collections succeeds and `bindingsList` of the result is the
concatenation in order; merging collections that share a variable name fails with
`DuplicateEnvironmentName`; merging collections whose target keys overlap structurally
(`service` in one, `service.port` in the other) fails with `ConflictingTargetKeys`;
`mergeBindings []` succeeds with an empty list. Add the settei-env/CHANGELOG.md
Unreleased entry (below the EP-18 breaking entry if present):

```markdown
- Add `mergeBindings`: combine validated `Bindings` collections with re-validation of
  cross-collection conflicts, enabling derived and hand-written bindings to compose.
```

Acceptance: `nix develop -c cabal test settei-env-tests --test-show-details=direct`
passes.

Milestone 2 — atomic ref-plus-binding derivation, in settei-kubernetes. Scope: one new
module, its tests, cabal wiring, changelog. At the end, the one-construction API exists
and is proven annotation-for-annotation equal to the hand-written idiom. Create
settei-kubernetes/src/Settei/Kubernetes/Bindings.hs:

```haskell
-- |
-- Module: Settei.Kubernetes.Bindings
-- Description: Derive validated environment bindings from Kubernetes object references.
module Settei.Kubernetes.Bindings
  ( ObjectKeyBinding (..),
    bindingsFromConfigMap,
    bindingsFromSecret,
    objectKeyBinding,
  )
where

import Data.Generics.Labels ()
import Settei
import Settei.Env
import Settei.Prelude

-- | One row of a derivation: this data key feeds this variable at this target key.
--
-- Holds only names and keys, never configuration values.
data ObjectKeyBinding = ObjectKeyBinding
  { objectKey :: !Text,
    envName :: !EnvName,
    targetKey :: !Key
  }
  deriving stock (Generic, Eq, Show)

-- | Construct one derivation row.
objectKeyBinding :: Text -> EnvName -> Key -> ObjectKeyBinding
objectKeyBinding objectKey envName targetKey =
  ObjectKeyBinding {objectKey, envName, targetKey}

-- | Derive validated bindings from one Secret: namespace, object name, key rows.
--
-- Every generated binding carries the annotations of a per-key reference whose
-- @kubernetes.object-key@ is the row's data key, so the provenance annotation cannot
-- drift from the binding. Validation is settei-env's: invalid or duplicate variable
-- names and duplicate or overlapping target keys are rejected as 'EnvError's.
bindingsFromSecret ::
  Maybe Text -> Text -> [ObjectKeyBinding] -> Either (NonEmpty EnvError) Bindings
bindingsFromSecret = bindingsFromObject SecretObject

-- | 'bindingsFromSecret' for a ConfigMap reference.
bindingsFromConfigMap ::
  Maybe Text -> Text -> [ObjectKeyBinding] -> Either (NonEmpty EnvError) Bindings
bindingsFromConfigMap = bindingsFromObject ConfigMapObject

bindingsFromObject ::
  KubernetesObjectKind ->
  Maybe Text ->
  Text ->
  [ObjectKeyBinding] ->
  Either (NonEmpty EnvError) Bindings
bindingsFromObject kind namespace objectName rows = bindings (fmap derive rows)
  where
    derive row =
      fromKubernetesObject
        (kubernetesRef kind namespace objectName (Just (row ^. #objectKey)))
        (binding (row ^. #envName) (row ^. #targetKey))
```

Register the module under `exposed-modules` in
settei-kubernetes/settei-kubernetes.cabal and ensure `build-depends` includes
`settei-env` (EP-22 may or may not have added it) and `generic-lens` (required by the
local label import per docs/adr/0001). Note that duplicate `objectKey` rows with distinct
variable names are deliberately legal — one Secret key may feed several variables — and
only the settei-env validation constrains the result. Tests go in EP-22's test tree
(assumed settei-kubernetes/test/, suite `settei-kubernetes-tests`; use whatever Step 0
recorded) in a new module or group "bindings derivation": (1) the equivalence test —
derive with `bindingsFromSecret Nothing "settei-example-service-database"
[objectKeyBinding "password" (EnvName "DATABASE_PASSWORD") databasePasswordKey]` (build
`databasePasswordKey` locally the way the example does, e.g. a validated
`database.password` key) and hand-build the exact
`fromKubernetesObject (kubernetesRef SecretObject Nothing …) (binding …)` value from
examples/settei-service/src/Settei/Example/Service.hs, then assert `bindingsList
derived` equals the one-element hand-built list (`EnvBinding` has `Eq`; this compares
name, key, and the full annotation map) and additionally assert `bindingAnnotations` of
the derived binding equals `kubernetesAnnotations` of the per-key ref, naming the
annotation-map equality explicitly; (2) the ConfigMap analog including a `Just
"payments"` namespace, asserting the `kubernetes.namespace` and `kubernetes.object-kind`
entries; (3) a multi-row derivation where two rows share `objectKey` but differ in
variable and target — succeeds — and each binding's `kubernetes.object-key` matches its
own row; (4) rejection — two rows with the same `envName` yield `Left` containing
`DuplicateEnvironmentName`, overlapping target keys yield `ConflictingTargetKeys`;
(5) composition — `mergeBindings [derivedSecret, manual]` with a disjoint manual
collection succeeds, and with a manual collection reusing `DATABASE_PASSWORD` fails.
Changelog entry in settei-kubernetes/CHANGELOG.md (Unreleased):

```markdown
- Add `Settei.Kubernetes.Bindings`: derive validated environment bindings from a
  ConfigMap or Secret reference in one construction, so each binding's provenance
  annotation is generated from the same data key that feeds it.
```

Acceptance: the settei-kubernetes suite passes and the equivalence test fails if either
side of the pairing is edited alone (spot-check by temporarily changing the expected
object key and watching the diff).

Milestone 3 — freshness and identity annotations on the mounted source. Scope: edit
EP-22's reader, add fixture tests, changelog line. At the end, every candidate served by
the mounted-directory source carries the three new annotations. In EP-22's reader
(assumed `readMountedDirectorySource` in settei-kubernetes/src/Settei/Kubernetes.hs; use
Step 0's recorded reality), after the existing successful construction of the `Source`
and inside the same IO action that read the files: capture `readAt <-
Data.Time.Clock.getCurrentTime` once; for each bound file that was actually read, capture
`System.Directory.getModificationTime` on the same resolved path the reader read
(`getModificationTime` follows symlinks, which is exactly right for the kubelet's
`..data` layout — the time reflects the real target file); then attach

```haskell
annotateSource
  ( Map.fromList
      [ ("kubernetes.mount-path", Text.pack directoryPath),
        ("kubernetes.read-at", renderUtcTime readAt)
      ]
  )
```

source-wide and

```haskell
annotateSourceAt perKeyFreshness
```

per key, where `perKeyFreshness` maps each bound target `Key` to
`Map.singleton "kubernetes.file-modified" (renderUtcTime modifiedAt)` for that key's file
and returns `Map.empty` for unknown keys, and

```haskell
renderUtcTime :: UTCTime -> Text
renderUtcTime = Text.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"
```

(`formatTime`/`defaultTimeLocale` from `Data.Time.Format`; add `time` and `directory` to
settei-kubernetes's `build-depends` if EP-22 did not already — EP-22 almost certainly
depends on `directory`/`filepath`; `time` is likely new). Ordering note:
`annotateSourceAt` composes and per-key entries win over source-wide ones, and the
freshness names are disjoint from the object-reference names EP-22 already attaches, so
no existing annotation is displaced; place the freshness calls after EP-22's existing
annotation calls to keep the reader readable. If EP-22 built its per-key object
annotations through a single `annotateSourceAt` hook, either extend that hook's map or
add a second hook — both compose correctly. IMPORTANT restatement: these annotations are
descriptive only; nothing about precedence, decoding, or resolution consults them
(docs/adr/0003). Tests, in the settei-kubernetes suite: build a temp-dir fixture (use
the suite's existing temp-dir helper if EP-22 made one, else
`System.IO.Temp.withSystemTempDirectory` — check whether `temporary` is already a test
dependency) containing two files (say `host` and `port`), read it with the mounted
reader bound to two keys, then for each bound key call `lookupSource` and inspect
`candidateOrigin` (from `Settei.Provenance`, re-exported through `Settei`): assert
`kubernetes.mount-path` equals the fixture directory as passed to the reader; assert
`kubernetes.read-at` and `kubernetes.file-modified` are present and PARSE with
`Data.Time.Format.parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"` (structural
assertion — never compare exact times, which would be flaky); assert both files' keys
carry their own `kubernetes.file-modified` (touch one file to a distinct known mtime
with `System.Directory.setModificationTime` and assert the two rendered values differ,
which proves per-file capture rather than one shared timestamp); assert EP-22's existing
object-reference annotations are still present on the same origins (no displacement).
Changelog entry (settei-kubernetes/CHANGELOG.md, Unreleased):

```markdown
- Mounted-directory origins now carry freshness identity: `kubernetes.mount-path`,
  per-key `kubernetes.file-modified`, and source-wide `kubernetes.read-at`
  (ISO-8601 UTC). Descriptive only; precedence is unchanged.
```

Acceptance: the settei-kubernetes suite passes, including the two-distinct-mtimes test.

Milestone 4 — the minimal core renderer extension. Scope: one function in
settei/src/Settei/Render.hs, unit tests, golden impact check, core changelog. Edit
`kubernetesSuffix` (lines 152–164) so the `(Just objectKind, Just objectName)` branch
appends a final piece:

```haskell
        <> maybe "" (" key " <>) (origin ^. #annotations . at "kubernetes.object-key")
        <> maybe
          ""
          (\modified -> " (modified " <> modified <> ")")
          (origin ^. #annotations . at "kubernetes.file-modified")
```

The suffix stays annotation-driven: origins without `kubernetes.file-modified` render
exactly as before, so settei-env's Kubernetes-annotated bindings (which have no file
behind them) are untouched. Add unit tests in settei/test/Settei/RenderTest.hs: build an
`Origin` bearing the four object annotations plus
`("kubernetes.file-modified", "2026-07-19T15:20:08Z")` (and, to prove they are ignored
by text, `kubernetes.mount-path`/`kubernetes.read-at`), render a report or error
containing it, and assert the output contains
`from Kubernetes ConfigMap payments/service-config key host (modified
2026-07-19T15:20:08Z)`; a second test with the same origin minus `file-modified` asserts
the old suffix exactly and asserts `(modified` is absent — follow the file's existing
test idioms for constructing reports. JSON: add or extend one assertion that
`renderResolutionJson`'s annotation object for such an origin contains all seven
`kubernetes.*` entries — proving JSON needed no code change. Golden impact check: run

```bash
grep -rn "from Kubernetes" settei/test/golden/
nix develop -c cabal test settei-tests --test-show-details=direct
```

The grep printed nothing on 2026-07-19, so no golden should change; if the suite reports
a golden mismatch, inspect the diff — only lines gaining ` (modified …)` on origins that
already carried `kubernetes.file-modified` are acceptable, and any accepted regeneration
must be recorded in Surprises & Discoveries. Also run the full suite: the
examples/settei-service and conformance tests assert Kubernetes metadata by substring
(`Text.isInfixOf`) on origins WITHOUT file-modified annotations, so they must pass
unchanged. Changelog entry in settei/CHANGELOG.md (Unreleased):

```markdown
- The text renderer's Kubernetes suffix appends `(modified TIME)` when an origin
  carries the `kubernetes.file-modified` annotation. JSON output is unchanged (it
  already emits the full annotation map).
```

Acceptance: `settei-tests` green; full suite green.

Milestone 5 — the written record. Scope: ADR work and bookkeeping; no code. Extend the
settei-kubernetes ADR that EP-22 wrote (Step 0 recorded its path) with a new section
"Freshness and identity annotations": the three names, their meanings, the ISO-8601 UTC
second-precision format, the capture-at-read-time-in-IO rule, the descriptive-only rule,
the clock-trust caveat (node clock via kubelet atomic writer; triage evidence, not
proof), the renderer decision (text shows only `modified`; JSON carries everything), and
the rejected alternatives (extending the `KubernetesRef` record — rejected by the
MasterPlan because a core record change ripples through every adapter for metadata only
one adapter produces; rendering mount-path/read-at in the text suffix — rejected for
line-length against incident value). Add an `Amended: <implementation date>` line to
that ADR's header per the docs/adr/0001 style. If Step 0 found no settei-kubernetes ADR,
write a standalone one at the next free number with the same content plus a one-paragraph
context note, and record the deviation in this plan's Decision Log. Then amend
docs/adr/0003-resolution-provenance-and-default-semantics.md: add a dated amendment note
in its header and adjust the renderer sentence to say the text renderer appends the
asserted object kind, namespace, name, key, and — when present — the file modification
time, and that adapter packages own additional `kubernetes.*` freshness names (pointing
at the settei-kubernetes ADR). Finally update the MasterPlan
(docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md):
set registry row EP-23 to Complete and tick its two Progress checkboxes; update this
plan's living sections; state explicitly (here, and it is already the MasterPlan's
position) that guide and cookbook coverage of the new API is deferred to EP-24
(docs/plans/24-write-the-namespace-driven-configuration-cookbook-and-deployment-manifests.md)
and EP-25
(docs/plans/25-integrate-kubernetes-support-into-the-reference-service-and-release-collateral.md).
Haddocks were written with the code in Milestones 1–4; verify with a documentation build
(`nix develop -c cabal haddock settei-kubernetes settei-env settei` — treat warnings
about unresolved references as failures to fix). Acceptance: final full suite green,
ADR diffs present, MasterPlan updated.


## Concrete Steps

All commands run from the repository root, /Users/shinzui/Keikaku/bokuno/settei, with
cabal commands prefixed by `nix develop -c`. Every commit in this plan uses Conventional
Commits (type(scope): subject) and MUST carry these three trailers, exactly as written,
one per line at the end of the commit message body:

```text
MasterPlan: docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md
ExecPlan: docs/plans/23-derive-environment-bindings-and-freshness-provenance-from-kubernetes-references.md
Intention: intention_01kxxfcw4ke5fbb2kas9ghvv9a
```

Commit directly to the current branch; do not create a feature branch. Update this
plan's Progress section in the same commit as the work it describes.

Step 0 — preflight:

```bash
git status
nix develop -c cabal test all --test-show-details=direct
ls settei-kubernetes/src/Settei* settei-kubernetes/src/Settei/Kubernetes* 2>/dev/null || ls settei-kubernetes/src
grep -n "test-suite" settei-kubernetes/settei-kubernetes.cabal
grep -n "readMountedDirectorySource\|MountedDirectory\|SourceKind\|CustomSource\|FileSource" settei-kubernetes/src -r
grep -n "newtype Bindings\|^bindings ::\|bindingsList ::\|mergeBindings" settei-env/src/Settei/Env.hs
grep -n "renderEnvErrorsText" settei-env/src/Settei/Env.hs
ls docs/adr/
```

Interpretation: the first grep block establishes EP-22's real module and reader names and
its `SourceKind`; the settei-env greps must show `Bindings`/`bindings`/`bindingsList`
(EP-18 landed — if absent, STOP and report) and should show `renderEnvErrorsText` (EP-17;
if absent, use `show` for any failure printing in tests and note it); `ls docs/adr/`
identifies EP-22's ADR and the free numbers. Record all findings in Surprises &
Discoveries. If `mergeBindings` already exists (someone got there first), skip Milestone
1's definition, verify its semantics match this plan's contract, and record that.

Step 1 — Milestone 1 edits (settei-env), then:

```bash
nix develop -c fourmolu -i settei-env/src/Settei/Env.hs settei-env/test/Settei/EnvTest.hs
nix develop -c cabal test settei-env-tests --test-show-details=direct
```

Expected tail:

```text
All N tests passed
Test suite settei-env-tests: PASS
```

Commit:

```bash
git add settei-env docs/plans/23-derive-environment-bindings-and-freshness-provenance-from-kubernetes-references.md
git commit -m "feat(settei-env): add mergeBindings for composing validated collections" \
  -m "mergeBindings concatenates and re-validates Bindings collections so derived and
hand-written bindings can compose, with cross-collection duplicate names and
overlapping target keys rejected through the existing EnvError vocabulary." \
  -m "MasterPlan: docs/masterplans/4-deliver-kubernetes-deployment-support-and-the-namespace-configuration-cookbook.md
ExecPlan: docs/plans/23-derive-environment-bindings-and-freshness-provenance-from-kubernetes-references.md
Intention: intention_01kxxfcw4ke5fbb2kas9ghvv9a"
```

Step 2 — Milestone 2 edits (settei-kubernetes bindings module, cabal, tests, changelog),
then:

```bash
nix develop -c fourmolu -i settei-kubernetes/src/Settei/Kubernetes/Bindings.hs
nix develop -c cabal test settei-kubernetes-tests --test-show-details=direct
```

(substitute the suite name Step 0 recorded if it differs). Expected: the suite lists the
new "bindings derivation" cases and ends with `PASS`. Commit as
`feat(settei-kubernetes): derive validated env bindings from object references` with the
three trailers, staging `settei-kubernetes` and this plan file.

Step 3 — Milestone 3 edits (freshness wiring plus fixture tests), then:

```bash
nix develop -c cabal test settei-kubernetes-tests --test-show-details=direct
```

Commit as `feat(settei-kubernetes): annotate mounted origins with freshness identity`
with the three trailers.

Step 4 — Milestone 4 edits (core renderer, tests, changelog), then:

```bash
grep -rn "from Kubernetes" settei/test/golden/
nix develop -c cabal test settei-tests --test-show-details=direct
nix develop -c cabal test all --test-show-details=direct
```

The grep should print nothing (no golden contains the Kubernetes suffix as of
2026-07-19); every suite must PASS. Commit as
`feat(settei): render kubernetes.file-modified in the text origin suffix` with the three
trailers, staging `settei` and this plan file.

Step 5 — Milestone 5 edits (ADR extension or standalone ADR, docs/adr/0003 amendment,
MasterPlan bookkeeping, this plan's living sections), then the final gate:

```bash
nix develop -c cabal haddock settei-kubernetes settei-env settei
nix develop -c cabal test settei-kubernetes-tests settei-env-tests settei-tests --test-show-details=direct
nix develop -c cabal test all --test-show-details=direct
```

(the three-suite command uses the names verified in Step 0). Commit as
`docs(settei-kubernetes): record the freshness annotation vocabulary and amend ADR 0003`
with the three trailers, staging `docs` and any changelog stragglers. Perform the ADR
distillation pass: re-read this plan's Decision Log and Surprises & Discoveries and
confirm everything durable lives in the settei-kubernetes ADR and the 0003 amendment;
promote anything missed in the same commit or a final `docs(plans):` commit with the same
trailers.


## Validation and Acceptance

Acceptance is behavioral. All commands run from the repository root.

First, atomic derivation. In the settei-kubernetes suite, the equivalence test proves
that

```haskell
bindingsFromSecret Nothing "settei-example-service-database"
  [objectKeyBinding "password" (EnvName "DATABASE_PASSWORD") databasePasswordKey]
```

produces, via `bindingsList`, exactly the binding the reference service builds by hand
with `fromKubernetesObject (kubernetesRef SecretObject Nothing
"settei-example-service-database" (Just "password")) (binding (EnvName
"DATABASE_PASSWORD") databasePasswordKey)` — equal as complete `EnvBinding` values, with
the annotation-map equality (`kubernetes.object-kind = "Secret"`,
`kubernetes.object-name = "settei-example-service-database"`,
`kubernetes.object-key = "password"`) asserted by name. The rejection tests prove
derivation cannot smuggle an invalid list past validation (`DuplicateEnvironmentName`,
`ConflictingTargetKeys` observed in `Left` results), and the merge tests prove derived
and manual collections compose through `mergeBindings` with cross-collection conflicts
rejected. To see failure and success text yourself, the derivation errors render through
settei-env's `renderEnvErrorsText`.

Second, freshness provenance. The temp-dir fixture test reads a directory through the
mounted source and asserts, per bound key, an origin whose annotations contain
`kubernetes.mount-path` equal to the fixture directory, a `kubernetes.file-modified`
value and a `kubernetes.read-at` value that both parse with
`parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"` (structural, never
exact-value), distinct `kubernetes.file-modified` values for two files given distinct
mtimes, and EP-22's object-reference annotations intact alongside. Precedence is proven
untouched by the full suite: no resolver test changes in this plan.

Third, rendering. `nix develop -c cabal test settei-tests --test-show-details=direct`
passes with the new RenderTest cases: an origin with the object annotations plus
`kubernetes.file-modified = "2026-07-19T15:20:08Z"` renders a line containing

```text
from Kubernetes ConfigMap payments/service-config key host (modified 2026-07-19T15:20:08Z)
```

while the same origin without the annotation renders the pre-existing suffix with no
`(modified` text, and the JSON assertion shows all `kubernetes.*` annotations in the
origin's annotation object without any JSON code change. `grep -rn "from Kubernetes"
settei/test/golden/` prints nothing, and no golden file changed (or any change is the
documented, reviewed kind).

Fourth, the workspace gate:

```bash
nix develop -c cabal test settei-kubernetes-tests settei-env-tests settei-tests --test-show-details=direct
nix develop -c cabal test all --test-show-details=direct
```

Every suite reports `PASS` (verify the three suite names against the cabal files in Step
0 — `settei-env-tests` and `settei-tests` were confirmed on 2026-07-19;
`settei-kubernetes-tests` is EP-22's to define). The examples and conformance suites
passing unchanged proves the core renderer extension did not disturb any existing
Kubernetes-annotated output.

Fifth, the record: the settei-kubernetes ADR contains the freshness vocabulary section
(or the standalone ADR exists), docs/adr/0003 carries a dated amendment, the three
changelogs (settei-kubernetes, settei-env, settei) have their Unreleased entries, and the
MasterPlan registry row EP-23 reads Complete. Guides and the cookbook deliberately do NOT
mention the new API yet — that is EP-24/EP-25 scope, stated in both this plan and the
MasterPlan.


## Idempotence and Recovery

Every step is an additive edit-plus-test cycle in a git working tree; nothing touches
state outside the tree except the content-addressed Nix store and, in tests, temp
directories that `withSystemTempDirectory` removes even on failure. Re-running any test
or grep command is always safe. If an edit goes wrong, `git status` / `git diff` show the
damage and `git restore <path>` returns to the last commit; each milestone is one package
(or docs only), so an abandoned milestone never leaves another package broken.

Ordering constraints for recovery: Milestone 2's merge test needs Milestone 1's function
— if you must redo Milestone 1 after Milestone 2 landed, keep `mergeBindings`'s name and
signature stable or update the settei-kubernetes test in the same change. Milestone 4
can be redone independently at any time; its only coupling is the exact suffix text,
which lives in one function and its tests. If EP-22's reader changes shape under this
plan (a late EP-22 fix), only Milestone 3's wiring needs re-application — the
annotations attach through the public `annotateSource`/`annotateSourceAt` combinators,
so re-wiring is mechanical. If a timestamp test flakes, the cause is almost certainly an
exact-value comparison that violated the structural-assertion rule — fix the test, never
widen the format. If the golden check in Milestone 4 unexpectedly reports diffs, do not
regenerate blindly: inspect, and only accept diffs that are the documented
`(modified …)` addition; anything else means the suffix edit leaked into the
no-annotation path — revert settei/src/Settei/Render.hs and re-apply.

If you stop mid-milestone, first update this plan's Progress checklist, splitting the
current item into done and remaining halves, so the work can restart from this document
alone. If a concurrent plan collides (EP-24 touches only docs and manifests; EP-25 lands
after this plan), the only shared code surface is settei-kubernetes with EP-22 — merge
rule: EP-22 owns the reader's parsing and error semantics, this plan owns the
`Settei.Kubernetes.Bindings` module and the three freshness annotation names and their
attachment.


## Interfaces and Dependencies

Packages and libraries. settei-env gains no new dependency (Milestone 1 uses only
existing imports). settei-kubernetes must depend on: `settei` and `settei-env` (the
MasterPlan's sanctioned direction — nothing may depend on settei-kubernetes),
`generic-lens` (local label instance, per docs/adr/0001), `directory` (for
`getModificationTime`; also `setModificationTime` in tests), `time` (for `UTCTime`,
`getCurrentTime`, `formatTime`, `parseTimeM`), and whatever EP-22 already declared;
tests may need `temporary` for `withSystemTempDirectory` if EP-22 did not already add
it. The core settei package gains no new dependency (the renderer edit is pure text).
Version bounds follow docs/adr/0001's process: `directory`, `time`, and `temporary` ship
with or alongside GHC 9.12 — check Mori for source, then verify current released
versions on Hackage before writing bounds; do not let the local corpus set a ceiling.

Signatures that must exist at the end of each milestone (module paths in full):

```haskell
-- Milestone 1, module Settei.Env (settei-env/src/Settei/Env.hs), additive:
mergeBindings :: [Bindings] -> Either (NonEmpty EnvError) Bindings

-- Milestone 2, new module Settei.Kubernetes.Bindings
-- (settei-kubernetes/src/Settei/Kubernetes/Bindings.hs):
data ObjectKeyBinding = ObjectKeyBinding
  { objectKey :: Text, envName :: EnvName, targetKey :: Key }   -- strict fields
objectKeyBinding :: Text -> EnvName -> Key -> ObjectKeyBinding
bindingsFromSecret ::
  Maybe Text -> Text -> [ObjectKeyBinding] -> Either (NonEmpty EnvError) Bindings
bindingsFromConfigMap ::
  Maybe Text -> Text -> [ObjectKeyBinding] -> Either (NonEmpty EnvError) Bindings

-- Milestone 3, inside EP-22's reader (assumed readMountedDirectorySource in
-- settei-kubernetes/src/Settei/Kubernetes.hs): no signature change; the returned
-- Source additionally carries kubernetes.mount-path and kubernetes.read-at
-- source-wide and kubernetes.file-modified per bound key.

-- Milestone 4, module Settei.Render (settei/src/Settei/Render.hs): no exported
-- signature change; kubernetesSuffix (private) recognizes kubernetes.file-modified.
```

Consumed interfaces, by full path: from settei — `kubernetesRef`,
`kubernetesAnnotations`, `KubernetesObjectKind (..)`, `KubernetesRef`
(settei/src/Settei/Origin.hs); `annotateSource`, `annotateSourceAt`, `lookupSource`
(settei/src/Settei/Source.hs); `candidateOrigin` (settei/src/Settei/Provenance.hs,
re-exported through the umbrella `Settei` module); `Key` and key construction
(settei/src/Settei/Key.hs). From settei-env — `EnvName (..)`, `EnvBinding`, `binding`,
`annotateBinding`, `fromKubernetesObject`, `bindingAnnotations`, `EnvError (..)`, and
post-EP-18 `Bindings`, `bindings`, `bindingsList` (settei-env/src/Settei/Env.hs). From
settei-kubernetes (EP-22) — the mounted-directory reader, its file-bindings structure,
and its test scaffolding, all verified in Step 0.

Plan-level dependencies: hard dependency EP-22
(docs/plans/22-create-the-settei-kubernetes-mounted-directory-source-adapter.md — the
package and reader this plan extends); assumed-landed prerequisites from the ergonomics
MasterPlan: EP-18 (docs/plans/18-make-environment-bindings-total-and-validated.md, the
validated `Bindings` this plan returns — a blocking precondition) and EP-17
(docs/plans/17-add-error-renderers-to-every-source-adapter.md, error rendering — a soft
convenience). Downstream consumers: EP-24 and EP-25 document and integrate what this
plan builds; they are the reason no guide or example changes here.
