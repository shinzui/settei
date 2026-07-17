{-# LANGUAGE ImportQualifiedPost #-}

module Settei.DefaultTest (tests) where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Settei
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Default"
    [ testCase "constant default resolves without a source" $ do
        result <- expectSuccess (resolve defaultResolveOptions [] constantPort)
        result ^. #value @?= 8080
        case result ^. #report . #nodes . at servicePort of
          Just node -> do
            fmap (^. #name) (node ^. #origin) @?= Just "built-in-port"
            fmap (^. #rule) (node ^. #derivation) @?= Just "built-in-port"
          Nothing -> fail "expected a derived port node",
      testCase "production port records its environment dependency" $ do
        result <- expectSuccess (resolve defaultResolveOptions [environmentSource Production] casePort)
        result ^. #value @?= 443
        case result ^. #report . #nodes . at servicePort of
          Just node -> case node ^. #derivation of
            Just derivation -> do
              derivation ^. #rule @?= "service-port-by-environment"
              derivation ^. #dependencies @?= [runtimeEnvironment]
              case node ^. #outcome of
                Resolved displayValue -> renderReportedValue displayValue @?= "443"
                _ -> fail "expected a resolved default value"
            Nothing -> fail "expected default derivation metadata"
          Nothing -> fail "expected the port report node",
      testCase "an explicit target overrides and skips its default dependencies" $ do
        result <- expectSuccess (resolve defaultResolveOptions [portSource 9443] casePort)
        result ^. #value @?= 9443
        case result ^. #report . #nodes . at runtimeEnvironment of
          Just node -> node ^. #outcome @?= NotSelected
          Nothing -> fail "expected the skipped dependency in the report"
        case result ^. #report . #nodes . at servicePort of
          Just node -> node ^. #derivation @?= Nothing
          Nothing -> fail "expected the explicit port node",
      testCase "an unmatched case without fallback is structured" $ do
        case resolve defaultResolveOptions [environmentSource Staging] casePort of
          Left errors -> case NonEmpty.toList errors of
            [DefaultError problem] -> do
              problem ^. #key @?= servicePort
              problem ^. #rule @?= RuleName "service-port-by-environment"
            _ -> fail "expected one default error"
          Right _ -> fail "expected the case default to fail",
      testCase "default dependencies remain conditional in the static schema" $ do
        let schema = describe casePort
            necessaryKeys = fmap schemaSettingKey (schemaNecessary schema)
        necessaryKeys @?= [servicePort]
        case filter ((== servicePort) . schemaSettingKey) (schemaPossible schema) of
          [portSchema] -> schemaSettingRequirement portSchema @?= Optional
          _ -> fail "expected one port schema entry",
      testCase "cyclic defaults fail before source evaluation" $ do
        case resolve defaultResolveOptions [poisonSource] cyclicA of
          Left errors -> case NonEmpty.toList errors of
            [DefaultCycle problem] ->
              NonEmpty.toList (problem ^. #rules)
                @?= [RuleName "cycle-a", RuleName "cycle-b", RuleName "cycle-a"]
            _ -> fail "expected one default cycle"
          Right _ -> fail "expected cyclic defaults to fail"
    ]

data Environment = Development | Test | Staging | Production
  deriving stock (Generic, Eq, Ord, Show)

constantPort :: Config Int
constantPort =
  withDefault
    portSetting
    (constantDefault (RuleName "built-in-port") "Built-in service port" 8080)

casePort :: Config Int
casePort =
  withDefault
    portSetting
    ( caseDefault
        (RuleName "service-port-by-environment")
        "Choose the conventional port for the runtime environment"
        (required environmentSetting)
        ((Development, 8080) :| [(Test, 8081), (Production, 443)])
        Nothing
    )

cyclicA :: Config Text
cyclicA =
  withDefault
    cycleASetting
    (derivedDefault (RuleName "cycle-a") "Depends on cycle B" cyclicB id)

cyclicB :: Config Text
cyclicB =
  withDefault
    cycleBSetting
    (derivedDefault (RuleName "cycle-b") "Depends on cycle A" cyclicA id)

portSetting :: Setting Int
portSetting =
  publicSettingWithRenderer
    servicePort
    "Service port"
    boundedIntegralDecoder
    (Text.pack . show)

environmentSetting :: Setting Environment
environmentSetting =
  publicSetting
    runtimeEnvironment
    "Runtime environment"
    ( enumDecoder
        [ ("development", Development),
          ("test", Test),
          ("staging", Staging),
          ("production", Production)
        ]
    )

cycleASetting :: Setting Text
cycleASetting = publicSetting cycleAKey "Cycle A" textDecoder

cycleBSetting :: Setting Text
cycleBSetting = publicSetting cycleBKey "Cycle B" textDecoder

environmentSource :: Environment -> Source
environmentSource environment =
  source
    "environment"
    EnvironmentSource
    ( RawObject
        ( Map.singleton
            "runtime"
            (RawObject (Map.singleton "environment" (RawText (environmentText environment))))
        )
    )

portSource :: Int -> Source
portSource value =
  source
    "command-line"
    CommandLineSource
    ( RawObject
        ( Map.singleton
            "service"
            (RawObject (Map.singleton "port" (RawNumber (fromIntegral value))))
        )
    )

poisonSource :: Source
poisonSource =
  locateSource
    (const (error "a cyclic default attempted to inspect a source"))
    ( source
        "poison"
        (CustomSource "test")
        ( RawObject
            ( Map.fromList
                [ ("cycle-a", RawText "unused"),
                  ("cycle-b", RawText "unused")
                ]
            )
        )
    )

environmentText :: Environment -> Text
environmentText Development = "development"
environmentText Test = "test"
environmentText Staging = "staging"
environmentText Production = "production"

expectSuccess :: Either (NonEmpty ConfigError) a -> IO a
expectSuccess = \case
  Left _ -> fail "expected successful resolution"
  Right value -> pure value

servicePort :: Key
servicePort = validKey "service.port"

runtimeEnvironment :: Key
runtimeEnvironment = validKey "runtime.environment"

cycleAKey :: Key
cycleAKey = validKey "cycle-a"

cycleBKey :: Key
cycleBKey = validKey "cycle-b"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
