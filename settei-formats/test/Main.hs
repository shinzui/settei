module Main (main) where

import Settei.FormatsOptparseTest qualified
import Settei.FormatsTest qualified
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain
    ( testGroup
        "settei-formats"
        [ Settei.FormatsTest.tests,
          Settei.FormatsOptparseTest.tests
        ]
    )
