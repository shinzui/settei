module Settei.ValueTest (tests) where

import Data.Int (Int16)
import Data.Ratio ((%))
import Data.Text qualified as Text
import Settei
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Value"
    [ testCase "text values decode" $
        decodeSetting publicText (RawText "hello") @?= Right "hello",
      testCase "textual booleans decode case-insensitively" $
        decodeSetting publicBoolean (RawText "TRUE") @?= Right True,
      testCase "bounded integral values decode" $
        decodeSetting publicInteger (RawText "42") @?= Right (42 :: Int),
      testCase "explicit enumerations decode" $
        decodeSetting environment (RawText "production") @?= Right Production,
      testCase "secret decoder failures omit rejected values" $ case decodeSetting secretText (RawText "supersecret") of
        Right _ -> fail "expected decoding to fail"
        Left failureValue ->
          assertBool
            "rendered failure leaked the rejected secret"
            (not (Text.isInfixOf "supersecret" (renderDecodeFailure failureValue))),
      testCase "fmap maps a successful decode" $
        runDecoder (Text.toUpper <$> textDecoder) exampleKey (RawText "hello")
          @?= Right "HELLO",
      testCase "fmap passes failures through unchanged" $
        case runDecoder (Text.toUpper <$> textDecoder) exampleKey (RawBool True) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue -> decodeFailureExpected failureValue @?= "text",
      testCase "listDecoder decodes arrays element-wise" $
        runDecoder (listDecoder textDecoder) exampleKey (RawArray [RawText "a", RawText "b"])
          @?= Right ["a", "b"],
      testCase "listDecoder rejects non-arrays" $
        case runDecoder (listDecoder textDecoder) exampleKey (RawText "a") of
          Right _ -> fail "expected decoding to fail"
          Left failureValue -> decodeFailureExpected failureValue @?= "an array",
      testCase "listDecoder wraps element expectations" $
        case runDecoder (listDecoder textDecoder) exampleKey (RawArray [RawText "a", RawBool True]) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue -> decodeFailureExpected failureValue @?= "an array of text",
      testCase "nonEmptyDecoder decodes non-empty arrays" $
        runDecoder (nonEmptyDecoder textDecoder) exampleKey (RawArray [RawText "a", RawText "b"])
          @?= Right ("a" :| ["b"]),
      testCase "nonEmptyDecoder rejects empty arrays" $
        case runDecoder (nonEmptyDecoder textDecoder) exampleKey (RawArray []) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue -> decodeFailureExpected failureValue @?= "a non-empty array",
      testCase "parsedDecoder applies the parser" $
        runDecoder portFromText exampleKey (RawText "8080") @?= Right (8080 :: Int),
      testCase "parsedDecoder reports only the caller's expectation" $
        case runDecoder portFromText exampleKey (RawText sentinel) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue ->
            decodeFailureExpected failureValue @?= "a port number",
      testCase "parsedDecoder discards parser messages that echo input" $
        case runDecoder portFromText exampleKey (RawText sentinel) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue ->
            assertBool
              "rendered failure leaked the parser input"
              (not (Text.isInfixOf sentinel (renderDecodeFailure failureValue))),
      testCase "listDecoder element failures never leak the value" $
        case runDecoder (listDecoder boolDecoder) exampleKey (RawArray [RawText sentinel]) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue ->
            assertBool
              "rendered failure leaked the array element"
              (not (Text.isInfixOf sentinel (renderDecodeFailure failureValue))),
      testCase "rationalDecoder accepts numbers and numeric text" $ do
        runDecoder rationalDecoder exampleKey (RawNumber (5 % 2)) @?= Right (5 % 2)
        runDecoder rationalDecoder exampleKey (RawText "2.5") @?= Right (5 % 2)
        runDecoder rationalDecoder exampleKey (RawText "-3") @?= Right (negate 3),
      testCase "rationalDecoder rejects trailing garbage" $
        case runDecoder rationalDecoder exampleKey (RawText "1.5x") of
          Right _ -> fail "expected decoding to fail"
          Left failureValue -> decodeFailureExpected failureValue @?= "a number",
      testCase "doubleDecoder rounds through the exact rational" $ do
        runDecoder doubleDecoder exampleKey (RawText "2.5") @?= Right 2.5
        runDecoder doubleDecoder exampleKey (RawNumber (1 % 10)) @?= Right 0.1,
      testCase "boundedIntegralDecoder reports its range" $
        case runDecoder (boundedIntegralDecoder :: Decoder Int16) exampleKey (RawNumber 100000) of
          Right _ -> fail "expected decoding to fail"
          Left failureValue ->
            decodeFailureExpected failureValue @?= "integer between -32768 and 32767"
    ]

data Environment = Development | Production
  deriving stock (Generic, Eq, Show)

publicText :: Setting Text
publicText = publicSetting exampleKey "Example text" textDecoder

secretText :: Setting Bool
secretText = secretSetting exampleKey "Example secret" boolDecoder

publicBoolean :: Setting Bool
publicBoolean = publicSetting exampleKey "Example boolean" boolDecoder

publicInteger :: Setting Int
publicInteger = publicSetting exampleKey "Example integer" boundedIntegralDecoder

environment :: Setting Environment
environment =
  publicSetting
    exampleKey
    "Runtime environment"
    (enumDecoder [("development", Development), ("production", Production)])

exampleKey :: Key
exampleKey = validKey "example.value"

portFromText :: Decoder Int
portFromText =
  parsedDecoder "a port number" $ \value ->
    case runDecoder (boundedIntegralDecoder :: Decoder Int) exampleKey (RawText value) of
      Right port -> Right port
      Left _ -> Left ("could not parse port from input: " <> value)

sentinel :: Text
sentinel = "s3cr3t\"\\\SOH!☃パス"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
