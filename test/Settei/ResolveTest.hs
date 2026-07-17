{-# LANGUAGE ImportQualifiedPost #-}

module Settei.ResolveTest (tests) where

import Control.Selective (select)
import Data.Generics.Labels ()
import Data.List (permutations)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Settei
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Resolve"
    [ testCase "rightmost source wins per leaf" $ do
        result <- expectSuccess (resolve defaultResolveOptions layeredSources serviceConfig)
        result ^. #value @?= ("file.example", 443)
        let nodes = result ^. #report . #nodes
        case nodes ^. at serviceHost of
          Just node -> do
            fmap (^. #name) (node ^. #origin) @?= Just "file"
            fmap (^. #name) (node ^. #shadowed) @?= ["built-in"]
          Nothing -> fail "expected host report node"
        case nodes ^. at servicePort of
          Just node -> do
            fmap (^. #name) (node ^. #origin) @?= Just "environment"
            fmap (^. #name) (node ^. #shadowed) @?= ["built-in"]
          Nothing -> fail "expected port report node",
      testCase "reversing source order predictably reverses precedence" $ do
        result <- expectSuccess (resolve defaultResolveOptions (reverse layeredSources) serviceConfig)
        result ^. #value @?= ("built-in.example", 8080),
      testCase "shadowed origins are ordered from highest to lowest precedence" $ do
        result <- expectSuccess (resolve defaultResolveOptions (fmap snd lawSources) (required portSetting))
        case result ^. #report . #nodes . at servicePort of
          Just node -> fmap (^. #name) (node ^. #shadowed) @?= ["two", "one"]
          Nothing -> fail "expected the port resolution node",
      testCase "rightmost-wins law holds for every three-source ordering" $
        mapM_ checkOrdering (permutations lawSources),
      testCase "malformed winner does not fall back" $ do
        let lower = treeSource "lower" (RawNumber 8080) Map.empty
            higher = treeSource "higher" (RawText "not-a-port") Map.empty
        case resolve defaultResolveOptions [lower, higher] (required portSetting) of
          Left errors -> case NonEmpty.toList errors of
            [DecodeError problem] -> do
              problem ^. #key @?= servicePort
              problem ^. #origin . #name @?= "higher"
            _ -> fail "expected one decode error"
          Right _ -> fail "expected the malformed winner to fail",
      testCase "arrays replace rather than concatenate" $ do
        let lower = arraySource "lower" ["one", "two"]
            higher = arraySource "higher" ["three"]
        result <- expectSuccess (resolve defaultResolveOptions [lower, higher] (required hostsSetting))
        result ^. #value @?= ["three"],
      testCase "unknown keys warn by default and can be promoted" $ do
        let values =
              RawObject
                ( Map.fromList
                    [ ("known", RawText "yes"),
                      ("typo", RawText "unused")
                    ]
                )
            input = source "document" (FileSource "memory") values
            declaration = required knownSetting
        result <- expectSuccess (resolve defaultResolveOptions [input] declaration)
        length (result ^. #warnings) @?= 1
        case result ^. #warnings of
          [UnknownKeyWarning problem] -> problem ^. #key @?= typoKey
          _ -> fail "expected one unknown-key warning"
        let strictOptions = ResolveOptions {unknownKeyPolicy = RejectUnknownKeys}
        case resolve strictOptions [input] declaration of
          Left errors -> case NonEmpty.toList errors of
            [UnknownKeyError problem] -> problem ^. #key @?= typoKey
            _ -> fail "expected one strict unknown-key error"
          Right _ -> fail "strict mode should reject the unknown key",
      testCase "independent applicative errors accumulate in declaration order" $ do
        case resolve defaultResolveOptions [] serviceConfig of
          Left errors ->
            fmap errorKey (NonEmpty.toList errors)
              @?= [serviceHost, servicePort]
          Right _ -> fail "expected both required settings to be missing",
      testCase "unselected selective branch is traced without errors" $ do
        let development = environmentSource "development"
        result <- expectSuccess (resolve defaultResolveOptions [development] productionPassword)
        result ^. #value @?= Nothing
        case result ^. #report . #nodes . at databasePassword of
          Just node -> node ^. #outcome @?= NotSelected
          Nothing -> fail "expected a not-selected password node"
        case result ^. #report . #branches of
          [branch] -> branch ^. #selected @?= False
          _ -> fail "expected one selective branch trace",
      testCase "selected selective branch reports its missing requirement" $ do
        case resolve defaultResolveOptions [environmentSource "production"] productionPassword of
          Left errors -> fmap errorKey (NonEmpty.toList errors) @?= [databasePassword]
          Right _ -> fail "production should require a password",
      testCase "structural conflicts are rejected even under an unselected branch" $ do
        let development = environmentSource "development"
            conflicting =
              source
                "conflicting"
                (FileSource "memory")
                (RawObject (Map.singleton "database" (RawText "not-an-object")))
        case resolve defaultResolveOptions [development, conflicting] productionPassword of
          Left errors -> case NonEmpty.toList errors of
            [StructuralConflict structuralError] ->
              structuralError ^. #key @?= databasePassword
            _ -> fail "expected one structural conflict"
          Right _ -> fail "source shape validation should fail"
    ]

checkOrdering :: [(Int, Source)] -> IO ()
checkOrdering orderedSources = do
  result <-
    expectSuccess
      (resolve defaultResolveOptions (fmap snd orderedSources) (required portSetting))
  result ^. #value @?= fst (last orderedSources)

lawSources :: [(Int, Source)]
lawSources =
  [ (1001, treeSource "one" (RawNumber 1001) Map.empty),
    (2002, treeSource "two" (RawNumber 2002) Map.empty),
    (3003, treeSource "three" (RawNumber 3003) Map.empty)
  ]

expectSuccess :: Either (NonEmpty ConfigError) a -> IO a
expectSuccess = \case
  Left _ -> fail "expected successful resolution"
  Right value -> pure value

errorKey :: ConfigError -> Key
errorKey = \case
  MissingRequired problem -> problem ^. #key
  DecodeError problem -> problem ^. #key
  StructuralConflict problem -> problem ^. #key
  UnknownKeyError problem -> problem ^. #key
  DefaultError problem -> problem ^. #key
  DefaultCycle _ -> error "a cycle has no single setting key"

serviceConfig :: Config (Text, Int)
serviceConfig = (,) <$> required hostSetting <*> required portSetting

productionPassword :: Config (Maybe Text)
productionPassword = select selector branch
  where
    selector =
      (\environment -> if environment == "production" then Left () else Right Nothing)
        <$> required environmentSetting
    branch = (\password _ -> Just password) <$> required passwordSetting

hostSetting :: Setting Text
hostSetting = publicSetting serviceHost "Service host" textDecoder

portSetting :: Setting Int
portSetting = publicSetting servicePort "Service port" boundedIntegralDecoder

hostsSetting :: Setting [Text]
hostsSetting = publicSetting serviceHosts "Service hosts" textArrayDecoder

knownSetting :: Setting Text
knownSetting = publicSetting knownKey "Known value" textDecoder

environmentSetting :: Setting Text
environmentSetting = publicSetting runtimeEnvironment "Runtime environment" textDecoder

passwordSetting :: Setting Text
passwordSetting = secretSetting databasePassword "Database password" textDecoder

textArrayDecoder :: Decoder [Text]
textArrayDecoder = decoder $ \key -> \case
  RawArray values -> traverse (decodeOne key) values
  _ -> Left (decodeFailure key "array of text")
  where
    decodeOne _ (RawText value) = Right value
    decodeOne key _ = Left (decodeFailure key "array of text")

layeredSources :: [Source]
layeredSources =
  [ treeSource "built-in" (RawNumber 8080) (Map.singleton "host" (RawText "built-in.example")),
    source
      "file"
      (FileSource "memory")
      (RawObject (Map.singleton "service" (RawObject (Map.singleton "host" (RawText "file.example"))))),
    treeSource "environment" (RawNumber 443) Map.empty
  ]

treeSource :: Text -> RawValue -> Map Text RawValue -> Source
treeSource name portValue extraServiceValues =
  source
    name
    (CustomSource "test")
    ( RawObject
        ( Map.singleton
            "service"
            (RawObject (extraServiceValues & at "port" ?~ portValue))
        )
    )

arraySource :: Text -> [Text] -> Source
arraySource name values =
  source
    name
    (CustomSource "test")
    ( RawObject
        ( Map.singleton
            "service"
            (RawObject (Map.singleton "hosts" (RawArray (fmap RawText values))))
        )
    )

environmentSource :: Text -> Source
environmentSource value =
  source
    "environment"
    EnvironmentSource
    ( RawObject
        ( Map.singleton
            "runtime"
            (RawObject (Map.singleton "environment" (RawText value)))
        )
    )

serviceHost :: Key
serviceHost = validKey "service.host"

servicePort :: Key
servicePort = validKey "service.port"

serviceHosts :: Key
serviceHosts = validKey "service.hosts"

runtimeEnvironment :: Key
runtimeEnvironment = validKey "runtime.environment"

databasePassword :: Key
databasePassword = validKey "database.password"

knownKey :: Key
knownKey = validKey "known"

typoKey :: Key
typoKey = validKey "typo"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
