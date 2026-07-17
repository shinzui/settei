module Settei.ConfigTest (tests) where

import Control.Selective (select)
import Data.Bifunctor (first)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Settei
import Settei.Internal.Config (Request (..), runConfig)
import Settei.Prelude
import Settei.Prototype.Free (freeNecessaryKeys, freePossibleKeys)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

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
          @?= Left (Missing passwordKey)
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

environmentSetting :: Setting Text
environmentSetting =
  publicSetting environmentKey "Runtime environment" textDecoder

passwordSetting :: Setting Text
passwordSetting =
  secretSetting passwordKey "Database password" textDecoder

environmentKey :: Key
environmentKey = validKey "runtime.environment"

passwordKey :: Key
passwordKey = validKey "database.password"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

keySet :: [SchemaSetting] -> Set Key
keySet = Set.fromList . fmap schemaSettingKey
