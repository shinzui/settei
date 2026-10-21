module Main (main) where

import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Options.Applicative qualified as Options
import Settei.Env (envSnapshot)
import Settei.Example.Deployment
import System.Environment qualified as Environment
import System.Exit (ExitCode (..), exitWith)
import System.IO qualified as IO

main :: IO ()
main = do
  options <- Options.execParser (deploymentParserInfo Server)
  result <-
    runDeploymentWithEnvironment
      Server
      ( do
          environment <- Environment.getEnvironment
          pure (envSnapshot (fmap (\(name, value) -> (Text.pack name, Text.pack value)) environment))
      )
      options
  TextIO.putStr (deploymentStandardOutput result)
  TextIO.hPutStr IO.stderr (deploymentStandardError result)
  exitWith (if deploymentExitCode result == 0 then ExitSuccess else ExitFailure (deploymentExitCode result))
