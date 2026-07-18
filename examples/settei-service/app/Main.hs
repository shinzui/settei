module Main (main) where

import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Options.Applicative qualified as Options
import Settei.Env (envSnapshot)
import Settei.Example.Service
import System.Environment qualified as Environment
import System.Exit (ExitCode (..), exitWith)
import System.IO qualified as IO

main :: IO ()
main = do
  options <- Options.execParser serviceParserInfo
  environment <- Environment.getEnvironment
  result <-
    runServiceWithSnapshot
      (envSnapshot (fmap (\(name, value) -> (Text.pack name, Text.pack value)) environment))
      options
  TextIO.putStr (serviceStandardOutput result)
  TextIO.hPutStr IO.stderr (serviceStandardError result)
  exitWith (if serviceExitCode result == 0 then ExitSuccess else ExitFailure (serviceExitCode result))
