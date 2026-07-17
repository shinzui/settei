module Settei.ValueTest (tests) where

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
        Left decodeFailure ->
          assertBool
            "rendered failure leaked the rejected secret"
            (not (Text.isInfixOf "supersecret" (renderDecodeFailure decodeFailure)))
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

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
