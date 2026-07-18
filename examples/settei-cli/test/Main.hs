module Main (main) where

import Settei.Example.CliTest qualified as CliTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = defaultMain (testGroup "Settei.Example.Cli" [CliTest.tests])
