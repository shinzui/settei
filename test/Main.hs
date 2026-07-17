module Main (main) where

import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

main :: IO ()
main =
  defaultMain $
    testGroup
      "Settei"
      [testCase "bootstrap" (True @?= True)]
