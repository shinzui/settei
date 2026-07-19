module Settei.KdlTest (tests) where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Paths_settei_kdl qualified as Paths
import Settei
import Settei.Kdl
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Kdl"
    [ testCase "nested nodes become segmented keys with exact spans" $ do
        input <- expectSource "runtime {\n  environment \"production\"\n}\nservice {\n  http {\n    host \"0.0.0.0\"\n    port 8080\n  }\n}\n"
        host <- expectCandidate serviceHttpHost input
        assertBool "host did not remain text" (candidateValue host == RawText "0.0.0.0")
        host ^? to candidateOrigin . #location . _Just . #path @?= Just "application.kdl"
        host ^? to candidateOrigin . #location . _Just . #line @?= Just (Just 6)
        host ^? to candidateOrigin . #location . _Just . #column @?= Just (Just 10)
        host ^. to candidateOrigin . #annotations . at "kdl.span.end-column" @?= Just "18"
        host ^. to candidateOrigin . #annotations . at "kdl.version" @?= Just "2",
      testCase "positional arguments become scalars or arrays and empty nodes become null" $ do
        input <- expectSource "tag \"api\"\ntags \"api\" \"public\"\noptional\n"
        expectRaw tagKey input (RawText "api")
        expectRaw tagsKey input (RawArray [RawText "api", RawText "public"])
        expectRaw optionalKey input RawNull,
      testCase "properties and non-colliding children form one object" $ do
        input <- expectSource "service host=\"api.internal\" {\n  port 8080\n}\n"
        expectRaw serviceHost input (RawText "api.internal")
        expectRaw servicePort input (RawNumber 8080),
      testCase "repeated siblings preserve document order as an array" $ do
        input <-
          expectSource
            "backend {\n  host \"one.internal\"\n  port 8080\n}\nbackend {\n  host \"two.internal\"\n  port 8081\n}\n"
        expectRaw
          backendKey
          input
          ( RawArray
              [ RawObject (Map.fromList [("host", RawText "one.internal"), ("port", RawNumber 8080)]),
                RawObject (Map.fromList [("host", RawText "two.internal"), ("port", RawNumber 8081)])
              ]
          )
        backend <- expectCandidate backendKey input
        backend ^? to candidateOrigin . #location . _Just . #line @?= Just (Just 1)
        backend ^. to candidateOrigin . #annotations . at "kdl.span.end-line" @?= Just "8",
      testCase "arguments mixed with children fail at the node span" $ do
        problem <- expectError "service \"api\" { port 8080 }\n"
        kdlErrorCategory problem @?= KdlMixedNodeShape
        fmap kdlSpanColumn (kdlErrorSpan problem) @?= Just 1,
      testCase "arguments mixed with properties fail at the node span" $ do
        problem <- expectError "service \"api\" port=8080\n"
        kdlErrorCategory problem @?= KdlMixedNodeShape
        fmap kdlSpanColumn (kdlErrorSpan problem) @?= Just 1,
      testCase "property-child collisions report both available locations" $ do
        problem <- expectError "service port=7000 {\n  port 8000\n}\n"
        kdlErrorCategory problem @?= KdlPropertyChildCollision
        kdlErrorContext problem @?= "$.service.port"
        fmap kdlSpanLine (kdlErrorSpan problem) @?= Just 1
        fmap kdlSpanLine (kdlErrorRelatedSpan problem) @?= Just 2,
      testCase "higher KDL overrides leaves and replaces arrays through core" $ do
        low <- expectNamedSource "low" "service { host \"old.internal\"; port 7000; names \"one\" \"two\"; }\n"
        high <- expectNamedSource "high" "service { port 9000; names \"three\" \"four\"; }\n"
        let result =
              resolve
                defaultResolveOptions
                [low, high]
                ((,,) <$> required hostSetting <*> required portSetting <*> required namesSetting)
        value <- expectResolution result
        value @?= ("old.internal", 9000, ["three", "four"])
        case result ^. #report . #nodes . at servicePort of
          Just node -> do
            node ^. #origin . _Just . #name @?= "high"
            fmap (^. #name) (node ^. #shadowed) @?= ["low"]
          Nothing -> fail "expected resolved KDL port provenance",
      testCase "mounted Secret metadata remains visible while its value is redacted" $ do
        let reference = kubernetesRef SecretObject (Just "production") "database-config" (Just "config.kdl")
            options = fromKubernetesMountedFile reference sourceOptions
        input <- expectSourceWith options ("database { password \"" <> secretSentinel <> "\"; }\n")
        let result = resolve defaultResolveOptions [input] (required passwordSetting)
        _ <- expectResolution result
        let textOutput = renderResolutionText (result ^. #report)
            jsonOutput = renderResolutionJson (result ^. #report)
        assertBool "secret reached text output" (not (secretSentinel `Text.isInfixOf` textOutput))
        assertBool "secret reached JSON output" (not (secretSentinel `Text.isInfixOf` jsonOutput))
        assertBool "Secret metadata was omitted" ("database-config" `Text.isInfixOf` textOutput),
      testCase "readKdlSource reports IO failures with the requested path" $ do
        result <- readKdlSource (kdlSourceOptions "missing") "test/fixtures/does-not-exist.kdl"
        case result of
          Left errors -> do
            let problem = NonEmpty.head errors
            kdlErrorCategory problem @?= KdlIoError
            kdlErrorPath problem @?= Just "test/fixtures/does-not-exist.kdl"
          Right _ -> fail "expected missing KDL file to fail",
      testCase "readKdlSource loads a fixture and records its actual path" $ do
        fixturePath <- Paths.getDataFileName "test/fixtures/characterization/nested.kdl"
        result <- readKdlSource (kdlSourceOptions "fixture") fixturePath
        input <- case result of
          Left errors -> fail (show errors)
          Right sourceValue -> pure sourceValue
        host <- expectCandidate serviceHttpHost input
        host ^? to candidateOrigin . #location . _Just . #path @?= Just (Text.pack fixturePath)
    ]

sourceOptions :: KdlSourceOptions
sourceOptions = withKdlSourcePath "application.kdl" (kdlSourceOptions "application")

expectSource :: Text -> IO Source
expectSource = expectSourceWith sourceOptions

expectNamedSource :: Text -> Text -> IO Source
expectNamedSource name =
  expectSourceWith (withKdlSourcePath (Text.unpack name <> ".kdl") (kdlSourceOptions name))

expectSourceWith :: KdlSourceOptions -> Text -> IO Source
expectSourceWith options input = case decodeKdlSource options input of
  Left errors -> fail (show errors)
  Right sourceValue -> pure sourceValue

expectError :: Text -> IO KdlSourceError
expectError input = case decodeKdlSource sourceOptions input of
  Left errors -> pure (NonEmpty.head errors)
  Right _ -> fail "expected KDL decoding to fail"

expectCandidate :: Key -> Source -> IO Candidate
expectCandidate key input = case lookupSource key input of
  Right (Just found) -> pure found
  _ -> fail "expected KDL candidate"

expectRaw :: Key -> Source -> RawValue -> IO ()
expectRaw key input expected = do
  found <- expectCandidate key input
  assertBool "unexpected KDL raw value" (candidateValue found == expected)

expectResolution :: ResolveResult a -> IO a
expectResolution result = case result ^. #answer of
  Left errors -> fail (Text.unpack (renderErrorsText errors))
  Right value -> pure value

hostSetting :: Setting Text
hostSetting = publicSetting serviceHost "Service host" textDecoder

portSetting :: Setting Int
portSetting = publicSetting servicePort "Service port" boundedIntegralDecoder

namesSetting :: Setting [Text]
namesSetting = publicSetting serviceNames "Service names" textListDecoder

passwordSetting :: Setting Text
passwordSetting = secretSetting databasePassword "Database password" textDecoder

textListDecoder :: Decoder [Text]
textListDecoder = decoder $ \key -> \case
  RawArray values -> traverse (textElement key) values
  _ -> Left (decodeFailure key "an array of text")

textElement :: Key -> RawValue -> Either DecodeFailure Text
textElement key = \case
  RawText value -> Right value
  _ -> Left (decodeFailure key "an array of text")

serviceHttpHost, tagKey, tagsKey, optionalKey, serviceHost, servicePort, serviceNames, backendKey, databasePassword :: Key
serviceHttpHost = validKey "service.http.host"
tagKey = validKey "tag"
tagsKey = validKey "tags"
optionalKey = validKey "optional"
serviceHost = validKey "service.host"
servicePort = validKey "service.port"
serviceNames = validKey "service.names"
backendKey = validKey "backend"
databasePassword = validKey "database.password"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

secretSentinel :: Text
secretSentinel = "never-render-this-kdl-secret"
