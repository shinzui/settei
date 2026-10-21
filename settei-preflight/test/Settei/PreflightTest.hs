module Settei.PreflightTest (tests) where

import Control.Concurrent (threadDelay)
import Control.Exception (bracket)
import Control.Monad (forM_)
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NE
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Paths_settei_preflight qualified as Paths
import Settei (Sensitivity (..))
import Settei.Env (EnvName (..))
import Settei.Preflight.Internal
import Settei.Prelude hiding (simple)
import System.Directory qualified as D
import System.Environment qualified as Env
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit

fixture :: Text -> [Argument] -> (ProposedInputs -> ProposedInputs) -> IO PreflightReport
fixture behaviour args modify = do
  exe <- Env.getExecutablePath
  runPreflight defaultPreflightOptions (RoleLabel "server") (CheckCommand exe args) (modify (fixtureInputs behaviour))

fixtureInputs :: Text -> ProposedInputs
fixtureInputs behaviour = emptyProposedInputs & #environment .~ [(EnvName "SETTEI_PREFLIGHT_FIXTURE", SuppliedValue Public "1"), (EnvName "FIXTURE_BEHAVIOUR", SuppliedValue Public behaviour)]

withEnv :: String -> String -> IO a -> IO a
withEnv n v action = bracket (Env.lookupEnv n <* Env.setEnv n v) (maybe (Env.unsetEnv n) (Env.setEnv n)) (const action)

noLeak :: Text -> PreflightReport -> Assertion
noLeak sentinel r = forM_ [renderPreflightReportText r, renderPreflightReportJson r, tshow r] $ \s -> assertBool "secret leaked" (not (sentinel `T.isInfixOf` s))

stdoutOf :: PreflightReport -> Text
stdoutOf = maybe "" (view #standardOutput) . view #execution

stderrOf :: PreflightReport -> Text
stderrOf = maybe "" (view #standardError) . view #execution

tests :: TestTree
tests =
  testGroup
    "Settei.Preflight"
    [ testCase "accept with supplied inputs passes" $ do
        r <- fixture "accept" [] id
        r ^. #outcome @?= Accepted
        r ^. #coverage @?= CompleteCoverage
        r ^. #verdict @?= Pass
        fmap (view #exitCode) (r ^. #execution) @?= Just (Just 0)
        stdoutOf r @?= "configuration valid\n",
      testGroup
        "exit mapping"
        [ testCase (T.unpack b) $ do
            r <- fixture b [] id
            r ^. #outcome @?= Rejected c n
            r ^. #verdict @?= Fail
        | (b, c, n) <- [("reject", ConfigurationRejected, 4), ("source-failure", SourceFailure, 3), ("usage", UsageError, 2), ("crash", UnknownExitCode, 1)]
        ],
      testGroup
        "executable lookup"
        [ testCase exe $ do
            r <- runPreflight defaultPreflightOptions (RoleLabel "worker") (CheckCommand exe []) emptyProposedInputs
            r ^. #outcome @?= NotRun (ExecutableNotFound exe)
            r ^. #role @?= RoleLabel "worker"
            r ^. #execution @?= Nothing
        | exe <- ["/definitely/missing", "settei-no-such-executable-ep28"]
        ],
      testCase "relative executable is resolved before changing cwd" $ do
        exe <- Env.getExecutablePath
        cwd <- D.getCurrentDirectory
        -- A relative symlink in a temporary directory still resolves from the harness cwd.
        withSystemTempDirectory "preflight-relative" $ \root -> do
          let link = root </> "fixture"
          D.createFileLink exe link
          relative <- D.makeRelativeToCurrentDirectory link
          r <- runPreflight defaultPreflightOptions (RoleLabel "server") (CheckCommand (if '/' `elem` relative then relative else "./" <> relative) []) (fixtureInputs "accept")
          r ^. #verdict @?= Pass
          D.getCurrentDirectory >>= (@?= cwd),
      testCase "nonexecutable file is spawn failure" $ withSystemTempDirectory "preflight-spawn" $ \root -> do
        let path = root </> "not-executable"
        writeFile path "not executable"
        r <- runPreflight defaultPreflightOptions (RoleLabel "worker") (CheckCommand path []) emptyProposedInputs
        case r ^. #outcome of NotRun (SpawnFailed _) -> pure (); _ -> assertFailure (show r),
      testCase "timeout retains captured bytes and removes its own directory" $ do
        exe <- Env.getExecutablePath
        r <- runPreflight (defaultPreflightOptions & #timeoutSeconds .~ 1) (RoleLabel "server") (CheckCommand exe []) (fixtureInputs "sleep")
        r ^. #outcome @?= NotRun (TimedOut 1)
        assertBool "cwd missing from timed-out invocation" (not (T.null (stdoutOf r)))
        D.doesDirectoryExist (T.unpack (T.strip (stdoutOf r))) >>= (@?= False),
      testCase "environment is exactly proposed when inherit is empty" $ withEnv "PREFLIGHT_AMBIENT" "must-not-inherit" $ do
        r <- fixture "echo" [] (\p -> p & #inherited .~ [])
        -- CoreFoundation may synthesize this variable inside a macOS GHC process.
        filter (not . T.isPrefixOf "__CF_USER_TEXT_ENCODING=") (T.lines (stdoutOf r)) @?= ["FIXTURE_BEHAVIOUR=echo", "SETTEI_PREFLIGHT_FIXTURE=1"]
        native <- runPreflight defaultPreflightOptions (RoleLabel "native") (CheckCommand "/usr/bin/env" []) (emptyProposedInputs & #inherited .~ [] & #environment .~ [(EnvName "ONLY", SuppliedValue Public "proposed")])
        stdoutOf native @?= "ONLY=proposed\n",
      testCase "explicit allowlist reports absent names" $ do
        r <- fixture "echo" [] (\p -> p & #inherited .~ [EnvName "PATH", EnvName "PREFLIGHT_MISSING_EP28"])
        assertBool "PATH missing" ("PATH=" `T.isInfixOf` stdoutOf r)
        r ^. #inherited @?= [(EnvName "PATH", True), (EnvName "PREFLIGHT_MISSING_EP28", False)],
      testCase "environment and file secrets are redacted in every report form" $ do
        r <- fixture "echo" [fileArgument (FileName "secrets/token")] $ \p ->
          p
            & #environment
            %~ (<> [(EnvName "DATABASE_URL", SuppliedValue Secret "ENV-SECRET-SENTINEL")])
            & #files
            .~ [ProposedFile (FileName "secrets/token") (SuppliedValue Secret "FILE-SECRET-SENTINEL")]
        noLeak "ENV-SECRET-SENTINEL" r
        noLeak "FILE-SECRET-SENTINEL" r
        assertBool "environment marker" ("[redacted:DATABASE_URL]" `T.isInfixOf` stdoutOf r)
        assertBool "file marker" ("[redacted:file secrets/token]" `T.isInfixOf` stdoutOf r),
      testCase "materialized compound file and directory arguments retain symbolic summary" $ do
        let name = FileName "etc/application.yaml"
        r <- fixture "echo" [Argument [LiteralPart "yaml:", FilePart name], Argument [DirectoryPart (FileName "etc")], fileArgument name] $ \p -> p & #files .~ [ProposedFile name (SuppliedValue Public "server: example\n")]
        assertBool "content not passed" ("server: example\n" `T.isInfixOf` stdoutOf r)
        assertBool "compound path missing" ("yaml:/" `T.isInfixOf` stderrOf r)
        r ^. #command . #arguments @?= ["yaml:{file:etc/application.yaml}", "{dir:etc}", "{file:etc/application.yaml}"],
      testCase "omitted file absent but directory exists" $ do
        r <- fixture "echo" [fileArgument (FileName "etc/missing"), Argument [DirectoryPart (FileName "etc")]] $ \p -> p & #files .~ [ProposedFile (FileName "etc/missing") (UnresolvedValue "not yet created")]
        r ^. #verdict @?= Inconclusive
        assertBool "omitted file passed" (not (any (\s -> s ^. #input == FileInput (FileName "etc/missing") && s ^. #passed) (r ^. #inputs))),
      testCase "synthetic secret is partial and redacted" $ do
        r <- fixture "echo" [] $ \p -> p & #environment %~ (<> [(EnvName "TOKEN", SyntheticValue Secret "FAKE-CREDENTIAL" "stand-in")])
        r ^. #verdict @?= Inconclusive
        length (limitations (r ^. #coverage)) @?= 1
        noLeak "FAKE-CREDENTIAL" r,
      testGroup
        "omissions stay visible"
        [ testCase (T.unpack b) $ do
            r <- fixture b [] $ \p -> p & #environment %~ (<> [(EnvName "GENERATED", UnresolvedValue "resource output"), (EnvName "TOKEN", UnavailableSecret "not provisioned")])
            r ^. #verdict @?= expected
            length (limitations (r ^. #coverage)) @?= 2
            length (filter (not . view #passed) (r ^. #inputs)) @?= 2
        | (b, expected) <- [("accept", Inconclusive), ("reject", Fail)]
        ],
      testCase "an extraction note alone prevents pass" $ do
        r <- fixture "accept" [] (\p -> p & #notes .~ ["unsupported projected volume"])
        r ^. #verdict @?= Inconclusive
        fmap (view #kind) (limitations (r ^. #coverage)) @?= [ExtractionIncomplete]
        assertBool "honest explanation missing" ("not a deployment validation" `T.isInfixOf` renderPreflightReportJson r),
      testCase "secret is redacted across flushed chunks" $ do
        r <- fixture "chunks" [] (\p -> p & #environment %~ (<> [(EnvName "TOKEN", SuppliedValue Secret "SECRET-ACROSS-CHUNKS")]))
        stdoutOf r @?= "[redacted:TOKEN]\n",
      testCase "redaction uses longest original match and never rescans markers" $ do
        redact [("LONG-SECRET", "[redacted:first]"), ("SECRET", "[redacted:second]"), ("first", "[redacted:third]")] "LONG-SECRET SECRET" @?= "[redacted:first] [redacted:second]",
      testCase "secret-bearing names use numeric markers" $ do
        r <- fixture "echo" [] (\p -> p & #environment %~ (<> [(EnvName "NAME_SENTINEL", SuppliedValue Secret "SENTINEL")]))
        noLeak "SENTINEL" r
        assertBool "numeric marker missing" ("[redacted:input 2]" `T.isInfixOf` stdoutOf r),
      testCase "unicode diagnostic survives empty default locale context" $ do
        r <- fixture "unicode" [] id
        stderrOf r @?= "runtime.environment: expected one of «dev»\n",
      testCase "server-like check skips startup and non-check control writes marker" $ withSystemTempDirectory "preflight-marker" $ \root -> do
        let marker = root </> "started"
            p x = x & #environment %~ (<> [(EnvName "FIXTURE_STARTUP_MARKER", SuppliedValue Public (T.pack marker))])
        checked <- fixture "server-like" [literalArgument "--check-config"] p
        checked ^. #verdict @?= Pass
        D.doesFileExist marker >>= (@?= False)
        control <- fixture "server-like" [] p
        control ^. #verdict @?= Pass
        D.doesFileExist marker >>= (@?= True),
      testGroup
        "injectable IO failures"
        [ testCase label $ do
            exe <- Env.getExecutablePath
            r <- runPreflightWith operations defaultPreflightOptions (RoleLabel "worker") (CheckCommand exe []) (fixtureInputs "accept")
            r ^. #verdict @?= Fail
            assertBool (show r) (predicate (r ^. #outcome))
            assertBool "upstream exception leaked" (not ("PRIVATE-EXCEPTION" `T.isInfixOf` tshow r))
            if label == "materialization" then assertBool "pre-spawn input marked passed" (all (not . view #passed) (r ^. #inputs)) else pure ()
        | (label, operations, predicate) <-
            [ ("materialization", defaultRunOperations & #materializeInputs .~ (\_ _ _ -> ioError (userError "PRIVATE-EXCEPTION")), \case NotRun (MaterializationFailed _) -> True; _ -> False),
              ("capture", defaultRunOperations & #captureOutput .~ (\_ -> ioError (userError "PRIVATE-EXCEPTION")), \case NotRun (CaptureFailed _) -> True; _ -> False),
              ("cleanup", defaultRunOperations & #removeInputs .~ (\_ -> pure ()), \case NotRun (CleanupFailed _) -> True; _ -> False)
            ]
        ],
      testCase "timeout includes pipe draining after immediate child exit" $ do
        exe <- Env.getExecutablePath
        -- A bounded descendant closes naturally; wait beyond its life to reap it via
        -- the fixture supervisor (see retain-pipe fixture), never leave it running.
        r <- runPreflight (defaultPreflightOptions & #timeoutSeconds .~ 1) (RoleLabel "server") (CheckCommand exe []) (fixtureInputs "retain-pipe")
        r ^. #outcome @?= NotRun (TimedOut 1)
        threadDelay 1100000,
      testGroup "validation" validationTests,
      testGroup
        "report goldens"
        [ testCase name $ do
            expected <- Paths.getDataFileName ("test/golden/" <> name) >>= TIO.readFile
            actual @?= expected
            actual @?= renderer report
        | (base, report) <- [("fail", goldenFail), ("inconclusive", goldenInconclusive)],
          (ext, renderer) <- [("txt", renderPreflightReportText), ("json", renderPreflightReportJson)],
          let name = "report-" <> base <> "." <> ext,
          let actual = renderer report
        ]
    ]

validationTests :: [TestTree]
validationTests =
  [ testCase label $ do
      let result = validatePreflight chosenOptions chosenRole chosenCommand chosenInputs
      case result of
        Left ps -> assertBool (T.unpack (renderPreflightProblemsText ps)) (any ((== kind) . (\x -> let (k, _, _, _) = problemFields x in k)) (NE.toList ps))
        Right () -> assertFailure "invalid request accepted"
      r <- runPreflight chosenOptions chosenRole chosenCommand chosenInputs
      r ^. #execution @?= Nothing
      assertBool "pre-spawn input marked passed" (all (not . view #passed) (r ^. #inputs))
      noLeak sentinel r
      case result of Left ps -> assertBool "pure validation leaked" (not (sentinel `T.isInfixOf` tshow ps)); _ -> pure ()
  | (label, kind, chosenOptions, chosenRole, chosenCommand, chosenInputs) <- cases
  ]
  where
    sentinel = "SECRET-SENTINEL"
    opts = defaultPreflightOptions
    role = RoleLabel "server"
    cmd = CheckCommand "/bin/echo" []
    p = emptyProposedInputs & #environment .~ [(EnvName "TOKEN", SuppliedValue Secret sentinel)]
    env n v = p & #environment %~ (<> [(EnvName n, v)])
    file n = ProposedFile (FileName n) (SuppliedValue Public "contents")
    c label kind opt rol command input = (label, kind, opt, rol, command, input)
    simple label kind input = c label kind opts role cmd input
    cases =
      [ simple "invalid name" "invalid-environment-name" (env "bad-name-SECRET-SENTINEL" (SuppliedValue Public "x")),
        simple "duplicate env" "duplicate-environment-name" (env "TOKEN" (SuppliedValue Public "x")),
        simple "NUL value" "invalid-environment-value" (env "BAD" (SuppliedValue Public "x\0")),
        simple "invalid file" "invalid-file-name" (p & #files .~ [file "../SECRET-SENTINEL"]),
        simple "duplicate file" "duplicate-file-name" (p & #files .~ [file "a", file "a"]),
        simple "file parent collision" "file-path-conflict" (p & #files .~ [file "a/b", file "a"]),
        simple "inherited invalid" "invalid-inherited-name" (p & #inherited .~ [EnvName "bad-name"]),
        simple "inherited duplicate" "duplicate-inherited-name" (p & #inherited .~ [EnvName "PATH", EnvName "PATH"]),
        simple "inherited proposed" "inherited-name-proposed" (p & #inherited .~ [EnvName "TOKEN"]),
        c "unknown file" "unknown-file-reference" opts role (cmd & #arguments .~ [fileArgument (FileName "missing")]) p,
        c "unknown dir" "unknown-file-reference" opts role (cmd & #arguments .~ [Argument [DirectoryPart (FileName "missing")]]) p,
        c "secret argument" "secret-in-argument" opts role (cmd & #arguments .~ [literalArgument sentinel]) p,
        c "split secret argument" "secret-in-argument" opts role (cmd & #arguments .~ [Argument [LiteralPart "SECRET-", LiteralPart "SENTINEL"]]) p,
        c "secret executable" "secret-in-executable" opts role (CheckCommand (T.unpack sentinel) []) p,
        c "empty executable" "invalid-executable" opts role (CheckCommand "" []) p,
        c "NUL argument" "invalid-argument" opts role (cmd & #arguments .~ [literalArgument "\0"]) p,
        c "invalid timeout" "invalid-timeout" (opts & #timeoutSeconds .~ 0) role cmd p,
        c "overflow timeout" "invalid-timeout" (opts & #timeoutSeconds .~ maxBound) role cmd p,
        c "overlapping codes" "invalid-exit-code-mapping" (opts & #exitCodes .~ ExitCodeMapping 0 [0] [] []) role cmd p,
        c "out of range code" "invalid-exit-code-mapping" (opts & #exitCodes .~ ExitCodeMapping 256 [] [] []) role cmd p,
        c "empty role" "empty-role-label" opts (RoleLabel " ") cmd p
      ]
        <> [simple ("invalid path " <> show n) "invalid-file-name" (p & #files .~ [file n]) | n <- ["", "/absolute", "a//b", "a/./b", "a/../b", "a\\b", "a\0b"]]

goldenFail, goldenInconclusive :: PreflightReport
goldenFail = makeReport defaultPreflightOptions (RoleLabel "server") "/fixture" [] (emptyProposedInputs & #inherited .~ []) [] True (Right 4, Just (CapturedExecution (Just 4) False "" "database.url: required value is missing\n"))
goldenInconclusive = makeReport defaultPreflightOptions (RoleLabel "worker") "/fixture" [literalArgument "--check-config"] (emptyProposedInputs & #inherited .~ [] & #environment .~ [(EnvName "POD_NAMESPACE", SyntheticValue Public "production" "downward API namespace")]) [] True (Right 0, Just (CapturedExecution (Just 0) False "configuration valid\n" ""))
