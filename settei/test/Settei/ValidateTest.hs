module Settei.ValidateTest (tests) where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Settei
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Validate"
    [ testCase "empty collection preserves the typed answer" $ do
        let result = validate (collection []) (resolved [])
        assertBool "answer changed" (result ^. #answer == resolved [] ^. #answer)
        validationOutcomes (result ^. #validation) @?= [],
      testCase "valid configuration passes all rules without changing values" $ do
        let base = resolved []; result = validate workerValidators base
        assertBool "answer changed" (result ^. #answer == base ^. #answer)
        statuses result @?= replicate 5 InvariantPassed
        result ^. #report @?= base ^. #report
        result ^. #warnings @?= base ^. #warnings,
      testCase "independent failures accumulate in declaration and violation order" $ do
        problems <- failures failingResult
        fmap (^. #rule) problems @?= fmap InvariantRule ["pool-capacity", "visibility-timeout", "provider-account", "provider-account"]
        fmap (^. #keys) problems @?= [validKeys ["workers.jobPoolSize", "workers.concurrency"], validKeys ["workers.visibilityTimeoutSeconds", "workers.concurrency"], validKeys ["email.accounts", "email.credentials"], validKeys ["email.accounts", "email.credentials"]]
        fmap (^. #detail) problems @?= [Nothing, Nothing, Just "account alpha", Just "account beta"]
        statuses failingResult @?= [InvariantFailed 1, InvariantFailed 1, InvariantPassed, InvariantPassed, InvariantFailed 2],
      testCase "failed prerequisite skips an unforced validator function" $ do
        let rules = take 3 hubRules <> [requires [InvariantRule "replica"] (invariant (InvariantRule "replica-pool-share") (validKeys ["workers.jobPoolSize", "workers.replica.count"]) "pool covers replicas" (error "skipped function forced"))]
            result = validate (collection rules) (resolved [("workers.replica.index", RawText "2")])
        statuses result @?= [InvariantPassed, InvariantPassed, InvariantFailed 1, InvariantSkipped (InvariantRule "replica" :| [])],
      testCase "requires composes and blocked prerequisites preserve order transitively" $ do
        let rule name = check (InvariantRule name) (validKeys ["workers.concurrency"]) "safe" (const False)
            rules = [rule "a", requires [InvariantRule "a"] (rule "b"), requires [InvariantRule "a", InvariantRule "b"] (requires [InvariantRule "b", InvariantRule "a"] (invariant (InvariantRule "c") (validKeys ["workers.concurrency"]) "safe" (error "blocked")))]
            report = validate (collection rules) (resolved []) ^. #validation
        fmap (^. #status) (validationOutcomes report) @?= [InvariantFailed 1, InvariantSkipped (InvariantRule "a" :| []), InvariantSkipped (InvariantRule "b" :| [InvariantRule "a"])]
        fmap (^. #prerequisites) (validationOutcomes report) @?= [[], [InvariantRule "a"], [InvariantRule "b", InvariantRule "a"]]
        assertBool "skipped JSON absent" ("\"blockedBy\":[\"b\",\"a\"]" `Text.isInfixOf` renderValidatedResolutionJson (ResolutionReport mempty []) report)
        assertBool "skipped text absent" ("[skipped after b, a]" `Text.isInfixOf` renderValidationText report),
      testCase "failed resolution retains errors report warnings and never runs functions" $ do
        let base = resolve defaultResolveOptions [fixture (filter ((/= "workers.concurrency") . fst) validPairs)] hubConfig
            declarations = collection [requires (entry ^. #prerequisites) (invariant (entry ^. #rule) (entry ^. #keys) (entry ^. #expectation) (error "failed-resolution function forced")) | entry <- validationOutcomes (describeValidators workerValidators)]
            result = validate declarations base
        assertBool "errors changed" (result ^. #answer == base ^. #answer)
        case result ^. #answer of
          Left (MissingRequired _ :| []) -> pure ()
          _ -> fail "expected original missing error"
        result ^. #report @?= base ^. #report
        result ^. #warnings @?= base ^. #warnings
        statuses result @?= replicate 5 InvariantNotRun,
      testCase "role collections select shared rules" $ do
        let base = resolved [("workers.jobPoolSize", RawText "2")]
        assertBool "server rejected" (case validate serverValidators base ^. #answer of Right _ -> True; _ -> False)
        statuses (validate workerValidators base) @?= [InvariantFailed 1, InvariantPassed, InvariantPassed, InvariantPassed, InvariantPassed],
      testCase "describe and direct execution are source free" $ do
        let report = describeValidators workerValidators
        fmap (^. #status) (validationOutcomes report) @?= replicate 5 InvariantNotRun
        fmap (^. #prerequisites) (validationOutcomes report) @?= [[], [], [], [InvariantRule "replica"], []]
        case resolved [] ^. #answer of
          Left _ -> fail "fixture failed"
          Right value -> do
            let (directReport, problems) = runValidators workerValidators value
            directReport @?= validate workerValidators (resolved []) ^. #validation
            problems @?= [],
      testCase "construction accumulates every offender in defined order" $ do
        let rule name ks = invariant (InvariantRule name) (validKeys ks) "safe" (error "construction forced function")
            declarations = [rule "" [], rule "white space" ["nothing.here"], rule "line\nbreak" ["workers.concurrency"], requires [InvariantRule "later"] (rule "early" ["workers.concurrency"]), requires [InvariantRule "self"] (rule "self" ["workers.concurrency"]), rule "later" ["workers.concurrency"], rule "later" ["workers.concurrency"], rule "later" ["workers.concurrency"]]
            expected = [InvalidInvariantRule (InvariantRule ""), EmptyInvariantKeys (InvariantRule ""), InvalidInvariantRule (InvariantRule "white space"), UndeclaredInvariantKey (InvariantRule "white space") (validKey "nothing.here"), InvalidInvariantRule (InvariantRule "line\nbreak"), UnknownPrerequisite (InvariantRule "early") (InvariantRule "later"), UnknownPrerequisite (InvariantRule "self") (InvariantRule "self"), DuplicateInvariantRule (InvariantRule "later")]
        case validators hubConfig declarations of
          Right _ -> fail "invalid declarations accepted"
          Left errors -> do
            NonEmpty.toList errors @?= expected
            length (Text.lines (renderValidatorErrorsText errors)) @?= length expected
            mapM_ (\problem -> assertBool "empty error" (not (Text.null (renderValidatorErrorText problem)))) expected
            assertBool "newline not escaped" ("line\\nbreak" `Text.isInfixOf` renderValidatorErrorsText errors),
      testCase "cycles precede metadata errors and suppress key-membership checks" $
        case validators cyclicA [check (InvariantRule "") [validKey "nothing.here"] "safe" (const True)] of
          Left errors -> do
            NonEmpty.toList errors @?= [CyclicDeclaration (DefaultCycleProblem (RuleName "cycle-a" :| [RuleName "cycle-b", RuleName "cycle-a"])), InvalidInvariantRule (InvariantRule "")]
            assertBool "cycle path missing" ("cycle-a -> cycle-b -> cycle-a" `Text.isInfixOf` renderValidatorErrorsText errors)
          Right _ -> fail "cycle accepted",
      testCase "optional keys are allowed without assuming presence" $ do
        let config = optional (publicSetting (validKey "maybe.value") "optional" textDecoder)
        case validators config [check (InvariantRule "optional-value") [validKey "maybe.value"] "may be absent" (const True)] of
          Left errors -> fail (Text.unpack (renderValidatorErrorsText errors))
          Right rules -> case validate rules (resolve defaultResolveOptions [] config) ^. #answer of
            Right Nothing -> pure ()
            _ -> fail "optional changed",
      testCase "conditional keys can be referenced on an unselected path" $ do
        let config = whenEq (pure False) True (required (publicSetting (validKey "branch.value") "conditional" textDecoder))
        case validators config [check (InvariantRule "branch-value") [validKey "branch.value"] "may be unselected" (== Nothing)] of
          Left errors -> fail (Text.unpack (renderValidatorErrorsText errors))
          Right rules -> statuses (validate rules (resolve defaultResolveOptions [] config)) @?= [InvariantPassed],
      testCase "direct failing execution agrees with validated resolution" $ do
        case resolved overrides ^. #answer of
          Left _ -> fail "fixture did not resolve"
          Right value -> do
            let (report, problems) = runValidators workerValidators value
            expected <- failures failingResult
            problems @?= expected
            report @?= failingResult ^. #validation,
      testCase "detail is retained verbatim and escaped by JSON" $ do
        let detail = "public \"account\" \\ label"
            result = validate (collection [invariant (InvariantRule "label") (validKeys ["email.accounts"]) "has credential" (const [violationWithDetail detail])]) (resolved [])
        problems <- failures result
        fmap (^. #detail) problems @?= [Just detail]
        errors <- errorList result
        assertBool "detail absent in text" (detail `Text.isInfixOf` renderErrorsText errors)
        assertBool "detail absent in JSON" ("public \\\"account\\\" \\\\ label" `Text.isInfixOf` renderErrorsJson errors),
      testCase "all retained structures and renderers omit raw and escaped secrets" $ do
        problems <- failures failingResult
        errors <- errorList failingResult
        let report = failingResult ^. #report; validation = failingResult ^. #validation
        mapM_ assertSafe [Text.pack (show problems), Text.pack (show errors), Text.pack (show report), Text.pack (show validation), Text.pack (show (validationOutcomes validation)), renderErrorsText errors, renderErrorsJson errors, renderValidationText validation, renderResolutionText report, renderResolutionJson report, renderValidatedResolutionJson report validation]
        assertBool "scan missed escaped leak" (hasSecret (Text.pack (show secretSentinel))),
      testCase "rendering is deterministic and preserves rule order independently of key order" $ do
        let output = renderValidatedResolutionJson (failingResult ^. #report) (failingResult ^. #validation)
            reordered = validate workerValidators (resolve defaultResolveOptions [fixture (reverse (overrides <> filter (\(name, _) -> name `notElem` fmap fst overrides) validPairs))] hubConfig)
        renderValidatedResolutionJson (reordered ^. #report) (reordered ^. #validation) @?= output
        renderValidatedResolutionJson (failingResult ^. #report) (failingResult ^. #validation) @?= output,
      testCase "validation text golden" $ golden "validation.txt" (renderValidationText (failingResult ^. #validation)),
      testCase "validated resolution JSON golden" $ golden "validation.json" (renderValidatedResolutionJson (failingResult ^. #report) (failingResult ^. #validation)),
      testCase "invariant error text golden" $ errorList failingResult >>= golden "invariant-errors.txt" . renderErrorsText,
      testCase "invariant error JSON golden" $ errorList failingResult >>= golden "invariant-errors.json" . renderErrorsJson
    ]

-- Intentionally no Show instance on either secret-bearing type.
newtype Credentials = Credentials [Text] deriving stock (Generic, Eq)

data HubConfig = HubConfig
  { environment :: !Text,
    pool :: !Int,
    jobPool :: !Int,
    concurrency :: !Int,
    visibility :: !Int,
    replicaIndex :: !Int,
    replicaCount :: !Int,
    accounts :: ![Text],
    databaseUrl :: !Text,
    credentials :: !Credentials
  }
  deriving stock (Generic, Eq)

hubConfig :: Config HubConfig
hubConfig =
  HubConfig
    <$> required (publicSetting (validKey "runtime.environment") "environment" (enumDecoder [("development", "development"), ("production", "production")]))
    <*> number "database.poolSize"
    <*> number "workers.jobPoolSize"
    <*> number "workers.concurrency"
    <*> number "workers.visibilityTimeoutSeconds"
    <*> number "workers.replica.index"
    <*> number "workers.replica.count"
    <*> required (publicSetting (validKey "email.accounts") "accounts" (listDecoder textDecoder))
    <*> required (secretSetting (validKey "database.url") "database" textDecoder)
    <*> required (secretSetting (validKey "email.credentials") "credentials" (Credentials <$> listDecoder textDecoder))
  where
    number name = required (publicSetting (validKey name) name boundedIntegralDecoder)

hubRules :: [Validator HubConfig]
hubRules =
  [ check (InvariantRule "pool-capacity") (validKeys ["workers.jobPoolSize", "workers.concurrency"]) "pool covers concurrency" (\c -> c ^. #jobPool >= c ^. #concurrency),
    check (InvariantRule "visibility-timeout") (validKeys ["workers.visibilityTimeoutSeconds", "workers.concurrency"]) "timeout covers twice concurrency" (\c -> toInteger (c ^. #visibility) >= 2 * toInteger (c ^. #concurrency)),
    check (InvariantRule "replica") (validKeys ["workers.replica.index", "workers.replica.count"]) "index is within replica count" (\c -> c ^. #replicaIndex >= 0 && c ^. #replicaIndex < c ^. #replicaCount),
    requires [InvariantRule "replica"] (check (InvariantRule "replica-pool-share") (validKeys ["workers.jobPoolSize", "workers.replica.count"]) "pool covers replicas" (\c -> c ^. #jobPool >= c ^. #replicaCount)),
    invariant (InvariantRule "provider-account") (validKeys ["email.accounts", "email.credentials"]) "every account has a credential" (\c -> let Credentials entries = c ^. #credentials; names = fmap (Text.takeWhile (/= ':')) entries in [violationWithDetail ("account " <> name) | name <- c ^. #accounts, name `notElem` names])
  ]

workerValidators, serverValidators :: Validators HubConfig
workerValidators = collection hubRules
serverValidators = collection [last hubRules]

collection :: [Validator HubConfig] -> Validators HubConfig
collection rules = either (error . Text.unpack . renderValidatorErrorsText) id (validators hubConfig rules)

validPairs :: [(Text, RawValue)]
validPairs = [("runtime.environment", RawText "production"), ("database.poolSize", RawText "10"), ("workers.jobPoolSize", RawText "8"), ("workers.concurrency", RawText "4"), ("workers.visibilityTimeoutSeconds", RawText "30"), ("workers.replica.index", RawText "0"), ("workers.replica.count", RawText "2"), ("email.accounts", RawArray [RawText "alpha", RawText "beta"]), ("database.url", RawText secretSentinel), ("email.credentials", RawArray [RawText ("alpha:" <> secretSentinel), RawText ("beta:" <> secretSentinel)])]

overrides :: [(Text, RawValue)]
overrides = [("workers.jobPoolSize", RawText "2"), ("workers.visibilityTimeoutSeconds", RawText "1"), ("email.credentials", RawArray [RawText ("other:" <> secretSentinel)])]

resolved :: [(Text, RawValue)] -> ResolveResult HubConfig
resolved changes = resolve defaultResolveOptions [fixture (changes <> filter (\(name, _) -> name `notElem` fmap fst changes) validPairs)] hubConfig

fixture :: [(Text, RawValue)] -> Source
fixture pairs = either (const (error "invalid fixture pairs")) id (sourceFromPairs "fixture" EnvironmentSource [(validKey name, value) | (name, value) <- pairs])

failingResult :: ValidatedResult HubConfig
failingResult = validate workerValidators (resolved overrides)

statuses :: ValidatedResult a -> [InvariantStatus]
statuses result = fmap (^. #status) (validationOutcomes (result ^. #validation))

errorList :: ValidatedResult a -> IO (NonEmpty ConfigError)
errorList result = case result ^. #answer of Left errors -> pure errors; Right _ -> fail "expected rejection"

failures :: ValidatedResult a -> IO [InvariantProblem]
failures result = do
  errors <- errorList result
  let problems = [problem | InvariantError problem <- NonEmpty.toList errors]
  length problems @?= length errors
  pure problems

validKey :: Text -> Key
validKey = either (error . show) id . parseKey

validKeys :: [Text] -> [Key]
validKeys = fmap validKey

secretSentinel :: Text
secretSentinel = "SETTEI_VALIDATION_SECRET_29\"\\\n秘密"

hasSecret :: Text -> Bool
hasSecret output = any (`Text.isInfixOf` output) [secretSentinel, "SETTEI_VALIDATION_SECRET_29"]

assertSafe :: Text -> IO ()
assertSafe output = assertBool "secret retained in diagnostic" (not (hasSecret output))

golden :: FilePath -> Text -> IO ()
golden name actual = do
  expected <- TextIO.readFile ("test/golden/" <> name)
  Text.stripEnd actual @?= Text.stripEnd expected

cyclicA, cyclicB :: Config Text
cyclicA = withDefault (publicSetting (validKey "cycle.a") "A" textDecoder) (derivedDefault (RuleName "cycle-a") "A from B" cyclicB id)
cyclicB = withDefault (publicSetting (validKey "cycle.b") "B" textDecoder) (derivedDefault (RuleName "cycle-b") "B from A" cyclicA id)
