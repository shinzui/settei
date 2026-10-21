module Settei.Example.Deployment.PreflightTest (tests) where

import Control.Exception (IOException, bracket, try)
import Control.Monad (forM_)
import Data.Aeson qualified as A
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Generics.Labels ()
import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Options.Applicative qualified as O
import Paths_settei_example_deployment qualified as Paths
import Settei (Sensitivity (..))
import Settei.Env (EnvName (..), envSnapshot)
import Settei.Example.Deployment
import Settei.Example.Deployment.Preflight
import Settei.Preflight qualified as P
import Settei.Preflight.Request qualified as R
import Settei.Prelude
import System.Directory (findExecutable)
import System.Environment qualified as Env
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit
import Text.Read (readMaybe)

roleText :: Role -> Text
roleText Server = "server"
roleText Worker = "worker"

roleExecutable :: Role -> IO FilePath
roleExecutable r = findExecutable ("settei-example-deployment-" <> T.unpack (roleText r)) >>= maybe (fail "build tool missing") pure

manifest :: IO A.Value
manifest = do
  bytes <- Paths.getDataFileName "test/fixtures/rendered-production.json" >>= BS.readFile
  either (const (fail "bad fixture")) pure (A.eitherDecodeStrict bytes)

requestFor :: Role -> (ExtractionOptions -> ExtractionOptions) -> A.Value -> IO R.PreflightRequest
requestFor r modify value = do
  exe <- roleExecutable r
  let extraction = modify (extractionOptions ("settei-example-deployment-" <> roleText r) (P.RoleLabel (roleText r)) exe)
  case extractPreflightRequest extraction value of Left e -> assertFailure (T.unpack (renderExtractionErrorText e)); Right (request, ns) -> do request ^. #notes @?= ns; pure request

syntheticNamespace :: ExtractionOptions -> ExtractionOptions
syntheticNamespace = #syntheticPublic .~ Map.singleton (EnvName "POD_NAMESPACE") "production"

secretEnvironment :: Bool -> R.RequestEnvironment
secretEnvironment email = R.RequestEnvironment lookupSecret (\_ -> pure (Left "not provisioned"))
  where
    lookupSecret (EnvName n) =
      pure $
        lookup
          n
          ( [ (prefix <> "DATABASE_URL", "postgres://preflight.invalid:5432/notification"),
              (prefix <> "WEBHOOK_SECRET", "WEBHOOK-PREFLIGHT-SECRET-SENTINEL")
            ]
              <> [(prefix <> "EMAIL_CREDENTIALS_JSON", "{\"account\":\"EMAIL-PREFLIGHT-SECRET-SENTINEL\"}") | email]
          )

prefix :: Text
prefix = "SETTEI_PREFLIGHT_SECRET_SETTEI_EXAMPLE_DEPLOYMENT_SECRETS_"

runRequest :: Bool -> R.PreflightRequest -> IO P.PreflightReport
runRequest email request = R.resolveRequest (secretEnvironment email) request >>= \r -> P.runPreflight (r ^. #options) (r ^. #role) (r ^. #command) (r ^. #inputs)

stdoutOf, stderrOf :: P.PreflightReport -> Text
stdoutOf = maybe "" (view #standardOutput) . view #execution
stderrOf = maybe "" (view #standardError) . view #execution

limits :: P.PreflightReport -> [P.Limitation]
limits r = case r ^. #coverage of P.CompleteCoverage -> []; P.PartialCoverage xs -> toList xs
  where
    toList (a :| as) = a : as

options :: Role -> [String] -> IO DeploymentOptions
options role args = case O.execParserPure O.defaultPrefs (deploymentParserInfo role) args of O.Success p -> pure p; _ -> fail "invalid test arguments"

-- JSON fixture edits preserve all other resources and deliberately exercise wiring.
field :: Text -> A.Value -> A.Value
field key (A.Object o) = maybe A.Null id (KM.lookup (K.fromText key) o)
field _ _ = A.Null

values :: A.Value -> [A.Value]
values v = case A.fromJSON v of A.Success xs -> xs; _ -> []

change :: [Text] -> (A.Value -> A.Value) -> A.Value -> A.Value
change [] f v = f v
change (key : rest) f (A.Object o) = A.Object (KM.insert (K.fromText key) (change rest f (maybe A.Null id (KM.lookup (K.fromText key) o))) o)
change (position : rest) f v = case readMaybe (T.unpack position) of Just i -> A.toJSON [if n == i then change rest f x else x | (n, x) <- zip [0 :: Int ..] (values v)]; Nothing -> v

resource :: Text -> (A.Value -> A.Value) -> A.Value -> A.Value
resource name f = change ["items"] (A.toJSON . fmap (\v -> if field "name" (field "metadata" v) == A.String name then f v else v) . values)

containerPath :: [Text]
containerPath = ["spec", "template", "spec", "initContainers", "0"]

container :: Role -> (A.Value -> A.Value) -> A.Value -> A.Value
container r = resource ("settei-example-deployment-" <> roleText r) . change containerPath

setEnv :: Text -> (A.Value -> A.Value) -> A.Value -> A.Value
setEnv name f = change ["env"] (A.toJSON . fmap (\v -> if field "name" v == A.String name then f v else v) . values)

obj :: [(A.Key, A.Value)] -> A.Value
obj = A.Object . KM.fromList

literal :: Text -> Text -> A.Value
literal n v = obj [("name", A.String n), ("value", A.String v)]

production :: [(Text, Text)]
production = [("ENVIRONMENT", "production"), ("DATABASE_URL", "postgres://preflight.invalid/notification"), ("WEBHOOK_SECRET", "WEBHOOK-PREFLIGHT-SECRET-SENTINEL"), ("EMAIL_CREDENTIALS_JSON", "{\"account\":\"EMAIL-PREFLIGHT-SECRET-SENTINEL\"}"), ("DELIVERY_ENDPOINT", "https://delivery.invalid")]

proposed :: [(Text, Text)] -> P.ProposedInputs
proposed es = P.emptyProposedInputs & #environment .~ [(EnvName n, P.SuppliedValue (if n `elem` ["DATABASE_URL", "WEBHOOK_SECRET", "EMAIL_CREDENTIALS_JSON"] then Secret else Public) v) | (n, v) <- es]

tests :: TestTree
tests =
  testGroup
    "preflight"
    [ testCase "extracted server roundtrip agrees with in-process configuration check" $ do
        value <- manifest
        request <- requestFor Server syntheticNamespace value
        request ^. #notes @?= []
        case R.parsePreflightRequest (TE.encodeUtf8 (R.renderPreflightRequestJson request)) of Right r -> assertBool "request changed" (r == request); Left _ -> assertFailure "request failed to parse"
        resolved <- R.resolveRequest (secretEnvironment True) request
        report <- runRequest True request
        report ^. #verdict @?= P.Inconclusive
        withSystemTempDirectory "preflight-equivalence" $ \root -> do
          let file = root </> "application.yaml"
          TIO.writeFile file "server:\n  host: 0.0.0.0\ndatabase:\n  poolSize: 20\n"
          parsed <- options Server ["--config", file, "--check-config"]
          let snapshot = [(n, v) | (EnvName n, pv) <- resolved ^. #inputs . #environment, v <- case pv of P.SuppliedValue _ t -> [t]; P.SyntheticValue _ t _ -> [t]; _ -> []]
          normal <- runDeploymentWithSnapshot Server (envSnapshot snapshot) parsed
          fmap (view #exitCode) (report ^. #execution) @?= Just (Just (deploymentExitCode normal))
          stderrOf report @?= deploymentStandardError normal,
      testGroup
        "precedence and role"
        [ testCase (T.unpack (roleText role)) $ do
            exe <- roleExecutable role
            let file = P.FileName "application.yaml"
                inputs = proposed (production <> [("PORT", "9100")]) & #files .~ [P.ProposedFile file (P.SuppliedValue Public "server:\n  port: 9000\n")]
            report <- P.runPreflight P.defaultPreflightOptions (P.RoleLabel (roleText role)) (P.CheckCommand exe [P.literalArgument "--config", P.fileArgument file, P.literalArgument "--set", P.literalArgument "server.port=9200", P.literalArgument "--explain-config-json"]) inputs
            report ^. #verdict @?= P.Pass
            doc <- either (const (assertFailure "invalid explain JSON")) pure (A.eitherDecodeStrict (TE.encodeUtf8 (stdoutOf report)))
            node <- maybe (assertFailure "missing port") pure (find (\n -> field "key" n == A.String "server.port") (values (field "nodes" doc)))
            field "value" node @?= A.String "\"9200\""
            field "kind" (field "origin" node) @?= A.String "command-line"
            fmap (field "kind") (values (field "shadowed" node)) @?= fmap A.String ["environment", "file", "built-in"]
            checked <- P.runPreflight P.defaultPreflightOptions (P.RoleLabel (roleText role)) (P.CheckCommand exe [P.literalArgument "--config", P.fileArgument file, P.literalArgument "--set", P.literalArgument "server.port=9200", P.literalArgument "--check-config"]) inputs
            withSystemTempDirectory "preflight-role-equivalence" $ \root -> do
              let path = root </> "application.yaml"
              TIO.writeFile path "server:\n  port: 9000\n"
              parsed <- options role ["--config", path, "--set", "server.port=9200", "--check-config"]
              normal <- runDeploymentWithSnapshot role (envSnapshot (production <> [("PORT", "9100")])) parsed
              fmap (view #exitCode) (checked ^. #execution) @?= Just (Just (deploymentExitCode normal))
              stderrOf checked @?= deploymentStandardError normal
            roleFailure <- P.runPreflight P.defaultPreflightOptions (P.RoleLabel (roleText role)) (P.CheckCommand exe [P.literalArgument "--check-config"]) (proposed (production <> [("WORKER_VISIBILITY_TIMEOUT_SECONDS", "1")]))
            roleFailure ^. #verdict @?= (if role == Worker then P.Fail else P.Pass)
            roleFailure ^. #role @?= P.RoleLabel (roleText role)
        | role <- [Server, Worker]
        ],
      testGroup
        "fixture coverage"
        [ testCase (T.unpack (roleText role)) $ do
            value <- manifest
            raw <- requestFor role id value
            assertBool "namespace unresolved missing" (any (\e -> e ^. #name == "POD_NAMESPACE" && e ^. #form == R.UnresolvedEntry "downward API fieldPath metadata.namespace") (raw ^. #environment))
            let refs = [env | e <- raw ^. #environment, R.SecretFromEnvironment (EnvName env) <- [e ^. #form]]
            refs @?= fmap (prefix <>) ["DATABASE_URL", "EMAIL_CREDENTIALS_JSON", "WEBHOOK_SECRET"]
            request <- requestFor role syntheticNamespace value
            missing <- runRequest False request
            missing ^. #verdict @?= P.Fail
            assertBool "missing application error" ("email.credentials: required value is missing" `T.isInfixOf` stderrOf missing)
            assertBool "unavailable limitation missing" (any ((== P.SecretUnavailable) . view #kind) (limits missing))
            supplied <- runRequest True request
            supplied ^. #verdict @?= P.Inconclusive
            length (limits supplied) @?= (if role == Server then 1 else 2)
            stdoutOf supplied @?= "configuration valid\n"
            forM_ ["postgres://preflight.invalid:5432/notification", "WEBHOOK-PREFLIGHT-SECRET-SENTINEL", "EMAIL-PREFLIGHT-SECRET-SENTINEL", "MANIFEST-PLACEHOLDER"] $ \sentinel ->
              forM_ [R.renderPreflightRequestJson request, P.renderPreflightReportText supplied, P.renderPreflightReportJson supplied, T.pack (show supplied)] $ \output -> assertBool "secret leaked" (not (sentinel `T.isInfixOf` output))
        | role <- [Server, Worker]
        ],
      testCase "extracted request reproduces all five input classifications" $ do
        value <- manifest
        request <- requestFor Server (\o -> o & #syntheticSecret .~ Map.singleton (EnvName "WEBHOOK_SECRET") "fake-credential-at-least-16-characters") value
        report <- runRequest False request
        let classifications = fmap (view #classification) (report ^. #inputs)
        forM_ [P.SuppliedPublic, P.SuppliedSecret, P.Unresolved, P.UnavailableSecretInput, P.SyntheticSecret] (\c -> assertBool (show c) (c `elem` classifications)),
      testCase "unsupported note alone remains inconclusive" $ do
        value <- manifest
        request <- requestFor Worker id (container Worker (setEnv "POD_NAMESPACE" (const (literal "POD_NAMESPACE" "production"))) value)
        report <- runRequest True request
        report ^. #verdict @?= P.Inconclusive
        fmap (view #kind) (limits report) @?= [P.ExtractionIncomplete],
      testGroup
        "deliberate mutations"
        [ testCase label $ do
            value <- manifest
            request <- requestFor role syntheticNamespace (mutation value)
            report <- runRequest True request
            report ^. #verdict @?= P.Fail
            assertBool (T.unpack (stderrOf report)) (message `T.isInfixOf` stderrOf report)
            report ^. #outcome @?= P.Rejected category code
        | (label, role, mutation, message, category, code) <-
            [ ("invalid environment mapping", Server, resource "settei-example-deployment" (change ["data", "ENVIRONMENT"] (const (A.String "prod"))), "runtime.environment:", P.ConfigurationRejected, 4),
              ("malformed mounted file", Server, resource "settei-example-deployment" (change ["data", "application.yaml"] (const (A.String "server: ["))), "configuration file", P.SourceFailure, 3),
              ("broken secret mapping", Server, container Server (setEnv "DATABASE_URL" (change ["valueFrom", "secretKeyRef", "key"] (const (A.String "NONEXISTENT")))), "database.url: required value is missing", P.ConfigurationRejected, 4),
              ("worker-specific value", Worker, container Worker (setEnv "WORKER_VISIBILITY_TIMEOUT_SECONDS" (const (literal "WORKER_VISIBILITY_TIMEOUT_SECONDS" "1"))), "workers.visibilityTimeoutSeconds, workers.concurrency: invariant worker-visibility-covers-concurrency failed: workers.visibilityTimeoutSeconds must be at least twice workers.concurrency", P.ConfigurationRejected, 4)
            ]
        ],
      testCase "renamed variable is invisible to check mode, honestly documenting the gap" $ do
        value <- manifest
        let renamed = container Server (setEnv "ENVIRONMENT" (const (literal "HASKELL_ENV" "production"))) value
        request <- requestFor Server syntheticNamespace renamed
        report <- runRequest True request
        report ^. #verdict @?= P.Inconclusive,
      testGroup
        "configuration-only startup boundary"
        [ testCase (T.unpack (roleText role)) $ do
            exe <- roleExecutable role
            let inputs = proposed (production <> [("SETTEI_DEPLOYMENT_TEST_FAIL_ON_STARTUP", "1")])
            checked <- P.runPreflight P.defaultPreflightOptions (P.RoleLabel (roleText role)) (P.CheckCommand exe [P.literalArgument "--check-config"]) inputs
            checked ^. #verdict @?= P.Pass
            stdoutOf checked @?= "configuration valid\n"
            control <- P.runPreflight P.defaultPreflightOptions (P.RoleLabel (roleText role)) (P.CheckCommand exe []) inputs
            control ^. #verdict @?= P.Fail
            assertBool "startup control did not fire" ("deployment startup action invoked" `T.isInfixOf` stderrOf control)
            parsed <- options role ["--check-config"]
            good <- runDeploymentWithStartup (ioError (userError "startup entered")) role (pure (envSnapshot production)) parsed
            deploymentExitCode good @?= 0
            bad <- runDeploymentWithStartup (ioError (userError "startup entered")) role (pure (envSnapshot [])) parsed
            deploymentExitCode bad @?= 4
            normal <- options role []
            triggered <- try (runDeploymentWithStartup (ioError (userError "startup entered")) role (pure (envSnapshot production)) normal) :: IO (Either IOException DeploymentRun)
            assertBool "control did not throw" (case triggered of Left _ -> True; Right _ -> False)
        | role <- [Server, Worker]
        ],
      testGroup "extractor edge cases" extractorTests,
      testCase "extractor and harness executable channels contain no secret sentinels" $ do
        exe <- roleExecutable Server
        fixture <- Paths.getDataFileName "test/fixtures/rendered-production.json"
        (code, out, err) <- readProcessWithExitCode "settei-example-deployment-preflight" ["--manifest", fixture, "--deployment", "settei-example-deployment-server", "--role", "server", "--executable", exe, "--synthetic", "POD_NAMESPACE=production"] ""
        code @?= ExitSuccess
        err @?= ""
        withSystemTempDirectory "preflight-pipeline" $ \root -> do
          let file = root </> "request.json"
          writeFile file out
          let withVariable suffix value action = bracket (Env.lookupEnv (T.unpack (prefix <> suffix)) <* Env.setEnv (T.unpack (prefix <> suffix)) value) (maybe (Env.unsetEnv (T.unpack (prefix <> suffix))) (Env.setEnv (T.unpack (prefix <> suffix)))) (const action)
          withVariable "DATABASE_URL" "DATABASE-CLI-SECRET-SENTINEL" $
            withVariable "WEBHOOK_SECRET" "WEBHOOK-CLI-SECRET-SENTINEL" $
              withVariable "EMAIL_CREDENTIALS_JSON" "EMAIL-CLI-SECRET-SENTINEL" $
                forM_ [[], ["--json"]] $ \args -> do
                  (harnessCode, report, harnessErr) <- readProcessWithExitCode "settei-preflight" (["--request", file] <> args) ""
                  harnessCode @?= ExitFailure 1
                  forM_ ["DATABASE-CLI-SECRET-SENTINEL", "WEBHOOK-CLI-SECRET-SENTINEL", "EMAIL-CLI-SECRET-SENTINEL", "MANIFEST-PLACEHOLDER"] $ \sentinel -> assertBool "pipeline leaked" (not (sentinel `T.isInfixOf` T.pack (out <> err <> report <> harnessErr)))
    ]

extractorTests :: [TestTree]
extractorTests =
  [ testCase "envFrom precedence, prefixes, and explicit duplicates use last effective entry" $ do
      v <- manifest
      let envFrom = A.toJSON [obj [("configMapRef", obj [("name", A.String "settei-example-deployment")]), ("prefix", A.String "FIRST_")], obj [("configMapRef", obj [("name", A.String "settei-example-deployment")])]]
          mutated = container Server (change ["envFrom"] (const envFrom) . change ["env"] (\es -> A.toJSON (values es <> [literal "ENVIRONMENT" "test", literal "ENVIRONMENT" "production"]))) v
      request <- requestFor Server id mutated
      assertBool "effective environment changed" ([e ^. #form | e <- request ^. #environment, e ^. #name == "ENVIRONMENT"] == [R.InlineValue "production"])
      assertBool "prefix lost" (any ((== "FIRST_ENVIRONMENT") . view #name) (request ^. #environment)),
    testCase "namespace lookup selects local resource, while duplicate identities fail" $ do
      v <- manifest
      let other = obj [("kind", A.String "ConfigMap"), ("metadata", obj [("name", A.String "settei-example-deployment"), ("namespace", A.String "other")]), ("data", obj [("ENVIRONMENT", A.String "wrong")])]
      request <- requestFor Server id (change ["items"] (A.toJSON . (<> [other]) . values) v)
      assertBool "effective environment changed" ([e ^. #form | e <- request ^. #environment, e ^. #name == "ENVIRONMENT"] == [R.InlineValue "production"])
      exe <- roleExecutable Server
      let duplicate = change ["items"] (\xs -> A.toJSON (values xs <> take 1 (values xs))) v
      assertBool "duplicate accepted" (case extractPreflightRequest (extractionOptions "settei-example-deployment-server" (P.RoleLabel "server") exe) duplicate of Left _ -> True; _ -> False),
    testCase "all-key ConfigMap and Secret mounts enumerate keys without reading secrets" $ do
      v <- manifest
      let volume = obj [("name", A.String "secret-files"), ("secret", obj [("secretName", A.String "settei-example-deployment-secrets")])]
          mount = obj [("name", A.String "secret-files"), ("mountPath", A.String "/etc/settei/secrets")]
          mutated = resource "settei-example-deployment-server" (change ["spec", "template", "spec", "volumes"] (\vs -> A.toJSON (values vs <> [volume])) . change ["spec", "template", "spec", "volumes", "0", "configMap"] (\case A.Object o -> A.Object (KM.delete "items" o); x -> x) . change (containerPath <> ["volumeMounts"]) (\ms -> A.toJSON (values ms <> [mount])) . change (containerPath <> ["args"]) (const (A.toJSON (["--config", "/etc/settei/application.yaml", "--directory=/etc/settei/secrets", "--check-config"] :: [Text])))) v
      request <- requestFor Server id mutated
      length (request ^. #files) @?= 6
      assertBool "longest mount lost" ("{\"directory\":\"etc/settei/secrets\"}" `T.isInfixOf` R.renderPreflightRequestJson request)
      assertBool "Secret content inspected" (not ("MANIFEST-PLACEHOLDER" `T.isInfixOf` R.renderPreflightRequestJson request)),
    testGroup
      "unsupported forms remain notes"
      [ testCase label $ do
          v <- manifest
          request <- requestFor Server id (mutation v)
          assertBool "unsupported input silently dropped" (any (fragment `T.isInfixOf`) (request ^. #notes))
      | (label, fragment, mutation) <-
          [ ("extra envFrom field", "unsupported fields", container Server (change ["envFrom"] (const (A.toJSON [obj [("configMapRef", obj [("name", A.String "settei-example-deployment")]), ("futureInput", A.String "not interpreted")]])))),
            ("unknown valueFrom", "valueFrom", container Server (setEnv "POD_NAMESPACE" (change ["valueFrom"] (const (obj [("resourceFieldRef", obj [])]))))),
            ("command override", "command", container Server (change ["command"] (const (A.toJSON (["/entrypoint"] :: [Text]))))),
            ("argument expansion", "expansion", container Server (change ["args"] (const (A.toJSON (["--check-config", "$(VAR)"] :: [Text]))))),
            ("env expansion", "expansion", container Server (change ["env"] (\es -> A.toJSON (values es <> [literal "EXPANDED" "$(VAR)"])))),
            ("subPath", "subPath", container Server (change ["volumeMounts", "0", "subPath"] (const (A.String "application.yaml")))),
            ("outside path boundary", "absolute path", container Server (change ["args"] (const (A.toJSON (["--config", "/etc/settei2/application.yaml", "--check-config"] :: [Text]))))),
            ("optional missing key", "optional ConfigMap", container Server (setEnv "ENVIRONMENT" (change ["valueFrom", "configMapKeyRef"] (const (obj [("name", A.String "absent"), ("key", A.String "absent"), ("optional", A.Bool True)]))))),
            ("unknown envFrom Secret", "cannot be enumerated", container Server (change ["envFrom"] (const (A.toJSON [obj [("secretRef", obj [("name", A.String "absent")])]])))),
            ("binaryData", "binaryData", resource "settei-example-deployment" (change ["binaryData"] (const (obj [("binary", A.String "AA==")]))))
          ]
      ],
    testCase "Secret envFrom enumerates union of data and stringData keys with prefixes" $ do
      v <- manifest
      let mutated =
            resource "settei-example-deployment-secrets" (change ["data"] (const (obj [("EXTRA", obj [("neverDecode", A.Bool True)]), ("DATABASE_URL", A.String "INVALID-BASE64-SECRET-PLACEHOLDER")]))) $
              container Server (change ["envFrom"] (const (A.toJSON [obj [("secretRef", obj [("name", A.String "settei-example-deployment-secrets")]), ("prefix", A.String "COPIED_")]]))) v
      request <- requestFor Server id mutated
      let copied = [e ^. #name | e <- request ^. #environment, "COPIED_" `T.isPrefixOf` (e ^. #name)]
      copied @?= ["COPIED_DATABASE_URL", "COPIED_EMAIL_CREDENTIALS_JSON", "COPIED_EXTRA", "COPIED_WEBHOOK_SECRET"]
      assertBool "Secret values read" (not ("INVALID-BASE64" `T.isInfixOf` R.renderPreflightRequestJson request)),
    testCase "ambiguous Deployments and duplicate checked containers fail" $ do
      v <- manifest
      exe <- roleExecutable Server
      deployment <- maybe (fail "fixture Deployment missing") pure (find (\r -> field "name" (field "metadata" r) == A.String "settei-example-deployment-server") (values (field "items" v)))
      let other = change ["metadata", "namespace"] (const (A.String "other")) deployment
          ambiguous = change ["items"] (A.toJSON . (<> [other]) . values) v
          duplicated = resource "settei-example-deployment-server" (change ["spec", "template", "spec", "initContainers"] (\cs -> A.toJSON (values cs <> values cs))) v
      forM_ [ambiguous, duplicated] $ \bad -> assertBool "ambiguous selection accepted" (case extractPreflightRequest (extractionOptions "settei-example-deployment-server" (P.RoleLabel "server") exe) bad of Left _ -> True; _ -> False),
    testCase "secret sanitized-name collisions fail instead of aliasing credentials" $ do
      v <- manifest
      exe <- roleExecutable Server
      let source secret = obj [("secretKeyRef", obj [("name", A.String secret), ("key", A.String "TOKEN")])]
          added = [obj [("name", A.String "ONE"), ("valueFrom", source "foo-bar")], obj [("name", A.String "TWO"), ("valueFrom", source "foo_bar")]]
          mutated = container Server (change ["env"] (A.toJSON . (<> added) . values)) v
      assertBool "sanitization collision accepted" (case extractPreflightRequest (extractionOptions "settei-example-deployment-server" (P.RoleLabel "server") exe) mutated of Left e -> "collision" `T.isInfixOf` renderExtractionErrorText e; _ -> False),
    testCase "substitution rejects unknown names, conflicts, and public replacement of a secret" $ do
      v <- manifest
      exe <- roleExecutable Server
      let base = extractionOptions "settei-example-deployment-server" (P.RoleLabel "server") exe
      forM_ [base & #syntheticPublic .~ Map.singleton (EnvName "UNKNOWN") "fake", base & #syntheticPublic .~ Map.singleton (EnvName "WEBHOOK_SECRET") "fake", base & #syntheticPublic .~ Map.singleton (EnvName "POD_NAMESPACE") "fake" & #syntheticSecret .~ Map.singleton (EnvName "POD_NAMESPACE") "fake"] $ \o ->
        assertBool "invalid substitution accepted" (case extractPreflightRequest o v of Left _ -> True; _ -> False),
    testCase "unsafe item paths and file collisions fail before serialization" $ do
      v <- manifest
      exe <- roleExecutable Server
      let base = extractionOptions "settei-example-deployment-server" (P.RoleLabel "server") exe
      forM_
        [ resource "settei-example-deployment-server" (change ["spec", "template", "spec", "volumes", "0", "configMap", "items", "0", "path"] (const (A.String "../escape"))) v,
          container Server (change ["volumeMounts"] (\ms -> A.toJSON (values ms <> values ms))) v
        ]
        $ \bad ->
          assertBool "unsafe files accepted" (case extractPreflightRequest base bad of Left _ -> True; _ -> False)
  ]
