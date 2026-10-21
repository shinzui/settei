module Settei.OptparseTest (tests) where

import Data.Generics.Labels ()
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
    [ validationTests,
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
        resolutionDiagnostic CheckConfig result @?= Just "configuration valid\n"
        resolutionDiagnostic NoDiagnostic result @?= Nothing,
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
        case validatedDiagnostic CheckConfig passingResult of
          DiagnosticOutput output -> output @?= "configuration valid\n"
          _ -> fail "check did not succeed"
        case validatedDiagnostic NoDiagnostic passingResult of
          DiagnosticContinue value -> assertBool "typed value changed" (Right value == validationBase [] ^. #answer)
          _ -> fail "startup did not continue",
      testCase "all eight modes reject one failingResult validated result" $
        mapM_
          ( \mode -> case validatedDiagnostic mode failingResult of
              DiagnosticFailure output -> do
                assertBool "rule missing" ("pool-covers-workers" `Text.isInfixOf` output)
                assertBool "key missing" ("service.poolSize" `Text.isInfixOf` output)
                assertBool "check falsely succeeded" (not ("configuration valid" `Text.isInfixOf` output))
                safe output
              _ -> fail "invalid configuration accepted"
          )
          modes,
      testCase "text success and failure include provenance and outcomes" $ do
        case validatedDiagnostic ExplainText passingResult of
          DiagnosticOutput output -> do
            assertBool "setting missing" ("service.workers = \"4\"" `Text.isInfixOf` output)
            assertBool "outcome missing" ("invariant pool-covers-workers [passed]" `Text.isInfixOf` output)
            safe output
          _ -> fail "explain did not succeed"
        case validatedDiagnostic ExplainText failingResult of
          DiagnosticFailure output -> do
            assertBool "origin missing" ("from environment source validation fixture" `Text.isInfixOf` output)
            assertBool "failed trace missing" ("[failed (1 violation)]" `Text.isInfixOf` output)
            safe output
          _ -> fail "explain did not fail",
      testCase "JSON success is one line and failure is two versioned documents" $ do
        case validatedDiagnostic ExplainJson passingResult of
          DiagnosticOutput output -> do
            length (Text.lines output) @?= 1
            assertBool "resolution type missing" ("{\"schemaVersion\":1,\"type\":\"settei.resolution\"" `Text.isPrefixOf` output)
            assertBool "invariant array missing" ("\"invariants\":[{\"rule\":\"pool-covers-workers\"" `Text.isInfixOf` output)
            safe output
          _ -> fail "explain did not succeed"
        case validatedDiagnostic ExplainJson failingResult of
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
              case validatedDiagnostic ExplainText result of
                DiagnosticFailure output -> do
                  assertBool "not-run trace missing" ("[not run]" `Text.isInfixOf` output)
                  safe output
                _ -> fail "base error accepted"
              case validatedDiagnostic ExplainJson result of
                DiagnosticFailure output -> length (Text.lines output) @?= 2
                _ -> fail "base JSON error accepted"
          )
          [ resolve defaultResolveOptions [] validationConfig,
            validationBase [("service.workers", RawText "broken")]
          ],
      testCase "nonempty warnings and static-mode success fallbacks survive validation" $ do
        let base = validationBase [("unknown.setting", RawText "public")]
            result = validate validationRules base
        assertBool "warning fixture empty" (not (null (base ^. #warnings)))
        result ^. #warnings @?= base ^. #warnings
        result ^. #report @?= base ^. #report
        mapM_
          ( \mode -> case validatedDiagnostic mode result of
              DiagnosticContinue value -> assertBool "value changed" (Right value == base ^. #answer)
              _ -> fail "static fallback changed"
          )
          [DescribeConfigText, DescribeConfigJson, DeploymentContractText, DeploymentContractJson]
    ]
  where
    passingResult = validate validationRules (validationBase [])
    failingResult = validate validationRules (validationBase [("service.poolSize", RawText "1")])
    modes = [NoDiagnostic, ExplainText, ExplainJson, CheckConfig, DescribeConfigText, DescribeConfigJson, DeploymentContractText, DeploymentContractJson]
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
