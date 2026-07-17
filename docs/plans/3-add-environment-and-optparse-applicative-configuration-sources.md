---
id: 3
slug: add-environment-and-optparse-applicative-configuration-sources
title: "Add environment and optparse-applicative configuration sources"
kind: exec-plan
created_at: 2026-07-16T23:50:04Z
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
value. Tests can inject an environment snapshot and use `parsePure`, so they do not mutate
the developer's process. Applications can annotate an environment variable as originating
from a Kubernetes ConfigMap or Secret without Settei contacting a cluster.

The plan produces two packages: `settei-env` and `settei-optparse-applicative`. It also
proves ordinary precedence such as file below environment below CLI. It does not discover
configuration files, parse YAML/KDL/Dhall, or prescribe every application's command-line
interface.


## Progress

- [ ] Add and register the `settei-env` package.
- [ ] Implement explicit bindings, prefix helpers, injected snapshots, and origin metadata.
- [ ] Add and register the `settei-optparse-applicative` package.
- [ ] Implement generic overrides, direct option bindings, config-path and explain options.
- [ ] Test repeated options, precedence, redaction, and Kubernetes annotations.
- [ ] Document migration from small `envparse` configurations.


## Surprises & Discoveries

(None yet.)


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


## Outcomes & Retrospective

To be filled during and after implementation. Record any naming or origin convention that
other adapters need in the relevant core ADR before completing this plan. Confirm that
both packages declare and import the canonical package-local GHC2024 stanza and follow the
strict-record, explicit-deriving, custom-prelude, lens, and import conventions before
marking the plan complete.


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

At planning time, registered `optparse-applicative` source is version 0.19.0.0 and its
`Parser` is Functor, Applicative, and Alternative. The package provides `parsePure`, which
is the correct boundary for deterministic tests. Refresh that source lookup before
implementation.

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

Consume the typed Kubernetes reference and annotation helper owned by core
`Settei.Origin`. It must be usable for both environment variables and mounted-file
sources; its semantic shape is:

```haskell
data KubernetesObject
  = ConfigMapRef { namespace :: !(Maybe Text), name :: !Text, key :: !Text }
  | SecretRef { namespace :: !(Maybe Text), name :: !Text, key :: !Text }
  deriving stock (Generic, Eq, Show)

kubernetesObjectAnnotations :: KubernetesObject -> Map Text Text

fromKubernetesObject :: KubernetesObject -> EnvBinding -> EnvBinding
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

Use `Options.Applicative.parsePure` and a supplied `EnvSnapshot` for every functional test.
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
  parsePure rejects an invalid key: OK
Settei.Integration.EnvironmentCli
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
use `ParserResult` and `parsePure`. It also declares `generic-lens` when label access is
used. Both packages consume core `Source`, `Origin`, `Key`, `RawValue`, and `Sensitivity`
types and must not duplicate resolution or redaction logic.


## Revision Note

2026-07-16: Updated both adapters to inherit the shared Haskell conventions, replaced
prefixed illustrative record fields with strict reusable labels, added explicit deriving
strategies and generic-lens dependency guidance, and applied the registered option-group
pattern to the reusable command-line parser.
