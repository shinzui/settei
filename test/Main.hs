module Main (main) where

import Settei.ConfigTest qualified as ConfigTest
import Settei.KeyTest qualified as KeyTest
import Settei.ValueTest qualified as ValueTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "Settei"
      [ KeyTest.tests,
        ValueTest.tests,
        ConfigTest.tests
      ]
