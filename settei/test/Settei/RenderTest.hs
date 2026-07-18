{-# LANGUAGE ImportQualifiedPost #-}

module Settei.RenderTest (tests) where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Settei
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Render"
    [ testCase "schema text matches its golden snapshot" $
        assertGolden "test/golden/schema.txt" (renderSchemaText snapshotSchema),
      testCase "schema JSON matches its versioned golden snapshot" $
        assertGolden "test/golden/schema.json" (renderSchemaJson snapshotSchema),
      testCase "resolution text matches its golden snapshot" $
        assertGolden "test/golden/resolution.txt" (renderResolutionText snapshotReport),
      testCase "resolution JSON matches its versioned golden snapshot" $
        assertGolden "test/golden/resolution.json" (renderResolutionJson snapshotReport),
      testCase "error renderers match their golden snapshots" $ do
        errors <- expectFailure (resolve defaultResolveOptions [secretSource] (required secretBoolSetting))
        assertGolden "test/golden/errors.txt" (renderErrorsText errors)
        assertGolden "test/golden/errors.json" (renderErrorsJson errors),
      testCase "warning renderers match their golden snapshots" $ do
        result <- expectSuccess (resolve defaultResolveOptions [unknownSecretSource] (pure ()))
        assertGolden "test/golden/warnings.txt" (renderWarningsText (result ^. #warnings))
        assertGolden "test/golden/warnings.json" (renderWarningsJson (result ^. #warnings)),
      testCase "renderers distinguish missing from not selected" $ do
        let textOutput = renderResolutionText absentReport
            jsonOutput = renderResolutionJson absentReport
        assertBool "text omitted the missing outcome" ("<missing>" `Text.isInfixOf` textOutput)
        assertBool "text omitted the not-selected outcome" ("<not selected>" `Text.isInfixOf` textOutput)
        assertBool "JSON omitted the missing outcome" ("\"outcome\":\"missing\"" `Text.isInfixOf` jsonOutput)
        assertBool "JSON omitted the not-selected outcome" ("\"outcome\":\"not-selected\"" `Text.isInfixOf` jsonOutput),
      testCase "every supported output redacts marked secrets" redactionTest
    ]

assertGolden :: FilePath -> Text -> IO ()
assertGolden path actual = do
  expected <- Text.stripEnd <$> TextIO.readFile path
  Text.stripEnd actual @?= expected

redactionTest :: IO ()
redactionTest = do
  success <- expectSuccess (resolve defaultResolveOptions [secretSource] (required secretTextSetting))
  errors <- expectFailure (resolve defaultResolveOptions [secretSource] (required secretBoolSetting))
  warningResult <- expectSuccess (resolve defaultResolveOptions [unknownSecretSource] (pure ()))
  let report = success ^. #report
      warnings = warningResult ^. #warnings
      outputs =
        [ renderSchemaText (describe (required secretTextSetting)),
          renderSchemaJson (describe (required secretTextSetting)),
          renderResolutionText report,
          renderResolutionJson report,
          renderErrorsText errors,
          renderErrorsJson errors,
          renderWarningsText warnings,
          renderWarningsJson warnings,
          Text.pack (show report),
          Text.pack (show errors),
          Text.pack (show warnings)
        ]
  assertBool
    "a secret sentinel reached a supported output"
    (all (not . Text.isInfixOf secretSentinel) outputs)
  assertBool "decode error did not show a redaction marker" $
    "<redacted>" `Text.isInfixOf` renderErrorsText errors

expectSuccess :: Either (NonEmpty ConfigError) a -> IO a
expectSuccess = \case
  Left _ -> fail "expected successful resolution"
  Right value -> pure value

expectFailure :: Either (NonEmpty ConfigError) a -> IO (NonEmpty ConfigError)
expectFailure = \case
  Left errors -> pure errors
  Right _ -> fail "expected resolution to fail"

snapshotSchema :: Schema
snapshotSchema = describe (required passwordSetting)

snapshotReport :: ResolutionReport
snapshotReport =
  ResolutionReport
    { nodes =
        Map.fromList
          [ (databasePassword, passwordNode),
            (runtimeEnvironment, environmentNode),
            (servicePort, portNode)
          ],
      branches = []
    }

passwordNode :: ResolutionNode
passwordNode =
  ResolutionNode
    { key = databasePassword,
      sensitivity = Secret,
      outcome = Resolved (reportedValue Secret (RawText secretSentinel)),
      origin = Just (environmentOrigin databasePassword "DATABASE_PASSWORD"),
      shadowed = [],
      derivation = Nothing
    }

environmentNode :: ResolutionNode
environmentNode =
  ResolutionNode
    { key = runtimeEnvironment,
      sensitivity = Public,
      outcome = Resolved (reportedValue Public (RawText "Production")),
      origin = Just (environmentOrigin runtimeEnvironment "HASKELL_ENV"),
      shadowed = [],
      derivation = Nothing
    }

portNode :: ResolutionNode
portNode =
  ResolutionNode
    { key = servicePort,
      sensitivity = Public,
      outcome = Resolved (visibleReportedValue "443"),
      origin = Just defaultOrigin,
      shadowed = [builtInOrigin],
      derivation =
        Just
          Derivation
            { rule = "service-port-by-environment",
              explanation = "Choose the conventional production port",
              dependencies = [runtimeEnvironment]
            }
    }

absentReport :: ResolutionReport
absentReport =
  ResolutionReport
    { nodes =
        Map.fromList
          [ ( databasePassword,
              ResolutionNode
                { key = databasePassword,
                  sensitivity = Secret,
                  outcome = NotSelected,
                  origin = Nothing,
                  shadowed = [],
                  derivation = Nothing
                }
            ),
            ( servicePort,
              ResolutionNode
                { key = servicePort,
                  sensitivity = Public,
                  outcome = MissingValue,
                  origin = Nothing,
                  shadowed = [],
                  derivation = Nothing
                }
            )
          ],
      branches =
        [ BranchTrace
            { dependencies = [runtimeEnvironment],
              settings = [databasePassword],
              selected = False
            }
        ]
    }

environmentOrigin :: Key -> Text -> Origin
environmentOrigin key variable =
  Origin
    { kind = EnvironmentSource,
      name = "environment",
      key,
      location = Nothing,
      annotations = Map.singleton "environment.variable" variable
    }

defaultOrigin :: Origin
defaultOrigin =
  Origin
    { kind = DerivedSource,
      name = "service-port-by-environment",
      key = servicePort,
      location = Nothing,
      annotations = Map.singleton "settei.default-rule" "service-port-by-environment"
    }

builtInOrigin :: Origin
builtInOrigin =
  Origin
    { kind = BuiltInSource,
      name = "built-in",
      key = servicePort,
      location = Nothing,
      annotations = Map.empty
    }

passwordSetting :: Setting Text
passwordSetting = secretSetting databasePassword "Database password" textDecoder

secretTextSetting :: Setting Text
secretTextSetting = secretSetting databasePassword "Database password" textDecoder

secretBoolSetting :: Setting Bool
secretBoolSetting = secretSetting databasePassword "Database password" boolDecoder

secretSource :: Source
secretSource =
  source
    "environment"
    EnvironmentSource
    ( RawObject
        ( Map.singleton
            "database"
            (RawObject (Map.singleton "password" (RawText secretSentinel)))
        )
    )

unknownSecretSource :: Source
unknownSecretSource =
  source
    "document"
    (FileSource "memory")
    (RawObject (Map.singleton "unknown" (RawText secretSentinel)))

secretSentinel :: Text
secretSentinel = "S3cr3t-\"\\\n-[]{}-雪"

databasePassword :: Key
databasePassword = validKey "database.password"

runtimeEnvironment :: Key
runtimeEnvironment = validKey "runtime.environment"

servicePort :: Key
servicePort = validKey "service.port"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
