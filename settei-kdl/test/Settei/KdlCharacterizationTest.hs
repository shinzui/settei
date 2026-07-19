module Settei.KdlCharacterizationTest (tests) where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Ratio ((%))
import Data.Text qualified as Text
import Settei
import Settei.Kdl
import Settei.Prelude
import Test.Tasty (TestTree, localOption, mkTimeout, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Kdl.Characterization"
    [ testCase "KDL v2 strings, booleans, null, and exact numbers remain typed" $ do
        input <- expectSource "text \"hello\"\nraw #\"raw text\"#\nflag #true\nempty #null\ninteger 12345678901234567890\ndecimal 1.25\n"
        expectValue "text" input (RawText "hello")
        expectValue "raw" input (RawText "raw text")
        expectValue "flag" input (RawBool True)
        expectValue "empty" input RawNull
        expectValue "integer" input (RawNumber 12345678901234567890)
        expectValue "decimal" input (RawNumber (5 % 4)),
      testCase "duplicate properties remain visible and fail at the second span" $ do
        problem <- expectError "service port=8000 port=9000\n"
        kdlErrorCategory problem @?= KdlDuplicateProperty
        fmap kdlSpanColumn (kdlErrorSpan problem) @?= Just 19
        fmap kdlSpanColumn (kdlErrorRelatedSpan problem) @?= Just 9,
      testCase "node and value type annotations fail explicitly" $ do
        nodeProblem <- expectError "(record)service { port 8080 }\n"
        kdlErrorCategory nodeProblem @?= KdlUnsupportedAnnotation
        valueProblem <- expectError "service (port)8080\n"
        kdlErrorCategory valueProblem @?= KdlUnsupportedAnnotation,
      testCase "non-finite KDL numbers fail instead of being coerced" $ do
        problem <- expectError "ratio #inf\n"
        kdlErrorCategory problem @?= KdlUnsupportedValue,
      testCase "comments and slash-dash remove values before translation" $ do
        input <- expectSource "// comment\nfoo 1 /- 2 3\n/- omitted 4\nbar 5\n"
        expectValue "foo" input (RawArray [RawNumber 1, RawNumber 3])
        expectValue "bar" input (RawNumber 5)
        assertBool
          "slash-dashed node remained in the document"
          (case lookupSource (validKey "omitted") input of Right Nothing -> True; _ -> False),
      testCase "quoted empty and dotted names reach explicit Settei validation" $ do
        emptyProblem <- expectError "\"\" 1\n"
        kdlErrorCategory emptyProblem @?= KdlInvalidName
        dottedProblem <- expectError "\"service.port\" 8080\n"
        kdlErrorCategory dottedProblem @?= KdlInvalidName,
      testCase "syntax failures keep only a one-based header location" $ do
        let sentinel = "never-retain-this-kdl-secret"
            input = "password \"" <> sentinel <> "\"\nservice { broken [\n"
        problem <- expectError input
        kdlErrorCategory problem @?= KdlSyntaxError
        assertBool "syntax error omitted its line" (maybe False ((> 0) . kdlSpanLine) (kdlErrorSpan problem))
        assertBool "syntax error omitted its column" (maybe False ((> 0) . kdlSpanColumn) (kdlErrorSpan problem))
        assertBool
          "syntax error retained the source excerpt"
          (not (sentinel `Text.isInfixOf` Text.pack (show problem))),
      localOption (mkTimeout 10000000) $
        testGroup
          "bounded numeric value conversion"
          [ testCase "huge positive exponents are rejected quickly" $ do
              problem <- expectError "huge 1e1000000000\n"
              expectExponentError "$.huge" problem,
            testCase "huge negative exponents are rejected quickly" $ do
              problem <- expectError "tiny 1e-1000000000\n"
              expectExponentError "$.tiny" problem,
            testCase "positive boundary exponents convert exactly" $ do
              input <- expectSource "edge 1e4096\n"
              expectValue "edge" input (RawNumber (10 ^ (4096 :: Integer) % 1)),
            testCase "negative boundary exponents convert exactly" $ do
              input <- expectSource "edge 1e-4096\n"
              expectValue "edge" input (RawNumber (1 % 10 ^ (4096 :: Integer))),
            testCase "exponents immediately above the bound are rejected" $ do
              problem <- expectError "over 1e4097\n"
              expectExponentError "$.over" problem,
            testCase "ordinary decimals and hex values remain exact" $ do
              input <- expectSource "rate 1.5e-3\nmask 0x1A\ncoefficient 12345678901234567890\n"
              expectValue "rate" input (RawNumber (3 % 2000))
              expectValue "mask" input (RawNumber 26)
              expectValue "coefficient" input (RawNumber 12345678901234567890)
          ]
    ]

sourceOptions :: KdlSourceOptions
sourceOptions = withKdlSourcePath "characterization.kdl" (kdlSourceOptions "characterization")

expectSource :: Text -> IO Source
expectSource input = case decodeKdlSource sourceOptions input of
  Left errors -> fail (show errors)
  Right sourceValue -> pure sourceValue

expectError :: Text -> IO KdlSourceError
expectError input = case decodeKdlSource sourceOptions input of
  Left errors -> pure (NonEmpty.head errors)
  Right _ -> fail "expected KDL decoding to fail"

expectValue :: Text -> Source -> RawValue -> IO ()
expectValue keyText input expected = case lookupSource (validKey keyText) input of
  Right (Just found) -> assertBool "unexpected KDL raw value" (candidateValue found == expected)
  _ -> fail "expected KDL candidate"

expectExponentError :: Text -> KdlSourceError -> IO ()
expectExponentError expectedContext problem = do
  kdlErrorCategory problem @?= KdlUnsupportedValue
  fmap kdlSpanLine (kdlErrorSpan problem) @?= Just 1
  kdlErrorContext problem @?= expectedContext
  kdlErrorMessage problem @?= "numeric value exponent is out of the supported range"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
