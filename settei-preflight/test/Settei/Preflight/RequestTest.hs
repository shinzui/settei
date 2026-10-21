module Settei.Preflight.RequestTest (tests) where

import Control.Exception (bracket)
import Control.Monad (forM_)
import Data.Aeson qualified as A
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Generics.Labels ()
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Paths_settei_preflight qualified as Paths
import Settei (Sensitivity (..))
import Settei.Env (EnvName (..))
import Settei.Preflight
import Settei.Preflight.Request
import Settei.Prelude hiding (set)
import System.Environment qualified as Env
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit

parse :: BS.ByteString -> IO PreflightRequest
parse bytes = case parsePreflightRequest bytes of Left e -> assertFailure (T.unpack (renderRequestErrorsText e)); Right r -> pure r

fixtureRequest :: Text -> IO PreflightRequest
fixtureRequest behaviour = do
  exe <- Env.getExecutablePath
  pure (preflightRequest (RoleLabel "request-role") (CheckCommand exe []) [RequestEntry "SETTEI_PREFLIGHT_FIXTURE" (InlineValue "1"), RequestEntry "FIXTURE_BEHAVIOUR" (InlineValue behaviour)] [])

runRequest :: PreflightRequest -> [String] -> IO (ExitCode, Text, Text)
runRequest request args = withSystemTempDirectory "request-cli" $ \root -> do
  let path = root </> "request.json"
  TIO.writeFile path (renderPreflightRequestJson request)
  (code, out, err) <- readProcessWithExitCode "settei-preflight" (["--request", path] <> args) ""
  pure (code, T.pack out, T.pack err)

withEnv :: String -> String -> IO a -> IO a
withEnv n v action = bracket (Env.lookupEnv n <* Env.setEnv n v) (maybe (Env.unsetEnv n) (Env.setEnv n)) (const action)

tests :: TestTree
tests =
  testGroup
    "Settei.Preflight.Request"
    [ testCase "request golden covers every form, round-trips, and renders identically" $ do
        bytes <- Paths.getDataFileName "test/golden/request.json" >>= BS.readFile
        r <- parse bytes
        renderPreflightRequestJson r @?= TE.decodeUtf8 bytes
        reparsed <- parse (TE.encodeUtf8 (renderPreflightRequestJson r))
        assertBool "round-trip changed request" (r == reparsed)
        resolved <- resolveRequest (RequestEnvironment (\(EnvName n) -> pure (if n == "PROVISIONED" then Just "SECRET-REFERENCE-SENTINEL" else Nothing)) (\p -> pure (if p == "available" then Right "FILE-SENTINEL\n" else Left "PRIVATE-ERROR"))) r
        let values = fmap snd (resolved ^. #inputs . #environment)
        assertBool "supplied public missing" (SuppliedValue Public "production" `elem` values)
        assertBool "supplied secret missing" (SuppliedValue Secret "SECRET-REFERENCE-SENTINEL" `elem` values)
        assertBool "synthetic secret missing" (SyntheticValue Secret "fake-credential" "test only" `elem` values)
        assertBool "unresolved missing" (UnresolvedValue "resource output" `elem` values)
        assertBool "unavailable reference missing" (UnavailableSecret "harness environment variable MISSING is not set" `elem` values)
        assertBool "file bytes changed" (ProposedFile (FileName "secrets/token") (SuppliedValue Secret "FILE-SENTINEL\n") `elem` (resolved ^. #inputs . #files))
        resolved ^. #inputs . #notes @?= ["unsupported input"],
      testCase "omitted optional fields retain documented defaults" $ do
        r <- parse "{\"schemaVersion\":1,\"type\":\"settei.preflight-request\",\"role\":\"server\",\"command\":{\"executable\":\"/bin/true\",\"arguments\":[]},\"environment\":[]}"
        resolved <- resolveRequest processRequestEnvironment r
        resolved ^. #inputs . #inherited @?= defaultInherited
        resolved ^. #options @?= defaultPreflightOptions,
      testCase "secret files are strict UTF-8, preserve newlines, and hide IO details" $ withSystemTempDirectory "secret-files" $ \root -> do
        let good = root </> "good"; invalid = root </> "invalid"
        BS.writeFile good "exact\n\n"
        BS.writeFile invalid (BS.pack [255, 254])
        r <- fixtureRequest "accept"
        resolved <- resolveRequest processRequestEnvironment (r & #files .~ [RequestEntry "good" (SecretFromFile good), RequestEntry "invalid" (SecretFromFile invalid), RequestEntry "missing" (SecretFromFile (root </> "missing"))])
        case resolved ^. #inputs . #files of
          [ProposedFile _ (SuppliedValue Secret t), ProposedFile _ (UnavailableSecret _), ProposedFile _ (UnavailableSecret _)] -> t @?= "exact\n\n"
          _ -> assertFailure "incorrect secret-file resolution",
      testGroup
        "strict schema and secret-safe diagnostics"
        [ testCase label $ do
            let bytes = BL.toStrict (A.encode (mutation baseDocument))
            case parsePreflightRequest bytes of
              Left ps -> do
                let message = renderRequestErrorsText ps
                assertBool (T.unpack message) (path `T.isInfixOf` message)
                assertBool "parser leaked secret input" (not (sentinel `T.isInfixOf` message))
              Right _ -> assertFailure "invalid request accepted"
        | (label, path, mutation) <- malformedCases
        ],
      testCase "syntax errors never retain Aeson diagnostics or input text" $ do
        let bytes = "{\"schemaVersion\":1,\"SECRET-PARSER-SENTINEL\": INVALID}"
        case parsePreflightRequest bytes of Left ps -> renderRequestErrorsText ps @?= "request: invalid JSON\n"; Right _ -> assertFailure "bad syntax accepted",
      testGroup
        "executable verdict mapping"
        [ testCase label $ do
            r <- fixtureRequest behaviour
            (code, out, err) <- runRequest (modify r) args
            code @?= expected
            assertBool "expected verdict missing" (verdict `T.isInfixOf` out)
            err @?= ""
        | (label, behaviour, modify, args, expected, verdict) <-
            [ ("pass", "accept", id, [], ExitSuccess, "pass"),
              ("inconclusive", "accept", \r -> r & #environment %~ (<> [RequestEntry "GENERATED" (SyntheticEntry Public "fake" "not provisioned")]), [], ExitFailure 1, "inconclusive"),
              ("rejected", "reject", id, [], ExitFailure 4, "fail"),
              ("missing executable", "accept", \r -> r & #command .~ CheckCommand "/definitely/missing" [], [], ExitFailure 3, "executable not found"),
              ("timeout", "sleep", \r -> r & #timeoutSeconds .~ 1, [], ExitFailure 3, "timed out"),
              ("json", "accept", id, ["--json"], ExitSuccess, "{\"schemaVersion\":1,\"type\":\"settei.preflight\"")
            ]
        ],
      testCase "missing and malformed request files exit 3 with safe stderr" $ do
        (code, _, err) <- readProcessWithExitCode "settei-preflight" ["--request", "/definitely/missing"] ""
        code @?= ExitFailure 3
        err @?= "request: file could not be read\n"
        withSystemTempDirectory "malformed-cli" $ \root -> do
          let path = root </> "bad.json"
          writeFile path "{\"SECRET-PARSER-SENTINEL\": invalid}"
          (badCode, out, badErr) <- readProcessWithExitCode "settei-preflight" ["--request", path] ""
          badCode @?= ExitFailure 3
          out @?= ""
          badErr @?= "request: invalid JSON\n",
      testCase "usage and grouped help" $ do
        (code, _, err) <- readProcessWithExitCode "settei-preflight" [] ""
        code @?= ExitFailure 2
        assertBool "usage missing" ("Usage:" `T.isInfixOf` T.pack err)
        (_, out, _) <- readProcessWithExitCode "settei-preflight" ["--help"] ""
        forM_ ["\nPreflight\n", "\nOutput\n"] (\heading -> assertBool "option group missing" (heading `T.isInfixOf` T.pack out)),
      testCase "real secret references never enter request, CLI reports, or invalid summaries" $ withEnv "EP28_PROVISIONED_SECRET" "CLI-SECRET-SENTINEL" $ do
        r <- fixtureRequest "echo"
        let secretRequest = r & #environment %~ (<> [RequestEntry "DATABASE_URL" (SecretFromEnvironment (EnvName "EP28_PROVISIONED_SECRET"))])
        assertBool "secret entered request" (not ("CLI-SECRET-SENTINEL" `T.isInfixOf` renderPreflightRequestJson secretRequest))
        forM_ [[], ["--json"]] $ \args -> do
          (code, out, err) <- runRequest secretRequest args
          code @?= ExitSuccess
          assertBool "secret leaked from CLI" (not ("CLI-SECRET-SENTINEL" `T.isInfixOf` (out <> err)))
          (invalidCode, invalidOut, invalidErr) <- runRequest (secretRequest & #command . #arguments .~ [literalArgument "CLI-SECRET-SENTINEL"]) args
          invalidCode @?= ExitFailure 3
          assertBool "invalid command leaked" (not ("CLI-SECRET-SENTINEL" `T.isInfixOf` (invalidOut <> invalidErr)))
    ]

sentinel :: Text
sentinel = "SECRET-PARSER-SENTINEL"

baseDocument :: A.Value
baseDocument = A.object ["schemaVersion" A..= (1 :: Int), "type" A..= ("settei.preflight-request" :: Text), "role" A..= ("server" :: Text), "command" A..= A.object ["executable" A..= ("/bin/true" :: Text), "arguments" A..= ([] :: [A.Value])], "environment" A..= [A.object ["name" A..= ("TOKEN" :: Text), "value" A..= sentinel]]]

set :: A.Key -> A.Value -> A.Value -> A.Value
set k v (A.Object o) = A.Object (KM.insert k v o)
set _ _ v = v

entry :: [(A.Key, A.Value)] -> A.Value -> A.Value
entry pairs = set "environment" (A.toJSON [A.Object (KM.fromList (("name", A.String "TOKEN") : pairs))])

malformedCases :: [(String, Text, A.Value -> A.Value)]
malformedCases =
  [ ("inline secret", "environment[0]", entry [("value", A.String sentinel), ("sensitivity", A.String "secret")]),
    ("multiple forms", "environment[0]", entry [("value", A.String sentinel), ("unresolved", A.String sentinel)]),
    ("no form", "environment[0]", entry []),
    ("unknown top key", "request", set "SECRET-PARSER-SENTINEL" (A.String sentinel)),
    ("unknown entry key", "environment[0]", entry [("value", A.String sentinel), ("SECRET-PARSER-SENTINEL", A.String sentinel)]),
    ("unknown command key", "command", set "command" (A.object ["SECRET-PARSER-SENTINEL" A..= sentinel])),
    ("wrong type", "request.type", set "type" (A.String sentinel)),
    ("wrong version", "schemaVersion", set "schemaVersion" (A.toJSON (2 :: Int))),
    ("timeout zero", "timeoutSeconds", set "timeoutSeconds" (A.toJSON (0 :: Int))),
    ("bad exit mapping", "exitCodes", set "exitCodes" (A.object ["accepted" A..= (0 :: Int), "usage" A..= [0 :: Int], "sourceFailure" A..= ([] :: [Int]), "rejected" A..= [4 :: Int]])),
    ("bad secret reference name", "secretFromEnvironment", entry [("secretFromEnvironment", A.String sentinel)]),
    ("missing synthetic reason", "reason", entry [("synthetic", A.String sentinel)]),
    ("wrong value type", "value", entry [("value", A.toJSON (4 :: Int))])
  ]
