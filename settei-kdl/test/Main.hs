module Main (main) where

import Settei.KdlCharacterizationTest qualified as CharacterizationTest
import Settei.KdlTest qualified as KdlTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = defaultMain (testGroup "settei-kdl" [CharacterizationTest.tests, KdlTest.tests])
