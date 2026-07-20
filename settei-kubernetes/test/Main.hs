module Main (main) where

import Settei.KubernetesTest qualified as KubernetesTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = defaultMain (testGroup "settei-kubernetes" [KubernetesTest.tests])
