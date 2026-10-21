---
id: 27
slug: validate-supplied-environment-variable-names-against-declared-bindings
title: "Validate supplied environment variable names against declared bindings"
kind: exec-plan
created_at: 2026-10-21T12:57:25Z
intention: "intention_01m5f8k7kxe4za4m14re9hgsk3"
provenance:
  created_by:
    model: "claude-fable-5-1"
    harness: "claude-code"
    at: 2026-10-21T12:57:25Z
  revisions:
    - model: "claude-fable-5-1"
      harness: "claude-code"
      at: 2026-10-21T13:09:55Z
      mode: "update"
      note: "Add renderSuppliedNameErrorsJson and the settei.supplied-names document; set IR-2 accepted with targetPlan"
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-21T13:19:51Z
      mode: "update"
      note: "Address all three review findings: define safe text-name escaping, prove absent bindings use built-in defaults, and require JSON consistently in ADR instructions."
  reviews:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-10-21T13:15:09Z
      verdict: "changes-requested"
      note: "Escape hostile names in one-line text diagnostics; correct AC-5 snapshot evidence; remove superseded JSON rejection from ADR-10 instructions."
---

# Validate supplied environment variable names against declared bindings

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan implements improvement request IR-2,
docs/improvement-requests/validate-supplied-environment-variable-names.md. Its five
acceptance criteria (AC-1 through AC-5) are the acceptance obligations of this plan; each
milestone below names the criteria it discharges.


## Purpose / Big Picture

Settei is a Haskell configuration library. An application declares its settings once, and
the `settei-env` adapter translates an explicit list of environment-variable *bindings*
(variable name to setting key) into a source the core resolver reads. That translation is
deliberately permissive: only bound variables are read, and every other variable in the
process is ignored. The resolver's `RejectUnknownKeys` policy therefore cannot see an
environment variable the application does not bind, because the adapter never turns it into
a key. A deployment author who copies another service's `HASKELL_ENV` wiring into a service
that binds `ENVIRONMENT` gets no error at all: the variable is silently ignored, the
built-in default `development` stays active, and `--check-config` prints
`configuration valid`.

After this plan, `Settei.Env` exposes a small, pure helper that takes the names a deployment
intends to supply (for example the `env` entries of a container specification), compares
them with the application's validated bindings plus an explicit list of variables the
application consumes outside Settei, and reports every unsupported or duplicated name. It
never reads values, never reads the process environment on its own, and never treats a
bound-but-unsupplied variable as an error, because a setting may legitimately come from a
file, a default, or a command-line flag. An opt-in strict source builder runs the same
check against an injected snapshot before building the ordinary environment source, so a
typo fails before resolution can hide it behind a default. Diagnostics carry names only,
never values, and render both as one operator-readable sentence per problem and as one
versioned JSON document that deployment tooling can parse. The reference CLI application
exercises the helper through a repeatable `--supplied-env NAME` option.

You can see it working from the repository root once the plan is implemented:

```bash
ENVIRONMENT=production nix develop -c cabal run settei-example-cli -- --check-config; echo "exit $?"
```

prints `configuration valid` and `exit 0` even though `ENVIRONMENT` is not a variable the
example understands (it binds `HASKELL_ENV`), while

```bash
ENVIRONMENT=production nix develop -c cabal run settei-example-cli -- --supplied-env ENVIRONMENT --check-config; echo "exit $?"
```

prints `supplied environment variable ENVIRONMENT: no binding or allowance accepts it` on
stderr and `exit 3`, and

```bash
HASKELL_ENV=production nix develop -c cabal run settei-example-cli -- --supplied-env HASKELL_ENV --supplied-env HTTPS_PROXY --check-config; echo "exit $?"
```

prints `configuration valid` and `exit 0`, because `HASKELL_ENV` is bound and
`HTTPS_PROXY` is an explicitly allowed external-consumer variable, while the surrounding
shell variables such as `PATH` are never part of the checked collection.


## Progress

- [ ] Milestone 1 — Library helper in `settei-env` (AC-1, AC-2, AC-3, AC-4 at the
      library boundary): `Settei.Env` exports `Allowance`, `AcceptedNames`,
      `SuppliedNameError`, `checkSuppliedNames`, `checkedEnvSource`,
      `checkedEnvironmentSource`, `snapshotNames`, the two text renderers, and
      `renderSuppliedNameErrorsJson`;
      `nix develop -c cabal test settei-env-tests --test-show-details=direct` passes
      with the new "supplied name validation" group, including the notification-hub-shaped
      `ENVIRONMENT`/`HASKELL_ENV` fixture and the sentinel scan.
- [ ] Milestone 2 — Reference CLI application integration (AC-2, AC-3, AC-4 at the
      application boundary): `settei-example-cli` accepts repeated `--supplied-env NAME`,
      declares one allowance, rejects unsupported supplied names with exit code 3 before
      loading any file, and keeps every existing test green;
      `nix develop -c cabal test settei-example-cli-tests --test-show-details=direct`
      passes with the new cases.
- [ ] Milestone 3 — Documentation and collateral (AC-5): the environment guide shows a
      deployment author checking exactly the variables a container specification supplies
      and explains that a missing variable is not an error; CAP-5, ADR-10, ADR-9, the
      security and compatibility documents, the changelog, and the example README are
      updated; IR-2 is moved to `completed`; every OKF bundle validates strictly.
- [ ] Milestone 4 — Full validation and closure: `cabal build all`, `cabal test all`,
      `treefmt`, and `nix flake check` pass; evidence is recorded here; Outcomes &
      Retrospective is written; the ADR distillation pass is done.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: The helper lives in `Settei.Env` (package `settei-env`) and is pure. It takes
  an explicit `[EnvName]` collection and never calls `getEnvironment`; a convenience
  `snapshotNames` exposes the keys of an injected `EnvSnapshot` so a caller can
  deliberately put a process snapshot into scope.
  Rationale: IR-2 requires that unrelated inherited process variables (`PATH`, `HOME`,
  Kubernetes service-discovery variables) are excluded unless the caller includes them,
  and that the checked collection is visible to callers. Making the collection an
  argument is the simplest way to guarantee both. `settei-env` already owns the
  `Bindings` vocabulary the check compares against
  (docs/adr/0010-validate-environment-bindings-at-construction.md).
  Date: 2026-10-21

- Decision: Allowances are validated together with bindings into one opaque
  `AcceptedNames` value through `acceptedNames :: Bindings -> [Allowance] -> Either
  (NonEmpty EnvError) AcceptedNames`. An allowance with an invalid name is reported as
  `InvalidEnvironmentName`; an allowance that repeats a bound name or another allowance is
  reported as `DuplicateEnvironmentName`. No new `EnvError` constructor is added.
  Rationale: An allowance that duplicates a binding is contradictory ("consumed outside
  Settei" and "translated by Settei" at once) and would let a reversed typo pass. Reusing
  the construction-time validation pattern and error vocabulary keeps static
  programming errors fail-fast and avoids a breaking change to `EnvError`.
  Date: 2026-10-21

- Decision: Supplied-name failures use a separate type `SuppliedNameError` with exactly
  two constructors, `UnsupportedSuppliedName EnvName` and `DuplicateSuppliedName EnvName`,
  rendered as text by `renderSuppliedNameErrorText` and `renderSuppliedNameErrorsText`
  following the adapter renderer contract.
  Rationale: Construction errors are static program defects; supplied-name errors are
  runtime input failures that the reference application maps to a different exit code,
  so they must be distinguishable by type. Keeping the text renderers to the singular
  plus `Text.unlines` shape of docs/adr/0009-adapter-error-rendering-contract.md gives
  operators the same grep-friendly lines every other adapter produces.
  Date: 2026-10-21

- Decision: Text diagnostics print portable names verbatim and quote and escape all
  other names using the display rule in Milestone 1. Structured errors retain the
  original name, and JSON encodes that original name independently.
  Rationale: Supplied names are untrusted text and can contain newlines or terminal
  controls. Escaping preserves one physical line per problem without normalizing the
  name used for comparison or changing the JSON document's data.
  Date: 2026-10-21

- Decision: `Settei.Env` also exports `renderSuppliedNameErrorsJson`, producing one
  versioned document of type `settei.supplied-names` with `schemaVersion` 1, encoded by a
  small private encoder in `settei-env` that mirrors the core's conventions (compact,
  key order fixed, string escaping identical to settei/src/Settei/Render.hs). The
  binding-construction `EnvError` type stays text-only. The reference CLI application
  appends the document to stderr after the text lines when `--explain-config-json` is
  selected, mirroring how it already reports resolution failures in that mode.
  Rationale: The first draft of this plan deferred JSON, citing ADR-9's text-only rule
  and IR-3's unfixed harness format; that was reversed on 2026-10-21 after discussion.
  AC-4 names JSON output explicitly, IR-2's consumer is deployment tooling, and ADR-9
  itself deferred per-adapter JSON "because no load-time tooling consumer requires them",
  adding that they "can be added later without changing the text contract" — this
  request is that consumer. `EnvError` has no tooling consumer (it reports static
  programming mistakes at startup), so it keeps the existing contract. The core's
  encoder is private and exposing it would widen the public surface for a few lines;
  Aeson stays excluded (docs/adr/0003-resolution-provenance-and-default-semantics.md).
  Date: 2026-10-21

- Decision: Diagnostics are produced in one pass over the supplied list in encounter
  order. A name that is not accepted yields `UnsupportedSuppliedName` at its first
  occurrence; a name seen before yields `DuplicateSuppliedName` once, at its second
  occurrence; later repetitions add nothing. An empty collection succeeds.
  Rationale: Encounter order mirrors the container specification the author is reading,
  is deterministic, and needs no sorting rule to explain. `snapshotNames` returns keys in
  ascending order and documents that a map snapshot has already collapsed duplicates, so
  `checkedEnvSource` can never report `DuplicateSuppliedName`; callers holding ordered
  deployment entries must check the list before building a snapshot.
  Date: 2026-10-21

- Decision: The command-line integration is added to the reference CLI application only
  (`examples/settei-cli`), as a repeatable `--supplied-env NAME` option in its
  Configuration group, and not to `Settei.Optparse`.
  Rationale: `settei-optparse-applicative` does not depend on `settei-env`
  (settei-optparse-applicative/settei-optparse-applicative.cabal), and a fleet-wide
  spelling should wait until IR-3 defines how a preflight harness supplies names (a
  flag, a file, or a different channel). The CLI example is the right host because it
  already has the shape that hides the typo: `runtime.environment` is `required` and the
  lowest-precedence `builtInSource` supplies `development`
  (examples/settei-cli/src/Settei/Example/Cli.hs), exactly the notification-hub pattern
  IR-2 describes. docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md
  requires a public capability to be exercised by a reference application.
  Date: 2026-10-21

- Decision: The CLI example declares one allowance, `HTTPS_PROXY` with consumer label
  `http-client`, and its README states that the allowance is representative: the example
  does not open a network connection.
  Rationale: AC-2 needs an allowed non-Settei variable in the application collection.
  The example's `service.endpoint` is an HTTPS URL, so a proxy variable read by an HTTP
  client library is the most natural variable a real deployment of such a program would
  supply without Settei translating it. The originating consumer has a real instance of
  this pattern: `mori://tan/notification-hub` sets `OTEL_SERVICE_NAME` for its telemetry
  SDK outside Settei.
  Date: 2026-10-21

- Decision: Unsupported supplied names fail the reference application with the existing
  source exit code `3`, with the rendered errors on stderr and nothing on stdout, after
  the source-free schema diagnostics and before any file is opened.
  Rationale: The failure is an environment-adapter input contract violation, which the
  examples already classify under "file IO, format, or adapter error" (exit 3), not a
  typed resolution failure (exit 4) and not a usage error (exit 2). Checking before file
  loading keeps the failure independent of nonexistent paths.
  Date: 2026-10-21


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### Validation of the request

IR-2 was checked against the working tree before this plan was written. The gap it
describes is real: settei-env/src/Settei/Env.hs `envSource` (lines 156–179) builds the
source only from `presentBindings`, the bindings whose variable exists in the snapshot;
every other snapshot entry is dropped before the core sees it, so the resolver's unknown-key
policy in settei/src/Settei/Resolve.hs never observes it. The originating consumer,
`mori://tan/notification-hub/packages/notification-hub-core` (module
`NotificationHub.App.Config`), binds `ENVIRONMENT` to its environment setting, supplies
`development` from a built-in `Source`, and already resolves with `RejectUnknownKeys`; a
supplied `HASKELL_ENV` would still pass its check mode. The request belongs in Settei
because the comparison needs only `Bindings`, which `settei-env` owns and already exposes
for inspection through `bindingsList`, and because IR-2 assigns extraction of names from
Pulumi inputs to `mori://tan/tan-app-infrastructure`, leaving Settei the generic helper,
the safe diagnostics, the tests, and the example. Nothing in the request requires a new
dependency, a change to the core package, or cluster access. Neither IR-1 (plan
docs/plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md)
nor IR-3 is a prerequisite.

### What exists today

- settei-env/src/Settei/Env.hs is the whole adapter (315 lines). `EnvName` is a newtype
  over `Text`; `EnvSnapshot` is a newtype over `Map EnvName Text` built by `envSnapshot`
  from name/value pairs (last value wins for a repeated name); `EnvBinding` pairs a name,
  a `Key`, and trusted annotations; `Bindings` is the opaque validated collection built by
  `bindings`, `prefixedBindings`, or `mergeBindings`; `EnvError` has five constructors
  (`InvalidEnvironmentName`, `DuplicateEnvironmentName`, `DuplicateTargetKey`,
  `ConflictingTargetKeys`, `PrefixedNameCollision`) rendered by `renderEnvErrorText` and
  `renderEnvErrorsText`; `envSource`/`environmentSource` are the total pure translators
  and `readEnvSource`/`readEnvironmentSource` their effectful wrappers. The private
  `validEnvName` accepts an ASCII letter or underscore followed by ASCII letters, digits,
  or underscores. The private `renderEnvName` unwraps an `EnvName`.
- settei-env/test/Settei/EnvTest.hs is the adapter suite (20 tests, all passing on
  2026-10-21). It already imports `Settei` for `resolve`, `lookupSource`,
  `candidateOrigin`, `renderResolutionText`, and declares a `secretSentinel` it scans
  reports for. New tests go in this file; settei-env/test/Main.hs needs no change.
- settei-env/settei-env.cabal declares the package at version 0.2.0.0 with dependencies
  `base`, `containers`, `generic-lens`, `settei`, and `text`. No dependency is added.
- settei/src/Settei/Source.hs exports `source`, `lookupSource`, and `sourceLeaves`;
  settei/src/Settei/Key.hs exports `Key`, `parseKey`, and `renderKey`. The fixture in
  Milestone 1 builds a built-in default source with `source "built-in defaults"
  BuiltInSource (RawObject …)` exactly as examples/settei-cli/src/Settei/Example/Cli.hs
  does for `builtInSource`.
- examples/settei-cli/src/Settei/Example/Cli.hs is the reference CLI application.
  `CliOptions` holds `configInputs`, `overrides`, and `diagnosticMode`; `cliOptionsParser`
  groups options under "Configuration" and "Diagnostics"; `environmentBindings` is a
  module-level `Bindings` value forced by the test suite; `runCliWithSnapshot` dispatches
  `schemaDiagnostic` first, then `resolveCliOptions`, which loads `--config` inputs and
  resolves `[builtInSource] <> files <> [environmentSource environmentBindings snapshot]
  <> cliSources …`. Exit codes are `usageExitCode = 2`, `sourceExitCode = 3`,
  `resolutionExitCode = 4`, and failures use `failedRun code message` (stderr only).
  examples/settei-cli/app/Main.hs reads the process environment and calls
  `runCliWithSnapshot`. Tests live in examples/settei-cli/test/Settei/Example/CliTest.hs
  and parse argument lists with `expectOptions`.
- docs/guides/environment-and-cli.md (handle `DOC-4`) is the guide for `settei-env` and
  `settei-optparse-applicative`; docs/guides/cli-application.md (handle `DOC-2`)
  documents the reference CLI's options and exit codes in the "Add
  diagnostics that match user intent" and "Distinguish exit behavior" sections.
- docs/capabilities/explicit-environment-sources.md is capability record `CAP-5` for
  `settei-env`; its `evidence` rows name the adapter suite, the guide, and the service
  example.
- docs/adr/, docs/guides/, docs/capabilities/, and docs/improvement-requests/ are OKF
  bundles validated by the pre-commit hook in flake.module.nix (lines 157–170) with the
  exact `okf validate` commands repeated under Concrete Steps.
- docs/security.md ("Environment variables" section) and docs/compatibility.md ("Input
  contracts" table, row "Environment") describe the adapter's contract to adopters.

### Terms used in this plan

A **binding** maps one environment-variable name to one setting key and is static program
data. A **supplied name** is a variable name a deployment intends to set for the
application, for example one `name:` entry under a container's `env:` list; the helper
only ever sees names, never values. An **allowance** declares one variable the application
consumes outside Settei (an SDK, a runtime, an HTTP client) together with a short consumer
label, so a deployment may supply it without Settei translating it. The **accepted names**
of an application are its bound names plus its allowances. A **snapshot** is the
injectable `EnvSnapshot` map of name to value that tests and the strict builder use in
place of the process environment. The **permissive path** is today's `envSource`; the
**strict path** is the new `checkedEnvSource`, which runs the name check on a snapshot's
keys before delegating to `envSource`.

### Relationship to concurrent work

docs/plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md
(IR-1, unimplemented when this plan was written) also edits `Settei.Env`'s export list
(adding `inputBindings`), `runCliWithSnapshot` in the CLI example (adding a contract
dispatch after the schema dispatch and a `runCliWithEnvironment` wrapper), the same guide,
CAP-5's neighbour CAP-7, and the ADR log. Whichever plan lands second rebases over the
other; the changes are additive and do not conflict in meaning. If plan 26 has landed,
place this plan's name check after its contract dispatch (both are source-free) and
before file loading.

### Relevant architecture decisions

- docs/adr/0010-validate-environment-bindings-at-construction.md: `Bindings` is opaque
  and valid by construction; static binding lists are validated once and forced in tests;
  `EnvError` retains only names and keys. `AcceptedNames` follows the same pattern, and
  this plan appends an amendment recording supplied-name validation.
- docs/adr/0009-adapter-error-rendering-contract.md: every adapter error type has a
  singular one-line text renderer and a plural renderer that is the singular mapped over
  `NonEmpty` and joined with `Text.unlines`; adapter rendering is text-only; renderers
  concatenate only retained fields; per-adapter JSON was deferred "because no load-time
  tooling consumer requires them" and "can be added later without changing the text
  contract". The new text renderers follow the contract, and the ADR is amended to admit
  the supplied-name JSON document as the tooling-consumer exception it anticipated.
- docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md: public
  capabilities are exercised by the internal reference applications; the CLI keeps
  distinct usage, source, and resolution exit codes; schema diagnostics are source-free.
  This plan adds the option to the CLI example and keeps the exit-code discipline.
- docs/adr/0003-resolution-provenance-and-default-semantics.md is relevant only as a
  boundary: the core resolver continues to own requiredness, unknown-key policy, and value
  decoding; the helper never resolves anything.

No existing ADR covers supplied-name validation; Milestone 3 amends ADR-10 rather than
creating a new record so that the two environment-validation decisions stay together
(plan 26 allocates the next free handle, ADR-12, for a different topic).


## Plan of Work

### Milestone 1 — Library helper in `settei-env`

Scope: the pure library surface and its tests. At the end, a Haskell caller can build
`AcceptedNames` from its bindings and allowances, check any list of names against it, and
build the ordinary environment source through a strict path that refuses unsupported
names, with tests proving each acceptance criterion at the library boundary.

Extend settei-env/src/Settei/Env.hs with the types and functions listed under Interfaces
and Dependencies, keeping the existing definitions untouched. `Allowance` is a record of
`name :: EnvName` and `consumer :: Text` with a private constructor and the accessors
`allowanceName` and `allowanceConsumer`. `AcceptedNames` holds the original `Bindings`
and the allowance list; `acceptedNames` validates the allowances with the same private
`validEnvName` check the bindings use and rejects any allowance name that equals a bound
name or an earlier allowance, returning the existing `EnvError` constructors in the
order invalid names (allowance order) then duplicates (ascending). `acceptedNamesList`
returns bound names in binding order followed by allowances in declaration order, each
tagged `BoundTo key` or `ConsumedBy consumer`; `acceptedBindings` returns the bindings so
an application can keep one top-level value.

`checkSuppliedNames` walks the supplied list once as fixed in the Decision Log and returns
`Right ()` or the non-empty diagnostics in encounter order. `snapshotNames` returns the
snapshot's keys in ascending order. `checkedEnvSource label accepted snapshot` runs
`checkSuppliedNames accepted (snapshotNames snapshot)` and, on success, returns exactly
`envSource label (acceptedBindings accepted) snapshot`; `checkedEnvironmentSource` fixes
the label to `"environment"`. The two renderers produce, respectively,
`supplied environment variable NAME: no binding or allowance accepts it` and
`supplied environment variable NAME: supplied more than once`, and the plural renderer is
`Text.unlines . fmap renderSuppliedNameErrorText . NonEmpty.toList`.

In those sentences, `NAME` is a display representation, never raw interpolation of
arbitrary input. A name satisfying `validEnvName` is printed verbatim, preserving the
ordinary-name transcripts. Otherwise wrap it in double quotes and use the JSON string
escapes specified below, additionally escaping U+007F–U+009F, U+2028, and U+2029 as
four-digit lowercase `\u` escapes for text display. This includes empty names, spaces,
quotes, backslashes, newlines, carriage returns, tabs, and escape characters without
letting them create additional diagnostic lines or terminal controls. Keep this display
helper private. Both error constructors use it; comparison and the retained `EnvName`
remain byte-for-byte unchanged. JSON encodes the original name, not this display string.

`renderSuppliedNameErrorsJson` renders the same non-empty list as one compact JSON
document with no whitespace and no trailing newline (callers that print it append `"\n"`,
as `schemaDiagnostic` does for schema JSON). For the list `[UnsupportedSuppliedName
"HASKELL_ENV", DuplicateSuppliedName "PORT"]` the output is exactly

```json
{"schemaVersion":1,"type":"settei.supplied-names","errors":[{"kind":"unsupported-supplied-name","name":"HASKELL_ENV"},{"kind":"duplicate-supplied-name","name":"PORT"}]}
```

Implement it with three private helpers in settei-env/src/Settei/Env.hs — `jsonObject`,
`jsonArray`, and `jsonString` — copied in shape from settei/src/Settei/Render.hs lines
443–473: a string is wrapped in double quotes with `"` and `\` escaped by a backslash,
`\b`, `\f`, `\n`, `\r`, and `\t` written as those two-character escapes, every other
character below U+0020 written as `\u` followed by four zero-padded lowercase hexadecimal
digits, and everything else verbatim. Supplied names are not validated on the way in (an
unsupported name may be any text), so the escaping is load-bearing, not decorative. Keep
the helpers private, add no dependency, and do not expose the core's encoder. Export
everything new from the module header in alphabetical order like the existing list, and
update the module description comment to mention supplied-name validation.

Add a `testGroup "supplied name validation"` to settei-env/test/Settei/EnvTest.hs with at
least these cases. Known names: a list of two bound names and one allowed name against
accepted names built from three bindings and one allowance returns `Right ()`. Multiple
unsupported names: `[HASKELL_ENV, DATABASE_URL, DB_URL]` against bindings for
`ENVIRONMENT` and `DATABASE_URL` returns exactly `[UnsupportedSuppliedName HASKELL_ENV,
UnsupportedSuppliedName DB_URL]`, and calling it twice gives the same list. Empty
collection returns `Right ()`. Duplicates: `[PORT, PORT, PORT, HOST]` with `PORT` bound
and `HOST` unbound returns `[DuplicateSuppliedName PORT, UnsupportedSuppliedName HOST]`.
Allowance scope (AC-2): an application collection `[ENVIRONMENT,
OTEL_EXPORTER_OTLP_ENDPOINT, HASKELL_ENV]` where the second is an allowance labelled
`opentelemetry-sdk` returns only `UnsupportedSuppliedName HASKELL_ENV`, while a process
snapshot containing `PATH`, `HOME`, and `KUBERNETES_SERVICE_HOST` in addition is shown to
be out of scope: `checkSuppliedNames` on the explicit list ignores it, and
`snapshotNames` of that snapshot contains `PATH`, proving the caller must opt in to a
process-wide check. Construction: `acceptedNames` rejects an allowance named `1BAD`
(`InvalidEnvironmentName`), an allowance equal to a bound name, and two equal allowances
(`DuplicateEnvironmentName`). Strict path (AC-3): declare `required` a public enum
setting at `runtime.environment` with spellings `development`/`production`, a built-in
source `source "built-in defaults" BuiltInSource` supplying `development`, and accepted
names from the single binding `ENVIRONMENT`; with the snapshot `[("HASKELL_ENV",
"production")]`, `resolve defaultResolveOptions [builtIn, environmentSource b snapshot]`
succeeds with `development` (the hidden typo), `checkedEnvironmentSource` returns
`Left (UnsupportedSuppliedName HASKELL_ENV :| [])`, and with the corrected snapshot
`[("ENVIRONMENT", "production")]` the strict builder returns a source that resolves to
`production` and whose `lookupSource` candidate for the key carries the same
`environment.variable` annotation as the permissive source (compatibility). Sentinels
(AC-4): with the snapshot `[("ENVIRONMENT", knownSentinel), ("HASKELL_ENV",
unknownSentinel)]` the strict builder fails and neither sentinel appears in `show` of the
errors, in `renderSuppliedNameErrorsText`, or in `renderSuppliedNameErrorsJson`; and a
successful strict source still redacts
a secret setting in `renderResolutionText` exactly as the existing "Secret annotation
remains redacted" test proves for the permissive path. Rendering: both singular text forms, the plural newline law, the exact JSON document
shown above for the two-error list, byte-identical JSON on two calls with the same input,
and a supplied name containing a double quote, a backslash, a newline, and U+0001 (for
example `EnvName "BAD\"\\\n\SOHNAME"`) reported as unsupported and rendered in JSON as
`"BAD\"\\\n\u0001NAME"`, mirroring `errorRenderingTests`.
Use the same hostile name to pin the complete singular text sentence for both error
constructors and the plural output. Add empty-name, carriage-return, tab, ESC, DEL,
U+0085, U+2028, and U+2029 cases: singular output has no physical line break or raw
control character, and plural output has exactly one terminating newline per error.
Assert ordinary portable names keep the existing unquoted spelling. JSON goldens must
encode the original hostile name once, without the text renderer's surrounding quotes
or double escaping.

Add an `## Unreleased` section at the top of settei-env/CHANGELOG.md describing the new
functions as an additive minor change.

### Milestone 2 — Reference CLI application integration

Scope: prove the helper at the conformance boundary and give deployment authors a command
to run.

In examples/settei-cli/src/Settei/Example/Cli.hs add a module-level
`acceptedEnvironmentNames :: AcceptedNames` built from `environmentBindings` and the one
allowance `allowance "http-client" (EnvName "HTTPS_PROXY")`, forced through the same
`either (error . Text.unpack . renderEnvErrorsText) id` pattern as `environmentBindings`,
and export it. Add a field `suppliedEnvironment :: ![EnvName]` to `CliOptions`, parsed
by a repeatable option in the Configuration group:

```haskell
suppliedEnvironmentOptions :: Parser [EnvName]
suppliedEnvironmentOptions =
  Options.many
    ( Options.option
        (EnvName . Text.pack <$> Options.str)
        ( Options.long "supplied-env"
            <> Options.metavar "NAME"
            <> Options.help "Declare an environment variable the deployment supplies; unsupported names are rejected"
        )
    )
```

In `runCliWithSnapshot`, after the `schemaDiagnostic` branch (and after plan 26's contract
dispatch if it exists) and before `resolveCliOptions`, run `checkSuppliedNames
acceptedEnvironmentNames (options ^. #suppliedEnvironment)` whenever the list is non-empty;
on `Left errors` return `failedRun sourceExitCode (renderSuppliedNameErrorsText errors <>
machineSuffix)`, where `machineSuffix` is `renderSuppliedNameErrorsJson errors <> "\n"`
when the diagnostic mode is `ExplainJson` and empty otherwise — the same stderr shape
(`failureReport`) the example already uses for resolution failures: text lines first, the
machine document after, stdout empty. Resolution itself is unchanged and still uses `environmentSource environmentBindings
snapshot`, so a passing check changes nothing about precedence or provenance.

Add tests to examples/settei-cli/test/Settei/Example/CliTest.hs: the accepted names
validate at construction (`length (acceptedNamesList acceptedEnvironmentNames) @?= 6`);
`--supplied-env HASKELL_ENV --supplied-env SERVICE_ENDPOINT --check-config` with
an explicit snapshot containing only `HASKELL_ENV=production` and
`SERVICE_ENDPOINT=https://environment.example` exits 0 with `configuration valid`.
Do not reuse `environmentSnapshot` for this absence case: it also contains
`SERVICE_TIMEOUT` and `OUTPUT_FORMAT`. Resolve the same two-entry snapshot and options
with `resolveCliOptions`, then use `expectResolution` and `expectAnswer` to assert
`timeout == 30` and `outputFormat == TextOutput`; inspect the report nodes for
`service.timeout` and `output.format` and assert their winning origins have kind
`BuiltInSource` and name `CLI built-in defaults`. This proves the omitted bound variables
are satisfied by the built-in source. `--supplied-env ENVIRONMENT
--check-config` with a snapshot containing `ENVIRONMENT=production` exits
`sourceExitCode`, prints nothing on stdout, and names `ENVIRONMENT` on stderr, while the
same snapshot without `--supplied-env` exits 0 (the hidden typo, proving permissive
behaviour is unchanged); `--supplied-env HTTPS_PROXY --supplied-env HASKELL_ENV
--check-config` with a snapshot that also contains `PATH` and `HOME` exits 0 (AC-2);
`--supplied-env SERVICE_TOKEN --supplied-env BOGUS_SECRET --check-config` with both
variables set to distinct sentinels exits `sourceExitCode` and neither sentinel appears on
stdout or stderr, and `--supplied-env SERVICE_TOKEN --explain-config-json` with the
sentinel exits 0 without the sentinel in the JSON (AC-4); the check runs before file
loading, so `--config yaml:/definitely/missing.yaml --supplied-env BOGUS --check-config`
exits `sourceExitCode` with the name error rather than the missing-file error;
`--supplied-env ENVIRONMENT --explain-config-json` with the `ENVIRONMENT` snapshot exits
`sourceExitCode` with empty stdout and a stderr containing the text line followed by a
line containing `"type":"settei.supplied-names"` and `"name":"ENVIRONMENT"`, while the
same arguments with `--explain-config` print only the text line; the sentinel case is
repeated in `--explain-config-json` mode; and `--help` lists `--supplied-env` under the
Configuration group.

Pass the hostile name from Milestone 1 as one argument following `--supplied-env`
through `expectOptions`. In check and text-explain modes, assert exit 3, empty stdout,
and exactly one escaped text line on stderr. In JSON-explain mode, assert exactly two
stderr lines: the same escaped text sentence followed by the exact
`settei.supplied-names` JSON document containing the original name encoded once. These
checks ensure control characters cannot forge a text line or an extra JSON document.

Update examples/settei-cli/README.md with one paragraph on `--supplied-env` and the
representative allowance.

### Milestone 3 — Documentation and collateral

Scope: make the capability discoverable, bounded, and recorded, and close the request.

Add a section `## Validate the names a deployment supplies` to
docs/guides/environment-and-cli.md after "Generate conventional bindings". It states the
problem in two sentences, shows `acceptedNames` with the guide's existing
`environmentBindings` plus an allowance for `OTEL_EXPORTER_OTLP_ENDPOINT` labelled
`opentelemetry-sdk`, shows `checkSuppliedNames` applied to a list copied from a container
specification's `env:` names, shows `checkedEnvironmentSource` as the strict in-process
path for tests and preflight tools, shows the `settei.supplied-names` JSON document with
its two `kind` values so a preflight tool knows what to parse, and then shows the three
`settei-example-cli` transcripts from Purpose / Big Picture plus the
`--explain-config-json` variant from Concrete Steps. It must say explicitly that the check is a
supplied-name check and not a required-value check: a bound variable that is not supplied
is never reported, because the setting may come from a file, a built-in or declared
default, or a `--set` override, and the resolver's own `MissingRequired` error remains the
authority on missing values; and that a map snapshot has already collapsed duplicate
entries, so ordered deployment entries should be checked as a list. Add a bullet to the
"Production checklist". In docs/guides/cli-application.md add a row for `--supplied-env
NAME` to the options table under "Add diagnostics that match user intent" (work
performed: "Compare the named variables with the application's bindings and allowances
before loading anything; exit 3 on an unsupported name") and one sentence under
"Distinguish exit behavior" listing unsupported supplied names under exit code 3. Append a
log entry with `okf log add docs/guides`.

Amend docs/capabilities/explicit-environment-sources.md (CAP-5): add a paragraph on
supplied-name validation and allowances, a bullet under "Limits" stating that absence is
not reported, and evidence rows pointing at the new test group, the CLI example test, and
the guide section; keep `capabilityId`, `status`, and `since` unchanged (the behaviour
ships in the next release; set `since` only if the catalog convention requires the
release version, in which case use the version the changelog bump implies). Append a log
entry with `okf log add docs/capabilities`.

Append `## Amendment <date>: supplied-name validation` to
docs/adr/0010-validate-environment-bindings-at-construction.md recording: the helper
compares explicit supplied names against bindings plus validated allowances; it never
reads the process environment or any value; absence is not an error; failures are a
separate runtime error type with escaped one-line text renderers and the required
`renderSuppliedNameErrorsJson` renderer; and the rejected alternatives (rejecting
the whole process environment by default, fuzzy name suggestions or silent normalization,
a `Settei.Optparse` flag ahead of a harness contract). State explicitly that the earlier
JSON deferral is superseded: IR-2 needs machine-readable supplied-name diagnostics now,
and IR-3 is not a prerequisite. Link the ADR-9 amendment for the JSON document contract.
Advance the record's `timestamp` to the amendment date. Append an amendment
`## Amendment <date>: supplied-name diagnostics and the first adapter JSON document` to
docs/adr/0009-adapter-error-rendering-contract.md recording: `Settei.Env` adds the
`renderSuppliedNameErrorText`/`renderSuppliedNameErrorsText` pair under the unchanged
text contract, with portable names verbatim and other names quoted and escaped under
Milestone 1's display rule; it also adds `renderSuppliedNameErrorsJson`, the first adapter JSON
renderer, admitted because IR-2's deployment tooling is the load-time consumer the
original decision anticipated; the document type is `settei.supplied-names` with
`schemaVersion` 1, compact encoding, and the core's string-escaping rules, so one consumer
can read core and adapter documents alike; `EnvError` and the other adapters' errors
remain text-only until a consumer requires otherwise; and the encoder stays private to
`settei-env` rather than exposing the core's. Advance its `timestamp`. Record both with
`okf log add docs/adr`.

Add one sentence to the "Environment variables" section of docs/security.md (name
validation retains names only, never values, including values attached to unknown names)
and extend the "Environment" row of the "Input contracts" table in docs/compatibility.md
with "opt-in validation of supplied names against bindings and allowances". Mention the
option in README.md's package map line for `settei-env` only if that line lists features;
otherwise leave README.md alone.

Finally edit docs/improvement-requests/validate-supplied-environment-variable-names.md.
The record already carries `status: accepted` and `targetPlan` naming this plan (set when
the plan was created); the first implementation session moves it to `status:
in-progress`, and this milestone sets `status: completed`, adds `completedAt` (RFC 3339
UTC) and a `resolution` line naming this plan and the test evidence — the field names
come from the improvement-request profile, docs/improvement-requests/profile.dhall
(okf-profiles v0.22.0, type documentation at
`mori://shinzui/okf-profiles` under docs/profiles/improvement-requests/types/improvement-request.md).
Run the strict validation command after each lifecycle edit and append a log entry with
`okf log add docs/improvement-requests`.

### Milestone 4 — Full validation and closure

Run the complete gates listed under Validation and Acceptance, record test totals and the
three CLI transcripts in this plan, write Outcomes & Retrospective, and confirm the ADR-10
and ADR-9 amendments capture everything durable from the Decision Log and Surprises &
Discoveries.


## Concrete Steps

All commands run from the repository root /Users/shinzui/Keikaku/bokuno/settei. `nix
develop -c` supplies GHC 9.12.4, Cabal 3.16, fourmolu, treefmt, and hlint; `okf`, `bun`,
and `mori` are on the user's PATH.

Baseline before any change (verified 2026-10-21: the adapter suite reports
`All 20 tests passed`):

```bash
git status --short            # expect no output
nix develop -c cabal test settei-env-tests --test-show-details=direct
```

Milestone 1:

```bash
# edit settei-env/src/Settei/Env.hs, settei-env/test/Settei/EnvTest.hs, settei-env/CHANGELOG.md
nix develop -c cabal build settei-env
nix develop -c cabal test settei-env-tests --test-show-details=direct
```

Expected tail of the test run (the count grows by the number of new cases):

```text
    supplied name validation
      accepts bound and allowed names:                       OK
      reports every unsupported name in supplied order:      OK
      ...
      strict path rejects HASKELL_ENV when ENVIRONMENT is bound: OK
      sentinels never reach supplied-name diagnostics:       OK
All N tests passed (0.00s)
Test suite settei-env-tests: PASS
```

Milestone 2:

```bash
# edit examples/settei-cli/src/Settei/Example/Cli.hs,
#      examples/settei-cli/test/Settei/Example/CliTest.hs, examples/settei-cli/README.md
nix develop -c cabal build settei-example-cli
nix develop -c cabal test settei-example-cli-tests --test-show-details=direct
ENVIRONMENT=production nix develop -c cabal run settei-example-cli -- --check-config; echo "exit $?"
ENVIRONMENT=production nix develop -c cabal run settei-example-cli -- --supplied-env ENVIRONMENT --check-config; echo "exit $?"
HASKELL_ENV=production nix develop -c cabal run settei-example-cli -- --supplied-env HASKELL_ENV --supplied-env HTTPS_PROXY --check-config; echo "exit $?"
ENVIRONMENT=production nix develop -c cabal run settei-example-cli -- --supplied-env ENVIRONMENT --explain-config-json; echo "exit $?"
```

Expected output of the four runs, in order (stdout and stderr interleaved):

```text
configuration valid
exit 0
supplied environment variable ENVIRONMENT: no binding or allowance accepts it
exit 3
configuration valid
exit 0
supplied environment variable ENVIRONMENT: no binding or allowance accepts it
{"schemaVersion":1,"type":"settei.supplied-names","errors":[{"kind":"unsupported-supplied-name","name":"ENVIRONMENT"}]}
exit 3
```

Milestone 3:

```bash
# edit the guide, CLI guide, CAP-5, ADR-10, ADR-9, security.md, compatibility.md, IR-2
okf log add docs/guides --kind Update -m "DOC-4 documents supplied-name validation and the CLI example's --supplied-env option."
okf log add docs/capabilities --kind Update -m "CAP-5 records supplied-name validation with allowances and its evidence."
okf log add docs/adr --kind Update -m "ADR-10 amended for supplied-name validation; ADR-9 amended to admit the settei.supplied-names JSON document as the first adapter JSON renderer."
okf log add docs/improvement-requests --kind Update -m "IR-2 completed by docs/plans/27-validate-supplied-environment-variable-names-against-declared-bindings.md."
okf validate docs/adr --strict --profile docs/adr/profile.dhall --profile-enforce --log-enforce
okf validate docs/guides --strict --profile mori/user-documentation-profile.dhall --profile-enforce --log-enforce
okf validate docs/capabilities --profile docs/capabilities/profile.dhall --profile-enforce --log-enforce
okf validate docs/improvement-requests --strict --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
```

Each `okf validate` prints `OK: <n> concepts (okf_version 0.2)`. No new file is created in
any bundle, so no `okf index --write` is needed; if a validator reports an index mismatch,
run `okf index <bundle> --write --okf-version 0.2` for that bundle and inspect the diff.

Milestone 4:

```bash
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c treefmt --fail-on-change --no-cache
nix flake check
```

Commits: one per milestone at minimum, each with the trailers

```text
ExecPlan: docs/plans/27-validate-supplied-environment-variable-names-against-declared-bindings.md
Intention: intention_01m5f8k7kxe4za4m14re9hgsk3
```

and a Conventional Commits subject such as `feat(settei-env): validate supplied
environment variable names`. Record a provenance revision entry the first time this plan
is edited in an implementation session:

```bash
bun agents/skills/exec-plan/record-provenance.ts revision \
  --plan docs/plans/27-validate-supplied-environment-variable-names-against-declared-bindings.md \
  --model <your-model-id> --harness <harness> --mode implement --note "<one line>"
```


## Validation and Acceptance

Each acceptance criterion of IR-2 maps to observable checks:

- AC-1 (deterministic, value-free comparison). The adapter suite checks known names,
  multiple unsupported names in supplied order, the empty collection, duplicate
  reporting, and byte-identical results on repeated calls — for the error list and for
  `renderSuppliedNameErrorsJson` — all against `AcceptedNames` built from the same
  `Bindings` that `environmentSource` accepts. `checkSuppliedNames` takes `[EnvName]` and
  no snapshot, so no value can be required.
- AC-2 (allowances and scope). The adapter test with the `opentelemetry-sdk` allowance
  and the CLI test with `HTTPS_PROXY` each reject only the unsupported application name
  while `PATH` and `HOME` exist in the surrounding snapshot and are never checked; the
  `snapshotNames` test shows that process-wide checking is a deliberate caller choice.
- AC-3 (opt-in strict path). The adapter fixture binds `ENVIRONMENT`, defaults to
  `development` through a built-in source, resolves successfully with `HASKELL_ENV`
  supplied (permissive), fails through `checkedEnvironmentSource` naming `HASKELL_ENV`,
  succeeds with `ENVIRONMENT`, and yields a source whose candidate annotations equal the
  permissive source's. The CLI example reproduces the same story at the process boundary
  with `--supplied-env`, and every pre-existing CLI test still passes unchanged.
- AC-4 (no values retained or rendered). `SuppliedNameError` carries only `EnvName`;
  sentinels placed in a known and an unknown variable are absent from `show`, from the
  text renderers, from the JSON renderer, from the CLI's stdout and stderr on the failure
  path in check and both explain modes, and from the CLI's `--explain-config-json` output
  on the success path. Hostile supplied names retain their original spelling in errors
  and are escaped independently for text and JSON. Adapter and CLI tests enforce one
  physical text line per error and one subsequent JSON document in JSON-explain mode.
- AC-5 (documentation). The guide section shows a container-specification name list being
  checked, the three CLI transcripts, and the paragraph on absent bindings; the CLI test
  `--supplied-env HASKELL_ENV --supplied-env SERVICE_ENDPOINT --check-config` passes
  with a snapshot containing only `HASKELL_ENV` and `SERVICE_ENDPOINT`, so
  `SERVICE_TIMEOUT` and `OUTPUT_FORMAT` are absent from both the supplied-name list and
  snapshot. The companion resolution assertions prove timeout `30` and `TextOutput`
  come from `CLI built-in defaults` with `BuiltInSource` provenance, which is the
  executable form of "absence is not an error".

Required gates before the plan is complete: all Milestone 4 commands pass; the four
`okf validate` commands pass; `git status --short` is empty after the final commit; the
three transcripts above are reproduced and pasted into this section.

Proposed, not required: a `Settei.Optparse` helper giving the fleet one spelling for
supplying names; a comparison of a deployment contract's bindings (plan 26) with supplied
names; JSON renderers for `EnvError` and the other adapters' error types. Each needs a
scope decision before becoming acceptance.


## Idempotence and Recovery

Every build and test command is safe to repeat. `okf log add` appends; run each once and
remove a duplicated entry by hand if repeated. `okf validate` is read-only. The work is
additive: no existing function, type, test, or document section is removed, so a
milestone can be abandoned by reverting its files with `git checkout -- <paths>` and the
previous milestone's commit is always a clean restart point. If the strict validation of
docs/improvement-requests/ fails after the IR status edit, restore the record's frontmatter
from git, fix the field the validator names, and retry. If `treefmt` reformats a Haskell
file, commit the reformatted version; fourmolu is the authority.


## Interfaces and Dependencies

Additions to `Settei.Env` in settei-env/src/Settei/Env.hs (no existing export changes):

```haskell
-- One variable the application consumes outside Settei, with a short consumer label.
data Allowance                                   -- private constructor
allowance :: Text -> EnvName -> Allowance        -- consumer label, variable name
allowanceConsumer :: Allowance -> Text
allowanceName :: Allowance -> EnvName

-- Bound names plus allowances, validated once.
data AcceptedNames                               -- private constructor; no Generic
acceptedNames :: Bindings -> [Allowance] -> Either (NonEmpty EnvError) AcceptedNames
acceptedBindings :: AcceptedNames -> Bindings
acceptedNamesList :: AcceptedNames -> [(EnvName, NameAcceptance)]
data NameAcceptance = BoundTo !Key | ConsumedBy !Text
  deriving stock (Generic, Eq, Show)

-- Supplied-name checking: names only, never values.
data SuppliedNameError
  = UnsupportedSuppliedName !EnvName
  | DuplicateSuppliedName !EnvName
  deriving stock (Generic, Eq, Show)
checkSuppliedNames :: AcceptedNames -> [EnvName] -> Either (NonEmpty SuppliedNameError) ()
renderSuppliedNameErrorText :: SuppliedNameError -> Text
renderSuppliedNameErrorsText :: NonEmpty SuppliedNameError -> Text
renderSuppliedNameErrorsJson :: NonEmpty SuppliedNameError -> Text   -- settei.supplied-names

-- The strict path and the visible checked collection.
snapshotNames :: EnvSnapshot -> [EnvName]        -- ascending; duplicates already collapsed
checkedEnvSource :: Text -> AcceptedNames -> EnvSnapshot -> Either (NonEmpty SuppliedNameError) Source
checkedEnvironmentSource :: AcceptedNames -> EnvSnapshot -> Either (NonEmpty SuppliedNameError) Source
```

JSON layout of `settei.supplied-names` (`schemaVersion` 1): a top-level object with the
keys `schemaVersion`, `type`, and `errors` in that order; `errors` is an array in
diagnostic order whose elements are objects with `kind` (`unsupported-supplied-name` or
`duplicate-supplied-name`) and `name` (the variable name as supplied, JSON-escaped). No
whitespace, no trailing newline. Adding a constructor to `SuppliedNameError` adds a `kind`
value and is a minor change for consumers that ignore unknown kinds; changing a field
name or the document type requires a new `schemaVersion`.

`AcceptedNames` and `Allowance` derive `Eq` but not `Generic`, matching `Bindings`, so
generic conversion cannot bypass validation. No lens type appears in a public signature
(the compatibility policy's audit rule in docs/compatibility.md). The changelog entry for
settei-env is a minor (additive) PVP bump.

Reference CLI application (examples/settei-cli/src/Settei/Example/Cli.hs): exported
`acceptedEnvironmentNames :: AcceptedNames`; `CliOptions` gains `suppliedEnvironment ::
![EnvName]`; the parser gains `--supplied-env NAME` (repeatable, Configuration group);
`runCliWithSnapshot` fails with `sourceExitCode` on an unsupported or duplicated supplied
name before loading files.

Dependencies whose choice matters: none are added. `settei-env` keeps `base`,
`containers`, `generic-lens`, `settei`, and `text`; the CLI example already depends on
`settei-env` and `optparse-applicative` 0.19 (`Options.many`, `Options.option`,
`Options.str`; source and documentation registered in Mori under
`pcapriotti/optparse-applicative`, inspect with `mori registry show
pcapriotti/optparse-applicative --full` before guessing an API). Tests use `tasty` and
`tasty-hunit` as the existing suites do.

Revision note (2026-10-21): after discussion, the plan now adds
`renderSuppliedNameErrorsJson` and the `settei.supplied-names` document instead of
deferring JSON to IR-3. The earlier deferral decision is retained in the Decision Log as
superseded; Milestones 1–3, the acceptance mapping for AC-1 and AC-4, the CLI transcripts,
the ADR-9 amendment, and the interface list were updated together.

Revision note (2026-10-21): addressed all three review findings by specifying and testing
escaped one-line text diagnostics, replacing the absence fixture with a two-entry
snapshot and explicit default-value/provenance assertions, and removing the obsolete
JSON rejection from the ADR-10 instructions. The JSON renderer, versioned document,
CLI integration, and acceptance tests remain required scope, as confirmed by the user.
