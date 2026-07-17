module Main (main) where

import Settei.EnvTest qualified
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = defaultMain (testGroup "settei-env" [Settei.EnvTest.tests])
