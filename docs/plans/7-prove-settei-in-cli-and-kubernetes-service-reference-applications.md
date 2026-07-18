---
id: 7
slug: prove-settei-in-cli-and-kubernetes-service-reference-applications
title: "Prove Settei in CLI and Kubernetes service reference applications"
kind: exec-plan
created_at: 2026-07-16T23:50:16Z
intention: intention_01kxr36cqgem8tmxjjtnq0t6ns
master_plan: "docs/masterplans/1-build-settei-as-a-provenance-aware-configuration-library-for-haskell.md"
---

# Prove Settei in CLI and Kubernetes service reference applications

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture

After this plan, the complete Settei package family is demonstrated in two executable,
tested examples. A CLI layers defaults, files, environment, and command-line overrides and
can print either its static schema or the exact construction of its resolved configuration.
A service-shaped program loads a mounted file and environment variables as Kubernetes
would deliver them, derives defaults from Development/Test/Production, requires a database
secret only in Production, and logs a redacted explanation.

Equivalent YAML, KDL, and Dhall inputs produce the same typed application value and the
same resolution shape apart from honest format-specific origins. The repository finishes
with package documentation, a compatibility matrix, and a release checklist. Deploying a
real cluster or migrating Rei, Mori, Seihou, `tan-commons-config`, or `mls-service-v2`
remains outside this plan.


## Progress

- [x] (2026-07-18 07:47 PDT) Audit the completed plans, six ADRs, adapter guides,
  current public modules, registered convention corpus, package metadata, and named
  consumer configuration boundaries. The pinned GHC 9.12.4 shell passes all 121
  pre-change tests; the host Cabal uses an older compiler and is not a valid build
  environment for this workspace.
- [x] (2026-07-18 07:53 PDT) Add the non-published `settei-example-cli` library,
  executable, packaged YAML fixture, and six end-to-end tests. The tests prove ordered
  file/environment/repeated-CLI precedence, source-free schema inspection, intent-grouped
  help, usage/source/resolution exit codes 2/3/4, versioned JSON, and secret redaction.
- [ ] Add a service reference package with derived defaults and selective requirements.
- [ ] Add Kubernetes ConfigMap, Secret, and Deployment example manifests.
- [ ] Build a cross-format conformance fixture and report comparison suite.
- [ ] Complete guides, API navigation, compatibility and security documentation.
- [ ] Validate Cabal, Nix, Haddocks, source distributions, and the release checklist.


## Surprises & Discoveries

- Observation: the host Cabal process uses GHC 9.10 and `base-4.20`, while every Settei
  package correctly requires GHC 9.12 or newer and `base >=4.21`.
  Evidence: a direct `cabal test all` solve rejected installed `base-4.20.2.0`, while
  `nix develop -c cabal test all --test-show-details=direct` selected GHC 9.12.4 and
  passed all 121 existing tests.
  Impact: every EP-7 build, test, Haddock, and source-distribution command runs through
  the pinned Nix development shell unless the active compiler independently reports GHC
  9.12 or newer.

- Observation: the prescribed `ServiceConfig` shape has no list field, but the
  cross-format fixture must include a list with at least two elements to exercise KDL's
  cardinality mapping.
  Evidence: Milestone 2 fixes the public service records, while Milestone 3 separately
  requires the shared list and equivalent typed values.
  Impact: the service declaration remains exactly as specified, and the conformance
  declaration pairs it with `service.tags :: [Text]` so list equivalence is tested
  without changing the reference service's public configuration type.


## Decision Log

- Decision: Use small reference executables in this repository before migrating existing
  applications.
  Rationale: examples can exercise the intended public API and change with it without
  coupling the first release to unrelated production release cycles.
  Date: 2026-07-16

- Decision: Demonstrate Kubernetes through ordinary environment variables and mounted
  files plus explicit origin annotations.
  Rationale: those are the deployment mechanisms visible to a process; cluster API access
  is unnecessary for configuration loading and provenance.
  Date: 2026-07-16

- Decision: Compare cross-format typed values and normalized provenance structure while
  retaining format-specific origin details.
  Rationale: equal configuration semantics should not erase the truthful difference
  between a YAML path, KDL span, and Dhall import graph.
  Date: 2026-07-16

- Decision: Make the reference applications demonstrate the shared Haskell conventions,
  including nested records with reusable labels and intent-based CLI option groups.
  Rationale: examples are the public proof of how consumers should use Settei; prefixed
  flat fields or an unstructured wall of flags would teach patterns that conflict with the
  registered convention corpus.
  Date: 2026-07-16

- Decision: Keep all non-published reference and conformance packages beneath
  `examples/`, while every publishable Settei library remains a same-named top-level
  sibling.
  Rationale: the directory boundary makes release ownership visible and prevents a root
  `test/` package from recreating the special workspace layout removed by Plan 8.
  Date: 2026-07-17

- Decision: Default every reference-app Dhall load to `NoImports`; allow only an explicit
  `LocalImportsWithin` canonical root where a local graph is part of the demonstration.
  Rationale: EP-6 proved those are the policies the maintained Dhall API can both enforce
  and report completely enough for Settei; the examples must not imply support for
  unrestricted filesystem, environment, or network imports.
  Date: 2026-07-18

- Decision: Keep `ServiceConfig` unchanged and define the conformance result as the
  service value paired with a required two-or-more-element `service.tags` list.
  Rationale: this resolves the plan's list-coverage requirement without teaching a field
  that the prescribed service application does not consume; YAML, KDL, and Dhall must
  still produce one equal typed conformance result and one equal normalized report.
  Date: 2026-07-18

- Decision: Treat the Nix development shell as the executable validation boundary for
  this repository.
  Rationale: the project explicitly targets GHC 9.12, and the host toolchain's older
  non-reinstallable `base` cannot solve the declared package bounds.
  Date: 2026-07-18


## Outcomes & Retrospective

To be filled during and after implementation. Before completing the MasterPlan, summarize
which parts of the reference API are stable enough for production adoption and create
follow-up migration plans for consumers only if separately authorized. Confirm that both
example `.cabal` files declare the canonical package-local GHC2024 common stanza, every
component imports it, and the examples and conformance suite pass the shared prelude,
record, deriving, lens, qualified-import, and CLI option-group audit.


## Context and Orientation

This plan depends on all adapter plans:

- `docs/plans/3-add-environment-and-optparse-applicative-configuration-sources.md`
- `docs/plans/4-add-yaml-configuration-support.md`
- `docs/plans/5-add-kdl-configuration-support.md`
- `docs/plans/6-add-dhall-configuration-support.md`

It also relies on the completed sibling-package migration in
`docs/plans/8-move-settei-packages-to-top-level-sibling-directories.md` and transitively on
the declaration and resolution work in Plans 1 and 2. Read the completed plans, ADRs,
guides, and actual public modules before starting. The core is rooted at `settei/`, every
publishable adapter is a same-named top-level sibling, and non-published packages belong
beneath `examples/`. If any adapter was deliberately narrowed, make the examples
demonstrate its real guarantee rather than the initial aspiration.

The CLI use case needs interactive errors, explicit file ordering, environment overrides,
command-line overrides, schema display, and text or JSON explanations. The service use case
needs deterministic startup, deployment metadata, environment-dependent defaults,
production-only secrets, and a safe diagnostic that can be logged. "Hierarchical" means
both nested keys such as `database.pool.size` and ordered layers; it does not imply that
every executable must implement automatic file discovery.

At planning time, `mls-service-v2` consumes environment configuration derived from
`tan-commons-config`, and its Kubernetes deployment supplies environment values from
ConfigMaps, Secrets, and direct deployment fields. Rei, Mori, and Seihou each contain
different configuration approaches. Re-locate them with Mori and read current source and
deployment files before writing comparison or migration prose.

Plan 1 owns the applicable conventions from registered project
`shinzui/haskell-jitsurei`. Example modules import `Settei.Prelude`, import
`Data.Generics.Labels ()` locally when using generic-lens labels, keep record fields strict
and unprefixed, and use explicit deriving strategies. They access nested configuration with
lens composition such as `config ^. #database . #port`, not generated selectors or record
updates, and write qualified imports postpositively. Example packages declare
`generic-lens` directly when they import the label instance. The registered option-group
pattern applies to the CLI example: group by user intent, keep labels short, and retain
optparse-applicative's ordinary help section for `--help`. Shell completions, help topics,
and terminal-width reflow are deliberately outside this small reference CLI unless later
requirements explicitly add them.
[ADR 0001](../adr/0001-haskell-project-conventions.md) records the durable rationale and
rejected alternatives for this baseline. Read
[ADR 0006](../adr/0006-dhall-input-import-and-provenance-semantics.md) before wiring Dhall
into either reference application; it defines the enforceable import surface and the
honest root-plus-closure provenance precision.


## Plan of Work

### Milestone 1: build the CLI reference application

Create `examples/settei-cli/settei-example-cli.cabal` and modules under
`examples/settei-cli/src/`. Register it as a non-published package in `cabal.project` and
Nix checks. Repeat Plan 1's canonical package-local `common common` stanza and import it
from the library, executable, and test components. Define one `Config CliConfig` containing
`runtime.environment`, a service endpoint, timeout, output format, and a secret token. Keep
the declaration in a library module so tests can inspect it without spawning the
executable.

The executable accepts ordered repeated `--config FORMAT:PATH`, where FORMAT is `yaml`,
`kdl`, or `dhall`; file arguments later on the command line have higher precedence. It
then adds explicitly mapped environment variables and CLI `--set KEY=VALUE` or direct
options. The resulting order is:

```text
named built-in defaults
< config files in command-line order
< explicitly mapped environment variables
< repeated --set values in their occurrence order
```

Use an explicit format tag rather than guessing from content. A convenience may infer a
format from `.yaml`, `.yml`, `.kdl`, or `.dhall`, but ambiguity and unknown extensions must
produce an actionable error. Dhall evaluation defaults to `NoImports`. If the CLI exposes
local imports, the user must provide an explicit root for `LocalImportsWithin`; do not add
an unrestricted or implicit standard-import mode.

Add `--describe-config` for the static schema, `--explain-config` for the actual text
report, `--explain-config-json` for the versioned JSON report, and `--check-config` to
validate without performing the example action. Explanation flags must not cause the
application to print a typed record with secrets afterward. Establish exit codes for CLI
usage errors, source IO/parse failures, and resolution failures and test them. Wrap config
paths, environment bindings, direct options, and `--set` under a short “Configuration”
`parserOptionGroup`; wrap describe, explain, and check modes under “Diagnostics”. The
groups change help layout only, not parsing or precedence, and tests should snapshot the
grouped `--help` headings.

### Milestone 2: build the service and Kubernetes example

Create `examples/settei-service/settei-example-service.cabal` with its declaration in a
testable library module. Repeat the canonical package-local `common common` stanza and
import it from the library, executable, and test components. Define:

```haskell
data RuntimeEnvironment = Development | Test | Production
  deriving stock (Generic, Eq, Ord, Show)

data ServiceConfig = ServiceConfig
  { environment :: !RuntimeEnvironment
  , http :: !HttpConfig
  , database :: !DatabaseConfig
  }
  deriving stock (Generic, Eq)

data HttpConfig = HttpConfig
  { host :: !Text
  , port :: !Int
  }
  deriving stock (Generic, Eq, Show)

data DatabaseConfig = DatabaseConfig
  { host :: !Text
  , port :: !Int
  , poolSize :: !Int
  , password :: !(Maybe SecretText)
  }
  deriving stock (Generic, Eq)
```

Use a named `caseDefault` or equivalent core rule for the HTTP `port` and database
`poolSize`, with different Development, Test, and Production values. Use a
Selective branch to require `database.password` only in Production. Use the
`#http . #port`, `#database . #poolSize`, and `#database . #password` paths when assembling
or inspecting the typed result. Keep `SecretText`, `DatabaseConfig`, and `ServiceConfig`
without revealing `Show` instances.

The service accepts one mounted config file with explicit format, then mapped environment
variables. It supports `--check-config` and redacted text or JSON explanation. In its
normal demonstration mode it prints only a safe startup summary and exits or runs a
minimal deterministic health server if the repository already has an appropriate
dependency; networking is not required to prove configuration.

Add these reviewed example assets beneath `examples/settei-service/kubernetes/`:

- `configmap.yaml` with a mounted public configuration file.
- `secret.yaml.example` with placeholders only and clear instructions not to commit real
  secret data.
- `deployment.yaml` mounting the ConfigMap, mapping `HASKELL_ENV`, and sourcing
  `DATABASE_PASSWORD` through `secretKeyRef`.
- `README.md` matching each manifest delivery path to the origin annotations supplied in
  Haskell code.

The source annotation for the password names the Kubernetes Secret and key but all output
shows `<redacted>`. The example does not use a Kubernetes SDK and is validated with local
fixtures; no cluster deployment is required.

### Milestone 3: create a cross-format conformance suite

Create the non-published package
`examples/settei-conformance/settei-example-conformance.cabal`. Its test suite owns
fixtures beneath `examples/settei-conformance/test/fixtures/`, where the same nested public
configuration is encoded in YAML, KDL, and Dhall, including environment, HTTP settings,
database host/port/pool, and a list with at least two elements so KDL's documented
cardinality mapping represents it as an array. Register this example package in
`cabal.project` and Nix checks, declare the canonical package-local common stanza, and
keep its fixtures in the package's source distribution. Do not put a real or stable
secret in fixtures. Keep the Dhall conformance fixture import-free and load it with
`NoImports`; exercise `LocalImportsWithin` separately only if the examples need to
demonstrate an import graph. Load each through its adapter and resolve the same
`Config ServiceConfig`.

Assert that all typed public values match. Normalize reports only by replacing the
format-specific origin payload with its source class; then assert equal key sets, selected
versus skipped states, derivation rule names, dependency edges, and shadow counts. Separate
assertions verify that YAML retains path/key precision, KDL retains spans, and Dhall retains
root/import precision and its explicit leaf-attribution limitation.

Add matrix tests for source ordering: defaults only; file over default; environment over
file; CLI over environment for the CLI app; malformed high-priority input; Development
without a password; Production without a password; and Production with an annotated
Secret. Scan every captured stdout, stderr, report, and golden for secret sentinels.

### Milestone 4: finish documentation and release readiness

Write a root `README.md` using the tagline "Typed, layered, explainable configuration for
Haskell." It should explain the package map, show one short declaration, show ordered
source assembly, show a derived environment default, and link to format and application
guides. Add `docs/guides/cli-application.md`, `docs/guides/kubernetes-service.md`, and
`docs/security.md`. The security guide covers sensitivity ownership, redaction guarantees,
environment exposure, mounted Secret limitations, Dhall imports, and safe error handling.

Add a compatibility page listing tested GHC, Cabal, Nix, `selective`, parser, and adapter
versions. Review every package's exposed modules, synopsis, description, license, source
repository metadata, dependency bounds, tested-with field, and changelog. Version the
initial publishable packages consistently, for example 0.1.0.0, without promising semantic
stability beyond documented public modules.

Ensure `mori.dhall` describes all repository packages and dependencies and `mori show
--full` remains accurate. Generate Haddocks with no unexpected warnings, build source
distributions, unpack them into a temporary directory, and build/test from the contents.
Create `docs/release-checklist.md`; do not upload packages or create a release unless the
user separately authorizes it.


## Concrete Steps

Run from `/Users/shinzui/Keikaku/bokuno/settei`. Refresh consumer evidence first:

```bash
mori show --full
mori registry search tan-commons-config
mori registry search mls-service-v2
mori registry search rei
mori registry search mori
mori registry search seihou
mori registry search generic-lens
mori registry show ekmett/lens --full
mori registry show shinzui/haskell-jitsurei --full
mori registry docs shinzui/haskell-jitsurei
```

Inspect each qualified result used in documentation:

```bash
mori registry show QUALIFIED_PROJECT_NAME --full
mori registry docs QUALIFIED_PROJECT_NAME
mori registry dependents QUALIFIED_PROJECT_NAME --packages
```

Exercise the CLI example with local fixtures:

```bash
cabal run settei-example-cli -- --config yaml:examples/settei-conformance/test/fixtures/service.yaml --check-config
cabal run settei-example-cli -- --config kdl:examples/settei-conformance/test/fixtures/service.kdl --describe-config
cabal run settei-example-cli -- --config dhall:examples/settei-conformance/test/fixtures/service.dhall --explain-config
```

Exercise service development and production behavior with the example's documented
fixture runner rather than the developer's environment:

```bash
cabal test settei-example-service-tests --test-show-details=direct
```

At completion, run:

```bash
nix fmt
cabal build all
cabal test all --test-show-details=direct
cabal haddock all
cabal sdist all
cabal check
mori show --full
nix flake check
git diff --check
```

Expected end-to-end test names include:

```text
Settei.Example.Cli
  cli overrides environment overrides ordered files: OK
  describe works without loading sources: OK
Settei.Example.Service
  development derives defaults without a password: OK
  production requires an annotated password: OK
Settei.Conformance
  YAML KDL and Dhall produce equal typed values: OK
  normalized explanation structure is format-independent: OK
Settei.Security
  no captured output contains secret sentinels: OK
All tests passed
```


## Validation and Acceptance

Run the CLI with a file port of 7000, injected environment port of 8000, and two CLI
overrides of 9000 and 9001. It must select 9001 and explain every shadowed candidate in
order. `--describe-config` must work without any file or environment access and list
possible conditional settings. `--explain-config-json` must parse as JSON and contain the
documented report schema version.

Run the service declaration as Development with no password. It must derive the documented
development HTTP port and pool size, skip the production-only password, and say both why
the defaults were chosen and why the secret was not evaluated. Run as Production without
a password and receive a missing-setting error naming the key but no value. Run as
Production with an injected, Kubernetes-annotated sentinel password and succeed while all
captured output remains redacted.

Load the equivalent YAML, KDL, and Dhall conformance files. Typed results, default rules,
dependency edges, and setting states must match. Origin assertions must demonstrate each
format's truthful precision instead of forcing identical text.

All packages must build and test together through Cabal and `nix flake check`. Haddocks
must cover every exposed module. Each source distribution must contain the required source,
license, docs, and fixtures and must build without files available only from the working
tree. The release checklist must be complete except for explicitly manual publication and
signing steps.


## Idempotence and Recovery

Examples and tests use injected environment snapshots and local fixture files, so they are
repeatable and do not require a cluster. Dhall conformance uses `NoImports`, so it cannot
read the network, process environment, or another file.
Kubernetes assets contain placeholders only; never generate or commit a real Secret value.

Source-distribution creation and Haddock generation are repeatable. Unpack distributions
under a new temporary directory each time and remove them only with an explicitly scoped
command. If an adapter has a documented limitation, adjust the conformance normalization
to represent that limitation honestly rather than weakening typed-value or redaction
assertions.


## Interfaces and Dependencies

`settei-example-cli` depends on all six publishable Settei packages and uses only their
public modules. `settei-example-service` depends on `settei`, `settei-env`, and the file
adapters it demonstrates; it may use `settei-optparse-applicative` for diagnostic flags.
`settei-example-conformance` depends on the core and all format adapters and owns the
cross-format fixtures and report-normalization tests.
Each example package declares `generic-lens` directly when its modules import
`Data.Generics.Labels ()`; each `.cabal` file declares the canonical package-local
`common common` stanza and imports it from all components. Examples are non-published
packages.

The conformance suite depends on `tasty`, `tasty-hunit`, and adapter test dependencies
already selected through Mori-backed source inspection. It must not introduce a second
merge or report implementation. Kubernetes files are static example assets and add no
Haskell dependency. No plan step uploads to Hackage, creates Git tags, deploys Kubernetes,
or mutates production consumers without separate authorization.


## Revision Note

2026-07-16: Updated both reference applications and their conformance work to demonstrate
the registered Haskell conventions. The service configuration is now nested with strict
reusable labels and explicit deriving, record access is lens-based, example packages carry
their own generic-lens dependency when needed, qualified imports are postpositive, and the
CLI presents intent-based Configuration and Diagnostics option groups without expanding
the reference application's scope.

2026-07-17: Aligned the reference work with Plan 8's sibling-package convention. The core
and adapters are consumed from their top-level package roots, while CLI, service, and the
new self-contained conformance test package remain beneath `examples/`; conformance
fixtures no longer recreate a repository-root `test/` tree.

2026-07-17: Propagated Plan 5's accepted KDL cardinality mapping into the conformance
fixture design. The shared list now requires at least two elements because one KDL
positional argument is canonically a scalar, while two or more arguments form an array.

2026-07-18: Propagated Plan 6's accepted Dhall contract into both reference applications
and the conformance suite. Dhall now defaults to `NoImports`, any demonstrated local graph
must use an explicit `LocalImportsWithin` root, and the examples must neither expose nor
imply an unrestricted standard-import mode.
