module Main (main) where

import Control.Exception (bracket_)
import Settei.DhallTest qualified as DhallTest
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (defaultMain)

main :: IO ()
main =
  withSystemTempDirectory "settei-dhall-cache" $ \cacheDirectory -> do
    previous <- lookupEnv "XDG_CACHE_HOME"
    bracket_
      (setEnv "XDG_CACHE_HOME" cacheDirectory)
      (maybe (unsetEnv "XDG_CACHE_HOME") (setEnv "XDG_CACHE_HOME") previous)
      (defaultMain DhallTest.tests)
