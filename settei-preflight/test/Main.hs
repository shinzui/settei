module Main (main) where

import Settei.Preflight.Fixture (fixtureMain)
import Settei.PreflightTest (tests)
import System.Environment (lookupEnv)
import Test.Tasty (defaultMain)

main :: IO ()
main = do
  fixture <- lookupEnv "SETTEI_PREFLIGHT_FIXTURE"
  case fixture of Just _ -> fixtureMain; Nothing -> defaultMain tests
