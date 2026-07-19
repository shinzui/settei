module Settei.EnvTest (tests) where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Settei
import Settei.Env
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Env"
    [ testCase "explicit binding records variable origin" $ do
        input <- expectSource [binding (EnvName "HASKELL_ENV") runtimeEnvironment] [("HASKELL_ENV", "Production")]
        case lookupSource runtimeEnvironment input of
          Right (Just found) -> do
            found ^. to candidateOrigin . #kind @?= EnvironmentSource
            found ^. to candidateOrigin . #annotations . at "environment.variable" @?= Just "HASKELL_ENV"
          _ -> fail "expected the environment candidate",
      testCase "missing variables remain absent" $ do
        input <- expectSource [binding (EnvName "OPTIONAL_VALUE") optionalValue] []
        case lookupSource optionalValue input of
          Right Nothing -> pure ()
          _ -> fail "expected the optional variable to remain absent",
      testCase "duplicate bindings are rejected" $ do
        let sameName =
              [ binding (EnvName "VALUE") runtimeEnvironment,
                binding (EnvName "VALUE") optionalValue
              ]
            sameKey =
              [ binding (EnvName "ONE") runtimeEnvironment,
                binding (EnvName "TWO") runtimeEnvironment
              ]
        assertLeftContains isDuplicateName (envSource "environment" sameName (envSnapshot []))
        assertLeftContains isDuplicateKey (envSource "environment" sameKey (envSnapshot [])),
      testCase "prefix collisions are rejected" $ do
        let keys = [validKey "service.http-port", validKey "service.http_port"]
        case prefixedBindings "MYAPP" keys of
          Left errors ->
            assertBool "expected a normalized-name collision" (any isPrefixCollision (NonEmpty.toList errors))
          Right _ -> fail "expected the prefix helper to reject a collision",
      testCase "overlapping target keys are rejected" $ do
        let bindings =
              [ binding (EnvName "SERVICE") (validKey "service"),
                binding (EnvName "PORT") (validKey "service.port")
              ]
        assertLeftContains isConflict (envSource "environment" bindings (envSnapshot [])),
      testCase "Secret annotation remains redacted" $ do
        let reference = kubernetesRef SecretObject (Just "payments") "payments-database" (Just "password")
            passwordBinding = fromKubernetesObject reference (binding (EnvName "DATABASE_PASSWORD") databasePassword)
        input <- expectSourceWith [passwordBinding] [("DATABASE_PASSWORD", secretSentinel)]
        let result = resolve defaultResolveOptions [input] (required passwordSetting)
        _ <- expectResolution result
        let output = renderResolutionText (result ^. #report)
        assertBool "secret value reached the report" (not (secretSentinel `Text.isInfixOf` output))
        assertBool "secret object metadata was omitted" ("payments-database" `Text.isInfixOf` output)
        assertBool "secret key metadata was omitted" ("password" `Text.isInfixOf` output),
      testCase "ConfigMap annotation retains public metadata" $ do
        let reference = kubernetesRef ConfigMapObject Nothing "service-network" (Just "host")
            hostBinding = fromKubernetesObject reference (binding (EnvName "SERVICE_HOST") serviceHost)
        input <- expectSourceWith [hostBinding] [("SERVICE_HOST", "api.internal")]
        let result = resolve defaultResolveOptions [input] (required hostSetting)
        _ <- expectResolution result
        let output = renderResolutionText (result ^. #report)
        assertBool "ConfigMap metadata was omitted" ("service-network" `Text.isInfixOf` output)
        assertBool "public value was omitted" ("api.internal" `Text.isInfixOf` output)
    ]

expectSource :: [EnvBinding] -> [(Text, Text)] -> IO Source
expectSource bindings values = expectSourceWith bindings values

expectSourceWith :: [EnvBinding] -> [(Text, Text)] -> IO Source
expectSourceWith bindings values =
  case envSource "environment" bindings (envSnapshot values) of
    Left _ -> fail "expected a valid environment source"
    Right value -> pure value

expectResolution :: ResolveResult a -> IO a
expectResolution result = case result ^. #answer of
  Left _ -> fail "expected successful resolution"
  Right value -> pure value

assertLeftContains :: (EnvError -> Bool) -> Either (NonEmpty EnvError) a -> IO ()
assertLeftContains predicate = \case
  Left errors -> assertBool "expected matching validation error" (any predicate (NonEmpty.toList errors))
  Right _ -> fail "expected binding validation to fail"

isDuplicateName :: EnvError -> Bool
isDuplicateName (DuplicateEnvironmentName _) = True
isDuplicateName _ = False

isDuplicateKey :: EnvError -> Bool
isDuplicateKey (DuplicateTargetKey _) = True
isDuplicateKey _ = False

isPrefixCollision :: EnvError -> Bool
isPrefixCollision (PrefixedNameCollision _ _) = True
isPrefixCollision _ = False

isConflict :: EnvError -> Bool
isConflict (ConflictingTargetKeys _ _) = True
isConflict _ = False

passwordSetting :: Setting Text
passwordSetting = secretSetting databasePassword "Database password" textDecoder

hostSetting :: Setting Text
hostSetting = publicSetting serviceHost "Service host" textDecoder

runtimeEnvironment :: Key
runtimeEnvironment = validKey "runtime.environment"

optionalValue :: Key
optionalValue = validKey "optional.value"

databasePassword :: Key
databasePassword = validKey "database.password"

serviceHost :: Key
serviceHost = validKey "service.host"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

secretSentinel :: Text
secretSentinel = "never-render-this-secret"
