module Settei.Preflight.Fixture (fixtureMain) where

import Control.Concurrent (threadDelay)
import Control.Monad (forM_, when)
import Data.List (sort)
import Data.Text qualified
import Data.Text.IO qualified as T
import System.Directory (doesFileExist, getCurrentDirectory)
import System.Environment (getArgs, getEnvironment, lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hFlush, stderr, stdout)

fixtureMain :: IO ()
fixtureMain = do
  args <- getArgs
  behaviour <- lookupEnv "FIXTURE_BEHAVIOUR"
  case behaviour of
    Just "reject" -> die 4 "database.url: required value is missing"
    Just "source-failure" -> die 3 "configuration file: could not be read"
    Just "usage" -> die 2 "usage: fixture --check-config"
    Just "crash" -> die 1 "unexpected failure"
    Just "unicode" -> die 4 "runtime.environment: expected one of «dev»"
    Just "sleep" -> getCurrentDirectory >>= putStrLn >> hFlush stdout >> threadDelay 30000000
    Just "chunks" -> do
      putStr "SECRET-"; hFlush stdout; threadDelay 20000; putStrLn "ACROSS-CHUNKS"
    Just "server-like" ->
      if "--check-config" `elem` args
        then putStrLn "configuration valid"
        else do
          marker <- lookupEnv "FIXTURE_STARTUP_MARKER"
          forM_ marker (\path -> writeFile path "started")
          putStrLn "ready"
    Just "echo" -> do
      env <- getEnvironment
      forM_ (sort env) (\(n, v) -> putStrLn (n <> "=" <> v))
      forM_ args (\a -> T.hPutStrLn stderr (fromString a))
      forM_ args (\a -> do exists <- doesFileExist a; when exists (readFile a >>= putStr))
    _ -> putStrLn "configuration valid"
  where
    die n message = T.hPutStrLn stderr message >> exitWith (ExitFailure n)
    fromString = Data.Text.pack
