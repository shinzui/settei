module Settei.OptparseTest (tests) where

import Data.Generics.Labels ()
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Options.Applicative qualified as Options
import Settei
import Settei.Env
import Settei.Optparse
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Optparse"
    [ preparationTests,
      validationTests,
      testCase "deployment contract modes parse and reject combinations" $ do
        mapM_
          ( \(flag, mode) -> do
              parsed <- expectParse diagnosticModeOptions [flag]
              parsed @?= mode
              mapM_
                (\other -> assertBool "combined diagnostics parsed" (Options.getParseResult (parse diagnosticModeOptions [flag, other]) == Nothing))
                ["--check-config", "--describe-config", "--explain-config-json", if flag == "--deployment-contract" then "--deployment-contract-json" else "--deployment-contract"]
          )
          [("--deployment-contract", DeploymentContractText), ("--deployment-contract-json", DeploymentContractJson)],
      testCase "contract diagnostic is lazy for unrelated modes and preserves failures" $ do
        mapM_
          (\mode -> contractDiagnostic mode (error "contract forced") @?= Nothing)
          [NoDiagnostic, CheckConfig, DescribeConfigText, DescribeConfigJson, ExplainText, ExplainJson]
        let contract = deploymentContract emptyContractInputs (required portSetting)
            errors = DefaultCycle (DefaultCycleProblem (RuleName "loop" :| [])) :| []
        contractDiagnostic DeploymentContractText contract @?= Just (renderContractText <$> contract)
        contractDiagnostic DeploymentContractJson contract @?= Just ((<> "\n") . renderContractJson <$> contract)
        contractDiagnostic DeploymentContractText (Left errors) @?= Just (Left errors),
      testCase "final repeated --set wins with shadow trace" $ do
        overrides <- expectParse overrideOptions ["--set", "service.port=9000", "--set", "service.port=9001"]
        environment <- environmentPort 8000
        let result =
              resolve
                defaultResolveOptions
                ([portSource "built-in" BuiltInSource 6000, portSource "file" (FileSource "memory") 7000, environment] <> cliSources "arguments" overrides)
                (required portSetting)
        value <- expectResolution result
        value @?= 9001
        case result ^. #report . #nodes . at servicePort of
          Just node -> do
            node ^. #origin . _Just . #annotations . at "command-line.occurrence" @?= Just "2"
            fmap (^. #name) (node ^. #shadowed)
              @?= ["arguments --set #1", "environment", "file", "built-in"]
          Nothing -> fail "expected the resolved port node",
      testCase "execParserPure rejects an invalid key" $ do
        let parsed = parse overrideOptions ["--set", "service..port=9000"]
        assertBool "invalid key unexpectedly parsed" (Options.getParseResult parsed == Nothing),
      testCase "malformed final CLI value does not fall back" $ do
        overrides <- expectParse overrideOptions ["--set", "service.port=9000", "--set", "service.port=broken"]
        environment <- environmentPort 8000
        case (resolve defaultResolveOptions (environment : cliSources "arguments" overrides) (required portSetting)) ^. #answer of
          Left errors -> case NonEmpty.toList errors of
            [DecodeError problem] -> do
              problem ^. #origin . #name @?= "arguments --set #2"
              problem ^. #origin . #annotations . at "command-line.occurrence" @?= Just "2"
            _ -> fail "expected one CLI decode error"
          Right _ -> fail "expected the malformed final override to fail",
      testCase "secret override spelling omits the value" $ do
        overrides <- expectParse overrideOptions ["--set", "database.password=" <> Text.unpack secretSentinel]
        let result = resolve defaultResolveOptions (cliSources "arguments" overrides) (required passwordSetting)
        _ <- expectResolution result
        let textOutput = renderResolutionText (result ^. #report)
            jsonOutput = renderResolutionJson (result ^. #report)
        assertBool "secret reached text output" (not (secretSentinel `Text.isInfixOf` textOutput))
        assertBool "secret reached JSON output" (not (secretSentinel `Text.isInfixOf` jsonOutput))
        case overrides of
          [override] -> cliOverrideSpelling override @?= "--set database.password"
          _ -> fail "expected one secret override",
      testCase "named option produces an optional source fragment" $ do
        input <-
          expectParse
            (namedOption "--port" servicePort (Options.long "port" <> Options.metavar "PORT"))
            ["--port", "8080"]
        case input of
          Nothing -> fail "expected the named option source"
          Just sourceValue -> do
            let result = resolve defaultResolveOptions [sourceValue] (required portSetting)
            value <- expectResolution result
            value @?= 8080,
      testCase "setteiOptions parses grouped paths, overrides, and diagnostics" $ do
        parsed <-
          expectParse
            setteiOptions
            [ "--config",
              "base.yaml",
              "--config",
              "local.yaml",
              "--set",
              "service.port=8080",
              "--explain-config-json"
            ]
        parsed ^. #configPaths @?= ["base.yaml", "local.yaml"]
        length (parsed ^. #overrides) @?= 1
        parsed ^. #diagnosticMode @?= ExplainJson,
      testCase "diagnostic modes default and are mutually exclusive" $ do
        defaulted <- expectParse diagnosticModeOptions []
        defaulted @?= NoDiagnostic
        let parsed = parse diagnosticModeOptions ["--explain-config", "--explain-config-json"]
        assertBool "both diagnostic modes unexpectedly parsed" (Options.getParseResult parsed == Nothing),
      testCase "diagnostic helpers render the requested outputs" $ do
        let schema = describe (required portSetting)
            result = resolve defaultResolveOptions [portSource "test" BuiltInSource 8080] (required portSetting)
        assertBool "text schema diagnostic missing" (schemaDiagnostic DescribeConfigText schema /= Nothing)
        assertBool "JSON schema diagnostic missing" (schemaDiagnostic DescribeConfigJson schema /= Nothing)
        case resolutionDiagnostic (runtime CheckConfig) result of
          DiagnosticOutput output -> output @?= "configuration valid\n"
          _ -> fail "expected successful check"
        case resolutionDiagnostic (runtime NoDiagnostic) result of
          DiagnosticContinue value -> value @?= 8080
          _ -> fail "expected startup permission",
      testCase "help groups configuration and diagnostics by intent" $ do
        let parserInfo = Options.info (setteiOptions Options.<**> Options.helper) Options.fullDesc
        case Options.execParserPure Options.defaultPrefs parserInfo ["--help"] of
          Options.Failure failure -> do
            let (helpText, _) = Options.renderFailure failure "settei-example"
            assertBool "Configuration group missing" ("Configuration" `Text.isInfixOf` Text.pack helpText)
            assertBool "Diagnostics group missing" ("Diagnostics" `Text.isInfixOf` Text.pack helpText)
            mapM_
              (\flag -> assertBool "contract flag missing from help" (flag `Text.isInfixOf` Text.pack helpText))
              ["--deployment-contract", "--deployment-contract-json"]
          _ -> fail "expected --help to produce parser help"
    ]

parse :: Options.Parser a -> [String] -> Options.ParserResult a
parse parser arguments =
  Options.execParserPure Options.defaultPrefs (Options.info parser Options.fullDesc) arguments

expectParse :: Options.Parser a -> [String] -> IO a
expectParse parser arguments =
  case Options.getParseResult (parse parser arguments) of
    Nothing -> fail "expected command-line parsing to succeed"
    Just value -> pure value

expectResolution :: ResolveResult a -> IO a
expectResolution result = case result ^. #answer of
  Left _ -> fail "expected configuration resolution to succeed"
  Right value -> pure value

environmentPort :: Int -> IO Source
environmentPort value = do
  validated <-
    either
      (fail . Text.unpack . renderEnvErrorsText)
      pure
      (bindings [binding (EnvName "SERVICE_PORT") servicePort])
  pure
    ( environmentSource
        validated
        (envSnapshot [("SERVICE_PORT", Text.pack (show value))])
    )

portSource :: Text -> SourceKind -> Int -> Source
portSource name kind value =
  source
    name
    kind
    (RawObject (Map.singleton "service" (RawObject (Map.singleton "port" (RawNumber (fromIntegral value))))))

portSetting :: Setting Int
portSetting = publicSetting servicePort "Service port" boundedIntegralDecoder

passwordSetting :: Setting Text
passwordSetting = secretSetting databasePassword "Database password" textDecoder

servicePort :: Key
servicePort = validKey "service.port"

databasePassword :: Key
databasePassword = validKey "database.password"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

secretSentinel :: Text
secretSentinel = "never-render-this-cli-secret"

validationTests :: TestTree
validationTests =
  testGroup
    "validated diagnostics"
    [ testCase "check succeeds only after validation and startup gets the same value" $ do
        case validatedDiagnostic (runtime CheckConfig) passingResult of
          DiagnosticOutput output -> output @?= "configuration valid\n"
          _ -> fail "check did not succeed"
        case validatedDiagnostic (runtime NoDiagnostic) passingResult of
          DiagnosticContinue value -> assertBool "typed value changed" (Right value == validationBase [] ^. #answer)
          _ -> fail "startup did not continue",
      testCase "all runtime modes reject a failing validated result" $
        mapM_
          ( \mode -> case validatedDiagnostic (runtime mode) failingResult of
              DiagnosticFailure output -> do
                assertBool "rule missing" ("pool-covers-workers" `Text.isInfixOf` output)
                assertBool "key missing" ("service.poolSize" `Text.isInfixOf` output)
                assertBool "check falsely succeeded" (not ("configuration valid" `Text.isInfixOf` output))
                safe output
              _ -> fail "invalid configuration accepted"
          )
          modes,
      testCase "text success and failure include provenance and outcomes" $ do
        case validatedDiagnostic (runtime ExplainText) passingResult of
          DiagnosticOutput output -> do
            assertBool "setting missing" ("service.workers = \"4\"" `Text.isInfixOf` output)
            assertBool "outcome missing" ("invariant pool-covers-workers [passed]" `Text.isInfixOf` output)
            safe output
          _ -> fail "explain did not succeed"
        case validatedDiagnostic (runtime ExplainText) failingResult of
          DiagnosticFailure output -> do
            assertBool "origin missing" ("from environment source validation fixture" `Text.isInfixOf` output)
            assertBool "failed trace missing" ("[failed (1 violation)]" `Text.isInfixOf` output)
            safe output
          _ -> fail "explain did not fail",
      testCase "JSON success is one line and failure is two versioned documents" $ do
        case validatedDiagnostic (runtime ExplainJson) passingResult of
          DiagnosticOutput output -> do
            length (Text.lines output) @?= 1
            assertBool "resolution type missing" ("{\"schemaVersion\":1,\"type\":\"settei.resolution\"" `Text.isPrefixOf` output)
            assertBool "invariant array missing" ("\"invariants\":[{\"rule\":\"pool-covers-workers\"" `Text.isInfixOf` output)
            safe output
          _ -> fail "explain did not succeed"
        case validatedDiagnostic (runtime ExplainJson) failingResult of
          DiagnosticFailure output -> case Text.lines output of
            [errors, report] -> do
              assertBool "error document missing" ("{\"schemaVersion\":1,\"type\":\"settei.errors\"" `Text.isPrefixOf` errors)
              assertBool "invariant kind missing" ("\"kind\":\"invariant\"" `Text.isInfixOf` errors)
              assertBool "origin missing" ("\"name\":\"validation fixture\",\"key\":\"service.poolSize\"" `Text.isInfixOf` report)
              assertBool "failed outcome missing" ("\"status\":\"failed\"" `Text.isInfixOf` report)
              safe output
            _ -> fail "expected two JSON documents"
          _ -> fail "explain did not fail",
      testCase "missing and decode failures retain original evidence and not-run outcomes" $
        mapM_
          ( \base -> do
              let result = validate validationRules base
              assertBool "answer changed" (result ^. #answer == base ^. #answer)
              result ^. #report @?= base ^. #report
              result ^. #warnings @?= base ^. #warnings
              fmap (^. #status) (validationOutcomes (result ^. #validation)) @?= [InvariantNotRun]
              case validatedDiagnostic (runtime ExplainText) result of
                DiagnosticFailure output -> do
                  assertBool "not-run trace missing" ("[not run]" `Text.isInfixOf` output)
                  safe output
                _ -> fail "base error accepted"
              case validatedDiagnostic (runtime ExplainJson) result of
                DiagnosticFailure output -> length (Text.lines output) @?= 2
                _ -> fail "base JSON error accepted"
          )
          [ resolve defaultResolveOptions [] validationConfig,
            validationBase [("service.workers", RawText "broken")]
          ],
      testCase "nonempty warnings and provenance survive runtime dispatch" $ do
        let base = validationBase [("unknown.setting", RawText "public")]
            result = validate validationRules base
        assertBool "warning fixture empty" (not (null (base ^. #warnings)))
        result ^. #warnings @?= base ^. #warnings
        result ^. #report @?= base ^. #report
        mapM_
          ( \mode -> case validatedDiagnostic (runtime mode) result of
              DiagnosticContinue value -> assertBool "value changed" (Right value == base ^. #answer)
              DiagnosticOutput output -> safe output
              DiagnosticFailure _ -> fail "valid result rejected"
          )
          [NoDiagnostic, CheckConfig, ExplainText, ExplainJson]
    ]
  where
    passingResult = validate validationRules (validationBase [])
    failingResult = validate validationRules (validationBase [("service.poolSize", RawText "1")])
    modes = [NoDiagnostic, ExplainText, ExplainJson, CheckConfig]
    safe output = assertBool "secret escaped into diagnostic" (not (any (`Text.isInfixOf` output) [validationSentinel, "SETTEI_VALIDATION_SECRET_29"]))

validationSentinel :: Text
validationSentinel = "SETTEI_VALIDATION_SECRET_29\"\\\n秘密"

validationConfig :: Config (Int, Int, Text)
validationConfig =
  (,,)
    <$> required (publicSetting (validKey "service.workers") "workers" boundedIntegralDecoder)
    <*> required (publicSetting (validKey "service.poolSize") "pool" boundedIntegralDecoder)
    <*> required (secretSetting (validKey "service.token") "token" textDecoder)

validationRules :: Validators (Int, Int, Text)
validationRules =
  either (error . Text.unpack . renderValidatorErrorsText) id $
    validators validationConfig [check (InvariantRule "pool-covers-workers") (fmap validKey ["service.poolSize", "service.workers"]) "pool must cover workers" (\(workers, pool, _) -> pool >= workers)]

validationBase :: [(Text, RawValue)] -> ResolveResult (Int, Int, Text)
validationBase changes = resolve defaultResolveOptions [input] validationConfig
  where
    pairs = [("service.workers", RawText "4"), ("service.poolSize", RawText "8"), ("service.token", RawText validationSentinel)]
    input = either (const (error "invalid fixture")) id (sourceFromPairs "validation fixture" EnvironmentSource [(validKey name, value) | (name, value) <- changes <> filter (\(name, _) -> name `notElem` fmap fst changes) pairs])

-- Test-only extraction; production consumers must handle all preparation decisions.
runtime :: DiagnosticMode -> RuntimeDiagnosticMode
runtime mode = case prepareDiagnostic mode (error "schema forced") (error "contract forced") of
  DiagnosticNeedsRuntime token -> token
  DiagnosticRendered _ -> error "expected runtime mode"
  DiagnosticRejected _ -> error "expected runtime mode"

allModes :: [DiagnosticMode]
allModes = [NoDiagnostic, CheckConfig, ExplainText, ExplainJson, DescribeConfigText, DescribeConfigJson, DeploymentContractText, DeploymentContractJson]

-- An exhaustive, independent expectation ensures newly added constructors need tests.
isRuntime :: DiagnosticMode -> Bool
isRuntime = \case
  NoDiagnostic -> True
  CheckConfig -> True
  ExplainText -> True
  ExplainJson -> True
  DescribeConfigText -> False
  DescribeConfigJson -> False
  DeploymentContractText -> False
  DeploymentContractJson -> False

-- Consumer-shaped public API boundary: input acquisition and startup are separate.
consumer :: DiagnosticMode -> Maybe (Either (NonEmpty ConfigError) DeploymentContract) -> IO (ResolveResult Int) -> IO () -> IO (Int, Text, Text)
consumer mode contract acquire startup =
  case prepareDiagnostic mode (describe (required portSetting)) contract of
    DiagnosticRejected message -> pure (4, "", message)
    DiagnosticRendered output -> pure (0, output, "")
    DiagnosticNeedsRuntime token -> do
      result <- acquire
      case resolutionDiagnostic token result of
        DiagnosticFailure message -> pure (4, "", message)
        DiagnosticOutput output -> pure (0, output, renderWarningsText (result ^. #warnings))
        DiagnosticContinue _ -> startup >> pure (0, "started\n", renderWarningsText (result ^. #warnings))

preparationTests :: TestTree
preparationTests =
  testGroup
    "complete dispatch"
    [ testCase "all eight modes acquire once and start only successful normal execution" $
        mapM_
          ( \mode -> do
              acquisitions <- newIORef (0 :: Int)
              starts <- newIORef (0 :: Int)
              let result = resolve defaultResolveOptions [portSource "fixture" BuiltInSource 8080] (required portSetting)
              (code, output, errors) <- consumer mode supported (modifyIORef' acquisitions (+ 1) >> pure result) (modifyIORef' starts (+ 1))
              code @?= 0
              errors @?= ""
              assertBool "empty output" (not (Text.null output))
              readIORef acquisitions >>= (@?= if isRuntime mode then 1 else 0)
              readIORef starts >>= (@?= if mode == NoDiagnostic then 1 else 0)
          )
          allModes,
      testCase "parsed contract flags reject omitted support before acquisition or startup" $
        mapM_
          ( \flag -> do
              mode <- expectParse diagnosticModeOptions [flag]
              result <- consumer mode Nothing poison poison
              result @?= (4, "", "deployment contract diagnostic is unavailable\n")
              (code, output, errors) <- consumer mode supported poison poison
              code @?= 0
              errors @?= ""
              assertBool "contract missing" ("service.port" `Text.isInfixOf` output)
          )
          ["--deployment-contract", "--deployment-contract-json"],
      testCase "mode selection leaves unrelated schema and contract unevaluated" $ do
        mapM_
          ( \mode -> case prepareDiagnostic mode poisonValue poisonValue of
              DiagnosticNeedsRuntime _ -> pure ()
              _ -> fail "expected runtime permission"
          )
          [NoDiagnostic, CheckConfig, ExplainText, ExplainJson]
        mapM_
          ( \mode -> case prepareDiagnostic mode (describe (required portSetting)) poisonValue of
              DiagnosticRendered output -> assertBool "schema missing" ("service.port" `Text.isInfixOf` output)
              _ -> fail "expected schema"
          )
          [DescribeConfigText, DescribeConfigJson]
        mapM_
          ( \mode -> case prepareDiagnostic mode poisonValue supported of
              DiagnosticRendered output -> assertBool "contract missing" ("service.port" `Text.isInfixOf` output)
              _ -> fail "expected contract"
          )
          [DeploymentContractText, DeploymentContractJson],
      testCase "contract construction errors reject safely before runtime" $
        mapM_
          ( \mode -> do
              let problems = DefaultCycle (DefaultCycleProblem (RuleName "loop" :| [])) :| []
              consumer mode (Just (Left problems)) poison poison >>= (@?= (4, "", renderErrorsText problems))
          )
          [DeploymentContractText, DeploymentContractJson],
      testCase "bare runtime dispatch preserves errors, provenance, JSON, warnings and secrets" $
        mapM_
          ( \mode ->
              mapM_
                ( \base -> do
                    let result = resolutionDiagnostic (runtime mode) base
                    case base ^. #answer of
                      Left problems -> case result of
                        DiagnosticFailure output -> do
                          let suffix = case mode of
                                ExplainText -> renderResolutionText (base ^. #report)
                                ExplainJson -> renderResolutionJson (base ^. #report) <> "\n"
                                _ -> ""
                          output @?= renderErrorsText problems <> suffix
                          assertBool "false success" (not ("configuration valid" `Text.isInfixOf` output))
                          safe output
                        _ -> fail "resolution failure accepted"
                      Right _ -> case result of
                        DiagnosticContinue _ -> mode @?= NoDiagnostic
                        DiagnosticOutput output -> do
                          assertBool "bare JSON gained invariants" (not ("invariants" `Text.isInfixOf` output))
                          safe output
                        DiagnosticFailure _ -> fail "resolution success rejected"
                )
                [validationBase [], resolve defaultResolveOptions [] validationConfig, validationBase [("service.workers", RawText "broken")], validationBase [("unknown.setting", RawText "public")]]
          )
          [NoDiagnostic, CheckConfig, ExplainText, ExplainJson],
      testCase "normal failure never starts" $ do
        let missing = resolve defaultResolveOptions [] (required portSetting)
        (code, output, _) <- consumer NoDiagnostic supported (pure missing) poison
        code @?= 4
        output @?= ""
    ]
  where
    supported = Just (deploymentContract emptyContractInputs (required portSetting))
    poison = fail "runtime effect invoked"
    poisonValue = error "unused static input forced"
    safe output = assertBool "secret leaked" (not (any (`Text.isInfixOf` output) [validationSentinel, "SETTEI_VALIDATION_SECRET_29"]))
