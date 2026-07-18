module Main (main) where

import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Options.Applicative qualified as Options
import Settei.Env (envSnapshot)
import Settei.Example.Cli
import System.Environment qualified as Environment
import System.Exit (ExitCode (..), exitWith)
import System.IO qualified as IO

main :: IO ()
main = do
  options <- Options.execParser cliParserInfo
  environment <- Environment.getEnvironment
  result <- runCliWithSnapshot (envSnapshot (fmap (\(name, value) -> (Text.pack name, Text.pack value)) environment)) options
  TextIO.putStr (cliStandardOutput result)
  TextIO.hPutStr IO.stderr (cliStandardError result)
  exitWith (if cliExitCode result == 0 then ExitSuccess else ExitFailure (cliExitCode result))
