---
id: 26
slug: export-a-deployment-configuration-contract-with-bindings-and-defaults
title: "Export a deployment configuration contract with bindings and defaults"
kind: exec-plan
created_at: 2026-10-21T12:23:47Z
intention: "intention_01m5f6nmytec59xh6099xfe37w"
provenance:
  created_by:
    model: "claude-fable-5-1"
    harness: "claude-code"
    at: 2026-10-21T12:23:47Z
---

# Export a deployment configuration contract with bindings and defaults

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.

This plan implements improvement request IR-1,
docs/improvement-requests/export-a-deployment-configuration-contract.md. Its seven
acceptance criteria (AC-1 through AC-7) are the acceptance obligations of this plan; each
milestone below names the criteria it discharges.


## Purpose / Big Picture

Settei is a Haskell configuration library. An application declares its settings once as a
`Config` value, and Settei resolves them from ordered sources (files, environment
variables, command-line flags) while keeping provenance and redacting secrets. Today an
application can print its static schema (`--describe-config-json`: keys, descriptions,
sensitivity, required/optional, necessary/conditional) and, after loading real inputs,
explain the resolved values (`--explain-config-json`). Neither answers the question a
person writing a service's *first* deployment actually has: which environment variables
must I set, which settings already have a safe default, which defaults are secrets I must
replace, and which values does the application insist I state explicitly in production?

The originating consumer is the notification-hub service (`mori://tan/notification-hub`).
It declares almost every setting as `required`, supplies most values from a built-in
lowest-precedence `Source` of defaults, binds each setting to an environment variable
such as `ENVIRONMENT` or `DATABASE_URL`, and ships a development-only webhook secret as a
default. Its schema therefore says "nearly everything is required" while the deployment
needs only a handful of external inputs. A deployment author who copies another service's
`HASKELL_ENV` wiring, or who trusts the development secret, gets a wrong deployment.

After this plan, an application exports a **deployment contract**: one deterministic,
versioned JSON document (and a text rendering) that joins, for every setting, its schema
metadata, every environment variable bound to it, the defaults it has (from the
declaration and from explicitly supplied default sources), whether the default value may
be shown, whether the deployment must still supply a value, and any application-declared
deployment requirement that demands an explicit value despite a default. The export runs
without environment values, files, secrets, databases, clusters, or a successful
resolution, and it never runs a default's computation to learn its value.

You can see it working on the new reference application added by this plan, from the
repository root:

```bash
nix develop -c cabal run settei-example-deployment-server -- --deployment-contract
```

prints a contract naming `ENVIRONMENT`, `DATABASE_URL`, the public endpoint defaults,
the redacted-but-present webhook secret default, and the production profile's explicit
requirements, with no environment variables set. Then

```bash
DATABASE_URL=postgres://invalid ENVIRONMENT=production \
  nix develop -c cabal run settei-example-deployment-server -- --check-config
```

exercises the application's existing check mode against the proposed inputs and fails
with the exact settings still missing. The same contract exports from the existing
reference CLI and Kubernetes-shaped service, so every maintained reference application
demonstrates the feature (see docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md).


## Progress

- [ ] Milestone 1 — Core contract API and renderers (AC-1, AC-2, AC-3, AC-4, AC-5 at the
      library boundary): `Settei.Contract` builds a `DeploymentContract` from a
      declaration, input bindings, explicit default sources, and an optional deployment
      profile; `Settei.Render` renders it as text and as versioned `settei.contract`
      JSON; `nix develop -c cabal test settei-tests --test-show-details=direct` passes
      with the new `Settei.ContractTest` group and goldens, including the no-evaluation,
      sentinel-redaction, and determinism cases.
- [ ] Milestone 2 — Adapter and CLI integration (AC-1 bindings join, AC-4 source-free
      modes): `Settei.Env.inputBindings` converts validated `Bindings` into contract
      bindings; `Settei.Optparse` adds the `--deployment-contract` and
      `--deployment-contract-json` modes and `contractDiagnostic`; the settei-env and
      settei-optparse-applicative suites pass with the new cases.
- [ ] Milestone 3 — Existing reference applications and conformance (AC-4, AC-5 at the
      application boundary): the reference CLI and Kubernetes-shaped service answer the
      new modes before opening any file or reading any environment value; the conformance
      suite scans a contract built through public modules for a secret sentinel; the
      three example suites pass.
- [ ] Milestone 4 — Notification-hub-shaped reference application (AC-4 instrumentation,
      AC-6 workflow): the new `examples/settei-deployment` package with server and worker
      executables, a built-in defaults source, `ENVIRONMENT`/`DATABASE_URL` bindings, a
      defaulted secret, a production deployment profile, distinct server and worker
      check-mode validations, and a test suite whose transcript proves the contract
      exports without credentials and that check mode rejects incomplete proposed
      inputs; registered in `cabal.project`, `flake.module.nix`, and `mori.dhall`.
- [ ] Milestone 5 — Documentation and collateral (AC-6 documented example, AC-7 limits
      and compatibility): guide DOC-11 under docs/guides/, capability CAP-14 and an
      updated CAP-7 under docs/capabilities/, ADR-12 plus an ADR-7 amendment under
      docs/adr/, README, compatibility, security, and changelog updates, and IR-1 moved to
      `completed` with acceptance evidence; every OKF bundle validates strictly.
- [ ] Milestone 6 — Full validation and closure: `cabal build all`, `cabal test all`,
      `treefmt`, `cabal check` for the new package, and `nix flake check` pass; evidence
      recorded here; Outcomes & Retrospective written; ADR distillation done.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: The contract is built inside the core `settei` package, in a new public
  module `Settei.Contract`, and is re-exported by the `Settei` umbrella module. Adapter
  packages contribute only through an adapter-neutral `InputBinding` value;
  `settei-env` converts its validated `Bindings` into that vocabulary.
  Rationale: Default rules are syntax nodes of the private algebra in
  settei/src/Settei/Internal/Config.hs, which only the core package may traverse; the core
  package deliberately depends on no adapter (docs/adr/0003-resolution-provenance-and-default-semantics.md,
  docs/adr/0009-adapter-error-rendering-contract.md). An adapter-neutral binding record
  keeps that layering and leaves room for a mounted-file channel later.
  Date: 2026-10-21

- Decision: Default sources are an explicit `[Source]` input to the export, ordered
  lowest to highest exactly as the application orders them for `resolve`. The export
  never infers "default" status from a source's name or kind, never reads a file, and
  never evaluates a derived or case default's function. It does run each setting's pure
  decoder over the winning default-source candidate to tell a valid default from an
  invalid one, then discards the decoded value.
  Rationale: IR-1 forbids inferring default status from labels, reading runtime files,
  and evaluating opaque functions, and it forbids turning a failed default decode into a
  claim that the setting is covered. Decoders are pure functions that resolution would
  run anyway; running them answers "is this default usable" without producing a value
  to display.
  Date: 2026-10-21

- Decision: Exporting a contract fails only when the declaration contains a default
  cycle, returning the existing `DefaultCycle` constructor of `ConfigError` so
  applications reuse `renderErrorsText` and `renderErrorsJson`. Every other
  inconsistency — a binding or profile requirement naming an undeclared key, a default
  source leaf under no declared key, a default source whose shape blocks a declared key,
  or one key declared with both sensitivities — is a structured diagnostic inside the
  contract, and a mixed-sensitivity key is reported as `secret` with its default value
  redacted.
  Rationale: A cyclic declaration cannot be traversed, so no contract exists. Every
  other problem still leaves a useful contract, and AC-1 asks for useful diagnostics
  rather than a refusal. Reporting mixed sensitivity as secret mirrors the schema's
  most-restrictive merge and proves AC-5's "cannot downgrade protection" with an
  exported document rather than with an absent one.
  Date: 2026-10-21

- Decision: `Settei.Optparse.DiagnosticMode` gains two constructors,
  `DeploymentContractText` and `DeploymentContractJson`, spelled
  `--deployment-contract` and `--deployment-contract-json`, in the existing mutually
  exclusive Diagnostics group. A new helper `contractDiagnostic` selects the renderer for
  those modes; `schemaDiagnostic` and the `settei.schema` JSON document are unchanged.
  The contract is a new JSON document type `settei.contract` with `schemaVersion: 1`.
  Rationale: IR-1 leaves the names to implementation and asks not to break
  `--describe-config-json`. A separate document type keeps existing JSON consumers
  untouched (AC-7) while reusing the schema's field names and the resolution report's
  origin encoding so one consumer can read all three. Adding constructors is a breaking
  change for exhaustive matches on `DiagnosticMode`, accepted under the experimental
  0.x policy and recorded in the changelog as a major PVP bump.
  Date: 2026-10-21

- Decision: The notification-hub-shaped fixture is a new internal reference package,
  `examples/settei-deployment` (`settei-example-deployment`), with one shared library
  declaration and two executables (server and worker), rather than a reshaping of the
  Kubernetes service example.
  Rationale: AC-6 requires `ENVIRONMENT`, `DATABASE_URL`, a built-in defaults source, a
  defaulted secret, and distinct server and worker checks. The Kubernetes service example
  uses `HASKELL_ENV`, declaration-level defaults, and one process, and its names are
  baked into the checked-in manifests, cookbook, and guides. Renaming them would churn
  collateral unrelated to this request; a new package mirrors the consumer honestly and
  keeps the existing examples stable while they also gain the new modes.
  Date: 2026-10-21

- Decision: The per-setting external-input verdict is computed by this fixed precedence:
  an explicit deployment-profile requirement wins; then an invalid winning default-source
  candidate makes input required; then a valid default-source candidate marks the setting
  defaulted; then a `required` schema requirement makes input required (conditional when
  the setting's presence is conditional); then any declaration-level default marks the
  setting defaulted; otherwise the setting is optional. A key that is both `required`
  somewhere and `withDefault` elsewhere is reported as required, because the required
  request fails without a source value.
  Rationale: This is exactly what the resolver would do at runtime, read off statically:
  `withDefault` consults sources before its rule, a required request never consults a
  rule, and an invalid winner is never skipped (docs/adr/0003). Fixing the order in the
  plan removes a judgment call from the implementer and the reader.
  Date: 2026-10-21

- Decision: Kubernetes mounted-file bindings (`Settei.Kubernetes.FileBindings`) are out
  of scope for this plan. The `InputChannel` type reserves a `CustomInput Text`
  constructor so a later plan can add that channel without changing the contract shape.
  Rationale: IR-1 asks for environment bindings; the originating consumer uses only
  environment variables. Adding a second adapter conversion would widen scope without
  serving the acceptance criteria.
  Date: 2026-10-21


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

### What exists today

The core package lives in settei/ and its public modules are listed in
docs/compatibility.md. The pieces this plan builds on:

- settei/src/Settei/Internal/Config.hs is the private syntax tree of a declaration. A
  `Config a` is one of `PureConfig`, `MapConfig`, `ApplyConfig`, `RequestConfig`
  (a `RequiredRequest` or `OptionalRequest` carrying a `Setting a`), `DefaultConfig`
  (a `Setting a` paired with a `Default a`), or `SelectConfig` (a selective branch). A
  `Default a` is `ConstantDefault rule explanation value`, `DerivedDefault rule
  explanation dependencyConfig function`, or `CaseDefault rule explanation
  dependencyConfig alternatives fallback`. The constructors are not public; only modules
  inside the `settei` package can match on them. `describeConfig` folds a declaration into
  a `Schema`.
- settei/src/Settei/Internal/Schema.hs defines `Schema` (a key-ordered map of
  `SchemaSetting` plus `Condition` rows) and the merge rules: `Secret` wins over
  `Public`, `Required` over `Optional`, `Necessary` over `Conditional`. A
  `SchemaSetting` also retains `declaredSensitivities`, so a key declared with both
  sensitivities is detectable. Note that `describeConfig` records a `DefaultConfig` node
  as an `Optional` request and marks the default's dependency settings `Conditional`.
- settei/src/Settei/Schema.hs is the public read-only view of a schema
  (`schemaPossible`, `schemaSettingKey`, `schemaSettingRequirement`, and so on).
- settei/src/Settei/Setting.hs defines `Setting a` with a key, description,
  `Sensitivity`, a pure `Decoder`, and an optional renderer for typed default values
  (`settingValueRenderer`). Secret settings ignore renderers.
- settei/src/Settei/Source.hs defines `Source` and `lookupSource :: Key -> Source ->
  Either StructuralError (Maybe Candidate)`, plus `sourceLeaves` for unknown-key
  discovery. A `Candidate` pairs a raw value with an `Origin`.
- settei/src/Settei/Provenance.hs defines `ReportedValue`, the only representation a
  report may retain: `reportedValue sensitivity rawValue` redacts secrets before anything
  is stored, and `renderReportedValue` prints `<redacted>` for them.
- settei/src/Settei/Resolve.hs is the resolver. It validates default cycles first
  (`validateDefaultCycles`, private), then sensitivity conflicts, then source structure,
  then evaluates. Its `evaluateDefaultRequest` shows the runtime rule this plan mirrors
  statically: a `withDefault` setting first looks for a source candidate and only runs
  its rule when none exists; an invalid winning candidate fails and never falls back.
- settei/src/Settei/Render.hs holds the text and versioned JSON renderers
  (`renderSchemaJson`, `renderResolutionJson`, `renderErrorsJson`, and their text
  forms) and the private deterministic JSON encoder (`versionedJson`, `jsonObject`,
  `jsonString`, `originJson`). Every JSON document has `schemaVersion: 1` and a `type`.
- settei-env/src/Settei/Env.hs defines `EnvName`, `EnvBinding`, the opaque validated
  `Bindings` collection (`bindings`, `mergeBindings`, `bindingsList`, `bindingName`,
  `bindingKey`, `bindingAnnotations`), and `envSource`, which attaches the
  `environment.variable` annotation plus any caller annotations (for example Kubernetes
  `secretKeyRef` identity from `fromKubernetesObject`) to each present key.
- settei-optparse-applicative/src/Settei/Optparse.hs defines `DiagnosticMode`
  (`NoDiagnostic`, `ExplainText`, `ExplainJson`, `CheckConfig`, `DescribeConfigText`,
  `DescribeConfigJson`), the `--describe-config*`/`--check-config`/`--explain-config*`
  flags in `diagnosticModeOptions`, and the helpers `schemaDiagnostic :: DiagnosticMode
  -> Schema -> Maybe Text` (source-free) and `resolutionDiagnostic` (post-resolution).
- examples/settei-cli/src/Settei/Example/Cli.hs and
  examples/settei-service/src/Settei/Example/Service.hs are the reference applications.
  Both dispatch `schemaDiagnostic` before loading anything, expose a pure
  `run…WithSnapshot` entry point for tests, and use exit code 2 for usage, 3 for source
  loading, and 4 for resolution failures. The CLI example already has a lowest-precedence
  `builtInSource :: Source` of defaults, which is exactly a "default source" in this
  plan's sense. The service's `environmentBindings` include a Kubernetes-derived binding
  for `DATABASE_PASSWORD`.
- examples/settei-conformance/test/Settei/Example/ConformanceTest.hs is the
  cross-package conformance suite; its "Security" group scans rendered outputs for secret
  sentinels.
- docs/guides/ (OKF bundle, profile mori/user-documentation-profile.dhall, handles
  `DOC-N`), docs/capabilities/ (profile docs/capabilities/profile.dhall, handles
  `CAP-N`), docs/adr/ (profile docs/adr/profile.dhall, handles `ADR-N`), and
  docs/improvement-requests/ (profile docs/improvement-requests/profile.dhall, handles
  `IR-N`) are validated by the pre-commit hook defined in flake.module.nix with the exact
  `okf validate` commands repeated in Concrete Steps.

### Terms used in this plan

A **declaration** is a `Config a` value. A **setting** is one `Setting a` inside it,
identified by its dotted `Key` such as `database.url`. The **schema** is the static
description `describe declaration` returns. A **declaration-level default** is a
`withDefault setting rule` node; a **source-based default** is a candidate for the key
found in one of the default sources the application hands to the export. A **binding**
is a mapping from an external input name (today, an environment variable name) to a key.
A **deployment profile** is application-supplied data naming settings that must be
supplied explicitly in some deployment context (for example production) even when a
default exists. The **verdict** for a setting is the contract's answer to "must the
deployment supply this value?".

### The originating consumer

The notification-hub declaration at
`mori://tan/notification-hub/packages/notification-hub-core` (module
`NotificationHub.App.Config`) declares every setting with `required`, puts non-secret
defaults into `builtInDefaultsSource :: Source` (kind `CustomSource "built-in-defaults"`),
leaves `database.url` out of that source deliberately, binds `runtime.environment` to
`ENVIRONMENT` and `database.url` to `DATABASE_URL`, and ships
`server.deliveryWebhookSecret` with the default `development-only-change-me`. Its server
(`NotificationHub.Server.Config`) validates event-webhook public keys inside check mode;
its workers (`NotificationHub.Workers.Config`) validate capacity, replica, and
provider-account invariants there. This plan's new reference application reproduces that
shape in miniature; it does not modify notification-hub, whose adoption remains
consumer-owned work.

### Relevant architecture decisions

- docs/adr/0002-inspectable-configuration-algebra.md: `Config` is a private GADT with no
  `Monad` instance so that complete static inspection is possible. The contract is one
  more source-free interpreter of that algebra; it adds no syntax nodes.
- docs/adr/0003-resolution-provenance-and-default-semantics.md: defaults are named syntax
  nodes; an explicit source candidate wins over a declaration default; an invalid winner
  never falls back; redaction happens before data enters any report; JSON documents are
  versioned, deterministic, and emitted without Aeson. The contract follows every one of
  these rules statically and reuses `ReportedValue` and the origin encoding.
- docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md: every
  public capability must be exercised by an internal reference application; diagnostics
  modes must be source-free when the application dispatches them first. This plan wires
  the new modes into both existing examples and adds a third application example, which
  requires an amendment to this ADR.
- docs/adr/0009-adapter-error-rendering-contract.md: adapters render their own errors as
  text; core JSON is reserved for core documents. The contract is a core document.
- docs/adr/0010-validate-environment-bindings-at-construction.md: `Bindings` is opaque and
  valid by construction; `bindingsList` is the inspection path this plan's converter uses.

No existing ADR covers deployment contracts, deployment profiles, or source-based default
reporting; Milestone 5 creates ADR-12 for them (`okf id next docs/adr --profile
docs/adr/profile.dhall ADR` returned `ADR-12` on 2026-10-21; re-run it when allocating).


## Plan of Work

### Milestone 1 — Core contract API and renderers

Scope: the pure library surface. At the end, a Haskell caller can build a
`DeploymentContract` from a declaration plus inputs, inspect it, and render it as text and
JSON, with tests proving the join, the default vocabulary, the verdict rule, the
no-evaluation guarantee, redaction, and determinism.

Move the default-cycle check out of the resolver so both interpreters share it: relocate
`validateDefaultCycles` and `defaultRule` from settei/src/Settei/Resolve.hs into
settei/src/Settei/Internal/Config.hs and export them from that private module. The
resolver's behavior and public surface do not change.

Create settei/src/Settei/Contract.hs with the types and functions listed under
Interfaces and Dependencies. The builder `deploymentContract :: ContractInputs -> Config a
-> Either (NonEmpty ConfigError) DeploymentContract` works in these passes:

1. Run the shared cycle validation; return `Left` with the `DefaultCycle` errors if any.
2. Compute the schema with `describeConfig`; it gives key order, effective (most
   restrictive) sensitivity, merged requirement, merged presence, condition rows, and the
   set of keys declared with both sensitivities (one `ConflictingSensitivity` diagnostic
   each).
3. Walk the declaration once, recursing into the dependency declarations of derived and
   case defaults (safe after step 1). For every `DefaultConfig` node, record one
   `DeclaredDefault` for its key: a constant becomes `ConstantShape` whose value is
   `VisibleDefault (renderer value)` only when the effective sensitivity is `Public` and
   the setting has a renderer, `UnrenderableDefault` when public without a renderer, and
   `RedactedDefault` when secret (the renderer must not be called); a derived default
   becomes `DerivedShape` with the possible keys of its dependency declaration; a case
   default becomes `CaseShape` with its dependency keys, the number of alternatives, and
   whether a fallback exists. Never apply a derived default's function and never render a
   case alternative. Also collect, per key, every `Setting` that requests it (the
   decoders are needed in the next pass).
4. For every schema key, look it up in each default source in order. A `Left` structural
   error becomes a `DefaultStructuralConflict` diagnostic. Present candidates form the
   winner (last) and shadowed origins (highest losing precedence first, as the resolver
   orders them). Decode the winner with every decoder collected for that key; the first
   rejection makes the default `InvalidDefault expected`, otherwise `ValidDefault`. The
   decoded value is discarded. The retained display value is `reportedValue
   effectiveSensitivity rawValue`, so secret defaults are redacted before storage.
5. Enumerate `sourceLeaves` of each default source; every leaf not beneath a declared key
   becomes an `UndeclaredDefaultLeaf` diagnostic (the resolver's unknown-key rule).
6. Attach bindings: group the supplied `InputBinding` list by key, preserving supplied
   order; a binding whose key is not in the schema becomes an `UndeclaredBindingKey`
   diagnostic and is not attached.
7. Attach the profile: each requirement whose key is in the schema sets that setting's
   `deploymentRequirement`; others become `UndeclaredProfileKey` diagnostics.
8. Compute each setting's `ExternalInput` verdict with the precedence fixed in the
   Decision Log.

Diagnostics are ordered deterministically: sensitivity conflicts in key order, then
structural conflicts in key then source order, then undeclared default leaves in source
then key order, then undeclared binding keys in supplied order, then undeclared profile
keys in key order.

Add `renderContractText` and `renderContractJson` to settei/src/Settei/Render.hs, next to
the schema renderers, reusing `requirementText`, `presenceText`, `sensitivityText`,
`originJson`, `conditionJson`, and `versionedJson`. The JSON document has type
`settei.contract`, `schemaVersion` 1, and the field layout given under Interfaces and
Dependencies. The text form prints one block per setting in key order, then the condition
rows exactly as `renderSchemaText` prints them, then one `diagnostic: …` line per
diagnostic. Export the new module from settei/src/Settei.hs and list it in
settei/settei.cabal (library and test-suite module lists).

Tests go in a new settei/test/Settei/ContractTest.hs registered in settei/test/Main.hs,
with goldens settei/test/golden/contract.txt and settei/test/golden/contract.json (add
them to `extra-source-files`). The fixture declaration must contain, at minimum: a
required public setting with no default; a required secret setting with no default; an
optional setting; a `withDefault` with a public constant and renderer; a `withDefault`
with a public constant and no renderer; a `withDefault` with a secret constant; a derived
default whose function is `\_ -> error "derived default must not be evaluated"`; a case
default with and without fallback whose alternative values are `error` thunks; a
`whenEq`-guarded conditional required setting; a key both `required` in one node and
`withDefault` in another; and a mixed-sensitivity key whose public constant default
renders the secret sentinel. Default sources must include a valid candidate, a candidate
that fails to decode, a secret candidate carrying the sentinel, two sources shadowing one
key, an undeclared leaf, and a scalar that blocks a declared key. Required assertions:
rendering the same inputs twice yields identical text and JSON; every binding appears
under exactly the key it targets and unbound settings have an empty `inputs` list;
each default kind renders with its documented vocabulary; the secret sentinel is absent
from the contract's `Show`, text, and JSON output and from every diagnostic; building and
rendering the contract never forces the `error` thunks; the verdicts for the
required-without-default, required-with-default, optional, conditional, and
profile-required settings match the precedence rule; and `Left (DefaultCycle …)` is
returned for a cyclic declaration without inspecting any source (pass `source` values
whose `locationAt` hook is `error` and assert the export does not force it, mirroring the
resolver's existing cycle law).

### Milestone 2 — Adapter and CLI integration

Scope: let real applications feed the export and expose it on the command line.

In settei-env/src/Settei/Env.hs add `inputBindings :: Bindings -> [InputBinding]`. Each
`EnvBinding` becomes `inputBinding EnvironmentVariable variableName key` annotated with
`environment.variable` and the binding's caller annotations, in the same precedence
`envSource` uses, so a Kubernetes-derived binding carries its `kubernetes.*` identity
into the contract. Test it in settei-env/test/Settei/EnvTest.hs: a hand-written binding
and a `fromKubernetesObject` binding convert with their names, keys, and annotations, and
`bindingsList` order is preserved.

In settei-optparse-applicative/src/Settei/Optparse.hs add the constructors
`DeploymentContractText` and `DeploymentContractJson` to `DiagnosticMode`, extend
`diagnosticModeOptions` with `--deployment-contract` ("Print the deployment
configuration contract") and `--deployment-contract-json` ("Print the deployment
configuration contract as JSON"), and add:

```haskell
contractDiagnostic ::
  DiagnosticMode ->
  Either (NonEmpty ConfigError) DeploymentContract ->
  Maybe (Either (NonEmpty ConfigError) Text)
```

It returns `Nothing` for every other mode without forcing its second argument, `Just
(Left errors)` for a cyclic declaration, and `Just (Right rendered)` otherwise (JSON
output gets a trailing newline like `schemaDiagnostic`). Tests in
settei-optparse-applicative/test/Settei/OptparseTest.hs: the two flags parse, remain
mutually exclusive with the other diagnostics, appear in the Diagnostics help group, and
`contractDiagnostic` returns the documented results for each mode.

Update settei-env/CHANGELOG.md and settei-optparse-applicative/CHANGELOG.md with an
`## Unreleased` section (the release skill moves it under the next version). The
optparse entry states that `DiagnosticMode` gained constructors and is a major PVP bump.

### Milestone 3 — Existing reference applications and conformance

Scope: prove the feature at the existing conformance boundary.

In examples/settei-cli/src/Settei/Example/Cli.hs, after the `schemaDiagnostic` branch
and before any loading, dispatch `contractDiagnostic` with inputs built from
`inputBindings environmentBindings`, default sources `[builtInSource]`, and no profile.
A `Just (Left errors)` exits with `resolutionExitCode` and `renderErrorsText`. Add tests
to examples/settei-cli/test/Settei/Example/CliTest.hs: both modes succeed with
`--config yaml:/definitely/missing.yaml` and an empty snapshot; `service.endpoint` is
reported as defaulted by the built-in source with its visible value; `credentials.token`
is optional, secret, bound to `SERVICE_TOKEN`, and carries the Kubernetes annotations; the
JSON document type is `settei.contract`.

In examples/settei-service/src/Settei/Example/Service.hs do the same with
`inputBindings environmentBindings`, no default sources, and no profile. Tests in
examples/settei-service/test/Settei/Example/ServiceTest.hs: both modes succeed with a
missing `--config` path and a missing `--secrets-dir`; `database.password` is conditional,
secret, and bound to `DATABASE_PASSWORD` with the Secret object identity; `http.port`
shows the `http-port-by-environment` case default with its dependency; a snapshot
containing the secret sentinel does not change the output.

In examples/settei-conformance/test/Settei/Example/ConformanceTest.hs add a "Deployment
contract" group that builds a contract through the public `Settei`, `Settei.Env`, and
`Settei.Optparse` modules from standalone fixtures (no new package dependencies): a
built-in default source carrying a secret sentinel for a secret setting, a secret
constant default, and a mixed-sensitivity key; assert the sentinel is absent from text,
JSON, and `contractDiagnostic` output.

### Milestone 4 — Notification-hub-shaped reference application

Scope: the AC-6 fixture as a real two-executable application.

Create examples/settei-deployment/ with LICENSE (copy from
examples/settei-service/LICENSE), README.md, settei-example-deployment.cabal (version
`0.2.0.0`, internal pins `==0.2.0.0` like the siblings, `tested-with: GHC ==9.12.4`),
`src/Settei/Example/Deployment.hs`, `app/server/Main.hs`, `app/worker/Main.hs`,
`test/Main.hs`, `test/Settei/Example/DeploymentTest.hs`, and a packaged
`test/fixtures/proposed-production.yaml`. Dependencies: `settei`, `settei-env`,
`settei-yaml`, `settei-optparse-applicative`, `optparse-applicative`, `text`,
`containers`, `generic-lens`; tests add `tasty`, `tasty-hunit`, and `filepath`.

The library declares, with these keys, bindings, and defaults:

| Key | Sensitivity | Binding | Default |
| --- | --- | --- | --- |
| `runtime.environment` | public, rendered enum | `ENVIRONMENT` | built-in source: `development` |
| `database.url` | secret | `DATABASE_URL` | none |
| `database.poolSize` | public | `DATABASE_POOL_SIZE` | built-in source: `10` |
| `server.host` | public | `HTTP_HOST` | built-in source: `127.0.0.1` |
| `server.port` | public | `PORT` | built-in source: `8080` |
| `server.webhookSecret` | secret | `WEBHOOK_SECRET` | built-in source: `development-only-change-me` |
| `workers.deliveryEndpoint` | public | `DELIVERY_ENDPOINT` | built-in source: `http://127.0.0.1:18091` |
| `workers.concurrency` | public | `WORKER_CONCURRENCY` | case default by environment, no fallback |
| `workers.visibilityTimeoutSeconds` | public | `WORKER_VISIBILITY_TIMEOUT_SECONDS` | constant default `180` |
| `telemetry.serviceName` | public | `OTEL_SERVICE_NAME` | derived default from `runtime.environment` |
| `email.credentials` | secret, conditional | `EMAIL_CREDENTIALS_JSON` | none; required only when the environment is production (`whenEq`) |

Every setting except the conditional one is declared `required`, exactly as
notification-hub does, so the schema alone overstates the external inputs. The built-in
source is `source "built-in defaults" BuiltInSource …` and is the first element of the
resolution source list. The production profile is `deploymentProfile "production"` with
explicit requirements for `runtime.environment` ("state the deployment's environment
explicitly"), `server.webhookSecret` ("the development webhook secret must never reach
production"), and `workers.deliveryEndpoint` ("the loopback endpoint is a local
development default").

The runner is `runDeploymentWithSnapshot :: Role -> EnvSnapshot -> DeploymentOptions ->
IO DeploymentRun` with `data Role = Server | Worker`; both executables parse the same
options (`--config PATH` YAML files in order, `--set KEY=VALUE`, and the Diagnostics
group) and differ only in the role. Dispatch order: `schemaDiagnostic`, then
`contractDiagnostic`, then load files, then resolve with built-in defaults < files <
environment < overrides, then the role's check, then `resolutionDiagnostic` or a safe
startup summary. Exit codes follow the siblings: 2 usage, 3 source, 4 resolution or check
failure. The server check rejects a webhook secret shorter than 16 characters with the
message `server.webhookSecret: must be at least 16 characters` (never echoing the value);
the worker check rejects `workers.visibilityTimeoutSeconds` below twice
`workers.concurrency` and rejects the development webhook default in production. Both
checks are pure functions over the typed configuration and are exported for tests.

Tests must include: bindings validate at construction; the contract exports with an empty
snapshot, `--config /definitely/missing.yaml`, and no database, with exit 0, and names
every table row above with its verdict (`DATABASE_URL` required, `ENVIRONMENT` defaulted
by source, the webhook secret defaulted but redacted and profile-required, the endpoint
defaulted with a visible public value, `workers.concurrency` defaulted by a case rule
depending on `runtime.environment`, `telemetry.serviceName` deferred, `email.credentials`
conditional); the derived default's function and the case alternatives are `error`
thunks and the export succeeds; a snapshot with a secret sentinel in `DATABASE_URL` and
`WEBHOOK_SECRET` leaves no sentinel in contract text, JSON, or stderr; `--check-config`
with only `ENVIRONMENT=production` set exits 4 listing `database.url` and
`email.credentials` as missing; `--check-config` for the server with a 5-character
`WEBHOOK_SECRET` exits 4 with the length message and no value; `--check-config` for the
worker with `WORKER_VISIBILITY_TIMEOUT_SECONDS=1` exits 4 with the capacity message; and a
complete production snapshot passes both checks with `configuration valid`. Record the
real contract text transcript in Validation and Acceptance once it exists.

Register the package: add `examples/settei-deployment` and a `package
settei-example-deployment` stanza with `tests: True` to cabal.project; add a
`setteiExampleDeploymentPackage` derivation in flake.module.nix mirroring the service's
`callCabal2nix` call (wrapped in `dontCheck` for the same optparse-applicative reason the
comment there gives) and a `packages.settei-example-deployment` output; add a
`Schema.Package` entry to mori.dhall (type Application, visibility Internal, dependencies
settei, settei-env, settei-yaml, settei-optparse-applicative).

### Milestone 5 — Documentation and collateral

Scope: make the feature discoverable, bounded, and recorded.

Write docs/guides/deployment-contract.md ("Authoring a first deployment from the
configuration contract", `docId: DOC-11`, `type: Guide`, tags
`[settei, deployment, configuration]`, `generated.by` naming the implementing agent per the
bundle's existing records). It walks the AC-6 workflow against the new example: export the
contract; read off external inputs, environment names, public defaults, secret inputs,
and profile-required overrides; write the proposed inputs; run the server and worker
check modes; show the expected failures for incomplete inputs and the passing run. It
then states the limits (AC-7): the contract does not validate provider credentials,
connectivity, Kubernetes resources, cross-setting invariants, or deployment wiring; those
remain the application's check mode and the operator's job. It ends with the
compatibility statement: `settei.schema` and `settei.resolution` are unchanged,
`settei.contract` reuses their field names and origin encoding, and existing consumers of
`--describe-config-json` keep working without changes. Register the guide: add a row to
docs/guides/README.md, regenerate docs/guides/index.md with `okf index docs/guides --write
--okf-version 0.2`, and append a log entry with `okf log add docs/guides --kind Add -m
"…"`. Also add a short "Deployment contract" subsection to
docs/guides/environment-and-cli.md's diagnostics table and to docs/guides/cli-application.md's
diagnostic table.

Write docs/capabilities/deployment-configuration-contract.md (`capabilityId: CAP-14`,
packages `settei`, `settei-env`, `settei-optparse-applicative`, interface
`Settei.Contract`, `Settei.Env`, `Settei.Optparse`, `requires` CAP-1, CAP-3, CAP-5, CAP-7,
`since` the next release version the changelog bump implies, evidence rows pointing at
settei/test/Settei/ContractTest.hs, the new example suite, and the guide). Update
docs/capabilities/configuration-diagnostic-options.md (CAP-7) to list the two new flags.
Add the row to docs/capabilities/index.md and a log entry.

Write docs/adr/0012-deployment-contract-export-semantics.md with the profile frontmatter
(`type: Architecture Decision Record`, `docId: ADR-12` after re-running `okf id next`,
`status: Accepted`, `date`, `timestamp`, `description`, `generated`). It records: the
contract is a source-free, effect-free interpreter of the private algebra; default
sources are explicit inputs; derived and case defaults are reported, never evaluated;
source-default candidates are decoded for validity only; sensitivity merges most
restrictively and conflicts are diagnostics; the verdict precedence; the separate
`settei.contract` document; and the rejected alternatives (extending `settei.schema`,
inferring defaults from `BuiltInSource` kinds, evaluating constant-only derivations,
failing the export on any inconsistency). Append a dated amendment to
docs/adr/0007-reference-applications-are-the-public-api-conformance-boundary.md stating
that a fourth internal example, the notification-hub-shaped deployment application, joins
the conformance boundary and that all three application examples expose the contract
modes. Record both with `okf log add docs/adr …`.

Update README.md (package map: mention the deployment example under examples; guides
list: add the new guide; release-status paragraph: one sentence on the contract),
docs/compatibility.md (public modules: add `Settei.Contract`; note the
`DiagnosticMode` extension), docs/security.md (a "Deployment contracts" paragraph: secret
defaults are redacted before retention, the document still reveals keys, variable names,
public defaults, and topology, so treat it as operational metadata), and
settei/CHANGELOG.md (`## Unreleased`: `Settei.Contract`, the renderers, the moved cycle
helper is internal). Finally edit
docs/improvement-requests/export-a-deployment-configuration-contract.md: set `status:
completed`, add `completedAt` (RFC 3339 UTC), a `resolution` naming this plan and the
evidence, and run the bundle validation; append a log entry.

### Milestone 6 — Full validation and closure

Run the complete gates listed in Validation and Acceptance, record the resulting test
totals and the contract transcript in this plan, write Outcomes & Retrospective, and
confirm ADR-12 and the ADR-7 amendment capture everything durable from the Decision Log
and Surprises & Discoveries.


## Concrete Steps

All commands run from the repository root /Users/shinzui/Keikaku/bokuno/settei unless
stated otherwise. `nix develop -c` supplies GHC 9.12.4, Cabal 3.16, fourmolu, treefmt,
and hlint; `okf`, `bun`, and `mori` are on the user's PATH.

Baseline before any change (expect every suite to pass; the 0.2.0.0 collateral records
333 tests across 12 suites):

```bash
git status --short            # expect no output
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
```

Milestone 1:

```bash
# edit settei/src/Settei/Internal/Config.hs, settei/src/Settei/Resolve.hs,
# create settei/src/Settei/Contract.hs, edit settei/src/Settei/Render.hs,
# settei/src/Settei.hs, settei/settei.cabal, settei/test/Main.hs,
# create settei/test/Settei/ContractTest.hs and the two golden files
nix develop -c cabal build settei
nix develop -c cabal test settei-tests --test-show-details=direct
```

Expected tail of the test run:

```text
    Settei.Contract
      renders the golden contract text:                      OK
      renders the golden contract JSON:                      OK
      ...
All N tests passed (0.xxs)
```

Golden files are written by hand first from the expected vocabulary and then corrected
to the real output only after reviewing the diff for leaks; never regenerate a golden
blindly.

Milestone 2:

```bash
nix develop -c cabal test settei-env-tests --test-show-details=direct
nix develop -c cabal test settei-optparse-applicative-tests --test-show-details=direct
```

Milestone 3:

```bash
nix develop -c cabal test settei-example-cli-tests --test-show-details=direct
nix develop -c cabal test settei-example-service-tests --test-show-details=direct
nix develop -c cabal test settei-example-conformance-tests --test-show-details=direct
nix develop -c cabal run settei-example-cli -- --deployment-contract
nix develop -c cabal run settei-example-service -- --config yaml:/missing.yaml --deployment-contract-json
```

Milestone 4:

```bash
mkdir -p examples/settei-deployment/{src/Settei/Example,app/server,app/worker,test/Settei/Example,test/fixtures}
cp examples/settei-service/LICENSE examples/settei-deployment/LICENSE
# create the cabal file, modules, executables, tests, and fixture;
# edit cabal.project, flake.module.nix, mori.dhall
nix develop -c cabal build settei-example-deployment
nix develop -c cabal test settei-example-deployment-tests --test-show-details=direct
nix develop -c cabal run settei-example-deployment-server -- --deployment-contract
nix develop -c cabal run settei-example-deployment-worker -- --deployment-contract-json
ENVIRONMENT=production nix develop -c cabal run settei-example-deployment-server -- --check-config; echo "exit $?"
mori registry show shinzui/settei --full | grep settei-example-deployment
(cd examples/settei-deployment && nix develop -c cabal check)
```

The check-config run (with `DATABASE_URL` and `EMAIL_CREDENTIALS_JSON` unset in your shell) must exit 4 and print, in this order,
`database.url: required value is missing` and `email.credentials: required value is
missing`. (If the local Mori registry lags the working tree, `mori registry show` may not
list the package until the registry is refreshed; the authoritative evidence is
mori.dhall itself.)

Milestone 5:

```bash
okf id next docs/guides --profile mori/user-documentation-profile.dhall DOC        # expect DOC-11
okf id next docs/capabilities --profile docs/capabilities/profile.dhall CAP        # expect CAP-14
okf id next docs/adr --profile docs/adr/profile.dhall ADR                          # expect ADR-12
# write the guide, capability, ADR, amendment, README/compat/security/changelog edits, IR status
okf index docs/guides --write --okf-version 0.2
okf index docs/capabilities --write --okf-version 0.2
okf index docs/adr --write --okf-version 0.2
okf index docs/improvement-requests --write --okf-version 0.2
okf log add docs/guides --kind Add -m "DOC-11 authors a first deployment from the exported configuration contract."
okf log add docs/capabilities --kind Add -m "CAP-14 deployment configuration contract; CAP-7 lists the contract diagnostic flags."
okf log add docs/adr --kind Add -m "ADR-12 fixes deployment-contract export semantics; ADR-7 amended for the deployment example."
okf log add docs/improvement-requests --kind Update -m "IR-1 completed by docs/plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md."
okf validate docs/adr --strict --profile docs/adr/profile.dhall --profile-enforce --log-enforce
okf validate docs/guides --strict --profile mori/user-documentation-profile.dhall --profile-enforce --log-enforce
okf validate docs/capabilities --profile docs/capabilities/profile.dhall --profile-enforce --log-enforce
okf validate docs/improvement-requests --strict --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
```

Check each `okf index` preview before `--write` if the bundle's index carries hand-written
prose (docs/capabilities/index.md does); for that bundle add the CAP-14 table row by hand
instead of regenerating.

Milestone 6:

```bash
nix develop -c cabal build all
nix develop -c cabal test all --test-show-details=direct
nix develop -c treefmt --fail-on-change --no-cache
nix flake check
```

Commits: one per milestone at minimum, each with the trailers

```text
ExecPlan: docs/plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md
Intention: intention_01m5f6nmytec59xh6099xfe37w
```

and a Conventional Commits subject such as `feat(settei): export deployment
configuration contracts`. Record a provenance revision entry the first time this plan is
edited in an implementation session:

```bash
bun agents/skills/exec-plan/record-provenance.ts revision \
  --plan docs/plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md \
  --model <your-model-id> --harness <harness> --mode implement --note "<one line>"
```


## Validation and Acceptance

Each acceptance criterion of IR-1 maps to observable checks:

- AC-1 (deterministic, versioned, joined, diagnosable). `Settei.ContractTest` renders the
  fixture twice and compares bytes; the JSON golden begins
  `{"schemaVersion":1,"type":"settei.contract"`; every fixture binding appears under its
  key; a setting without bindings has `"bindings":[]`; a binding to `nothing.here`
  produces an `undeclared-binding-key` diagnostic naming the variable and key.
- AC-2 (default availability and provenance). The golden shows, for distinct keys:
  `constant` with a visible value; `constant` with `unrenderable`; `constant` with
  `redacted`; `derived` with dependency keys and no value; `case` with dependency keys,
  alternative count, and fallback flag; a source default with `valid`, origin, and
  shadowed origins; a source default with `invalid` and its expected description; and the
  deployment example's test asserts that its all-`required` declaration reports only
  `database.url` (and, conditionally, `email.credentials`) as needing input, plus the
  three profile-required keys.
- AC-3 (requirement distinctions). The core test checks the five verdict cases named in
  the Decision Log; the deployment example's contract shows `server.webhookSecret` as
  `required` with reason `deployment-profile` although a default exists, and
  `email.credentials` as `conditional`.
- AC-4 (no effects, no evaluation). Core: `error` thunks inside derived and case defaults
  are never forced; a cyclic declaration returns `Left` without forcing a source's
  location hook. Applications: every example suite exports with nonexistent `--config`
  and `--secrets-dir` paths, an empty snapshot, and no database; the deployment example
  additionally proves `--check-config` with the same arguments fails (so the contract
  path demonstrably did less work than resolution).
- AC-5 (secret safety). Sentinels injected into a secret constant default, a secret
  source default, a mixed-sensitivity key's public default, a binding value in the
  snapshot, and a diagnostic-bearing source are absent from `show`, text, JSON, stderr,
  and the conformance group's outputs; the mixed-sensitivity key renders as `secret`
  with `redacted`.
- AC-6 (documented first-deployment workflow). The guide's transcript is reproduced by
  the deployment example's suite: contract export without credentials, then server and
  worker check-mode failures for incomplete inputs, then a passing production run.
- AC-7 (limits and compatibility). The guide states the non-claims; the CLI and service
  suites still pass their unchanged `--describe-config-json` assertions
  (`"type":"settei.schema"` with the same five fields); the core golden
  settei/test/golden/schema.json is byte-identical to its pre-plan content.

Required gates before the plan is complete: all commands in Milestone 6 pass; the four
`okf validate` commands pass; `cabal check` in examples/settei-deployment reports no
errors; `git status --short` is empty after the final commit.

Expected shape of the deployment example's text contract (to be replaced with the real
transcript during Milestone 4; the vocabulary, order, and redaction are the requirement,
the exact spacing is not):

```text
database.poolSize [required, necessary, public] Database pool size
  input: defaulted (built-in source)
  default: 10 from built-in source built-in defaults
  bound: environment variable DATABASE_POOL_SIZE
database.url [required, necessary, secret] PostgreSQL connection string
  input: required (no default)
  bound: environment variable DATABASE_URL
email.credentials [required, conditional, secret] Email account credentials as JSON
  input: conditional (no default)
  bound: environment variable EMAIL_CREDENTIALS_JSON
runtime.environment [required, necessary, public] Runtime environment
  input: required (deployment profile production: state the deployment's environment explicitly)
  default: "development" from built-in source built-in defaults
  bound: environment variable ENVIRONMENT
server.webhookSecret [required, necessary, secret] Delivery webhook HMAC secret
  input: required (deployment profile production: the development webhook secret must never reach production)
  default: <redacted> from built-in source built-in defaults
  bound: environment variable WEBHOOK_SECRET
telemetry.serviceName [optional, necessary, public] OpenTelemetry service name
  input: defaulted (declaration rule telemetry-service-name-by-environment, derived from runtime.environment; value not computed)
  bound: environment variable OTEL_SERVICE_NAME
workers.concurrency [optional, necessary, public] Concurrent delivery handlers
  input: defaulted (declaration rule worker-concurrency-by-environment, case on runtime.environment, 3 alternatives, no fallback)
  bound: environment variable WORKER_CONCURRENCY
condition 1: runtime.environment -> email.credentials
```

Proposed, not required: a settei-kubernetes converter from `FileBindings` to
`InputBinding` values (`CustomInput "kubernetes-mounted-file"`), and a `mina`/`mori`
consumer that compares a Pulumi program's environment names against a contract. Both
need a scope decision before they become acceptance.


## Idempotence and Recovery

Every change in this plan is additive to the working tree: new modules, new tests, new
golden files, new documentation records, and one new example package. Re-running any
build or test command is safe. `okf id next` only reports the next free handle, so it may
be re-run freely; `okf log add` appends, so run it once per entry and remove a duplicated
entry by hand if a command is repeated. `okf index --write` regenerates generated index
files deterministically. If a golden test fails after an intentional renderer change,
inspect the diff for secret leaks before updating the golden. If the Nix derivation for
the new example fails to evaluate, the Cabal build and tests remain authoritative for the
code; fix the `flake.module.nix` entry by comparing it line by line with the service's. If
a milestone must be abandoned midway, commit only green states; `git stash` holds partial
work, and the previous milestone's commit is always a clean restart point.

The IR status edit is the only non-additive change; if validation then fails, restore the
previous frontmatter from git, fix the field the validator names (`completedAt` must be
RFC 3339 UTC when `status: completed`), and retry.


## Interfaces and Dependencies

New public module `Settei.Contract` in the `settei` package (also re-exported by
`Settei`):

```haskell
-- Inputs
data InputChannel = EnvironmentVariable | CustomInput !Text
data InputBinding                              -- private constructor
inputBinding :: InputChannel -> Text -> Key -> InputBinding
annotateInputBinding :: Map Text Text -> InputBinding -> InputBinding
inputBindingChannel :: InputBinding -> InputChannel
inputBindingName :: InputBinding -> Text
inputBindingKey :: InputBinding -> Key
inputBindingAnnotations :: InputBinding -> Map Text Text

data DeploymentProfile                         -- private constructor
deploymentProfile :: Text -> [(Key, Text)] -> DeploymentProfile   -- name, (key, reason)
profileName :: DeploymentProfile -> Text
profileRequirements :: DeploymentProfile -> Map Key Text

data ContractInputs = ContractInputs
  { inputs :: ![InputBinding],
    defaultSources :: ![Source],               -- lowest to highest precedence
    profile :: !(Maybe DeploymentProfile)
  }
emptyContractInputs :: ContractInputs

-- Builder
deploymentContract :: ContractInputs -> Config a -> Either (NonEmpty ConfigError) DeploymentContract

-- Output
data DeploymentContract                        -- private constructor
contractSettings :: DeploymentContract -> [ContractSetting]       -- key order
contractConditions :: DeploymentContract -> [Condition]
contractProfile :: DeploymentContract -> Maybe Text
contractDiagnostics :: DeploymentContract -> [ContractDiagnostic]

data ContractSetting = ContractSetting
  { key :: !Key, description :: !Text, sensitivity :: !Sensitivity,
    requirement :: !Requirement, presence :: !Presence,
    inputs :: ![InputBinding],
    declaredDefaults :: ![DeclaredDefault],
    sourceDefault :: !(Maybe SourceDefault),
    deploymentRequirement :: !(Maybe Text),
    externalInput :: !ExternalInput }

data DeclaredDefault = DeclaredDefault { rule :: !RuleName, explanation :: !Text, shape :: !DefaultShape }
data DefaultShape = ConstantShape !DefaultValue | DerivedShape ![Key] | CaseShape ![Key] !Int !Bool
data DefaultValue = VisibleDefault !Text | RedactedDefault | UnrenderableDefault

data SourceDefault = SourceDefault
  { origin :: !Origin, shadowed :: ![Origin], value :: !ReportedValue, validity :: !DefaultValidity }
data DefaultValidity = ValidDefault | InvalidDefault !Text      -- expected description only

data ExternalInput
  = InputRequired !InputReason
  | InputConditional !InputReason
  | InputDefaulted !DefaultCoverage
  | InputOptional
data InputReason = NoDefault | InvalidSourceDefault | RequiredRequest | ProfileRequirement
data DefaultCoverage = CoveredBySource | CoveredByDeclaration ![Key]

data ContractDiagnostic
  = ConflictingSensitivity !Key
  | DefaultStructuralConflict !StructuralError
  | UndeclaredDefaultLeaf !UnknownKeyProblem
  | UndeclaredBindingKey !InputBinding
  | UndeclaredProfileKey !Key
```

All of these types derive `Generic`, `Eq`, and `Show`; `Show` is safe because every
retained value is a `ReportedValue`, a `DefaultValue`, a name, a key, or an origin. No
lens type appears in a public signature (the compatibility policy's audit rule). The
record fields are deliberately named `inputs` rather than `bindings`: `Settei.Contract` is
re-exported by `Settei`, every reference application imports `Settei` and `Settei.Env`
unqualified, and a field selector named `bindings` would make `Settei.Env.bindings`
ambiguous in all of them. Do not reintroduce that name.

`Settei.Render` additions:

```haskell
renderContractText :: DeploymentContract -> Text
renderContractJson :: DeploymentContract -> Text
```

JSON layout (`schemaVersion` 1, `type` `settei.contract`): top-level `profile` (string
or null), `settings` (array in key order), `conditions` (as in `settei.schema`), and
`diagnostics` (array). Each setting object carries `key`, `description`, `sensitivity`,
`requirement`, `presence` spelled exactly as `settei.schema`, then `bindings` (objects
with `channel` = `environment` or `custom`, `channelDetail` string or null, `name`,
`annotations` map), `declaredDefaults` (objects with `rule`, `explanation`, `kind` =
`constant`/`derived`/`case`, `value` string or null, `valueAvailability` =
`visible`/`redacted`/`unrenderable`/null, `dependencies` key array, `alternatives` int
or null, `fallback` bool or null), `sourceDefault` (null or object with `origin` and
`shadowed` using the resolution report's origin encoding, `value` rendered with
`renderReportedValue`, `validity` = `valid`/`invalid`, `expected` string or null),
`deploymentRequirement` (string or null), and `externalInput` (object with `verdict` =
`required`/`conditional`/`defaulted`/`optional`, `reason` =
`no-default`/`invalid-source-default`/`required-request`/`deployment-profile`/null,
`coverage` = `source`/`declaration`/null, `dependencies` key array). Each diagnostic
object has `kind` = `conflicting-sensitivity`/`default-structural-conflict`/
`undeclared-default-leaf`/`undeclared-binding-key`/`undeclared-profile-key` and the
fields of its payload using the existing `errorJson` spellings for origins and keys.

`Settei.Internal.Config` additions (private): `validateDefaultCycles :: Config a ->
[ConfigError]` and `defaultRule :: Default a -> RuleName`, moved from `Settei.Resolve`.

`Settei.Env` addition:

```haskell
inputBindings :: Bindings -> [InputBinding]
```

`Settei.Optparse` additions: constructors `DeploymentContractText` and
`DeploymentContractJson` on `DiagnosticMode`; flags `--deployment-contract` and
`--deployment-contract-json` in `diagnosticModeOptions`; and

```haskell
contractDiagnostic ::
  DiagnosticMode ->
  Either (NonEmpty ConfigError) DeploymentContract ->
  Maybe (Either (NonEmpty ConfigError) Text)
```

New internal package `settei-example-deployment` (examples/settei-deployment): library
module `Settei.Example.Deployment` exporting `Role (..)`, `DeploymentOptions`,
`DeploymentRun`, `deploymentConfig :: Config DeploymentConfig`, `builtInDefaultsSource ::
Source`, `environmentBindings :: Bindings`, `productionProfile :: DeploymentProfile`,
`deploymentContractInputs :: ContractInputs`, `deploymentParserInfo :: Role -> ParserInfo
DeploymentOptions`, `runDeploymentWithSnapshot`, `checkServer`, `checkWorker`, the exit
code constants, and the run accessors; executables `settei-example-deployment-server` and
`settei-example-deployment-worker`; test suite `settei-example-deployment-tests`.

Dependencies whose choice matters: no new third-party dependency is introduced anywhere.
The core keeps emitting JSON through its own deterministic encoder (docs/adr/0003 rejects
Aeson for this purpose). The example uses `settei-yaml` for its `--config PATH` files
because the originating consumer does; it deliberately does not use `settei-formats` or
`settei-kubernetes`. Dependency source and documentation for `optparse-applicative`
0.19 (`parserOptionGroup`, `flag'`) and `tasty` are registered in Mori
(`mori registry show pcapriotti/optparse-applicative --full`, `mori registry show
UnkindPartition/tasty --full`); consult them before guessing an API.
