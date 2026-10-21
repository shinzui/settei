---
type: Guide
title: Building a CLI application
description: Build a CLI application that layers files, environment variables, overrides, and safe diagnostics with Settei.
docId: DOC-2
tags: [settei, cli, configuration]
generated:
  by: human:nadeem
  at: 2026-10-21T16:36:34Z
---

# Building a CLI application

This guide assembles a command-line application with built-in values, explicit config
files, environment variables, command-line overrides, and safe diagnostics. The complete
working implementation is the [`settei-example-cli`](../../examples/settei-cli/) package.

Start with [Getting started](getting-started.md) if you have not yet defined the
application's `Setting` and `Config` values.

## Add dependencies and split the modules

A CLI that accepts all supported file formats needs:

```cabal
build-depends:
  , containers
  , generic-lens
  , optparse-applicative
  , settei
  , settei-env
  , settei-formats
  , settei-optparse-applicative
  , text
```

The [`settei-formats`](formats.md) package provides the `--config FORMAT:PATH` reader and
format-dispatching loader shown explicitly later in this guide. Multi-format applications
can use that package instead of maintaining their own parser and three-way dispatch.

Use fewer adapter packages when the application supports fewer formats.

The code excerpts below use these imports in addition to application modules:

```haskell
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Options.Applicative qualified as Options
import Settei
import Settei.Env
import Settei.Formats
import Settei.Formats.Optparse
import Settei.Optparse
import Settei.Prelude ((^.))
```

Keep these responsibilities separate:

```text
App.Config    typed records, settings, Config declaration, environment bindings
App.Options   optparse-applicative parser and explicit file-format policy
App.Run       load sources, resolve, render diagnostics, run the application action
Main          read arguments/environment, write stdout/stderr, select exit code
```

Putting the declaration and runner in library modules makes them directly testable. `Main`
should remain a small IO wrapper.

## Choose a visible source order

The reference CLI uses this low-to-high order:

```text
built-in values
< each --config file in occurrence order
< explicitly bound environment variables
< each --set override in occurrence order
```

Put the assembly in one function so reviewers and tests can see the complete order:

```haskell
resolveCli
  :: [Source]
  -> Source
  -> [CliOverride]
  -> ResolveResult AppConfig
resolveCli fileSources environmentSource overrides =
  resolve
    defaultResolveOptions
    ( [builtInSource]
        <> fileSources
        <> [environmentSource]
        <> cliSources "arguments" overrides
    )
    appConfig
```

Later sources win one leaf at a time. Repeated config files and repeated `--set` options
retain their occurrence order, and shadowed origins remain available in the report.

### Built-in source or declared default?

Use a low-precedence built-in `Source` when the value should behave like explicit input
and appear as a shadowable origin:

```haskell
builtInSource :: Source
builtInSource =
  source
    "application built-ins"
    BuiltInSource
    ( RawObject
        ( Map.fromList
            [ ("runtime", RawObject (Map.singleton "environment" (RawText "development"))),
              ("output", RawObject (Map.singleton "format" (RawText "text")))
            ]
        )
    )
```

Use `constantDefault`, `derivedDefault`, or `caseDefault` when the fallback belongs to the
declaration, should run only when every source is absent, or should appear as a named
derivation.

## Parse configuration options

For a single file format, `setteiOptions` supplies repeated `--config PATH`, repeated
`--set KEY=VALUE`, and mutually exclusive explanation flags:

```haskell
optionsInfo :: Options.ParserInfo SetteiOptions
optionsInfo =
  Options.info
    (setteiOptions Options.<**> Options.helper)
    (Options.fullDesc <> Options.progDesc "Run the application")
```

If several formats are accepted, require an explicit tag instead of guessing from file
contents. The reference application parses:

```text
--config yaml:path/to/application.yaml
--config kdl:path/to/local.kdl
--config dhall:path/to/application.dhall
```

Use `Settei.Formats.ConfigInput` and `configInputOptions`; they require `FORMAT:PATH`,
reject empty paths and unsupported tags, and never open a file while parsing.

For a stable user-facing option such as `--port`, use `namedOption`. Use generic `--set`
for advanced overrides and automation. Both produce command-line `Source` values whose
labels omit the raw value.

## Load each file explicitly

The shared loader dispatches on the tag and retains structured adapter errors:

```haskell
loadedFiles <- traverse (loadConfigInput defaultLoadOptions) configInputs
```

Render failures with `renderFormatLoadErrorText` for each `FormatLoadError`; it delegates
to the relevant adapter renderer and never requires `Show` output.

The example uses `NoImports` for command-line Dhall files. If the application needs local
imports, add a separate trusted root option and use `LocalImportsWithin root`. Do not take
an unrestricted import policy from the Dhall file itself.

If any file fails, report a source-loading failure and do not resolve a partial list.

## Load environment variables

Map every supported variable explicitly:

```haskell
environmentBindings :: Bindings
environmentBindings =
  either (error . Text.unpack . renderEnvErrorsText) id
    ( bindings
        [ binding (EnvName "HASKELL_ENV") (validKey "runtime.environment"),
          binding (EnvName "SERVICE_ENDPOINT") (validKey "service.endpoint"),
          binding (EnvName "SERVICE_TIMEOUT") (validKey "service.timeout"),
          binding (EnvName "OUTPUT_FORMAT") (validKey "output.format"),
          fromKubernetesObject
            (kubernetesRef SecretObject Nothing "my-application" (Just "token"))
            (binding (EnvName "SERVICE_TOKEN") (validKey "credentials.token"))
        ]
    )

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
```

Call `readEnvironmentSource` once after argument parsing. For a runner that accepts an
injected snapshot, call the pure `environmentSource` instead and let `Main` create the
snapshot. Use the labeled `readEnvSource` and `envSource` variants only when a different
source label is useful. This keeps end-to-end tests independent of the developer's
environment.

## Add diagnostics that match user intent

For applications with invariants, check mode consumes the validated result through
`validatedDiagnostic`.

Useful diagnostic modes are:

| Option | Work performed |
| --- | --- |
| `--supplied-env NAME` (repeatable, reference CLI) | Compare the named variables with the application's bindings and allowances before loading files; exit 3 on an unsupported or duplicated name. |
| `--describe-config` | Render `describe appConfig` without reading files or environment values. |
| `--describe-config-json` | Render the source-free schema as JSON. |
| `--deployment-contract` | Join bindings, safe defaults, and profile requirements without loading runtime inputs. |
| `--deployment-contract-json` | Render the source-free versioned `settei.contract` document. |
| `settei-preflight --request PATH` | [Run check mode on proposed deployment inputs](deployment-preflight.md) with explicit coverage and secret channels. |
| `--check-config` | Load and resolve configuration, print a short success message, then exit. |
| `--explain-config` | Load and resolve, then render the redacted text report. |
| `--explain-config-json` | Load and resolve, then render the versioned JSON report. |

Make diagnostic modes mutually exclusive in the parser. A schema-only mode should branch
before file and environment loading:

```haskell
case schemaDiagnostic diagnosticMode (describe appConfig) of
  Just output -> TextIO.putStr output
  Nothing -> loadResolveAndRun
```

After `result ^. #answer` yields a configuration:

```haskell
renderSuccess mode config result =
  maybe (runApplication config) id (resolutionDiagnostic mode result)
```

Do not print the typed result after an explanation. The typed record contains real secret
values, while report renderers receive only redacted representations. Normal application
output should use an allowlist of known-public fields.

Also render `result ^. #warnings` or reject unknown keys with `RejectUnknownKeys`. A
successful `--check-config` that silently drops warnings is usually less useful to users.

## Validate cross-setting invariants after resolution

The next shared 0.3.0.0 release adds `Settei.Validate`. Declare pure rules next to the
configuration. Each rule has a stable identifier, declared keys, a fixed expectation,
and a function over the typed value. For a declaration with pool, concurrency, account,
and credential fields:

```haskell
poolCapacity :: Validator AppConfig
poolCapacity =
  check (InvariantRule "pool-capacity")
    [validKey "workers.jobPoolSize", validKey "workers.concurrency"]
    "pool must cover concurrency"
    (\config -> jobPool config >= concurrency config)

providerAccounts :: Validator AppConfig
providerAccounts =
  invariant (InvariantRule "provider-account")
    [validKey "email.accounts", validKey "email.credentials"]
    "every account must have a credential"
    (\config ->
      [ violationWithDetail ("account " <> publicAccountName account)
      | account <- accounts config
      , not (hasCredential config account)
      ])

workerValidators, serverValidators :: Validators AppConfig
workerValidators = checked [poolCapacity, providerAccounts]
serverValidators = checked [providerAccounts]

checked :: [Validator AppConfig] -> Validators AppConfig
checked rules =
  either (error . Text.unpack . renderValidatorErrorsText) id
    (validators appConfig rules)
```

Here `jobPool`, `concurrency`, `accounts`, `publicAccountName`, and `hasCredential` are
application functions; account names must be public labels, never tokens. Force the
module-level collections in tests. `validators` checks all identifiers, keys, and
prerequisites without loading inputs. Use each collection with the same declaration
used for resolution. Conditional keys are accepted, so predicates must handle optional
values. An empty collection is valid.

Rules run in declaration order and independent failures accumulate. To run a rule only
when earlier rules passed, attach `requires [InvariantRule "earlier-rule"]`. Repeated
calls append distinct prerequisites in first-occurrence order. A failed or skipped
prerequisite skips the dependent function. Base resolution failure runs no validators
and marks every outcome `not run`. Functions must be total and return finite lists.

> **Author contract:** All metadata must be safe to publish, including rule identifiers,
> keys, expectations, and details. `violation` has no detail; `violationWithDetail` retains
> author text verbatim for public labels. Never embed secret setting values or log the
> typed configuration. Settei cannot sanitise arbitrary text. Keep expectations and details
> single-line for line-oriented output.

After static schema and contract dispatch and source loading, replace the earlier
`resolutionDiagnostic` dispatch with:

```haskell
let resolved = resolve defaultResolveOptions sources appConfig
    validated = validate workerValidators resolved
case validatedDiagnostic mode validated of
  DiagnosticFailure output -> do
    TextIO.hPutStr stderr output
    exitWith (ExitFailure 4)
  DiagnosticOutput output -> do
    TextIO.putStr output
    TextIO.hPutStr stderr (renderWarningsText (validated ^. #warnings))
  DiagnosticContinue config -> do
    TextIO.hPutStr stderr (renderWarningsText (validated ^. #warnings))
    runApplication config
```

Import `Data.Text.IO qualified as TextIO`, `System.IO (stderr)`, and
`System.Exit (ExitCode(..), exitWith)` for this dispatch. In a multi-role program select
the appropriate collection before `validate`; share each domain rule once across role
lists. The [deployment example](../../examples/settei-deployment/src/Settei/Example/Deployment.hs)
migrates its original server and worker checks this way, including overflow-safe timeout
arithmetic. Successful typed values are preserved. The helper checks the validated
answer before emitting `configuration valid`; normal startup receives that same value.
Source-loading errors still exit 3 before validation.

Build the worker, locate it with `cabal list-bin` inside `nix develop`, and run the
production fixture with `WORKER_VISIBILITY_TIMEOUT_SECONDS=1` and `--explain-config`.
The application writes the following to stderr and exits 4 (the full report is abbreviated):

```text
workers.visibilityTimeoutSeconds, workers.concurrency: invariant worker-visibility-covers-concurrency failed: workers.visibilityTimeoutSeconds must be at least twice workers.concurrency
...
workers.visibilityTimeoutSeconds = "1"
  from environment variable WORKER_VISIBILITY_TIMEOUT_SECONDS
...
invariant worker-visibility-covers-concurrency [failed (1 violation)]: workers.visibilityTimeoutSeconds, workers.concurrency
  expects workers.visibilityTimeoutSeconds must be at least twice workers.concurrency
invariant production-webhook-secret [passed]: server.webhookSecret, runtime.environment
  expects the development webhook secret must never reach production
```

`--explain-config-json` rejects the same input with exactly two stderr lines, one
`settei.errors` document and one `settei.resolution` document. The latter contains the
winning origins and an ordered `invariants` array. The first document is:

```json
{"schemaVersion":1,"type":"settei.errors","errors":[{"kind":"invariant","rule":"worker-visibility-covers-concurrency","keys":["workers.visibilityTimeoutSeconds","workers.concurrency"],"expectation":"workers.visibilityTimeoutSeconds must be at least twice workers.concurrency","detail":null}]}
```

The resolution document includes this outcome (excerpt):

```json
{"rule":"worker-visibility-covers-concurrency","keys":["workers.visibilityTimeoutSeconds","workers.concurrency"],"expectation":"workers.visibilityTimeoutSeconds must be at least twice workers.concurrency","prerequisites":[],"status":"failed","violations":1,"blockedBy":[]}
```

Check mode prints only the error line, and startup also rejects before acquiring
resources. Successful JSON explain emits one resolution document on stdout. With this
helper, missing and decode failures also emit two JSON documents in JSON explain mode,
with outcomes marked `not-run`; source-load failures retain their adapter text path.
Bare `renderResolutionJson` stays byte-identical; `renderValidatedResolutionJson` adds
optional `invariants` to the existing version-1 representation. `ConfigError` gains a
constructor, so update exhaustive matches for 0.3.0.0.

## Distinguish exit behavior

Choose stable exit codes and document them. The reference application uses:

| Exit code | Meaning |
| ---: | --- |
| `0` | Normal run or successful diagnostic. |
| `2` | Command-line usage error. |
| `3` | File IO, format, or adapter error. |
| `4` | Missing, malformed, structurally conflicting, or strictly unknown configuration, or a failed invariant. |

Unsupported or duplicated explicitly supplied environment names also use exit code `3`.

Set the usage code with `Options.failureCode`. Send usage and human-readable failures to
stderr. Requested JSON reports belong on stdout so scripts can consume them without
log-prefix contamination.

The report and warnings remain available when `result ^. #answer` contains errors. In an
explain mode, render the errors first and append the requested redacted text or JSON report
to stderr; keep the resolution exit code at `4` and stdout empty. Non-explain failures
should continue to print only their errors. This makes an in-pod
`--explain-config` run useful even when the pod cannot finish startup.

## Test the executable workflow

Parse arguments without spawning a process:

```haskell
parseOptions :: [String] -> Maybe CliOptions
parseOptions arguments =
  Options.getParseResult
    ( Options.execParserPure
        Options.defaultPrefs
        cliParserInfo
        arguments
    )
```

Pass `envSnapshot` to the runner and capture its exit code, stdout, and stderr. Cover:

- `--describe-config` with a nonexistent file path, proving it performs no source IO;
- files in occurrence order and environment over file;
- repeated `--set` values, proving the final occurrence wins;
- an invalid winning override, proving it does not fall back;
- separate usage, source-loading, and resolution exit codes;
- text and JSON explanations;
- a failing explain run that prints the provenance report to stderr;
- unknown-key warnings or strict failures; and
- a secret sentinel absent from stdout, stderr, errors, warnings, and reports.

The full composition is in
[`Settei.Example.Cli`](../../examples/settei-cli/src/Settei/Example/Cli.hs), with
[end-to-end tests](../../examples/settei-cli/test/Settei/Example/CliTest.hs).


### Deployment contract

For deployment authoring, dispatch `contractDiagnostic` after `schemaDiagnostic` and
before source loading or executing an environment-reader action. Build its contract
from `appConfig`, `inputBindings environmentBindings`, explicit built-in default
sources, and an optional deployment profile. The [deployment guide](deployment-contract.md)
shows the complete discovery-to-check workflow, and the reference CLI's
`runCliWithEnvironment` demonstrates the static dispatch boundary used by `main`.
