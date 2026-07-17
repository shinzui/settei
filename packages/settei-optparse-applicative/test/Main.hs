module Main (main) where

import Settei.OptparseTest qualified
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = defaultMain (testGroup "settei-optparse-applicative" [Settei.OptparseTest.tests])
