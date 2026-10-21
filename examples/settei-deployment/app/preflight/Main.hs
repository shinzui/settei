module Main (main) where

import Control.Exception (IOException, try)
import Control.Monad (unless)
import Data.Aeson qualified as A
import Data.ByteString qualified as BS
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Options.Applicative qualified as O
import Settei.Env (EnvName (..))
import Settei.Example.Deployment.Preflight
import Settei.Preflight (RoleLabel (..))
import Settei.Preflight.Request (renderPreflightRequestJson)
import Settei.Prelude
import System.Exit (ExitCode (..), exitWith)
import System.IO (hSetEncoding, stderr, stdout, utf8)

data Cli = Cli !FilePath !Text !Text !Text !FilePath !Text ![(EnvName, Text)] ![(EnvName, Text)]

main :: IO ()
main = do
  mapM_ (`hSetEncoding` utf8) [stdout, stderr]
  Cli path deployment container role exe prefix public secret <- O.execParser (O.info (parser O.<**> O.helper) (O.fullDesc <> O.failureCode 2))
  unless (length public == Map.size (Map.fromList public) && length secret == Map.size (Map.fromList secret)) (abort 2 "duplicate synthetic substitution")
  bytes <- try (BS.readFile path) :: IO (Either IOException BS.ByteString)
  manifest <- case bytes of Left _ -> abort 3 "manifest: file could not be read"; Right b -> case A.eitherDecodeStrict b of Left _ -> abort 3 "manifest: invalid JSON"; Right v -> pure v
  let options = extractionOptions deployment (RoleLabel role) exe & #containerName .~ container & #secretPrefix .~ prefix & #syntheticPublic .~ Map.fromList public & #syntheticSecret .~ Map.fromList secret
  case extractPreflightRequest options manifest of
    Left e -> abort 3 (renderExtractionErrorText e)
    Right (request, notes) -> TIO.putStrLn (renderPreflightRequestJson request) >> mapM_ (TIO.hPutStrLn stderr) notes
  where
    abort n message = TIO.hPutStrLn stderr message >> exitWith (ExitFailure n)
    parser =
      O.parserOptionGroup
        "Manifest"
        ( Cli
            <$> O.strOption (O.long "manifest" <> O.metavar "PATH")
            <*> O.strOption (O.long "deployment" <> O.metavar "NAME")
            <*> O.strOption (O.long "container" <> O.value "check-config" <> O.showDefault <> O.metavar "NAME")
            <*> O.strOption (O.long "role" <> O.metavar "LABEL")
            <*> O.strOption (O.long "executable" <> O.metavar "PATH")
            <*> O.strOption (O.long "secret-prefix" <> O.value "SETTEI_PREFLIGHT_SECRET_" <> O.metavar "TEXT")
            <*> O.many (O.option assignment (O.long "synthetic" <> O.metavar "NAME=VALUE" <> O.help "Fake public value for an unresolved input"))
            <*> O.many (O.option assignment (O.long "synthetic-secret" <> O.metavar "NAME=VALUE" <> O.help "Fake secret value; real secrets must use references"))
        )
    assignment = O.eitherReader $ \raw -> case T.breakOn "=" (T.pack raw) of
      (n, v) | not (T.null n) && not (T.null v) -> Right (EnvName n, T.drop 1 v)
      _ -> Left "expected NAME=VALUE"
