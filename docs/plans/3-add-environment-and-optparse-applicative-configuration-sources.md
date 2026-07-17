---
id: 3
slug: add-environment-and-optparse-applicative-configuration-sources
title: "Add environment and optparse-applicative configuration sources"
kind: exec-plan
created_at: 2026-07-16T23:50:04Z
intention: intention_01kxr36cqgem8tmxjjtnq0t6ns
master_plan: "docs/masterplans/1-build-settei-as-a-provenance-aware-configuration-library-for-haskell.md"
---

# Add environment and optparse-applicative configuration sources

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture

After this plan, services can load explicitly mapped environment variables and CLIs can
turn `optparse-applicative` options into the same provenance-aware sources used everywhere
else. An explanation names the precise variable or option occurrence that supplied a
value. Tests can inject an environment snapshot and use `execParserPure`, so they do not mutate
the developer's process. Applications can annotate an environment variable as originating
from a Kubernetes ConfigMap or Secret without Settei contacting a cluster.

The plan produces two packages: `settei-env` and `settei-optparse-applicative`. It also
proves ordinary precedence such as file below environment below CLI. It does not discover
configuration files, parse YAML/KDL/Dhall, or prescribe every application's command-line
interface.


## Progress

- [x] (2026-07-17 07:34 PDT) Add and register the `settei-env` package.
- [x] (2026-07-17 07:34 PDT) Implement explicit bindings, prefix helpers, injected snapshots, and origin metadata.
- [x] (2026-07-17 07:41 PDT) Add and register the `settei-optparse-applicative` package.
- [x] (2026-07-17 07:41 PDT) Implement generic overrides, direct option bindings, config-path and explain options.
- [x] (2026-07-17 07:41 PDT) Test repeated options, precedence, redaction, and Kubernetes annotations.
- [x] (2026-07-17 07:56 PDT) Document migration from small `envparse` configurations.


## Surprises & Discoveries

- Observation: core `Source` originally attached annotations only once for the entire
  source, but one environment source can contain many keys controlled by different
  variables.
  Evidence: the initial adapter could build the correct raw tree but could not make
  `lookupSource` return distinct `environment.variable` annotations for two keys.
  Impact: core now provides `annotateSourceAt`; YAML, KDL, and Dhall adapters can use the
  same hook for exact-key metadata without splitting one document into many sources.

- Observation: the deterministic pure runner in registered optparse-applicative 0.19.0.0
  is named `execParserPure`, not `parsePure`.
  Evidence: direct inspection of `Options.Applicative` and
  `Options.Applicative.Extra` found the exported `execParserPure`, `ParserResult`, and
  `getParseResult` API and no `parsePure` definition.
  Impact: adapter tests and this plan use the supported public function name.

- Observation: core JSON rendering already retained all Kubernetes annotations, while
  core text rendering named only the environment variable or command-line option.
  Evidence: the first Secret and ConfigMap explanation tests found object metadata in
  `renderResolutionJson` but not `renderResolutionText`.
  Impact: the shared text renderer now adds a Kubernetes object suffix for any annotated
  origin, including future mounted-file adapters.

- Observation: preserving the complete `KEY=VALUE` token as command-line origin metadata
  would copy a secret value into otherwise safe reports.
  Evidence: the adapter's redaction test resolves a secret `--set` value and audits text
  and JSON output for the sentinel while still requiring an exact key and occurrence.
  Impact: `CliOverride` has a private constructor and retains the safe spelling
  `--set KEY`; value text remains only in constructor-private `RawValue` until core applies
  setting sensitivity.

- Observation: nixpkgs' GHC 9.12.4 package set provides optparse-applicative 0.18, while
  this adapter requires the source-inspected 0.19 `parserOptionGroup` API; moreover, the
  nixpkgs `tasty` derivation was built against 0.18.
  Evidence: the first explicit Nix adapter build could not resolve the 0.19 lower bound;
  after pinning 0.19, enabling the adapter test component mixed both optparse ABIs in one
  graph. Cabal's coherent solver plan ran the same tests successfully against 0.19.
  Impact: the flake pins the 0.19.0.0 Hackage source, the Nix library output disables its
  test component, and `cabal test all` remains the authoritative executable test run.


## Decision Log

- Decision: Require explicit environment-to-key bindings by default and offer prefix-based
  name derivation only as an opt-in helper.
  Rationale: implicit global conversion rules create surprising collisions and make it
  harder to tell users which variable controls a setting.
  Date: 2026-07-16

- Decision: Model Kubernetes ConfigMap and Secret identity as trusted origin annotations.
  Rationale: a process normally sees only its environment or mounted files and cannot
  reliably infer the Kubernetes object that populated them.
  Date: 2026-07-16

- Decision: Preserve repeated CLI overrides as ordered source fragments rather than
  collapsing them before core resolution.
  Rationale: the core report can then show that the last occurrence won and earlier
  occurrences were shadowed.
  Date: 2026-07-16

- Decision: Apply the shared Haskell record and prelude conventions to both adapter
  packages, and use `parserOptionGroup` for the reusable Settei option parser.
  Rationale: unprefixed labels remain readable through generic-lens, while grouping
  configuration inputs separately from diagnostics makes generated `--help` easier to
  scan without changing parser semantics.
  Date: 2026-07-16

- Decision: Validate portable environment names as ASCII letters or underscore followed
  by ASCII letters, digits, or underscores, and reject target keys that overlap by prefix.
  Rationale: shell-portable names make generated bindings predictable, while a scalar at
  `service` and another value at `service.port` cannot coexist in one raw object tree.
  Date: 2026-07-17

- Decision: Extend core sources with composable per-key annotations and render shared
  Kubernetes annotations in the core text explanation.
  Rationale: exact provenance belongs to each candidate, and every adapter must receive
  identical JSON and text behavior without adding format-specific renderers.
  Date: 2026-07-17

- Decision: Keep `CliOverride` construction private, omit values from origin spellings,
  and order shadowed origins from highest to lowest losing precedence.
  Rationale: private construction preserves the redaction invariant, while descending
  shadow order makes repeated command-line overrides explainable from nearest loser to
  oldest fallback.
  Date: 2026-07-17

- Decision: Pin optparse-applicative 0.19.0.0 for the Nix adapter output and use
  `pkgs.haskell.lib.dontCheck` only on that output while nixpkgs' test libraries retain the
  0.18 ABI.
  Rationale: the shipped library must expose the tested 0.19 API, while Cabal can execute
  all 62 tests in one dependency plan without weakening the adapter's version bound.
  Date: 2026-07-17


## Outcomes & Retrospective

Completed on 2026-07-17. `settei-env` now translates explicit or deliberately prefixed
bindings from an injectable snapshot, rejects ambiguous binding sets, and attaches exact
environment and trusted Kubernetes metadata per key. `settei-optparse-applicative` now
provides ordered secret-safe overrides, named options, config paths, mutually exclusive
explanation modes, and intent-grouped reusable parsers. The migration guide records the
audited `envparse`, Rei, and Seihou patterns and shows file below environment below CLI.

The acceptance suite contains 47 core, 7 environment, and 8 command-line tests. It proves
repeated-option ordering, malformed-winner failure, absent variables, binding collisions,
Kubernetes ConfigMap and Secret annotations, grouped help, and adversarial redaction
without reading or mutating the live environment. Cabal build, all 62 tests, Cabal check,
Haddock, Nix formatting, explicit adapter Nix builds, and `nix flake check` pass.

Both adapter Cabal files declare the canonical package-local GHC2024 stanza and every
library and test component imports it. Representative modules and tests use strict
unprefixed records, explicit deriving strategies, `Settei.Prelude`, local
`Data.Generics.Labels ()` imports, lens access, and postpositive qualified imports. ADRs
0001 and 0003 now retain the durable Nix dependency, per-key annotation, safe-origin, text
rendering, and shadow-order decisions needed by later adapters.


## Context and Orientation

This plan has a hard dependency on
`docs/plans/2-implement-hierarchical-resolution-provenance-and-derived-defaults.md`.
The completed core must provide validated `Key` values, `RawValue`, ordered `Source`
resolution, extensible `Origin` annotations, sensitivity-aware reports, and structured
errors. Read the actual API and its ADR before editing; update this plan if final names
differ from the interfaces below.

Existing applications use several styles. `tan-commons-config` and
`mls-service-v2` use `envparse`, including `HASKELL_ENV` values Development, Production,
and Test. Rei combines a YAML file with field-specific environment overrides. Seihou has a
richer precedence and explanation model. Locate all of these with `mori registry search`
and read registered source directly before writing migration documentation; the adapter
must not guess their current APIs.

The refreshed registered `optparse-applicative` source is version 0.19.0.0 and its
`Parser` is Functor, Applicative, and Alternative. The package provides
`execParserPure`, `ParserResult`, and `getParseResult`; `execParserPure` is the correct
boundary for deterministic tests. There is no public `parsePure` function in this
version.

Plan 1 embeds the registered `shinzui/haskell-jitsurei` core baseline. Both new `.cabal`
files repeat the canonical package-local `common common` stanza and import it from every
component; both packages use `Settei.Prelude`. A module using generic-lens labels imports
`Data.Generics.Labels ()` locally and declares `generic-lens` directly in its package
dependencies. Records use strict unprefixed fields and explicit deriving strategies,
reads and updates use lens operators, and qualified imports are postpositive.
For the CLI boundary, the applicable `cli-option-groups` convention requires
`optparse-applicative >= 0.19`: group file paths and overrides under “Configuration” and
explanation modes under “Diagnostics”. The separate hierarchical-config convention's
“no merge between independent concerns” rule does not prohibit Settei's precedence stack,
because these inputs are alternate sources for one declaration rather than unrelated
configuration domains. [ADR 0001](../adr/0001-haskell-project-conventions.md) records the
durable rationale and rejected alternatives for this baseline.


## Plan of Work

### Milestone 1: implement pure environment translation

Create `packages/settei-env/settei-env.cabal` with exposed modules `Settei.Env` and, only
if needed, `Settei.Env.Kubernetes`. Register the package in `cabal.project` and the Nix
project build. Repeat Plan 1's canonical `common common` stanza in this `.cabal` file and
import it from the library and test components. The core transformation accepts a supplied
snapshot rather than reading IO:

```haskell
newtype EnvName = EnvName Text
  deriving stock (Generic, Eq, Ord, Show)

newtype EnvSnapshot = EnvSnapshot (Map EnvName Text)
  deriving stock (Generic, Eq)

data EnvBinding = EnvBinding
  { name :: !EnvName
  , key :: !Key
  , annotations :: !(Map Text Text)
  }
  deriving stock (Generic, Eq)

envSource
  :: Text
  -> [EnvBinding]
  -> EnvSnapshot
  -> Either (NonEmpty EnvError) Source

readEnvSource
  :: Text
  -> [EnvBinding]
  -> IO (Either (NonEmpty EnvError) Source)
```

If the checked-in core's source constructor makes absence naturally non-failing, preserve
that: an unset optional variable does not appear in the source, and the declaration later
decides whether its key is required. Reject duplicate `EnvName` bindings, duplicate target
keys, invalid variable names, and a supplied value that cannot be represented as the
core's text `RawValue`. Do not decode the target type in this package.

Add `binding` for explicit names and `prefixedBindings` as an opt-in helper that converts
key segments to uppercase underscore names beneath a caller-supplied prefix. The helper
must return collisions as construction errors. For example, a caller may deliberately map
`service.http.port` to `MYAPP_SERVICE_HTTP_PORT`; this is never applied globally without
being requested.

Origins record the exact environment name. Sensitivity comes only from the declared
setting in the core, so a binding cannot downgrade a secret setting to public.

### Milestone 2: support deployment annotations without cluster access

Consume the typed `KubernetesRef` and `kubernetesAnnotations` helper owned by core
`Settei.Origin`. It is usable for both environment variables and mounted-file sources;
the checked-in core constructs it with:

```haskell
kubernetesRef
  :: KubernetesObjectKind
  -> Maybe Text
  -> Text
  -> Maybe Text
  -> KubernetesRef

kubernetesAnnotations :: KubernetesRef -> Map Text Text

fromKubernetesObject :: KubernetesRef -> EnvBinding -> EnvBinding
```

The resulting explanation can say that `DATABASE_PASSWORD` was delivered from Secret
`service-database`, key `password`, but its value remains `<redacted>`. Clearly document
that metadata is asserted by the application or generated deployment code and is not
verified against the Kubernetes API. The package must not depend on a Kubernetes client.

### Milestone 3: implement command-line source construction

Create
`packages/settei-optparse-applicative/settei-optparse-applicative.cabal` and expose
`Settei.Optparse`. Depend on `settei` and `optparse-applicative`, not `settei-env`.
Repeat the canonical package-local `common common` stanza and import it from every
component in this package.

Provide an applicative parser for generic overrides using repeated
`--set KEY=VALUE`. Parse the key with the core `parseKey`; keep the value as text for the
setting decoder. Each occurrence becomes a source fragment with its occurrence number and
spelling in the origin, so normal low-to-high core resolution makes the last repeated
override win while preserving shadowed occurrences.

```haskell
data CliOverride = CliOverride
  { key :: !Key
  , value :: !RawValue
  , spelling :: !Text
  }
  deriving stock (Generic)

overrideOptions :: Parser [CliOverride]
cliSources :: Text -> [CliOverride] -> [Source]
```

The production constructor remains private. `cliOverride`, `cliOverrideKey`,
`cliOverrideValue`, and `cliOverrideSpelling` provide safe construction and inspection;
the spelling records `--set KEY` and never repeats `VALUE` into origin metadata.

`overrideOptions` preserves list order. `cliSources` enumerates that list and stores an
occurrence number in each origin; it does not depend on an undocumented absolute argument
index from `optparse-applicative`.

Also provide a small building block for applications that prefer named flags such as
`--port 8080`. It should return an optional source fragment rather than a decoded
application value, and its caller must supply the target `Key` and option metadata. Do not
reach inside `optparse-applicative` internals or invent a dynamic parser from the entire
Settei schema in version one. If multiple independently parsed named flags target the same
key, the application must assemble their precedence explicitly; only repetitions within
one returned list claim command-line occurrence order.

Provide reusable parser types for zero or more config paths and explanation output:

```haskell
data ExplainMode = NoExplain | ExplainText | ExplainJson
  deriving stock (Generic, Eq, Ord, Show)

data SetteiOptions = SetteiOptions
  { configPaths :: ![FilePath]
  , overrides :: ![CliOverride]
  , explainMode :: !ExplainMode
  }
  deriving stock (Generic)

setteiOptions :: Parser SetteiOptions
```

The option names should have sensible defaults such as `--config`, `--set`,
`--explain-config`, and `--explain-config-json`, while modifier-taking lower-level helpers
allow an application to avoid name collisions. This package parses paths but does not open
them. Compose `setteiOptions` from two smaller record parsers wrapped with
`parserOptionGroup "Configuration"` and `parserOptionGroup "Diagnostics"`; group by user
intent and keep the help option in optparse-applicative's default section. Access the
parsed records with `#configPaths`, `#overrides`, and `#explainMode`, not generated record
selectors.

### Milestone 4: integration tests and migration guide

Use `Options.Applicative.execParserPure` and a supplied `EnvSnapshot` for every functional test.
Prove the combined order built-in default, in-memory file-shaped source, environment, then
CLI. Cover duplicate overrides, invalid keys, missing environment values, prefix
collisions, secret redaction, ConfigMap annotations, and Secret annotations.

Add `docs/guides/environment-and-cli.md`. Include a direct translation of a small
`envparse` declaration using `HASKELL_ENV`, database host, database port, and a secret
password. Show a named derived default based on Development/Test/Production, but refer to
the core implementation rather than rebuilding default logic in `settei-env`. Show how an
application deliberately assembles source order and how `--explain-config` is rendered.


## Concrete Steps

Run from `/Users/shinzui/Keikaku/bokuno/settei`. Refresh all dependency and consumer
locations before coding:

```bash
mori show --full
mori registry search optparse-applicative
mori registry search envparse
mori registry search tan-commons-config
mori registry search mls-service-v2
mori registry search rei
mori registry search seihou
mori registry search generic-lens
mori registry show ekmett/lens --full
mori registry show shinzui/haskell-jitsurei --full
mori registry docs shinzui/haskell-jitsurei
```

For each relevant result, use its returned qualified name:

```bash
mori registry show QUALIFIED_PROJECT_NAME --full
mori registry docs QUALIFIED_PROJECT_NAME
```

After registering both packages, run:

```bash
nix fmt
cabal build settei-env settei-optparse-applicative
cabal test all --test-show-details=direct
nix flake check
```

Expected behavior-focused output includes:

```text
Settei.Env
  explicit binding records variable origin: OK
  prefix collisions are rejected: OK
  Secret annotation remains redacted: OK
Settei.Optparse
  final repeated --set wins with shadow trace: OK
  execParserPure rejects an invalid key: OK
  cli overrides environment overrides file: OK
All tests passed
```


## Validation and Acceptance

Given `HASKELL_ENV=Production` and an explicit binding to `runtime.environment`, the
resolved value must be Production and the report must name `HASKELL_ENV`. Given an absent
optional variable, `envSource` must build successfully and core resolution must decide
whether a default or missing-setting error applies.

Given file-shaped port 7000, environment port 8000, and arguments
`--set service.port=9000 --set service.port=9001`, the result must be 9001. The report must
show the last CLI occurrence as winner and the first CLI occurrence, environment, and file
as shadowed candidates in descending relevance. A malformed final CLI value must fail at
that option and must not fall back to 9000 or 8000.

Given a secret environment binding annotated as Kubernetes Secret
`payments-database`, key `password`, the report must contain the object and key names but
not the sentinel secret value. Given the equivalent ConfigMap annotation for a public
host, both the object metadata and public value may appear.

No test may depend on or modify the real process environment. No package in this plan may
open a configuration file, query Kubernetes, or depend on YAML, KDL, or Dhall.


## Idempotence and Recovery

Dependency lookup, formatting, builds, and pure parser tests are repeatable. `readEnvSource`
is the only environment-reading convenience; keep its effect at the application boundary
and implement it by taking one snapshot before calling the pure translator.

Add each package to `cabal.project` once. If Nix multi-package changes fail, keep the root
`settei` output working, validate all packages through Cabal, and repair the Nix project
definition without moving or renaming the core package. Never use the developer's live
environment as a golden fixture.


## Interfaces and Dependencies

Package `settei-env` depends on `settei`, `base`, `containers`, and `text`. It exposes pure
translation plus a thin IO snapshot function. It need not depend on `envparse`; Settei's
core decoders and explicit binding metadata replace that role. Migration examples must be
verified against registered `envparse` and consumer source before publication. Add
`generic-lens` directly when its modules use `#label`; do not rely on the core package's
dependency visibility.

Package `settei-optparse-applicative` depends on `settei`, `base`, `text`, and the inspected
`optparse-applicative` version. Its public API uses official combinators and `Parser`; tests
use `ParserResult` and `execParserPure`. It also declares `generic-lens` when label access is
used. Both packages consume core `Source`, `Origin`, `Key`, `RawValue`, and `Sensitivity`
types and must not duplicate resolution or redaction logic.

The flake pins the inspected optparse-applicative 0.19.0.0 Hackage source because nixpkgs'
GHC 9.12.4 package set still carries 0.18. Cabal owns executable test validation until the
nixpkgs `tasty` graph uses the same ABI; the Nix adapter output therefore builds the
library with checks disabled rather than combining incompatible library instances.


## Revision Note

2026-07-16: Updated both adapters to inherit the shared Haskell conventions, replaced
prefixed illustrative record fields with strict reusable labels, added explicit deriving
strategies and generic-lens dependency guidance, and applied the registered option-group
pattern to the reusable command-line parser.

2026-07-17: Reconciled the plan with the implemented core and refreshed dependency source.
The environment adapter now uses core `KubernetesRef`, per-key source annotations, and
`execParserPure`, the actual optparse-applicative 0.19 pure runner.

2026-07-17: Kept `CliOverride` construction private and clarified that its origin spelling
omits the raw value. This preserves core redaction while still recording the exact key and
occurrence number.

2026-07-17: Completed both adapters and the audited migration guide, recorded the
optparse-applicative 0.19 Nix pin and temporary library-only Nix check policy, and replaced
the provisional retrospective with the 62-test acceptance evidence.
