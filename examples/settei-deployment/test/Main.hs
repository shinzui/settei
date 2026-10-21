module Main (main) where

import Settei.Example.DeploymentTest qualified as DeploymentTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = defaultMain (testGroup "Settei.Example.Deployment" [DeploymentTest.tests])
