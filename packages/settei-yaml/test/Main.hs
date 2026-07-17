module Main (main) where

import Settei.YamlCharacterizationTest qualified as CharacterizationTest
import Settei.YamlTest qualified as YamlTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = defaultMain (testGroup "settei-yaml" [CharacterizationTest.tests, YamlTest.tests])
