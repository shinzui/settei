module Settei.YamlCharacterizationTest (tests) where

import Data.ByteString.Char8 qualified as ByteString8
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Ratio ((%))
import Data.Text (Text)
import Settei
import Settei.Yaml
import Test.Tasty (TestTree, localOption, mkTimeout, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Yaml.Characterization"
    [ testCase "duplicate block mapping keys fail at the second key" $ do
        problem <- expectError "service:\n  port: 8000\n  port: 9000\n"
        yamlErrorCategory problem @?= YamlDuplicateKey
        yamlErrorLine problem @?= Just 3
        yamlErrorContext problem @?= "$.service.port",
      testCase "duplicate flow mapping keys fail at the second key" $ do
        problem <- expectError "service: {port: 8000, port: 9000}\n"
        yamlErrorCategory problem @?= YamlDuplicateKey
        yamlErrorLine problem @?= Just 1,
      testCase "multiple documents fail instead of dropping a document" $ do
        problem <- expectError "---\nservice: one\n---\nservice: two\n"
        yamlErrorCategory problem @?= YamlMultipleDocuments
        yamlErrorLine problem @?= Just 3,
      testCase "aliases and anchors fail explicitly" $ do
        anchorProblem <- expectError "shared: &shared\n  port: 8000\n"
        yamlErrorCategory anchorProblem @?= YamlUnsupportedFeature
        aliasProblem <- expectError "service: *shared\n"
        yamlErrorCategory aliasProblem @?= YamlUnsupportedFeature,
      testCase "merge keys fail explicitly" $ do
        problem <- expectError "service:\n  <<: {port: 8000}\n"
        yamlErrorCategory problem @?= YamlUnsupportedFeature
        yamlErrorContext problem @?= "$.service.<<",
      testCase "custom tags fail explicitly" $ do
        problem <- expectError "service: !custom value\n"
        yamlErrorCategory problem @?= YamlUnsupportedFeature,
      testCase "non-string mapping keys fail" $ do
        problem <- expectError "1: value\n"
        yamlErrorCategory problem @?= YamlNonStringKey,
      testCase "syntax failures retain one-based parser marks" $ do
        problem <- expectError "service: [one, two\n"
        yamlErrorCategory problem @?= YamlSyntaxError
        assertBool "syntax error omitted its line" (maybe False (> 0) (yamlErrorLine problem))
        assertBool "syntax error omitted its column" (maybe False (> 0) (yamlErrorColumn problem)),
      localOption (mkTimeout 10000000) $
        testGroup
          "bounded numeric scalar conversion"
          [ testCase "huge positive exponents are rejected quickly" $ do
              problem <- expectError "huge: 1e1000000000\n"
              expectExponentError "$.huge" problem,
            testCase "huge negative exponents are rejected quickly" $ do
              problem <- expectError "tiny: 1e-1000000000\n"
              expectExponentError "$.tiny" problem,
            testCase "float-tagged numbers apply the exponent bound" $ do
              problem <- expectError "huge: !!float 1e1000000000\n"
              expectExponentError "$.huge" problem,
            testCase "integer-tagged numbers apply the exponent bound" $ do
              problem <- expectError "huge: !!int 1e1000000000\n"
              expectExponentError "$.huge" problem,
            testCase "positive boundary exponents convert exactly" $ do
              input <- expectSource "edge: 1e4096\n"
              expectValue "edge" input (RawNumber (10 ^ (4096 :: Integer) % 1)),
            testCase "negative boundary exponents convert exactly" $ do
              input <- expectSource "edge: 1e-4096\n"
              expectValue "edge" input (RawNumber (1 % 10 ^ (4096 :: Integer))),
            testCase "exponents immediately above the bound are rejected" $ do
              problem <- expectError "over: 1e4097\n"
              expectExponentError "$.over" problem,
            testCase "ordinary decimals, hex, octal, and integers remain exact" $ do
              input <- expectSource "rate: 1.5e-3\nmask: 0x1A\nmode: 0o17\nport: 8080\n"
              expectValue "rate" input (RawNumber (3 % 2000))
              expectValue "mask" input (RawNumber 26)
              expectValue "mode" input (RawNumber 15)
              expectValue "port" input (RawNumber 8080)
          ]
    ]

sourceOptions :: YamlSourceOptions
sourceOptions = withYamlSourcePath "characterization.yaml" (yamlSourceOptions "characterization")

expectSource :: String -> IO Source
expectSource input =
  case decodeYamlSource sourceOptions (ByteString8.pack input) of
    Left errors -> fail (show errors)
    Right sourceValue -> pure sourceValue

expectError :: String -> IO YamlSourceError
expectError input =
  case decodeYamlSource sourceOptions (ByteString8.pack input) of
    Left errors -> pure (NonEmpty.head errors)
    Right _ -> fail "expected strict YAML characterization to fail"

expectValue :: Text -> Source -> RawValue -> IO ()
expectValue keyText input expected = case lookupSource (validKey keyText) input of
  Right (Just found) -> assertBool "unexpected YAML raw value" (candidateValue found == expected)
  _ -> fail "expected YAML candidate"

expectExponentError :: Text -> YamlSourceError -> IO ()
expectExponentError expectedContext problem = do
  yamlErrorCategory problem @?= YamlInvalidScalar
  yamlErrorLine problem @?= Just 1
  yamlErrorContext problem @?= expectedContext
  yamlErrorMessage problem @?= "numeric scalar exponent is out of the supported range"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
