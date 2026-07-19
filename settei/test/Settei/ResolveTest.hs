{-# LANGUAGE ImportQualifiedPost #-}

module Settei.ResolveTest (tests) where

import Control.Selective (select)
import Data.Generics.Labels ()
import Data.List (permutations)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Settei
import Settei.Internal.Schema (mergeSensitivity)
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Resolve"
    [ testCase "rightmost source wins per leaf" $ do
        let result = resolve defaultResolveOptions layeredSources serviceConfig
        value <- expectAnswer result
        value @?= ("file.example", 443)
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
        let result = resolve defaultResolveOptions (reverse layeredSources) serviceConfig
        value <- expectAnswer result
        value @?= ("built-in.example", 8080),
      testCase "shadowed origins are ordered from highest to lowest precedence" $ do
        let result = resolve defaultResolveOptions (fmap snd lawSources) (required portSetting)
        _ <- expectAnswer result
        case result ^. #report . #nodes . at servicePort of
          Just node -> fmap (^. #name) (node ^. #shadowed) @?= ["two", "one"]
          Nothing -> fail "expected the port resolution node",
      testCase "rightmost-wins law holds for every three-source ordering" $
        mapM_ checkOrdering (permutations lawSources),
      testCase "malformed winner does not fall back" $ do
        let lower = treeSource "lower" (RawNumber 8080) Map.empty
            higher = treeSource "higher" (RawText "not-a-port") Map.empty
        case (resolve defaultResolveOptions [lower, higher] (required portSetting)) ^. #answer of
          Left errors -> case NonEmpty.toList errors of
            [DecodeError problem] -> do
              problem ^. #key @?= servicePort
              problem ^. #origin . #name @?= "higher"
            _ -> fail "expected one decode error"
          Right _ -> fail "expected the malformed winner to fail",
      testCase "arrays replace rather than concatenate" $ do
        let lower = arraySource "lower" ["one", "two"]
            higher = arraySource "higher" ["three"]
        let result = resolve defaultResolveOptions [lower, higher] (required hostsSetting)
        value <- expectAnswer result
        value @?= ["three"],
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
        let result = resolve defaultResolveOptions [input] declaration
        _ <- expectAnswer result
        length (result ^. #warnings) @?= 1
        case result ^. #warnings of
          [UnknownKeyWarning problem] -> problem ^. #key @?= typoKey
          _ -> fail "expected one unknown-key warning"
        let strictOptions = ResolveOptions {unknownKeyPolicy = RejectUnknownKeys}
        case (resolve strictOptions [input] declaration) ^. #answer of
          Left errors -> case NonEmpty.toList errors of
            [UnknownKeyError problem] -> problem ^. #key @?= typoKey
            _ -> fail "expected one strict unknown-key error"
          Right _ -> fail "strict mode should reject the unknown key",
      testCase "independent applicative errors accumulate in declaration order" $ do
        case (resolve defaultResolveOptions [] serviceConfig) ^. #answer of
          Left errors ->
            fmap errorKey (NonEmpty.toList errors)
              @?= [serviceHost, servicePort]
          Right _ -> fail "expected both required settings to be missing",
      testCase "unselected selective branch is traced without errors" $ do
        let development = environmentSource "development"
        let result = resolve defaultResolveOptions [development] productionPassword
        value <- expectAnswer result
        value @?= Nothing
        case result ^. #report . #nodes . at databasePassword of
          Just node -> node ^. #outcome @?= NotSelected
          Nothing -> fail "expected a not-selected password node"
        case result ^. #report . #branches of
          [branch] -> branch ^. #selected @?= False
          _ -> fail "expected one selective branch trace",
      testCase "selected selective branch reports its missing requirement" $ do
        case (resolve defaultResolveOptions [environmentSource "production"] productionPassword) ^. #answer of
          Left errors -> fmap errorKey (NonEmpty.toList errors) @?= [databasePassword]
          Right _ -> fail "production should require a password",
      testCase "failure report retains evaluated provenance" $ do
        let input = treeSource "only-port" (RawNumber 8080) Map.empty
            result = resolve defaultResolveOptions [input] serviceConfig
        case result ^. #answer of
          Left errors -> fmap errorKey (NonEmpty.toList errors) @?= [serviceHost]
          Right _ -> fail "expected the missing host to fail"
        case result ^. #report . #nodes . at servicePort of
          Just node -> do
            node ^. #outcome @?= Resolved (reportedValue Public (RawNumber 8080))
            fmap (^. #name) (node ^. #origin) @?= Just "only-port"
          Nothing -> fail "expected the evaluated port node"
        case result ^. #report . #nodes . at serviceHost of
          Just node -> node ^. #outcome @?= MissingValue
          Nothing -> fail "expected the missing host node",
      testCase "decode failure keeps the rejected candidate's provenance" $ do
        let lower = treeSource "lower" (RawNumber 8080) Map.empty
            higher = treeSource "higher" (RawText "not-a-port") Map.empty
            result = resolve defaultResolveOptions [lower, higher] (required portSetting)
        case result ^. #answer of
          Left errors -> case NonEmpty.toList errors of
            [DecodeError problem] -> problem ^. #origin . #name @?= "higher"
            _ -> fail "expected one decode error"
          Right _ -> fail "expected the malformed winner to fail"
        case result ^. #report . #nodes . at servicePort of
          Just node -> do
            node ^. #outcome @?= Resolved (reportedValue Public (RawText "not-a-port"))
            fmap (^. #name) (node ^. #origin) @?= Just "higher"
            fmap (^. #name) (node ^. #shadowed) @?= ["lower"]
          Nothing -> fail "expected the rejected winner's report node",
      testCase "failure report completes not-selected settings" $ do
        let declaration = (,) <$> productionPassword <*> required knownSetting
            result = resolve defaultResolveOptions [environmentSource "development"] declaration
        case result ^. #answer of
          Left errors -> fmap errorKey (NonEmpty.toList errors) @?= [knownKey]
          Right _ -> fail "expected the unrelated required setting to fail"
        case result ^. #report . #nodes . at databasePassword of
          Just node -> node ^. #outcome @?= NotSelected
          Nothing -> fail "expected the unselected password node"
        case result ^. #report . #branches of
          [branch] -> branch ^. #selected @?= False
          _ -> fail "expected one unselected branch trace",
      testCase "structural conflicts are rejected even under an unselected branch" $ do
        let development = environmentSource "development"
            conflicting =
              source
                "conflicting"
                (FileSource "memory")
                (RawObject (Map.singleton "database" (RawText "not-an-object")))
        case (resolve defaultResolveOptions [development, conflicting] productionPassword) ^. #answer of
          Left errors -> case NonEmpty.toList errors of
            [StructuralConflict structuralError] ->
              structuralError ^. #key @?= databasePassword
            _ -> fail "expected one structural conflict"
          Right _ -> fail "source shape validation should fail",
      testCase "structural exit still reports schema and warnings" $ do
        let malformed =
              source
                "malformed"
                (FileSource "memory")
                ( RawObject
                    ( Map.fromList
                        [ ("database", RawText "not-an-object"),
                          ("typo", RawText "unused")
                        ]
                    )
                )
            result =
              resolve
                defaultResolveOptions
                [environmentSource "development", malformed]
                productionPassword
        case result ^. #answer of
          Left errors -> case NonEmpty.toList errors of
            [StructuralConflict structuralError] ->
              structuralError ^. #key @?= databasePassword
            _ -> fail "expected one structural conflict"
          Right _ -> fail "source shape validation should fail"
        fmap (^. #key) (reportNodes (result ^. #report))
          @?= [databasePassword, runtimeEnvironment]
        fmap (^. #outcome) (reportNodes (result ^. #report))
          @?= [NotSelected, NotSelected]
        fmap (^. #origin) (reportNodes (result ^. #report)) @?= [Nothing, Nothing]
        result ^. #report . #branches @?= []
        any
          ( \case
              UnknownKeyWarning problem -> problem ^. #key == typoKey
          )
          (result ^. #warnings)
          @?= True,
      testCase "warnings accompany failures and strict mode promotes them" $ do
        let input =
              source
                "document"
                (FileSource "memory")
                (RawObject (Map.singleton "typo" (RawText "unused")))
            warned = resolve defaultResolveOptions [input] (required knownSetting)
        case warned ^. #answer of
          Left errors -> fmap errorKey (NonEmpty.toList errors) @?= [knownKey]
          Right _ -> fail "expected the missing known setting to fail"
        case warned ^. #warnings of
          [UnknownKeyWarning problem] -> problem ^. #key @?= typoKey
          _ -> fail "expected one warning alongside the failure"
        let strictOptions = ResolveOptions {unknownKeyPolicy = RejectUnknownKeys}
            rejected = resolve strictOptions [input] (required knownSetting)
        case rejected ^. #answer of
          Left errors -> fmap errorKey (NonEmpty.toList errors) @?= [knownKey, typoKey]
          Right _ -> fail "strict mode should reject the unknown key"
        rejected ^. #warnings @?= [],
      testCase "conflicting sensitivity declarations fail with a structured error" $ do
        assertSensitivityConflict secretThenPublic
        assertSensitivityConflict publicThenSecret,
      testCase "sensitivity conflicts include unselected selective branches" $
        assertSensitivityConflict selectiveSensitivityConflict,
      testCase "sensitivity conflicts include default dependencies" $
        assertSensitivityConflict defaultSensitivityConflict,
      testCase "effective sensitivity is secret-dominant at the schema seam" $ do
        mergeSensitivity Public Public @?= Public
        mergeSensitivity Public Secret @?= Secret
        mergeSensitivity Secret Public @?= Secret
        mergeSensitivity Secret Secret @?= Secret
        schemaSettingSensitivity (schemaEntry databasePassword (describe secretThenPublic))
          @?= Secret
        schemaSettingSensitivity (schemaEntry databasePassword (describe publicThenSecret))
          @?= Secret,
      testCase "redactReportedValue collapses every retained representation" $
        mapM_
          (\value -> renderReportedValue (redactReportedValue value) @?= "<redacted>")
          [ visibleReportedValue "x",
            derivedReportedValue Public,
            reportedValue Secret (RawText "x")
          ]
    ]

assertSensitivityConflict :: Config a -> IO ()
assertSensitivityConflict declaration = do
  let result = resolve defaultResolveOptions [passwordSource] declaration
  case result ^. #answer of
    Left errors -> case NonEmpty.toList errors of
      [SensitivityConflict problem] -> problem ^. #key @?= databasePassword
      _ -> fail "expected one sensitivity conflict"
    Right _ -> fail "mixed-sensitivity declaration should fail"
  case result ^. #report . #nodes . at databasePassword of
    Just node -> do
      node ^. #sensitivity @?= Secret
      node ^. #outcome @?= NotSelected
      node ^. #origin @?= Nothing
    Nothing -> fail "expected a schema-only conflict report node"

schemaEntry :: Key -> Schema -> SchemaSetting
schemaEntry key schema =
  case filter ((== key) . schemaSettingKey) (schemaPossible schema) of
    [entry] -> entry
    entries -> error ("expected one schema entry, found " <> show (length entries))

checkOrdering :: [(Int, Source)] -> IO ()
checkOrdering orderedSources = do
  let result = resolve defaultResolveOptions (fmap snd orderedSources) (required portSetting)
  value <- expectAnswer result
  value @?= fst (last orderedSources)

lawSources :: [(Int, Source)]
lawSources =
  [ (1001, treeSource "one" (RawNumber 1001) Map.empty),
    (2002, treeSource "two" (RawNumber 2002) Map.empty),
    (3003, treeSource "three" (RawNumber 3003) Map.empty)
  ]

expectAnswer :: ResolveResult a -> IO a
expectAnswer result = case result ^. #answer of
  Left errors -> fail ("expected successful resolution: " <> show errors)
  Right value -> pure value

errorKey :: ConfigError -> Key
errorKey = \case
  MissingRequired problem -> problem ^. #key
  DecodeError problem -> problem ^. #key
  StructuralConflict problem -> problem ^. #key
  UnknownKeyError problem -> problem ^. #key
  DefaultError problem -> problem ^. #key
  DefaultCycle _ -> error "a cycle has no single setting key"
  SensitivityConflict problem -> problem ^. #key

serviceConfig :: Config (Text, Int)
serviceConfig = (,) <$> required hostSetting <*> required portSetting

productionPassword :: Config (Maybe Text)
productionPassword = select selector branch
  where
    selector =
      (\environment -> if environment == "production" then Left () else Right Nothing)
        <$> required environmentSetting
    branch = (\password _ -> Just password) <$> required passwordSetting

secretThenPublic :: Config (Text, Text)
secretThenPublic =
  (,) <$> required passwordSetting <*> required publicPasswordSetting

publicThenSecret :: Config (Text, Text)
publicThenSecret =
  (,) <$> required publicPasswordSetting <*> required passwordSetting

selectiveSensitivityConflict :: Config Text
selectiveSensitivityConflict =
  select
    ((\password -> Right password :: Either () Text) <$> required passwordSetting)
    ((\publicValue () -> publicValue) <$> required publicPasswordSetting)

defaultSensitivityConflict :: Config Text
defaultSensitivityConflict =
  withDefault
    passwordSetting
    ( derivedDefault
        (RuleName "password-from-public-duplicate")
        "Exercise a sensitivity conflict in a default dependency"
        (required publicPasswordSetting)
        id
    )

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

publicPasswordSetting :: Setting Text
publicPasswordSetting = publicSetting databasePassword "Metrics password label" textDecoder

passwordSource :: Source
passwordSource =
  source
    "password"
    (CustomSource "test")
    ( RawObject
        ( Map.singleton
            "database"
            (RawObject (Map.singleton "password" (RawText "sensitive-value")))
        )
    )

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
