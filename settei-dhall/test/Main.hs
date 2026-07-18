module Main (main) where

import Settei.DhallPrototypeTest qualified as DhallPrototypeTest
import Test.Tasty (defaultMain)

main :: IO ()
main = defaultMain DhallPrototypeTest.tests
