module Main (main) where

import Settei.Example.ConformanceTest qualified as ConformanceTest
import Test.Tasty (defaultMain)

main :: IO ()
main = defaultMain ConformanceTest.tests
