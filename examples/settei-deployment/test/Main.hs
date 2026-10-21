module Main (main) where

import Settei.Example.Deployment.PreflightTest qualified as PreflightTest
import Settei.Example.DeploymentTest qualified as DeploymentTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main = defaultMain (testGroup "Settei.Example.Deployment" [DeploymentTest.tests, PreflightTest.tests])
