module Settei.EnvTest (tests) where

import Data.Either (isLeft, isRight)
import Data.Generics.Labels ()
import Data.List qualified as List
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Settei
import Settei.Env
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Env"
    [ testCase "contract bindings preserve order and trusted annotations without values" $ do
        let reference = kubernetesRef SecretObject (Just "payments") "database" (Just "password")
            first = annotateBinding (mempty & at "environment.variable" ?~ "spoofed") (binding (EnvName "MODE") runtimeEnvironment)
            second = fromKubernetesObject reference (binding (EnvName "PASSWORD") databasePassword)
        validated <- either (fail . show) pure (bindings [first, second])
        let converted = inputBindings validated
        fmap inputBindingName converted @?= ["MODE", "PASSWORD"]
        fmap inputBindingKey converted @?= [runtimeEnvironment, databasePassword]
        fmap inputBindingChannel converted @?= [EnvironmentVariable, EnvironmentVariable]
        case converted of
          [firstConverted, secondConverted] -> do
            inputBindingAnnotations firstConverted ^. at "environment.variable" @?= Just "MODE"
            inputBindingAnnotations secondConverted ^. at "kubernetes.object-name" @?= Just "database"
          _ -> fail "expected two bindings",
      errorRenderingTests,
      bindingMergingTests,
      suppliedNameTests,
      testCase "explicit binding records variable origin" $ do
        input <- expectSource [binding (EnvName "HASKELL_ENV") runtimeEnvironment] [("HASKELL_ENV", "Production")]
        case lookupSource runtimeEnvironment input of
          Right (Just found) -> do
            found ^. to candidateOrigin . #kind @?= EnvironmentSource
            found ^. to candidateOrigin . #annotations . at "environment.variable" @?= Just "HASKELL_ENV"
          _ -> fail "expected the environment candidate",
      testCase "missing variables remain absent" $ do
        input <- expectSource [binding (EnvName "OPTIONAL_VALUE") optionalValue] []
        case lookupSource optionalValue input of
          Right Nothing -> pure ()
          _ -> fail "expected the optional variable to remain absent",
      testCase "invalid names are rejected at construction" $
        assertLeftContains isInvalidName (bindings [binding (EnvName "1BAD") runtimeEnvironment]),
      testCase "duplicate bindings are rejected" $ do
        let sameName =
              [ binding (EnvName "VALUE") runtimeEnvironment,
                binding (EnvName "VALUE") optionalValue
              ]
            sameKey =
              [ binding (EnvName "ONE") runtimeEnvironment,
                binding (EnvName "TWO") runtimeEnvironment
              ]
        assertLeftContains isDuplicateName (bindings sameName)
        assertLeftContains isDuplicateKey (bindings sameKey),
      testCase "prefix collisions are rejected" $ do
        let keys = [validKey "service.http-port", validKey "service.http_port"]
        case prefixedBindings "MYAPP" keys of
          Left errors ->
            assertBool "expected a normalized-name collision" (any isPrefixCollision (NonEmpty.toList errors))
          Right _ -> fail "expected the prefix helper to reject a collision",
      testCase "prefixed bindings preserve their derived names" $ do
        let keys = [validKey "service.host", validKey "service.port"]
        validated <- either (fail . show) pure (prefixedBindings "MYAPP" keys)
        fmap bindingName (bindingsList validated)
          @?= [EnvName "MYAPP_SERVICE_HOST", EnvName "MYAPP_SERVICE_PORT"],
      testCase "overlapping target keys are rejected" $ do
        let overlapping =
              [ binding (EnvName "SERVICE") (validKey "service"),
                binding (EnvName "PORT") (validKey "service.port")
              ]
        assertLeftContains isConflict (bindings overlapping),
      testCase "constructed bindings never fail during source building" $ do
        let pool =
              [ binding (EnvName "POOL_A") (validKey "a"),
                binding (EnvName "POOL_AB") (validKey "a.b"),
                binding (EnvName "POOL_AC") (validKey "a.c"),
                binding (EnvName "POOL_B") (validKey "b"),
                binding (EnvName "POOL_BCD") (validKey "b.c.d"),
                binding (EnvName "POOL_C") (validKey "c")
              ]
            snapshot =
              envSnapshot [(name, "value") | EnvName name <- fmap bindingName pool]
            outcomes =
              [ (subset, bindings subset)
              | subset <- List.subsequences pool
              ]
        assertBool "expected some subsets to fail construction" (any (isLeft . snd) outcomes)
        assertBool "expected some subsets to construct" (any (isRight . snd) outcomes)
        sequence_
          [ case lookupSource (bindingKey bound) (envSource "environment" validated snapshot) of
              Right (Just _) -> pure ()
              _ -> fail "expected every bound key to be served by the total source"
          | (subset, Right validated) <- outcomes,
            bound <- subset
          ],
      testCase "Secret annotation remains redacted" $ do
        let reference = kubernetesRef SecretObject (Just "payments") "payments-database" (Just "password")
            passwordBinding = fromKubernetesObject reference (binding (EnvName "DATABASE_PASSWORD") databasePassword)
        input <- expectSourceWith [passwordBinding] [("DATABASE_PASSWORD", secretSentinel)]
        let result = resolve defaultResolveOptions [input] (required passwordSetting)
        _ <- expectResolution result
        let output = renderResolutionText (result ^. #report)
        assertBool "secret value reached the report" (not (secretSentinel `Text.isInfixOf` output))
        assertBool "secret object metadata was omitted" ("payments-database" `Text.isInfixOf` output)
        assertBool "secret key metadata was omitted" ("password" `Text.isInfixOf` output),
      testCase "ConfigMap annotation retains public metadata" $ do
        let reference = kubernetesRef ConfigMapObject Nothing "service-network" (Just "host")
            hostBinding = fromKubernetesObject reference (binding (EnvName "SERVICE_HOST") serviceHost)
        input <- expectSourceWith [hostBinding] [("SERVICE_HOST", "api.internal")]
        let result = resolve defaultResolveOptions [input] (required hostSetting)
        _ <- expectResolution result
        let output = renderResolutionText (result ^. #report)
        assertBool "ConfigMap metadata was omitted" ("service-network" `Text.isInfixOf` output)
        assertBool "public value was omitted" ("api.internal" `Text.isInfixOf` output)
    ]

suppliedNameTests :: TestTree
suppliedNameTests =
  testGroup
    "supplied name validation"
    [ testCase "accepts bound and allowed names and preserves declarations" $ do
        validated <-
          expectBindings
            [ binding (EnvName "ENVIRONMENT") runtimeEnvironment,
              binding (EnvName "DATABASE_URL") databasePassword,
              binding (EnvName "PORT") optionalValue
            ]
        let external = allowance "opentelemetry-sdk" (EnvName "OTEL_EXPORTER_OTLP_ENDPOINT")
        accepted <- either (fail . show) pure (acceptedNames validated [external])
        assertBool "bindings changed" (acceptedBindings accepted == validated)
        allowanceConsumer external @?= "opentelemetry-sdk"
        allowanceName external @?= EnvName "OTEL_EXPORTER_OTLP_ENDPOINT"
        acceptedNamesList accepted
          @?= [ (EnvName "ENVIRONMENT", BoundTo runtimeEnvironment),
                (EnvName "DATABASE_URL", BoundTo databasePassword),
                (EnvName "PORT", BoundTo optionalValue),
                (EnvName "OTEL_EXPORTER_OTLP_ENDPOINT", ConsumedBy "opentelemetry-sdk")
              ]
        checkSuppliedNames accepted (fmap EnvName ["ENVIRONMENT", "DATABASE_URL", "OTEL_EXPORTER_OTLP_ENDPOINT"]) @?= Right (),
      testCase "reports every unsupported name in supplied order deterministically" $ do
        accepted <- expectAccepted [binding (EnvName "ENVIRONMENT") runtimeEnvironment, binding (EnvName "DATABASE_URL") databasePassword] []
        let supplied = fmap EnvName ["HASKELL_ENV", "DATABASE_URL", "DB_URL"]
            result = checkSuppliedNames accepted supplied
        result @?= Left (UnsupportedSuppliedName (EnvName "HASKELL_ENV") :| [UnsupportedSuppliedName (EnvName "DB_URL")])
        checkSuppliedNames accepted supplied @?= result,
      testCase "empty collection accepts absent bindings" $ do
        accepted <- expectAccepted [binding (EnvName "ENVIRONMENT") runtimeEnvironment] []
        checkSuppliedNames accepted [] @?= Right (),
      testCase "reports duplicates once at their second encounter" $ do
        accepted <- expectAccepted [binding (EnvName "PORT") optionalValue] []
        checkSuppliedNames accepted (fmap EnvName ["PORT", "PORT", "PORT", "HOST", "HOST", "HOST"])
          @?= Left (DuplicateSuppliedName (EnvName "PORT") :| [UnsupportedSuppliedName (EnvName "HOST"), DuplicateSuppliedName (EnvName "HOST")]),
      testCase "allowance scope excludes unrelated inherited variables" $ do
        accepted <-
          expectAccepted
            [binding (EnvName "ENVIRONMENT") runtimeEnvironment]
            [allowance "opentelemetry-sdk" (EnvName "OTEL_EXPORTER_OTLP_ENDPOINT")]
        let snapshot = envSnapshot [("PATH", "bin"), ("HOME", "home"), ("KUBERNETES_SERVICE_HOST", "host"), ("ENVIRONMENT", "production")]
        checkSuppliedNames accepted (fmap EnvName ["ENVIRONMENT", "OTEL_EXPORTER_OTLP_ENDPOINT", "HASKELL_ENV"])
          @?= Left (UnsupportedSuppliedName (EnvName "HASKELL_ENV") :| [])
        snapshotNames snapshot @?= fmap EnvName ["ENVIRONMENT", "HOME", "KUBERNETES_SERVICE_HOST", "PATH"]
        assertBool "snapshot-wide check should be an explicit stricter choice" (isLeft (checkedEnvironmentSource accepted snapshot)),
      testCase "snapshot names are sorted and duplicates are already collapsed" $
        snapshotNames (envSnapshot [("Z", "first"), ("A", "a"), ("Z", "last")]) @?= fmap EnvName ["A", "Z"],
      testCase "validates allowance names and collisions together" $ do
        validated <- expectBindings [binding (EnvName "PORT") optionalValue]
        let declarations = fmap (allowance "external" . EnvName) ["1BAD", "PORT", "Z", "Z", "A", "A", "1BAD"]
        case acceptedNames validated declarations of
          Left errors ->
            NonEmpty.toList errors
              @?= [ InvalidEnvironmentName (EnvName "1BAD"),
                    InvalidEnvironmentName (EnvName "1BAD"),
                    DuplicateEnvironmentName (EnvName "1BAD"),
                    DuplicateEnvironmentName (EnvName "A"),
                    DuplicateEnvironmentName (EnvName "PORT"),
                    DuplicateEnvironmentName (EnvName "Z")
                  ]
          Right _ -> fail "invalid allowances accepted",
      testCase "strict path rejects HASKELL_ENV when ENVIRONMENT is bound" $ do
        accepted <- expectAccepted [binding (EnvName "ENVIRONMENT") runtimeEnvironment] []
        let declaration = required (publicSetting runtimeEnvironment "Runtime environment" (enumDecoder [("development", False), ("production", True)]))
            builtIn = source "built-in defaults" BuiltInSource (RawObject (Map.singleton "runtime" (RawObject (Map.singleton "environment" (RawText "development")))))
            typo = envSnapshot [("HASKELL_ENV", "production")]
            corrected = envSnapshot [("ENVIRONMENT", "production")]
            permissive = environmentSource (acceptedBindings accepted) corrected
        expectResolution (resolve defaultResolveOptions [builtIn, environmentSource (acceptedBindings accepted) typo] declaration) >>= (@?= False)
        case checkedEnvironmentSource accepted typo of
          Left errors -> errors @?= UnsupportedSuppliedName (EnvName "HASKELL_ENV") :| []
          Right _ -> fail "typo hidden by default"
        strictSource <- either (fail . show) pure (checkedEnvironmentSource accepted corrected)
        expectResolution (resolve defaultResolveOptions [builtIn, strictSource] declaration) >>= (@?= True)
        case (lookupSource runtimeEnvironment strictSource, lookupSource runtimeEnvironment permissive) of
          (Right (Just actual), Right (Just expected)) -> do
            candidateOrigin actual @?= candidateOrigin expected
            candidateOrigin actual ^. #annotations . at "environment.variable" @?= Just "ENVIRONMENT"
          _ -> fail "expected strict and permissive candidates"
        labeled <- either (fail . show) pure (checkedEnvSource "deployment" accepted corrected)
        case lookupSource runtimeEnvironment labeled of
          Right (Just found) -> candidateOrigin found ^. #name @?= "deployment"
          _ -> fail "expected custom source label",
      testCase "sentinels never reach supplied-name diagnostics" $ do
        accepted <- expectAccepted [binding (EnvName "ENVIRONMENT") runtimeEnvironment] []
        let unknownSentinel = "unknown-value-sentinel"
        case checkedEnvironmentSource accepted (envSnapshot [("ENVIRONMENT", secretSentinel), ("HASKELL_ENV", unknownSentinel)]) of
          Left errors -> do
            let outputs = [Text.pack (show errors), renderSuppliedNameErrorsText errors, renderSuppliedNameErrorsJson errors]
            sequence_ [assertBool "value leaked" (not (sentinel `Text.isInfixOf` output)) | output <- outputs, sentinel <- [secretSentinel, unknownSentinel]]
          Right _ -> fail "expected strict failure",
      testCase "successful strict source still redacts secrets" $ do
        accepted <- expectAccepted [binding (EnvName "DATABASE_PASSWORD") databasePassword] []
        input <- either (fail . show) pure (checkedEnvironmentSource accepted (envSnapshot [("DATABASE_PASSWORD", secretSentinel)]))
        let result = resolve defaultResolveOptions [input] (required passwordSetting)
        _ <- expectResolution result
        assertBool "secret leaked from strict source" (not (secretSentinel `Text.isInfixOf` renderResolutionText (result ^. #report))),
      suppliedNameRenderingTests
    ]

expectAccepted :: [EnvBinding] -> [Allowance] -> IO AcceptedNames
expectAccepted values allowances = do
  validated <- expectBindings values
  either (fail . show) pure (acceptedNames validated allowances)

suppliedNameRenderingTests :: TestTree
suppliedNameRenderingTests =
  testGroup
    "rendering"
    [ testCase "portable text and exact versioned JSON are stable" $ do
        let errors = UnsupportedSuppliedName (EnvName "HASKELL_ENV") :| [DuplicateSuppliedName (EnvName "PORT")]
            expected = "{\"schemaVersion\":1,\"type\":\"settei.supplied-names\",\"errors\":[{\"kind\":\"unsupported-supplied-name\",\"name\":\"HASKELL_ENV\"},{\"kind\":\"duplicate-supplied-name\",\"name\":\"PORT\"}]}"
        renderSuppliedNameErrorsText errors @?= "supplied environment variable HASKELL_ENV: no binding or allowance accepts it\nsupplied environment variable PORT: supplied more than once\n"
        renderSuppliedNameErrorsJson errors @?= expected
        renderSuppliedNameErrorsJson errors @?= renderSuppliedNameErrorsJson errors,
      testCase "hostile names retain spelling but escape text and JSON independently" $ do
        accepted <- expectAccepted [] []
        let name = EnvName "BAD\"\\\n\SOHNAME"
            problem = UnsupportedSuppliedName name
            duplicate = DuplicateSuppliedName name
        checkSuppliedNames accepted [name] @?= Left (problem :| [])
        renderSuppliedNameErrorText problem @?= "supplied environment variable \"BAD\\\"\\\\\\n\\u0001NAME\": no binding or allowance accepts it"
        renderSuppliedNameErrorText duplicate @?= "supplied environment variable \"BAD\\\"\\\\\\n\\u0001NAME\": supplied more than once"
        renderSuppliedNameErrorsText (problem :| [duplicate]) @?= Text.unlines [renderSuppliedNameErrorText problem, renderSuppliedNameErrorText duplicate]
        renderSuppliedNameErrorsJson (problem :| []) @?= "{\"schemaVersion\":1,\"type\":\"settei.supplied-names\",\"errors\":[{\"kind\":\"unsupported-supplied-name\",\"name\":\"BAD\\\"\\\\\\n\\u0001NAME\"}]}",
      testGroup
        "nonportable display names"
        [ testCase (show original) $ do
            let errors = UnsupportedSuppliedName (EnvName original) :| [DuplicateSuppliedName (EnvName original)]
                sentences = ["supplied environment variable " <> escaped <> ": " <> suffix | suffix <- ["no binding or allowance accepts it", "supplied more than once"]]
            fmap renderSuppliedNameErrorText (NonEmpty.toList errors) @?= sentences
            renderSuppliedNameErrorsText errors @?= Text.unlines sentences
            length (Text.lines (renderSuppliedNameErrorsText errors)) @?= 2
        | (original, escaped) <-
            [("", "\"\""), ("with space", "\"with space\""), ("\r", "\"\\r\""), ("\t", "\"\\t\""), ("\ESC", "\"\\u001b\""), ("\DEL", "\"\\u007f\""), ("\x85", "\"\\u0085\""), ("\x2028", "\"\\u2028\""), ("\x2029", "\"\\u2029\"")]
        ]
    ]

bindingMergingTests :: TestTree
bindingMergingTests =
  testGroup
    "merging validated bindings"
    [ testCase "preserves disjoint collections in order" $ do
        let firstValues = [binding (EnvName "SERVICE_HOST") serviceHost]
            secondValues = [binding (EnvName "DATABASE_PASSWORD") databasePassword]
        first <- expectBindings firstValues
        second <- expectBindings secondValues
        merged <- either (fail . show) pure (mergeBindings [first, second])
        assertBool
          "merged bindings did not preserve collection order"
          (bindingsList merged == firstValues <> secondValues),
      testCase "rejects a cross-collection duplicate variable name" $ do
        first <- expectBindings [binding (EnvName "SERVICE_VALUE") serviceHost]
        second <- expectBindings [binding (EnvName "SERVICE_VALUE") databasePassword]
        assertLeftContains isDuplicateName (mergeBindings [first, second]),
      testCase "rejects cross-collection overlapping target keys" $ do
        first <- expectBindings [binding (EnvName "SERVICE") (validKey "service")]
        second <- expectBindings [binding (EnvName "SERVICE_PORT") (validKey "service.port")]
        assertLeftContains isConflict (mergeBindings [first, second]),
      testCase "accepts an empty collection list" $ do
        merged <- either (fail . show) pure (mergeBindings [])
        assertBool "empty merge produced bindings" (null (bindingsList merged))
    ]

errorRenderingTests :: TestTree
errorRenderingTests =
  testGroup
    "error rendering"
    [ testCase "invalid environment name" $
        renderEnvErrorText (InvalidEnvironmentName (EnvName "http port"))
          @?= "environment binding http port: invalid variable name",
      testCase "duplicate environment name" $
        renderEnvErrorText (DuplicateEnvironmentName (EnvName "HTTP_PORT"))
          @?= "environment binding HTTP_PORT: variable bound more than once",
      testCase "duplicate target key" $
        renderEnvErrorText (DuplicateTargetKey (validKey "http.port"))
          @?= "bindings target the same key http.port twice",
      testCase "conflicting target keys" $
        renderEnvErrorText
          (ConflictingTargetKeys (validKey "http") (validKey "http.port"))
          @?= "bindings target overlapping keys http and http.port",
      testCase "prefixed name collision" $
        renderEnvErrorText
          ( PrefixedNameCollision
              (EnvName "MYAPP_SERVICE_HTTP_PORT")
              (validKey "service.http-port" :| [validKey "service.http_port"])
          )
          @?= "environment binding MYAPP_SERVICE_HTTP_PORT: normalized name collides for keys service.http-port, service.http_port",
      testCase "plural rendering is singular rendering plus a newline" $ do
        let problem = InvalidEnvironmentName (EnvName "http port")
        renderEnvErrorsText (NonEmpty.singleton problem)
          @?= renderEnvErrorText problem <> "\n"
    ]

expectSource :: [EnvBinding] -> [(Text, Text)] -> IO Source
expectSource values snapshot = expectSourceWith values snapshot

expectBindings :: [EnvBinding] -> IO Bindings
expectBindings values = either (fail . show) pure (bindings values)

expectSourceWith :: [EnvBinding] -> [(Text, Text)] -> IO Source
expectSourceWith values snapshot = do
  validated <- expectBindings values
  pure (envSource "environment" validated (envSnapshot snapshot))

expectResolution :: ResolveResult a -> IO a
expectResolution result = case result ^. #answer of
  Left _ -> fail "expected successful resolution"
  Right value -> pure value

assertLeftContains :: (EnvError -> Bool) -> Either (NonEmpty EnvError) a -> IO ()
assertLeftContains predicate = \case
  Left errors -> assertBool "expected matching validation error" (any predicate (NonEmpty.toList errors))
  Right _ -> fail "expected binding validation to fail"

isDuplicateName :: EnvError -> Bool
isDuplicateName (DuplicateEnvironmentName _) = True
isDuplicateName _ = False

isInvalidName :: EnvError -> Bool
isInvalidName (InvalidEnvironmentName _) = True
isInvalidName _ = False

isDuplicateKey :: EnvError -> Bool
isDuplicateKey (DuplicateTargetKey _) = True
isDuplicateKey _ = False

isPrefixCollision :: EnvError -> Bool
isPrefixCollision (PrefixedNameCollision _ _) = True
isPrefixCollision _ = False

isConflict :: EnvError -> Bool
isConflict (ConflictingTargetKeys _ _) = True
isConflict _ = False

passwordSetting :: Setting Text
passwordSetting = secretSetting databasePassword "Database password" textDecoder

hostSetting :: Setting Text
hostSetting = publicSetting serviceHost "Service host" textDecoder

runtimeEnvironment :: Key
runtimeEnvironment = validKey "runtime.environment"

optionalValue :: Key
optionalValue = validKey "optional.value"

databasePassword :: Key
databasePassword = validKey "database.password"

serviceHost :: Key
serviceHost = validKey "service.host"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)

secretSentinel :: Text
secretSentinel = "never-render-this-secret"
