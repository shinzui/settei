{-# LANGUAGE ImportQualifiedPost #-}

module Settei.RenderTest (tests) where

import Control.Selective (select)
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Ratio qualified as Ratio
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
      testCase "failure resolution text matches its golden snapshot" $ do
        _ <- expectFailure failureResolutionResult
        assertGolden
          "test/golden/failure-resolution.txt"
          (renderResolutionText (failureResolutionResult ^. #report)),
      testCase "failure resolution JSON matches its versioned golden snapshot" $ do
        _ <- expectFailure failureResolutionResult
        assertGolden
          "test/golden/failure-resolution.json"
          (renderResolutionJson (failureResolutionResult ^. #report)),
      testCase "error renderers match their golden snapshots" $ do
        errors <- expectFailure (resolve defaultResolveOptions [secretSource] (required secretBoolSetting))
        assertGolden "test/golden/errors.txt" (renderErrorsText errors)
        assertGolden "test/golden/errors.json" (renderErrorsJson errors),
      testCase "warning renderers match their golden snapshots" $ do
        let result = resolve defaultResolveOptions [unknownSecretSource] (pure ())
        _ <- expectAnswer result
        assertGolden "test/golden/warnings.txt" (renderWarningsText (result ^. #warnings))
        assertGolden "test/golden/warnings.json" (renderWarningsJson (result ^. #warnings)),
      testCase "renderers distinguish missing from not selected" $ do
        let textOutput = renderResolutionText absentReport
            jsonOutput = renderResolutionJson absentReport
        assertBool "text omitted the missing outcome" ("<missing>" `Text.isInfixOf` textOutput)
        assertBool "text omitted the not-selected outcome" ("<not selected>" `Text.isInfixOf` textOutput)
        assertBool "JSON omitted the missing outcome" ("\"outcome\":\"missing\"" `Text.isInfixOf` jsonOutput)
        assertBool "JSON omitted the not-selected outcome" ("\"outcome\":\"not-selected\"" `Text.isInfixOf` jsonOutput),
      testCase "terminating rationals render as exact decimals" $ do
        renderNumber (1 Ratio.% 2) @?= "0.5"
        renderNumber ((-3) Ratio.% 8) @?= "-0.375"
        renderNumber (1 Ratio.% 1000) @?= "0.001"
        renderNumber (25 Ratio.% 2) @?= "12.5",
      testCase "non-terminating rationals retain exact fractions" $ do
        renderNumber (1 Ratio.% 3) @?= "1/3"
        renderNumber (7 Ratio.% 12) @?= "7/12",
      testCase "arrays use decimal and fraction rendering recursively" $
        renderReportedValue
          ( reportedValue
              Public
              (RawArray [RawNumber (1 Ratio.% 2), RawNumber (1 Ratio.% 3)])
          )
          @?= "[0.5, 1/3]",
      testCase "sensitivity conflicts render as structured errors" $ do
        let errors = SensitivityConflict (SensitivityConflictProblem {key = databasePassword}) :| []
        assertBool
          "text omitted the conflict explanation"
          ("database.password: declared with both public and secret sensitivity" `Text.isInfixOf` renderErrorsText errors)
        assertBool
          "JSON omitted the sensitivity-conflict kind"
          ("\"kind\":\"sensitivity-conflict\"" `Text.isInfixOf` renderErrorsJson errors),
      testCase "every supported output redacts marked secrets" redactionTest,
      testCase "mixed-sensitivity declarations never expose their secret sentinel" $
        sensitivityConflictRedactionTest
    ]

renderNumber :: Rational -> Text
renderNumber = renderReportedValue . reportedValue Public . RawNumber

assertGolden :: FilePath -> Text -> IO ()
assertGolden path actual = do
  expected <- Text.stripEnd <$> TextIO.readFile path
  Text.stripEnd actual @?= expected

redactionTest :: IO ()
redactionTest = do
  let success = resolve defaultResolveOptions [secretSource] (required secretTextSetting)
      failure = resolve defaultResolveOptions [secretSource] (required secretBoolSetting)
      warningResult = resolve defaultResolveOptions [unknownSecretSource] (pure ())
  _ <- expectAnswer success
  errors <- expectFailure failure
  _ <- expectAnswer warningResult
  let report = success ^. #report
      failureReport = failure ^. #report
      warnings = warningResult ^. #warnings
      outputs =
        [ renderSchemaText (describe (required secretTextSetting)),
          renderSchemaJson (describe (required secretTextSetting)),
          renderResolutionText report,
          renderResolutionJson report,
          renderResolutionText failureReport,
          renderResolutionJson failureReport,
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
  assertBool "failure report did not show a redaction marker" $
    "<redacted>" `Text.isInfixOf` renderResolutionText failureReport

sensitivityConflictRedactionTest :: IO ()
sensitivityConflictRedactionTest = do
  let conflictResult = resolve defaultResolveOptions [conflictSource] conflictingConfig
  case conflictResult ^. #answer of
    Right _ -> fail "mixed-sensitivity declaration should fail"
    Left errors -> do
      assertBool
        "resolution omitted the sensitivity conflict"
        ( any
            ( \case
                SensitivityConflict problem -> problem ^. #key == databasePassword
                _ -> False
            )
            (NonEmpty.toList errors)
        )
      let secretOnly = resolve defaultResolveOptions [conflictSource] (required secretTextSetting)
      _ <- expectAnswer secretOnly
      let schema = describe conflictingConfig
          report = secretOnly ^. #report
          conflictReport = conflictResult ^. #report
          outputs =
            [ renderSchemaText schema,
              renderSchemaJson schema,
              renderErrorsText errors,
              renderErrorsJson errors,
              renderResolutionText report,
              renderResolutionJson report,
              renderResolutionText conflictReport,
              renderResolutionJson conflictReport,
              Text.pack (show schema),
              Text.pack (show errors),
              Text.pack (show report)
            ]
      assertBool
        "the conflict sentinel reached a schema, error, resolution, or Show output"
        (all (not . Text.isInfixOf conflictSentinel) outputs)
      assertBool
        "the conflicted schema key was not marked secret"
        ("database.password [required, necessary, secret]" `Text.isInfixOf` renderSchemaText schema)
  where
    conflictingConfig =
      (,) <$> required secretTextSetting <*> required publicConflictSetting

expectAnswer :: ResolveResult a -> IO a
expectAnswer result = case result ^. #answer of
  Left errors -> fail ("expected successful resolution: " <> show errors)
  Right value -> pure value

expectFailure :: ResolveResult a -> IO (NonEmpty ConfigError)
expectFailure result = case result ^. #answer of
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

failureResolutionResult :: ResolveResult (Text, Int, Maybe Text)
failureResolutionResult =
  resolve defaultResolveOptions failureSources failureResolutionConfig

failureResolutionConfig :: Config (Text, Int, Maybe Text)
failureResolutionConfig =
  (,,)
    <$> required hostSetting
    <*> required portSetting
    <*> productionPassword

productionPassword :: Config (Maybe Text)
productionPassword = select selector branch
  where
    selector =
      (\environment -> if environment == "production" then Left () else Right Nothing)
        <$> required environmentSetting
    branch = (\password _ -> Just password) <$> required passwordSetting

failureSources :: [Source]
failureSources =
  [ source
      "built-in"
      BuiltInSource
      ( RawObject
          ( Map.fromList
              [ ("runtime", RawObject (Map.singleton "environment" (RawText "development"))),
                ("service", RawObject (Map.singleton "port" (RawNumber 8080)))
              ]
          )
      ),
    source
      "command-line"
      CommandLineSource
      ( RawObject
          ( Map.singleton
              "service"
              (RawObject (Map.singleton "port" (RawText "not-a-port")))
          )
      )
  ]

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

hostSetting :: Setting Text
hostSetting = publicSetting serviceHost "Service host" textDecoder

portSetting :: Setting Int
portSetting = publicSetting servicePort "Service port" boundedIntegralDecoder

environmentSetting :: Setting Text
environmentSetting = publicSetting runtimeEnvironment "Runtime environment" textDecoder

secretTextSetting :: Setting Text
secretTextSetting = secretSetting databasePassword "Database password" textDecoder

secretBoolSetting :: Setting Bool
secretBoolSetting = secretSetting databasePassword "Database password" boolDecoder

publicConflictSetting :: Setting Text
publicConflictSetting = publicSetting databasePassword "Metrics password label" textDecoder

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

conflictSource :: Source
conflictSource =
  source
    "conflict-sentinel"
    (CustomSource "test")
    ( RawObject
        ( Map.singleton
            "database"
            (RawObject (Map.singleton "password" (RawText conflictSentinel)))
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

conflictSentinel :: Text
conflictSentinel = "CONFLICT-S3cr3t-\"\\\n-[]{}-雪"

databasePassword :: Key
databasePassword = validKey "database.password"

serviceHost :: Key
serviceHost = validKey "service.host"

runtimeEnvironment :: Key
runtimeEnvironment = validKey "runtime.environment"

servicePort :: Key
servicePort = validKey "service.port"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
