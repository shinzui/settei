module Main (main) where

import Control.Exception (IOException, try)
import Data.ByteString qualified as BS
import Data.Generics.Labels ()
import Data.Text.IO qualified as T
import Options.Applicative qualified as O
import Settei.Preflight
import Settei.Preflight.Request
import Settei.Prelude
import System.Exit (ExitCode (..), exitWith)
import System.IO (hSetEncoding, stderr, stdout, utf8)

main :: IO ()
main = do
  mapM_ (`hSetEncoding` utf8) [stdout, stderr]
  (path, asJson) <-
    O.execParser $
      O.info
        ( (,)
            <$> O.parserOptionGroup "Preflight" (O.strOption (O.long "request" <> O.metavar "PATH" <> O.help "Read a preflight request document"))
            <*> O.parserOptionGroup "Output" (O.switch (O.long "json" <> O.help "Print the versioned JSON report")) O.<**> O.helper
        )
        (O.fullDesc <> O.progDesc "Check proposed inputs with the application's own check command" <> O.failureCode 2)
  readResult <- try (BS.readFile path) :: IO (Either IOException BS.ByteString)
  request <- case readResult of
    Left _ -> abort "request: file could not be read\n"
    Right bytes -> case parsePreflightRequest bytes of Left ps -> abort (renderRequestErrorsText ps); Right r -> pure r
  resolved <- resolveRequest processRequestEnvironment request
  report <- runPreflight (resolved ^. #options) (resolved ^. #role) (resolved ^. #command) (resolved ^. #inputs)
  if asJson then T.putStrLn (renderPreflightReportJson report) else T.putStr (renderPreflightReportText report)
  exitWith $ case report ^. #verdict of
    Pass -> ExitSuccess
    Inconclusive -> ExitFailure 1
    Fail -> ExitFailure (case report ^. #outcome of Rejected _ _ -> 4; _ -> 3)
  where
    abort message = T.hPutStr stderr message >> exitWith (ExitFailure 3)
