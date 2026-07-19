# Getting started with Settei

This guide builds a small typed configuration from declaration through resolution. By the
end, the application can load the same logical keys from any Settei source adapter,
validate them once, and explain which source supplied each value.

## Add the packages

Every application needs the core package:

```cabal
default-language: GHC2024

build-depends:
  , containers
  , generic-lens
  , settei
  , text
```

The Haskell excerpts use GHC2024 plus `OverloadedStrings`; excerpts with generic record
lenses also use `OverloadedLabels`. Enable those extensions per module or in the Cabal
component.

Add only the adapters used by the executable:

```cabal
  , settei-env
  , settei-optparse-applicative
  , settei-yaml
  , settei-kdl
  , settei-dhall
```

Import `Settei` for the core API. Adapter modules are separate, so a library that only
declares configuration can depend on `settei` without depending on file parsers or
`optparse-applicative`.

```haskell
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}

import Data.Generics.Labels ()
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Settei
import Settei.Prelude ((^.))
```

## Declare application types and settings

Application code consumes ordinary typed records. A `Setting a` connects one structural
configuration key to its description, decoder, and sensitivity.

```haskell
data Environment = Development | Production
  deriving stock (Eq, Ord, Show)

data AppConfig = AppConfig
  { environment :: !Environment,
    host :: !Text,
    port :: !Int,
    apiToken :: !(Maybe Text)
  }
  deriving stock (Eq)

environmentSetting :: Setting Environment
environmentSetting =
  publicSettingWithRenderer
    (validKey "runtime.environment")
    "Runtime environment"
    (enumDecoder [("development", Development), ("production", Production)])
    renderEnvironment

hostSetting :: Setting Text
hostSetting =
  publicSetting (validKey "service.host") "Service host" textDecoder

portSetting :: Setting Int
portSetting =
  publicSettingWithRenderer
    (validKey "service.port")
    "Service port"
    boundedIntegralDecoder
    (Text.pack . show)

apiTokenSetting :: Setting Text
apiTokenSetting =
  secretSetting (validKey "credentials.apiToken") "API token" textDecoder

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

renderEnvironment :: Environment -> Text
renderEnvironment Development = "development"
renderEnvironment Production = "production"
```

Use `publicSettingWithRenderer` when a public typed value may be produced by a default.
The renderer lets explanations show that typed default. Source values do not need it.
Use `secretSetting` for every credential or sensitive value; Settei then redacts the value
before constructing errors and reports. Declaring the same key with different sensitivity
in one declaration is a resolve-time `SensitivityConflict`, and schemas and reports always
use the most restrictive declaration (`Secret` wins).

`parseKey` accepts non-empty dotted paths such as `service.port`. The dots represent
structural segments. Source formats therefore use nested objects or nodes rather than a
literal dotted field name.

## Compose decoders

Decoders compose, so most applications never write a raw case expression.
`Decoder` is a `Functor`: wrap a decoded value in a newtype or transform it
with `<$>`:

```haskell
newtype SecretText = SecretText Text

apiTokenDecoder :: Decoder SecretText
apiTokenDecoder = SecretText <$> textDecoder
```

Decode arrays with `listDecoder` and `nonEmptyDecoder`:

```haskell
tagsDecoder :: Decoder [Text]
tagsDecoder = listDecoder textDecoder
```

Decode any type with a textual parser using `parsedDecoder`. Its first
argument is the expectation shown on failure; the parser's own error message
is discarded so a failure can never echo a (possibly secret) input value:

```haskell
listenUriDecoder :: Decoder Uri
listenUriDecoder = parsedDecoder "an absolute URI" parseAbsoluteUri
```

Numbers decode with `boundedIntegralDecoder` (whole numbers with an explicit
range in failures), `rationalDecoder` (exact), and `doubleDecoder` (rounded
to the nearest `Double`). All numeric decoders also accept textual numbers,
so the same declaration works for environment variables and file formats.
`enumDecoder` matches spellings case-sensitively.

## Compose the declaration

A `Config a` describes how settings form an application value:

```haskell
appConfig :: Config AppConfig
appConfig =
  AppConfig
    <$> required environmentSetting
    <*> required hostSetting
    <*> withDefault portSetting portDefault
    <*> optional apiTokenSetting

portDefault :: Default Int
portDefault =
  caseDefault
    (RuleName "service-port-by-environment")
    "Choose the service port for the runtime environment"
    (required environmentSetting)
    ((Development, 8080) :| [(Production, 80)])
    Nothing
```

The request combinators have distinct absence behavior:

| Combinator | When no source supplies the key |
| --- | --- |
| `required setting` | Resolution returns `MissingRequired`. |
| `optional setting` | The typed result contains `Nothing`. |
| `withDefault setting rule` | The named rule is evaluated. |

Use `constantDefault` for a fixed fallback, `derivedDefault` for a computed fallback, and
`caseDefault` for a finite mapping. Defaults run only when the setting is absent from all
sources. An explicit value that fails to decode is an error; Settei does not hide it by
falling back to a default or an earlier source.

## Inspect the schema without loading input

`describe` works without reading files, arguments, or the process environment:

```haskell
schemaText :: Text
schemaText = renderSchemaText (describe appConfig)

schemaJson :: Text
schemaJson = renderSchemaJson (describe appConfig)
```

The schema lists possible keys, descriptions, requirements, sensitivity, and conditional
relationships. This is useful for a `--describe-config` command, generated documentation,
and tests that prevent accidental schema changes.

## Load and order sources

Each adapter produces a `Source`. Pass sources to `resolve` from lowest to highest
precedence:

```haskell
resolveApp
  :: [Source]
  -> ResolveResult AppConfig
resolveApp sources =
  resolve defaultResolveOptions sources appConfig
```

For a typical service, build the list in this order:

```haskell
orderedSources =
  builtInSources
    <> fileSources
    <> [environmentSource]
    <> commandLineSources
```

Resolution is leaf-wise. A higher source can override `service.port` without replacing a
lower source's `service.host`. Arrays are leaves and are replaced as a whole. A scalar at
`service` conflicts structurally with a requested key such as `service.port`.

Unknown input keys produce warnings under `defaultResolveOptions`. Applications that must
reject stale or misspelled keys can opt into strict handling:

```haskell
strictOptions :: ResolveOptions
strictOptions = ResolveOptions {unknownKeyPolicy = RejectUnknownKeys}
```

## Use the typed result and diagnostics

Every `ResolveResult` contains an `answer` (the application value or non-empty errors), a
redacted report, and non-fatal warnings. With `OverloadedLabels` and
`Data.Generics.Labels`, the fields can be read as follows:

```haskell
handleResult :: ResolveResult AppConfig -> IO AppConfig
handleResult result = do
  let warningText = renderWarningsText (result ^. #warnings)
  -- Send warningText to stderr or the application's logger when non-empty.
  either
    (fail . Text.unpack . renderErrorsText)
    pure
    (result ^. #answer)

explanationText :: ResolveResult a -> Text
explanationText result = renderResolutionText (result ^. #report)

explanationJson :: ResolveResult a -> Text
explanationJson result = renderResolutionJson (result ^. #report)
```

Render the error side of `answer` with `renderErrorsText` or `renderErrorsJson`. These
renderers can safely report secret settings because rejected secret values have already
been replaced with `<redacted>`. The report and warnings are still available on that
failure path, which is usually when operators need provenance most.

Do not log the complete typed configuration record: it contains the real values needed by
the application, including secrets. Prefer an allowlisted startup summary plus Settei's
report renderers.

## Write deterministic tests

Keep the declaration in a library module and keep IO in the executable. Tests can then
construct sources directly or use pure adapter entry points:

```haskell
testSource :: Source
testSource =
  source
    "test"
    BuiltInSource
    ( RawObject
        ( Map.fromList
            [ ("runtime", RawObject (Map.singleton "environment" (RawText "development"))),
              ( "service",
                RawObject
                  (Map.fromList [("host", RawText "127.0.0.1"), ("port", RawNumber 9000)])
              )
            ]
        )
    )
```

Test at least these cases:

- the smallest valid configuration;
- each source layer overriding the layer below it;
- a missing required key and a malformed winning value;
- unknown-key warning or rejection behavior;
- every default and conditional branch; and
- a secret sentinel that must not appear in errors, warnings, schema output, or
  resolution reports.

Continue with [environment and command-line configuration](environment-and-cli.md) or one
of the [YAML](yaml.md), [KDL](kdl.md), and [Dhall](dhall.md) file adapters.
