module Settei.YamlTest (tests) where

import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Ratio ((%))
import Data.Text qualified as Text
import Paths_settei_yaml qualified as Paths
import Settei
import Settei.Prelude
import Settei.Yaml
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Yaml"
    [ testCase "nested mappings become segmented keys with exact locations" $ do
        input <- expectSource "service:\n  http:\n    host: api.internal\n    port: 8080\n"
        host <- expectCandidate serviceHttpHost input
        assertBool "host did not remain text" (candidateValue host == RawText "api.internal")
        host ^. to candidateOrigin . #name @?= "application"
        host ^? to candidateOrigin . #location . _Just . #path @?= Just "application.yaml"
        host ^? to candidateOrigin . #location . _Just . #line @?= Just (Just 3)
        host ^? to candidateOrigin . #location . _Just . #column @?= Just (Just 11)
        port <- expectCandidate serviceHttpPort input
        assertBool "port did not remain numeric" (candidateValue port == RawNumber 8080),
      testCase "explicit null remains a present candidate" $ do
        input <- expectSource "service:\n  optional: null\n"
        found <- expectCandidate serviceOptional input
        assertBool "explicit null became absence" (candidateValue found == RawNull),
      testCase "large integers, decimals, booleans, and arrays retain portable meaning" $ do
        input <-
          expectSource
            "limits:\n  huge: 123456789012345678901234567890\n  ratio: 1.25\nfeature:\n  enabled: true\n  names: [one, two]\n"
        huge <- expectCandidate hugeNumber input
        assertBool
          "large integer lost precision"
          (candidateValue huge == RawNumber 123456789012345678901234567890)
        ratio <- expectCandidate ratioNumber input
        assertBool "decimal lost precision" (candidateValue ratio == RawNumber (5 % 4))
        enabled <- expectCandidate featureEnabled input
        assertBool "boolean was not typed" (candidateValue enabled == RawBool True)
        names <- expectCandidate featureNames input
        assertBool
          "array shape changed"
          (candidateValue names == RawArray [RawText "one", RawText "two"]),
      testCase "Norway regression: YAML 1.1 boolean spellings remain text" $ do
        input <-
          expectSource
            "country: no\nfeature:\n  legacy: yes\n  toggle: on\n  kill: off\n  short: y\n  tiny: n\n"
        country <- expectCandidate countryKey input
        assertCandidateValue "country did not remain text" country (RawText "no")
        legacy <- expectCandidate legacyKey input
        assertCandidateValue "legacy did not remain text" legacy (RawText "yes")
        toggle <- expectCandidate toggleKey input
        assertCandidateValue "toggle did not remain text" toggle (RawText "on")
        kill <- expectCandidate killKey input
        assertCandidateValue "kill did not remain text" kill (RawText "off")
        short <- expectCandidate shortKey input
        assertCandidateValue "short did not remain text" short (RawText "y")
        tiny <- expectCandidate tinyKey input
        assertCandidateValue "tiny did not remain text" tiny (RawText "n"),
      testCase "core-schema booleans parse case-insensitively and quoted true stays text" $ do
        input <- expectSource "plain: true\nupper: TRUE\nnegative: false\nquoted: \"true\"\n"
        plain <- expectCandidate plainKey input
        assertCandidateValue "plain true was not boolean" plain (RawBool True)
        upper <- expectCandidate upperKey input
        assertCandidateValue "uppercase true was not boolean" upper (RawBool True)
        negative <- expectCandidate negativeKey input
        assertCandidateValue "plain false was not boolean" negative (RawBool False)
        quoted <- expectCandidate quotedKey input
        assertCandidateValue "quoted true did not remain text" quoted (RawText "true"),
      testCase "higher YAML overrides leaves and replaces arrays wholesale" $ do
        low <- expectNamedSource "low" "service:\n  host: old.internal\n  port: 7000\n  names: [one, two]\n"
        high <- expectNamedSource "high" "service:\n  port: 9000\n  names: [three]\n"
        let result =
              resolve
                defaultResolveOptions
                [low, high]
                ((,,) <$> required hostSetting <*> required portSetting <*> required namesSetting)
        value <- expectResolution result
        value @?= ("old.internal", 9000, ["three"])
        case result ^. #report . #nodes . at servicePort of
          Just node -> do
            node ^. #origin . _Just . #name @?= "high"
            fmap (^. #name) (node ^. #shadowed) @?= ["low"]
          Nothing -> fail "expected resolved YAML port provenance",
      testCase "dotted keys fail instead of becoming implicit nesting" $ do
        problem <- expectError "service.port: 8080\n"
        yamlErrorCategory problem @?= YamlDottedKey
        yamlErrorContext problem @?= "$.service.port",
      testCase "special floating values fail instead of becoming text" $ do
        problem <- expectError "service:\n  ratio: !!float .inf\n"
        yamlErrorCategory problem @?= YamlInvalidScalar,
      testCase "invalid UTF-8 fails without retaining source bytes" $ do
        let invalid = ByteString.pack [115, 101, 114, 118, 105, 99, 101, 58, 32, 255]
        case decodeYamlSource sourceOptions invalid of
          Left errors -> do
            let problem = NonEmpty.head errors
            assertBool
              "unexpected invalid UTF-8 category"
              (yamlErrorCategory problem `elem` [YamlSyntaxError, YamlInvalidScalar])
          Right _ -> fail "expected invalid UTF-8 to fail",
      testCase "mounted Secret metadata remains visible while its setting is redacted" $ do
        let reference = kubernetesRef SecretObject (Just "production") "database-config" (Just "config.yaml")
            options = fromKubernetesMountedFile reference sourceOptions
        input <- expectSourceWith options ("database:\n  password: " <> Text.unpack secretSentinel <> "\n")
        let result = resolve defaultResolveOptions [input] (required passwordSetting)
        _ <- expectResolution result
        let textOutput = renderResolutionText (result ^. #report)
            jsonOutput = renderResolutionJson (result ^. #report)
        assertBool "secret reached text output" (not (secretSentinel `Text.isInfixOf` textOutput))
        assertBool "secret reached JSON output" (not (secretSentinel `Text.isInfixOf` jsonOutput))
        assertBool "Secret metadata was omitted" ("database-config" `Text.isInfixOf` textOutput),
      testCase "readYamlSource reports IO failures with the requested path" $ do
        result <- readYamlSource (yamlSourceOptions "missing") "test/fixtures/does-not-exist.yaml"
        case result of
          Left errors -> do
            let problem = NonEmpty.head errors
            yamlErrorCategory problem @?= YamlIoError
            yamlErrorPath problem @?= Just "test/fixtures/does-not-exist.yaml"
          Right _ -> fail "expected missing YAML file to fail",
      testCase "readYamlSource loads a fixture and records its actual path" $ do
        fixturePath <- Paths.getDataFileName "test/fixtures/characterization/nested.yaml"
        result <- readYamlSource (yamlSourceOptions "fixture") fixturePath
        input <- case result of
          Left errors -> fail (show errors)
          Right sourceValue -> pure sourceValue
        host <- expectCandidate serviceHttpHost input
        host ^? to candidateOrigin . #location . _Just . #path @?= Just (Text.pack fixturePath),
      testCase "syntax errors never echo an earlier secret scalar" $ do
        let input =
              "database:\n  password: "
                <> Text.unpack secretSentinel
                <> "\nbroken: [one, two\n"
        case decodeYamlSource sourceOptions (ByteString8.pack input) of
          Left errors ->
            assertBool
              "secret reached structured YAML errors"
              (not (secretSentinel `Text.isInfixOf` Text.pack (show errors)))
          Right _ -> fail "expected malformed YAML to fail",
      testCase "top-level sequences fail because configuration keys require a mapping" $ do
        problem <- expectError "[one, two]\n"
        yamlErrorCategory problem @?= YamlTopLevelType
    ]

sourceOptions :: YamlSourceOptions
sourceOptions = withYamlSourcePath "application.yaml" (yamlSourceOptions "application")

expectSource :: String -> IO Source
expectSource = expectSourceWith sourceOptions

expectNamedSource :: Text -> String -> IO Source
expectNamedSource name =
  expectSourceWith (withYamlSourcePath (Text.unpack name <> ".yaml") (yamlSourceOptions name))

expectSourceWith :: YamlSourceOptions -> String -> IO Source
expectSourceWith options input =
  case decodeYamlSource options (ByteString8.pack input) of
    Left errors -> fail (show errors)
    Right value -> pure value

expectError :: String -> IO YamlSourceError
expectError input = case decodeYamlSource sourceOptions (ByteString8.pack input) of
  Left errors -> pure (NonEmpty.head errors)
  Right _ -> fail "expected YAML decoding to fail"

expectCandidate :: Key -> Source -> IO Candidate
expectCandidate key input = case lookupSource key input of
  Right (Just found) -> pure found
  _ -> fail "expected YAML candidate"

assertCandidateValue :: String -> Candidate -> RawValue -> IO ()
assertCandidateValue message found expected =
  assertBool message (candidateValue found == expected)

expectResolution :: ResolveResult a -> IO a
expectResolution result = case result ^. #answer of
  Left _ -> fail "expected YAML resolution to succeed"
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

serviceHttpHost, serviceHttpPort, serviceHost, servicePort, serviceNames, serviceOptional, hugeNumber, ratioNumber, featureEnabled, featureNames, databasePassword, countryKey, legacyKey, toggleKey, killKey, shortKey, tinyKey, plainKey, upperKey, negativeKey, quotedKey :: Key
serviceHttpHost = validKey "service.http.host"
serviceHttpPort = validKey "service.http.port"
serviceHost = validKey "service.host"
servicePort = validKey "service.port"
serviceNames = validKey "service.names"
serviceOptional = validKey "service.optional"
hugeNumber = validKey "limits.huge"
ratioNumber = validKey "limits.ratio"
featureEnabled = validKey "feature.enabled"
featureNames = validKey "feature.names"
databasePassword = validKey "database.password"
countryKey = validKey "country"
legacyKey = validKey "feature.legacy"
toggleKey = validKey "feature.toggle"
killKey = validKey "feature.kill"
shortKey = validKey "feature.short"
tinyKey = validKey "feature.tiny"
plainKey = validKey "plain"
upperKey = validKey "upper"
negativeKey = validKey "negative"
quotedKey = validKey "quoted"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

secretSentinel :: Text
secretSentinel = "never-render-this-yaml-secret"
