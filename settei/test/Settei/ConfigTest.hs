module Settei.ConfigTest (tests) where

import Control.Selective (select)
import Data.Bifunctor (first)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Settei
import Settei.Internal.Config (Request (..), runConfig)
import Settei.Prelude
import Settei.Prototype.Free (freeNecessaryKeys, freePossibleKeys)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Config"
    [ testCase "applicative settings are necessary" $ do
        let schema = describe ((,) <$> required environmentSetting <*> required passwordSetting)
        keySet (schemaNecessary schema)
          @?= Set.fromList [environmentKey, passwordKey],
      testCase "selective production secret is conditional" $ do
        let schema = describe productionOnly
        keySet (schemaPossible schema)
          @?= Set.fromList [environmentKey, passwordKey]
        keySet (schemaNecessary schema)
          @?= Set.singleton environmentKey
        case schemaConditions schema of
          [condition] -> do
            conditionDependencies condition @?= Set.singleton environmentKey
            conditionSettings condition @?= Set.singleton passwordKey
          conditions -> fail ("expected one condition, found " <> show (length conditions)),
      testCase "whenEq matches the raw selective schema" $ do
        let schema = describe sugaredProductionOnly
        schema @?= describe productionOnly
        assertProductionSchema schema,
      testCase "whenConfig preserves the conditional schema footprint" $
        assertProductionSchema (describe whenConfigProductionOnly),
      testCase "fallbackTo makes only the fallback key conditional" $ do
        let schema = describe endpointWithFallback
        keySet (schemaPossible schema)
          @?= Set.fromList [serviceEndpointKey, serviceUrlKey]
        keySet (schemaNecessary schema)
          @?= Set.singleton serviceEndpointKey
        case schemaConditions schema of
          [condition] -> do
            conditionDependencies condition @?= Set.singleton serviceEndpointKey
            conditionSettings condition @?= Set.singleton serviceUrlKey
          conditions -> fail ("expected one condition, found " <> show (length conditions)),
      testCase "free-selective prototype agrees on possible effects" $
        Set.fromList (freePossibleKeys environmentKey passwordKey)
          @?= Set.fromList [environmentKey, passwordKey],
      testCase "free-selective prototype agrees on necessary effects" $
        Set.fromList (freeNecessaryKeys environmentKey passwordKey)
          @?= Set.singleton environmentKey,
      testCase "development skips production secret" $
        runConfig (interpret developmentValues) productionOnly
          @?= Right Nothing,
      testCase "production requests its secret" $
        runConfig (interpret productionValues) productionOnly
          @?= Left (Missing passwordKey),
      testCase "whenEq skips, requires, and returns its conditional value" $ do
        runConfig (interpret developmentValues) sugaredProductionOnly
          @?= Right Nothing
        runConfig (interpret productionValues) sugaredProductionOnly
          @?= Left (Missing passwordKey)
        runConfig (interpret productionWithPasswordValues) sugaredProductionOnly
          @?= Right (Just "fleet-secret"),
      testCase "fallbackTo prefers the primary and otherwise evaluates the fallback" $ do
        runConfig (interpret primaryEndpointValues) endpointWithFallback
          @?= Right "new.example"
        runConfig (interpret fallbackEndpointValues) endpointWithFallback
          @?= Right "old.example"
        runConfig (interpret Map.empty) endpointWithFallback
          @?= Left (Missing serviceUrlKey),
      testCase "duplicate sensitivity is secret-biased in either applicative order" $ do
        schemaSettingSensitivity (schemaEntry passwordKey (describe secretThenPublic))
          @?= Secret
        schemaSettingSensitivity (schemaEntry passwordKey (describe publicThenSecret))
          @?= Secret
        let rendered = renderSchemaText (describe publicThenSecret)
        assertBool "schema did not mark the duplicate key secret" ("secret" `Text.isInfixOf` rendered)
        assertBool "schema marked the duplicate key public" (not ("public" `Text.isInfixOf` rendered)),
      testCase "duplicate sensitivity is secret-biased through a selective branch" $
        schemaSettingSensitivity (schemaEntry passwordKey (describe selectiveDuplicate))
          @?= Secret,
      testCase "duplicate sensitivity is secret-biased through a default dependency" $
        schemaSettingSensitivity (schemaEntry passwordKey (describe defaultDuplicate))
          @?= Secret
    ]

data RuntimeError
  = Missing !Key
  | Decode !DecodeFailure
  deriving stock (Generic, Eq, Show)

productionOnly :: Config (Maybe Text)
productionOnly = select selector productionBranch
  where
    selector =
      (\environment -> if environment == "production" then Left () else Right Nothing)
        <$> required environmentSetting
    productionBranch = (\password _ -> Just password) <$> required passwordSetting

sugaredProductionOnly :: Config (Maybe Text)
sugaredProductionOnly =
  whenEq (required environmentSetting) "production" (required passwordSetting)

whenConfigProductionOnly :: Config (Maybe Text)
whenConfigProductionOnly =
  whenConfig
    ((== "production") <$> required environmentSetting)
    (required passwordSetting)

endpointWithFallback :: Config Text
endpointWithFallback =
  optional endpointSetting `fallbackTo` required urlSetting

secretThenPublic :: Config (Text, Text)
secretThenPublic =
  (,) <$> required passwordSetting <*> required publicPasswordSetting

publicThenSecret :: Config (Text, Text)
publicThenSecret =
  (,) <$> required publicPasswordSetting <*> required passwordSetting

selectiveDuplicate :: Config Text
selectiveDuplicate =
  select
    (Left <$> required passwordSetting)
    (const <$> required publicPasswordSetting)

defaultDuplicate :: Config Text
defaultDuplicate =
  withDefault
    passwordSetting
    ( derivedDefault
        (RuleName "password-from-public-duplicate")
        "Exercise duplicate sensitivity in a default dependency"
        (required publicPasswordSetting)
        id
    )

interpret :: Map Key RawValue -> Request a -> Either RuntimeError a
interpret values = \case
  RequiredRequest settingSpec ->
    case Map.lookup (settingKey settingSpec) values of
      Nothing -> Left (Missing (settingKey settingSpec))
      Just rawValue -> first Decode (decodeSetting settingSpec rawValue)
  OptionalRequest settingSpec ->
    case Map.lookup (settingKey settingSpec) values of
      Nothing -> Right Nothing
      Just rawValue -> Just <$> first Decode (decodeSetting settingSpec rawValue)

developmentValues :: Map Key RawValue
developmentValues = Map.singleton environmentKey (RawText "development")

productionValues :: Map Key RawValue
productionValues = Map.singleton environmentKey (RawText "production")

productionWithPasswordValues :: Map Key RawValue
productionWithPasswordValues =
  Map.fromList
    [ (environmentKey, RawText "production"),
      (passwordKey, RawText "fleet-secret")
    ]

primaryEndpointValues :: Map Key RawValue
primaryEndpointValues = Map.singleton serviceEndpointKey (RawText "new.example")

fallbackEndpointValues :: Map Key RawValue
fallbackEndpointValues = Map.singleton serviceUrlKey (RawText "old.example")

environmentSetting :: Setting Text
environmentSetting =
  publicSetting environmentKey "Runtime environment" textDecoder

passwordSetting :: Setting Text
passwordSetting =
  secretSetting passwordKey "Database password" textDecoder

publicPasswordSetting :: Setting Text
publicPasswordSetting =
  publicSetting passwordKey "Metrics password label" textDecoder

endpointSetting :: Setting Text
endpointSetting =
  publicSetting serviceEndpointKey "Service endpoint" textDecoder

urlSetting :: Setting Text
urlSetting =
  publicSetting serviceUrlKey "Legacy service URL" textDecoder

environmentKey :: Key
environmentKey = validKey "runtime.environment"

passwordKey :: Key
passwordKey = validKey "database.password"

serviceEndpointKey :: Key
serviceEndpointKey = validKey "service.endpoint"

serviceUrlKey :: Key
serviceUrlKey = validKey "service.url"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

keySet :: [SchemaSetting] -> Set Key
keySet = Set.fromList . fmap schemaSettingKey

assertProductionSchema :: Schema -> IO ()
assertProductionSchema schema = do
  keySet (schemaPossible schema)
    @?= Set.fromList [environmentKey, passwordKey]
  keySet (schemaNecessary schema)
    @?= Set.singleton environmentKey
  case schemaConditions schema of
    [condition] -> do
      conditionDependencies condition @?= Set.singleton environmentKey
      conditionSettings condition @?= Set.singleton passwordKey
    conditions -> fail ("expected one condition, found " <> show (length conditions))

schemaEntry :: Key -> Schema -> SchemaSetting
schemaEntry key schema =
  case filter ((== key) . schemaSettingKey) (schemaPossible schema) of
    [entry] -> entry
    entries -> error ("expected one schema entry, found " <> show (length entries))
