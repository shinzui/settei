module Main (main) where

import Settei.Example.ServiceTest qualified as ServiceTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = defaultMain (testGroup "Settei.Example.Service" [ServiceTest.tests])
