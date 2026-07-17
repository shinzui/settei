module Main (main) where

import Settei.ConfigTest qualified as ConfigTest
import Settei.KeyTest qualified as KeyTest
import Settei.ResolveTest qualified as ResolveTest
import Settei.SourceTest qualified as SourceTest
import Settei.ValueTest qualified as ValueTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "Settei"
      [ KeyTest.tests,
        ValueTest.tests,
        ConfigTest.tests,
        SourceTest.tests,
        ResolveTest.tests
      ]
