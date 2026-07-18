module Settei.YamlCharacterizationTest (tests) where

import Data.ByteString.Char8 qualified as ByteString8
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Settei.Yaml
import Test.Tasty (TestTree, testGroup)
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
        assertBool "syntax error omitted its column" (maybe False (> 0) (yamlErrorColumn problem))
    ]

expectError :: String -> IO YamlSourceError
expectError input =
  case decodeYamlSource (withYamlSourcePath "characterization.yaml" (yamlSourceOptions "characterization")) (ByteString8.pack input) of
    Left errors -> pure (NonEmpty.head errors)
    Right _ -> fail "expected strict YAML characterization to fail"
