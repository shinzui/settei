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
  , settei-dhall
  , settei-env
  , settei-kdl
  , settei-optparse-applicative
  , settei-yaml
  , text
```

The [`settei-formats`](formats.md) package provides the `--config FORMAT:PATH` reader and
format-dispatching loader shown explicitly later in this guide. Multi-format applications
can use that package instead of maintaining their own parser and three-way dispatch.

Use fewer adapter packages when the application supports fewer formats.

The code excerpts below use these imports in addition to application modules:

```haskell
import Data.Generics.Labels ()
import Data.List.NonEmpty (NonEmpty)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Options.Applicative qualified as Options
import Settei
import Settei.Dhall qualified as Dhall
import Settei.Env
import Settei.Kdl qualified as Kdl
import Settei.Optparse
import Settei.Prelude ((^.))
import Settei.Yaml qualified as Yaml
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

Represent a parsed input as a format plus path:

```haskell
data ConfigFormat = YamlFormat | KdlFormat | DhallFormat
  deriving stock (Eq, Show)

data ConfigInput = ConfigInput
  { format :: !ConfigFormat,
    path :: !FilePath
  }
  deriving stock (Eq, Show)
```

Use an `Options.eitherReader` to require `FORMAT:PATH`, reject an empty path, and accept
only documented format names. Parsing a path must not open it; IO belongs after command-line
validation succeeds.

For a stable user-facing option such as `--port`, use `namedOption`. Use generic `--set`
for advanced overrides and automation. Both produce command-line `Source` values whose
labels omit the raw value.

## Load each file explicitly

Dispatch on the parsed format:

```haskell
loadConfigInput :: ConfigInput -> IO (Either Text Source)
loadConfigInput input =
  let label = Text.pack (input ^. #path)
   in case input ^. #format of
        YamlFormat ->
          fmap (either (Left . renderYamlErrors) Right)
            (Yaml.readYamlSource (Yaml.yamlSourceOptions label) (input ^. #path))
        KdlFormat ->
          fmap (either (Left . renderKdlErrors) Right)
            (Kdl.readKdlSource (Kdl.kdlSourceOptions label) (input ^. #path))
        DhallFormat ->
          fmap (either (Left . renderDhallErrors) Right)
            ( Dhall.loadDhallSource
                (Dhall.dhallSourceOptions label Dhall.NoImports)
                (Dhall.DhallFile (input ^. #path))
            )
```

The `render*Errors` helpers should use the structured fields shown in each adapter guide.
Do not include raw file content in the message.

The example uses `NoImports` for command-line Dhall files. If the application needs local
imports, add a separate trusted root option and use `LocalImportsWithin root`. Do not take
an unrestricted import policy from the Dhall file itself.

Traverse inputs in command-line occurrence order:

```haskell
loadedFiles <- traverse loadConfigInput configInputs
```

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

Useful diagnostic modes are:

| Option | Work performed |
| --- | --- |
| `--describe-config` | Render `describe appConfig` without reading files or environment values. |
| `--check-config` | Load and resolve configuration, print a short success message, then exit. |
| `--explain-config` | Load and resolve, then render the redacted text report. |
| `--explain-config-json` | Load and resolve, then render the versioned JSON report. |

Make diagnostic modes mutually exclusive in the parser. A schema-only mode should branch
before file and environment loading:

```haskell
case diagnosticMode of
  DescribeConfiguration ->
    TextIO.putStr (renderSchemaText (describe appConfig))
  _ ->
    loadResolveAndRun
```

After `result ^. #answer` yields a configuration:

```haskell
renderSuccess mode config result =
  case mode of
    CheckConfiguration -> "configuration valid\n"
    ExplainConfigurationText -> renderResolutionText (result ^. #report)
    ExplainConfigurationJson -> renderResolutionJson (result ^. #report) <> "\n"
    RunApplication -> runApplication config
```

Do not print the typed result after an explanation. The typed record contains real secret
values, while report renderers receive only redacted representations. Normal application
output should use an allowlist of known-public fields.

Also render `result ^. #warnings` or reject unknown keys with `RejectUnknownKeys`. A
successful `--check-config` that silently drops warnings is usually less useful to users.

## Distinguish exit behavior

Choose stable exit codes and document them. The reference application uses:

| Exit code | Meaning |
| ---: | --- |
| `0` | Normal run or successful diagnostic. |
| `2` | Command-line usage error. |
| `3` | File IO, format, or adapter error. |
| `4` | Missing, malformed, structurally conflicting, or strictly unknown configuration. |

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
