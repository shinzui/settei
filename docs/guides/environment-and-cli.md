# Environment and command-line configuration

Use `settei-env` to map selected environment variables to Settei keys and
`settei-optparse-applicative` to add ordered command-line overrides and explanation flags.
Both adapters produce ordinary `Source` values, so application types and decoders remain
in the core declaration.

## Add the packages

```cabal
build-depends:
  , optparse-applicative
  , settei
  , settei-env
  , settei-optparse-applicative
  , text
```

The main modules are:

```haskell
import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Data.Text qualified as Text
import Options.Applicative qualified as Options
import Settei
import Settei.Env
import Settei.Optparse
```

## Declare settings independently of input names

Settei keys are application-facing names. Environment variables and flags are bindings to
those keys, not separate declarations:

```haskell
data Environment = Development | Production
  deriving stock (Eq, Ord, Show)

data AppConfig = AppConfig
  { environment :: !Environment,
    databaseHost :: !Text,
    databasePort :: !Int,
    databasePassword :: !Text
  }
  deriving stock (Eq)

appConfig :: Config AppConfig
appConfig =
  AppConfig
    <$> required environmentSetting
    <*> required databaseHostSetting
    <*> withDefault
      databasePortSetting
      (constantDefault (RuleName "postgres-port") "Use PostgreSQL's standard port" 5432)
    <*> required databasePasswordSetting

environmentSetting :: Setting Environment
environmentSetting =
  publicSettingWithRenderer
    (validKey "runtime.environment")
    "Runtime environment"
    (enumDecoder [("development", Development), ("production", Production)])
    renderEnvironment

databaseHostSetting :: Setting Text
databaseHostSetting =
  publicSetting (validKey "database.host") "Database host" textDecoder

databasePortSetting :: Setting Int
databasePortSetting =
  publicSettingWithRenderer
    (validKey "database.port")
    "Database port"
    boundedIntegralDecoder
    (Text.pack . show)

databasePasswordSetting :: Setting Text
databasePasswordSetting =
  secretSetting (validKey "database.password") "Database password" textDecoder

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

renderEnvironment :: Environment -> Text
renderEnvironment Development = "development"
renderEnvironment Production = "production"
```

Environment and command-line values arrive as `RawText`. The built-in
`boundedIntegralDecoder` and `boolDecoder` accept their textual spellings, as do
`textDecoder` and `enumDecoder`. A custom decoder for a key used by these adapters should
also define how `RawText` is handled.

## Bind environment variables explicitly

An `EnvBinding` maps one portable environment name to one structural key. Build the
complete list once with `bindings`; the opaque `Bindings` result proves that the list is
valid before any source is assembled:

```haskell
environmentBindings :: Bindings
environmentBindings =
  either (error . Text.unpack . renderEnvErrorsText) id
    ( bindings
        [ binding (EnvName "HASKELL_ENV") (validKey "runtime.environment"),
          binding (EnvName "DATABASE_HOST") (validKey "database.host"),
          binding (EnvName "DATABASE_PORT") (validKey "database.port"),
          fromKubernetesObject
            (kubernetesRef SecretObject (Just "production") "service-database" (Just "password"))
            (binding (EnvName "DATABASE_PASSWORD") (validKey "database.password"))
        ]
    )
```

Only listed variables are read. An absent variable creates no candidate, so `required`,
`optional`, or `withDefault` controls what absence means. Empty strings are present values
and are passed to the setting decoder.

`bindings` rejects invalid or repeated variable names, repeated target keys, and
overlapping targets such as `database` together with `database.host`. The resulting
`EnvError` values contain names and keys, never environment values. The top-level
definition validates the static list once; force it in the application test suite so a
bad edit fails in tests before it can fail at startup:

```haskell
testCase "environment bindings are valid" $
  length (bindingsList environmentBindings) @?= 4
```

`fromKubernetesObject` adds origin metadata for explanations. It does not contact a
cluster and does not make a value secret. The `secretSetting` declaration above is what
guarantees redaction.

At application startup, snapshot the environment once:

```haskell
loadEnvironment :: IO Source
loadEnvironment =
  readEnvironmentSource environmentBindings
```

`readEnvironmentSource` reads the process environment once and uses the stable,
display-safe source label `"environment"`. Use `readEnvSource` only when the application
needs a different label; both functions are total because `Bindings` is already valid.

### Test without modifying the process environment

Use an `EnvSnapshot` in unit tests:

```haskell
testEnvironment :: Source
testEnvironment =
  envSource
    "test environment"
    environmentBindings
    ( envSnapshot
        [ ("HASKELL_ENV", "development"),
          ("DATABASE_HOST", "127.0.0.1"),
          ("DATABASE_PASSWORD", "test-only-secret")
        ]
    )
```

`renderEnvErrorText` renders one sentence and `renderEnvErrorsText` renders a non-empty
batch with one problem per line and a trailing newline. Both functions can mention only
variable names and structural keys because `EnvError` never retains environment values.
Use the plural renderer when the one-time `bindings` construction fails, as the
`environmentBindings` definition above does.

### Generate conventional bindings

For a large flat set of keys, `prefixedBindings` derives names by uppercasing segments and
joining them with underscores:

```haskell
generatedBindings :: Either (NonEmpty EnvError) Bindings
generatedBindings =
  prefixedBindings
    "MYAPP"
    [validKey "service.host", validKey "service.port"]
```

This produces `MYAPP_SERVICE_HOST` and `MYAPP_SERVICE_PORT`. A successful result is
already validated and can go directly to `envSource`, `environmentSource`, or their
effectful siblings. Normalization collisions are reported instead of silently selecting
one binding.

## Parse reusable command-line options

`setteiOptions` provides:

| Option | Parsed value |
| --- | --- |
| repeated `--config PATH` | `[FilePath]`; the application opens each path |
| repeated `--set KEY=VALUE` | ordered `[CliOverride]` values |
| `--explain-config` | `ExplainText` |
| `--explain-config-json` | `ExplainJson` |

Add it to an ordinary optparse-applicative parser:

```haskell
parserInfo :: Options.ParserInfo SetteiOptions
parserInfo =
  Options.info
    (setteiOptions Options.<**> Options.helper)
    ( Options.fullDesc
        <> Options.progDesc "Run the service with layered configuration"
    )
```

The parser validates the key portion of `--set KEY=VALUE`, but it intentionally leaves the
value as text. The winning setting decoder performs type validation during `resolve`.
This means `--set service.port=not-a-number` is a resolution error tied to that option.

`--config` returns paths only. Choose one documented file policy in the application—for
example, a fixed YAML format, an explicit `FORMAT:PATH` reader, or separate
`--yaml-config` and `--kdl-config` options—and load paths with the corresponding adapter.

### Use named flags when they improve the interface

`namedOption` turns a normal text option into an optional one-key `Source`:

```haskell
portOption :: Options.Parser (Maybe Source)
portOption =
  namedOption
    "--port"
    (validKey "service.port")
    ( Options.long "port"
        <> Options.metavar "PORT"
        <> Options.help "Override the service port"
    )
```

The display spelling must name the option without including its value. Place the returned
source in the precedence list at the exact level you want. If a parser has both named
options and generic `--set`, the parser's assembly function—not raw argument position—must
define which group wins.

For custom help text or flag names, use `configPathOptionsWith`, `overrideOptionsWith`, and
`explainModeOptionsWith`.

## Resolve files, environment, and CLI overrides

After the parser has run and file sources have been loaded, assemble one visibly ordered
list. This example uses generic-lens field access; record pattern matching works as well.

```haskell
import Data.Generics.Labels ()
import Data.Text qualified as Text
import Settei.Prelude ((^.))

resolveApplication
  :: [Source]
  -> Source
  -> SetteiOptions
  -> ResolveResult AppConfig
resolveApplication fileSources environmentSource options =
  resolve
    defaultResolveOptions
    ( fileSources
        <> [environmentSource]
        <> cliSources "arguments" (options ^. #overrides)
    )
    appConfig
```

Sources are low to high:

```text
first file < later file < environment < first --set < later --set
```

Repeated overrides remain separate sources. If the same key occurs twice, the final
occurrence wins and the earlier occurrence remains visible in the shadow trace. A
malformed final occurrence is an error and never falls back to an earlier valid value.

## Render diagnostics

Select a report renderer from the total result:

```haskell
renderRequestedExplanation :: SetteiOptions -> ResolveResult a -> Maybe Text
renderRequestedExplanation options result =
  case options ^. #explainMode of
    NoExplain -> Nothing
    ExplainText -> Just (renderResolutionText (result ^. #report))
    ExplainJson -> Just (renderResolutionJson (result ^. #report))
```

Render errors from `result ^. #answer` with `renderErrorsText` or `renderErrorsJson`, and
warnings with `renderWarningsText` or `renderWarningsJson`. The report and warnings remain
available when the answer is an error. Send human-readable diagnostics to stderr; reserve
stdout for requested machine-readable JSON on success or the application's normal output.

The reports may include variable names, option names, keys, and trusted Kubernetes
metadata. Secret setting values remain `<redacted>`. Do not append raw environment values
or full command-line arguments to adapter or resolution errors.

## Production checklist

- Read the environment once during startup and inject snapshots in tests.
- Bind only supported variables; do not scan arbitrary prefixes at runtime.
- Document the source order and test an override at every layer.
- Treat an empty environment value as explicit input, not as absence.
- Make custom decoders accept the textual forms used by environment and CLI sources.
- Mark sensitive settings with `secretSetting` before resolving any input.
- Use stable, value-free labels for sources and option spellings.
- Keep file loading and its IO errors separate from typed resolution failures.

See [Building a CLI application](cli-application.md) for a complete executable structure
and [Building a Kubernetes service](kubernetes-service.md) for Secret-backed environment
bindings.
