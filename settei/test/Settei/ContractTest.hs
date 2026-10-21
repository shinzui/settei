module Settei.ContractTest (tests) where

import Data.Generics.Labels ()
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Settei
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Contract"
    [ testCase "renders the golden contract text" $ do
        expected <- TextIO.readFile "test/golden/contract.txt"
        renderContractText golden @?= expected,
      testCase "renders the golden contract JSON" $ do
        expected <- TextIO.readFile "test/golden/contract.json"
        renderContractJson golden <> "\n" @?= expected,
      testCase "joins bindings in supplied order and keeps unbound keys" $ do
        let contract = comprehensive
        fmap inputBindingName (entry "required" contract ^. #inputs) @?= ["FIRST", "SECOND"]
        entry "optional" contract ^. #inputs @?= []
        assertBool "missing orphan binding diagnostic" (UndeclaredBindingKey (inputBinding EnvironmentVariable "ORPHAN" (validKey "nothing.here")) `elem` contractDiagnostics contract),
      testCase "reports all default shapes without evaluating computations or case values" $ do
        let contract = comprehensive
        entry "constant" contract ^. #declaredDefaults @?= [DeclaredDefault (RuleName "constant-rule") "constant" (ConstantShape (VisibleDefault "42"))]
        shapes "opaque" contract @?= [ConstantShape UnrenderableDefault]
        shapes "secret" contract @?= [ConstantShape RedactedDefault]
        shapes "derived" contract @?= [DerivedShape [validKey "required"]]
        shapes "case" contract @?= [CaseShape [validKey "required"] 1 False]
        shapes "caseFallback" contract @?= [CaseShape [validKey "required"] 1 True]
        assertBool "deferred computation omitted" ("value not computed" `Text.isInfixOf` renderContractText contract),
      testCase "source candidates retain validity, winning origin and ordered shadows" $ do
        let contract = comprehensive
        fmap
          (\value -> (value ^. #origin . #name, fmap (\origin -> origin ^. #name) (value ^. #shadowed), value ^. #validity))
          (entry "source" contract ^. #sourceDefault)
          @?= Just ("high", ["middle", "low"], ValidDefault)
        verdict "source" contract @?= InputDefaulted CoveredBySource
        verdict "invalid" contract @?= InputRequired InvalidSourceDefault
        assertBool "missing invalid validity" ("\"validity\":\"invalid\"" `Text.isInfixOf` renderContractJson contract),
      testCase "diagnostics contain no candidate values and retain all inconsistency kinds" $ do
        let output = renderContractJson comprehensive
        mapM_
          (\kind -> assertBool (Text.unpack kind) (kind `Text.isInfixOf` output))
          ["conflicting-sensitivity", "default-structural-conflict", "undeclared-default-leaf", "undeclared-binding-key", "undeclared-profile-key"]
        assertBool "conflict did not become secret" (entry "mixed" comprehensive ^. #sensitivity == Secret),
      testCase "secret sentinel is absent from Show, text, JSON and diagnostics" $
        mapM_
          (\output -> assertBool "secret leaked" (not (sentinel `Text.isInfixOf` output)))
          [Text.pack (show comprehensive), renderContractText comprehensive, renderContractJson comprehensive, Text.pack (show (contractDiagnostics comprehensive))],
      testCase "identical inputs produce byte-identical outputs" $ do
        renderContractText comprehensive @?= renderContractText (build comprehensiveInputs comprehensiveConfig)
        renderContractJson comprehensive @?= renderContractJson (build comprehensiveInputs comprehensiveConfig),
      testCase "profile requires explicit input while retaining default metadata" $ do
        verdict "profiled" comprehensive @?= InputRequired ProfileRequirement
        assertBool "profile default lost" (not (null (entry "profiled" comprehensive ^. #declaredDefaults))),
      testCase "required occurrence is not satisfied by another occurrence's default" $ do
        let declaration = (,) <$> required x <*> withDefault x (constantDefault (RuleName "x-default") "fallback" "fallback")
            contract = build emptyContractInputs declaration
        verdict "x" contract @?= InputRequired RequiredRequest
        assertBool "required request unexpectedly resolved" (isFailure (resolve defaultResolveOptions [] declaration)),
      testCase "optional plus conditional required keeps occurrence-based verdict and merged schema" $ do
        let declaration = (,) <$> optional x <*> conditional x
            contract = build emptyContractInputs declaration
        entry "x" contract ^. #requirement @?= Required
        entry "x" contract ^. #presence @?= Necessary
        assertVerdict "x" (InputConditional NoDefault) contract
        assertBool "unselected branch failed" (not (isFailure (resolve defaultResolveOptions [environment "development"] declaration)))
        assertBool "selected branch succeeded" (isFailure (resolve defaultResolveOptions [environment "production"] declaration)),
      testCase "declaration default plus conditional required stays conditional" $ do
        let declaration = (,) <$> withDefault x (constantDefault (RuleName "x-default") "fallback" "fallback") <*> conditional x
            contract = build emptyContractInputs declaration
        assertVerdict "x" (InputConditional RequiredRequest) contract
        assertBool "development failed" (not (isFailure (resolve defaultResolveOptions [environment "development"] declaration)))
        assertBool "production succeeded" (isFailure (resolve defaultResolveOptions [environment "production"] declaration)),
      testCase "conditional-only source rejection remains conditional and branch-local" $ do
        let declaration = conditional integerX
            sources = [pairs "bad" [("x", RawText "bad")]]
            contract = build (ContractInputs [] sources Nothing) declaration
        assertVerdict "x" (InputConditional InvalidSourceDefault) contract
        assertBool "unselected invalid branch failed" (not (isFailure (resolve defaultResolveOptions (environment "development" : sources) declaration)))
        assertBool "selected invalid branch succeeded" (isFailure (resolve defaultResolveOptions (environment "production" : sources) declaration)),
      testCase "necessary acceptance plus conditional rejection remains conditional" $ do
        let declaration = (,) <$> required x <*> conditional integerX
            contract = build (ContractInputs [] [pairs "bad" [("x", RawText "bad")]] Nothing) declaration
        assertVerdict "x" (InputConditional InvalidSourceDefault) contract,
      testCase "later necessary rejection outranks earlier conditional rejection" $ do
        let declaration = (,) <$> conditional integerX <*> required integerX
            contract = build (ContractInputs [] [pairs "bad" [("x", RawText "bad")]] Nothing) declaration
        assertVerdict "x" (InputRequired InvalidSourceDefault) contract,
      testCase "cycle preflight avoids all source hooks" $ do
        let cyclic = withDefault x (derivedDefault (RuleName "cycle") "recursive" cyclic id)
            poison = locateSource (\_ -> error "source hook evaluated") (pairs "poison" [("x", RawText sentinel)])
        case deploymentContract (ContractInputs [] [poison] Nothing) cyclic of
          Left (DefaultCycle _ :| []) -> pure ()
          _ -> assertFailure "expected a default cycle"
    ]

validKey :: Text -> Key
validKey = either (error . show) id . parseKey

publicText :: Text -> Setting Text
publicText name = publicShowSetting (validKey name) name textDecoder

publicInt :: Text -> Setting Int
publicInt name = publicShowSetting (validKey name) name boundedIntegralDecoder

x :: Setting Text
x = publicText "x"

integerX :: Setting Int
integerX = publicInt "x"

conditional :: Setting a -> Config (Maybe a)
conditional settingSpec = whenEq (required (publicText "environment")) "production" (required settingSpec)

environment :: Text -> Source
environment value = pairs "environment" [("environment", RawText value)]

pairs :: Text -> [(Text, RawValue)] -> Source
pairs name values = either (error . show) id (sourceFromPairs name BuiltInSource [(validKey target, value) | (target, value) <- values])

build :: ContractInputs -> Config a -> DeploymentContract
build supplied = either (error . show) id . deploymentContract supplied

entry :: Text -> DeploymentContract -> ContractSetting
entry target contract = case filter ((== validKey target) . view #key) (contractSettings contract) of
  value : _ -> value
  [] -> error ("missing contract key: " <> Text.unpack target)

verdict :: Text -> DeploymentContract -> ExternalInput
verdict target contract = entry target contract ^. #externalInput

shapes :: Text -> DeploymentContract -> [DefaultShape]
shapes target contract = fmap (view #shape) (entry target contract ^. #declaredDefaults)

isFailure :: ResolveResult a -> Bool
isFailure result = case result ^. #answer of Left _ -> True; Right _ -> False

assertVerdict :: Text -> ExternalInput -> DeploymentContract -> IO ()
assertVerdict target expected contract = do
  verdict target contract @?= expected
  let verdictTag = case expected of InputRequired _ -> "required"; InputConditional _ -> "conditional"; InputDefaulted _ -> "defaulted"; InputOptional -> "optional"
  assertBool "text verdict absent" (("input: " <> verdictTag) `Text.isInfixOf` renderContractText contract)
  assertBool "JSON verdict absent" (("\"verdict\":\"" <> verdictTag <> "\"") `Text.isInfixOf` renderContractJson contract)

sentinel :: Text
sentinel = "SECRET-CONTRACT-SENTINEL-雪"

golden :: DeploymentContract
golden = build (ContractInputs [inputBinding EnvironmentVariable "NAME" (validKey "name")] [] Nothing) (required (publicText "name"))

comprehensive :: DeploymentContract
comprehensive = build comprehensiveInputs comprehensiveConfig

comprehensiveInputs :: ContractInputs
comprehensiveInputs =
  ContractInputs
    [inputBinding EnvironmentVariable "FIRST" (validKey "required"), inputBinding (CustomInput "mounted") "SECOND" (validKey "required"), inputBinding EnvironmentVariable "ORPHAN" (validKey "nothing.here")]
    [ pairs "low" [("source", RawText "low"), ("secretSource", RawText sentinel), ("invalid", RawText "bad"), ("unknown", RawText sentinel), ("blocked", RawText sentinel)],
      pairs "middle" [("source", RawText "middle")],
      pairs "high" [("source", RawText "high")]
    ]
    (Just (deploymentProfile "production" [(validKey "profiled", "state explicitly"), (validKey "unknownProfile", "absent")]))

comprehensiveConfig :: Config ()
comprehensiveConfig =
  sequenceA_
    [ () <$ required (publicText "required"),
      () <$ required (secretSetting (validKey "requiredSecret") "secret" textDecoder),
      () <$ optional (publicText "optional"),
      () <$ withDefault (publicInt "constant") (constantDefault (RuleName "constant-rule") "constant" 42),
      () <$ withDefault (publicSetting (validKey "opaque") "opaque" textDecoder) (constantDefault (RuleName "opaque-rule") "opaque" "opaque"),
      () <$ withDefault (secretSetting (validKey "secret") "secret" textDecoder) (constantDefault (RuleName "secret-rule") "secret" sentinel),
      () <$ withDefault (publicText "derived") (derivedDefault (RuleName "derived-rule") "derived" (required (publicText "required")) (\_ -> error "derived evaluated")),
      () <$ withDefault (publicText "case") (caseDefault (RuleName "case-rule") "case" (required (publicText "required")) (("development", error "case evaluated") :| []) Nothing),
      () <$ withDefault (publicText "caseFallback") (caseDefault (RuleName "fallback-rule") "fallback" (required (publicText "required")) (("development", error "case evaluated") :| []) (Just (error "fallback evaluated"))),
      () <$ conditional (publicText "conditional"),
      () <$ required (publicText "source"),
      () <$ required (publicInt "invalid"),
      () <$ required (secretSetting (validKey "secretSource") "secret source" textDecoder),
      () <$ required (publicText "blocked.child"),
      () <$ withDefault (publicText "mixed") (constantDefault (RuleName "mixed-rule") "mixed" sentinel),
      () <$ optional (secretSetting (validKey "mixed") "mixed" textDecoder),
      () <$ withDefault (publicText "profiled") (constantDefault (RuleName "profile-rule") "profile" "default")
    ]
  where
    sequenceA_ = foldr (*>) (pure ())
