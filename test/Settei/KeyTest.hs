module Settei.KeyTest (tests) where

import Settei.Key
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Key"
    [ testCase "dotted keys round-trip" $ do
        (renderKey <$> parseKey "database.pool.size")
          @?= Right "database.pool.size",
      testCase "empty keys are rejected" $
        parseKey "" @?= Left KeyIsEmpty,
      testCase "empty middle segments are rejected" $
        parseKey "database..size" @?= Left KeySegmentIsEmpty,
      testCase "empty leading segments are rejected" $
        parseKey ".database" @?= Left KeySegmentIsEmpty,
      testCase "structural segments cannot contain dots" $
        mkKey ("database.name" :| [])
          @?= Left (KeySegmentContainsDot "database.name")
    ]
