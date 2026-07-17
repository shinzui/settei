# Environment and command-line configuration

`settei-env` and `settei-optparse-applicative` turn environment variables and command-line
options into the same ordered `Source` values used by Settei core. The adapters do not
decode application types or choose precedence. A `Setting` owns decoding and sensitivity,
and the application supplies sources from lowest to highest precedence.

This guide translates a small `envparse` configuration into Settei, adds a named derived
default, and then layers file-shaped sources below environment variables and command-line
overrides. All examples use an injected environment snapshot. The only function that reads
the real process environment is `readEnvSource`, which belongs at the executable boundary.


## What changes from envparse

Registered source inspection found no standalone Mori project for `envparse`, so the
comparison below uses its checked-in consumers. The registered `tan/tan-commons` source
defines `HASKELL_ENV` with `Env.var`, a custom reader, and `Env.parse`. Its PostgreSQL
module uses `Env.str`, `Env.auto`, and `Env.def`. The registered
`tan/mls-service-v2` source composes those parsers applicatively with service-specific
variables.

With `envparse`, the parser both names a variable and decodes it. With Settei, the work is
split deliberately: `EnvBinding` maps a variable to a structural `Key`, `envSource` stores
present values as `RawText`, and the core `Setting` decoder interprets the winning value.
This separation is what allows a YAML value, an environment variable, and `--set` to obey
one precedence and provenance model.

A typical envparse declaration looks like this:

```haskell
environmentParser :: Env.Parser Env.Error Environment
environmentParser =
  Env.var environmentReader "HASKELL_ENV" (Env.help "Runtime environment")

databasePortParser :: Env.Parser Env.Error Int
databasePortParser =
  Env.var Env.auto "DATABASE_PORT" (Env.help "Database port" <> Env.def 5432)
```

The Settei declaration names the same inputs once, independently of their sources:

```haskell
import Data.Bifunctor (first)
import Data.Generics.Labels ()
import Data.Text qualified as Text
import Settei
import Settei.Env
import Settei.Optparse
import Settei.Prelude

data Environment = Development | Production | Test
  deriving stock (Generic, Eq, Ord, Show)

data AppConfig = AppConfig
  { environment :: !Environment,
    databaseHost :: !Text,
    databasePort :: !Int,
    databasePassword :: !Text,
    servicePort :: !Int
  }
  deriving stock (Generic, Eq)

environmentSetting :: Setting Environment
environmentSetting =
  publicSettingWithRenderer
    environmentKey
    "Runtime environment"
    ( enumDecoder
        [ ("development", Development),
          ("production", Production),
          ("test", Test)
        ]
    )
    renderEnvironment

databaseHostSetting :: Setting Text
databaseHostSetting =
  publicSetting databaseHostKey "Database host" textDecoder

databasePortSetting :: Setting Int
databasePortSetting =
  publicSetting databasePortKey "Database port" boundedIntegralDecoder

databasePasswordSetting :: Setting Text
databasePasswordSetting =
  secretSetting databasePasswordKey "Database password" textDecoder

servicePortSetting :: Setting Int
servicePortSetting =
  publicSettingWithRenderer servicePortKey "Service port" boundedIntegralDecoder (Text.pack . show)

servicePortConfig :: Config Int
servicePortConfig =
  withDefault
    servicePortSetting
    ( caseDefault
        (RuleName "service-port-by-environment")
        "Choose the conventional port for the runtime environment"
        (required environmentSetting)
        ( (Development, 8080)
            :| [ (Test, 18080),
                  (Production, 443)
                ]
        )
        Nothing
    )

appConfig :: Config AppConfig
appConfig =
  AppConfig
    <$> required environmentSetting
    <*> required databaseHostSetting
    <*> withDefault
      databasePortSetting
      (constantDefault (RuleName "default-database-port") "Use PostgreSQL's conventional port" 5432)
    <*> required databasePasswordSetting
    <*> servicePortConfig

renderEnvironment :: Environment -> Text
renderEnvironment Development = "development"
renderEnvironment Production = "production"
renderEnvironment Test = "test"

environmentKey, databaseHostKey, databasePortKey, databasePasswordKey, servicePortKey :: Key
environmentKey = validKey "runtime.environment"
databaseHostKey = validKey "database.host"
databasePortKey = validKey "database.port"
databasePasswordKey = validKey "database.password"
servicePortKey = validKey "service.port"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
```

The port rules are named configuration syntax, not hidden post-processing. If no source
supplies `database.port`, the report names `default-database-port`. If no source supplies
`service.port`, the report retains the resolved `runtime.environment` dependency and names
`service-port-by-environment`. An explicit port skips its default dependency.


## Bind environment variables explicitly

Bindings are ordinary data and can be tested without changing the process environment:

```haskell
environmentBindings :: [EnvBinding]
environmentBindings =
  [ binding (EnvName "HASKELL_ENV") environmentKey,
    binding (EnvName "DATABASE_HOST") databaseHostKey,
    binding (EnvName "DATABASE_PORT") databasePortKey,
    fromKubernetesObject
      (kubernetesRef SecretObject (Just "production") "service-database" (Just "password"))
      (binding (EnvName "DATABASE_PASSWORD") databasePasswordKey),
    binding (EnvName "SERVICE_PORT") servicePortKey
  ]

testSnapshot :: EnvSnapshot
testSnapshot =
  envSnapshot
    [ ("HASKELL_ENV", "production"),
      ("DATABASE_HOST", "postgres.internal"),
      ("DATABASE_PASSWORD", "test-only-sentinel")
    ]
```

`envSource` rejects invalid or duplicate variable names, duplicate or structurally
overlapping target keys, and collisions introduced by `prefixedBindings`. An absent
variable is simply absent from the source. The core declaration then decides whether the
setting is required, optional, or defaulted.

The Kubernetes reference above is trusted metadata asserted by the application or its
deployment generator. Settei does not query a cluster. Reports may show the namespace,
Secret name, and Secret key, but `database.password` remains `<redacted>` because its
`Setting` is secret.


## Assemble precedence deliberately

`Settei.Optparse.setteiOptions` parses repeated `--config PATH`, repeated
`--set KEY=VALUE`, and the mutually exclusive `--explain-config` and
`--explain-config-json` flags. It only parses paths; a file adapter is responsible for
opening them. The following function receives already parsed file sources and places them
below environment and command-line inputs:

```haskell
resolveApplication
  :: [Source]
  -> EnvSnapshot
  -> SetteiOptions
  -> Either Text (ResolveResult AppConfig)
resolveApplication fileSources snapshot options = do
  environmentSource <-
    first
      (Text.pack . show)
      (envSource "environment" environmentBindings snapshot)
  first
    renderErrorsText
    ( resolve
        defaultResolveOptions
        ( fileSources
            <> [environmentSource]
            <> cliSources "arguments" (options ^. #overrides)
        )
        appConfig
    )
```

The order is low to high: a named default applies only when every explicit source is
absent, file sources lose to environment variables, and environment variables lose to
command-line fragments. Repeated `--set` options remain separate fragments, so the last
occurrence wins and earlier occurrences appear in the shadow trace from nearest to oldest.
A malformed final value is an error at that occurrence and never falls back.

This explicit stack matches the useful parts of two registered application patterns.
Rei resolves environment fields over YAML fields, while Seihou resolves CLI values over
environment, scoped configuration, global configuration, and defaults. Settei keeps the
ordering at the application boundary and centralizes the actual winner and explanation
semantics in core.


## Parse and explain without process mutation

Tests use optparse-applicative 0.19's `execParserPure` and an `EnvSnapshot`:

```haskell
import Options.Applicative qualified as Options

parseOptions :: [String] -> Maybe SetteiOptions
parseOptions arguments =
  Options.getParseResult
    ( Options.execParserPure
        Options.defaultPrefs
        (Options.info (setteiOptions Options.<**> Options.helper) Options.fullDesc)
        arguments
    )

exampleArguments :: [String]
exampleArguments =
  [ "--config",
    "service.yaml",
    "--set",
    "service.port=9000",
    "--set",
    "service.port=9001",
    "--explain-config"
  ]
```

After successful resolution, the executable selects the requested renderer:

```haskell
renderExplanation :: SetteiOptions -> ResolveResult a -> Text
renderExplanation options result =
  case options ^. #explainMode of
    NoExplain -> ""
    ExplainText -> renderResolutionText (result ^. #report)
    ExplainJson -> renderResolutionJson (result ^. #report)
```

For the example stack, the text report identifies command-line occurrence 2 as the
winner, then occurrence 1, environment, and file as shadowed candidates. The database
password explanation can name `HASKELL_ENV`, `DATABASE_PASSWORD`, and Kubernetes Secret
`production/service-database` key `password`, but it never contains the password value.

At the real executable boundary, replace the injected snapshot with one effectful call:

```haskell
readEnvironmentSource :: IO (Either (NonEmpty EnvError) Source)
readEnvironmentSource =
  readEnvSource "environment" environmentBindings
```

Taking one snapshot before resolution makes the result deterministic even if another
thread changes the process environment while configuration is being assembled.
