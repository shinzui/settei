{-# LANGUAGE ImportQualifiedPost #-}

module Settei.KubernetesTest (tests) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Settei
import Settei.Kubernetes
import Settei.Prelude
import System.Directory qualified as Directory
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Kubernetes"
    [ atomicWriterTests,
      bindingValidationTests,
      missingAndErrorTests,
      newlineTests,
      provenanceTests,
      rendererTests
    ]

atomicWriterTests :: TestTree
atomicWriterTests =
  testGroup
    "atomic writer layout"
    [ testCase "reads bound keys through ..data symlinks" $
        withSystemTempDirectory "settei-kubernetes" $ \root -> do
          atomicWriterFixture
            root
            [ ("password", ByteString8.pack "s3cr3t"),
              ("http-host", ByteString8.pack "api.internal")
            ]
          validated <- expectBindings [fileBinding "password" passwordKey, fileBinding "http-host" hostKey]
          input <- expectSource =<< readMountedDirectorySource defaultOptions validated root
          value <- expectAnswer (resolve defaultResolveOptions [input] serviceConfig)
          value @?= ("s3cr3t", "api.internal"),
      testCase "unboundMountedFiles skips atomic-writer entries" $
        withSystemTempDirectory "settei-kubernetes" $ \root -> do
          atomicWriterFixture
            root
            [ ("password", ByteString8.pack "s3cr3t"),
              ("http-host", ByteString8.pack "api.internal")
            ]
          validated <- expectBindings [fileBinding "password" passwordKey]
          unbound <- unboundMountedFiles validated root
          unbound @?= ["http-host"]
    ]

bindingValidationTests :: TestTree
bindingValidationTests =
  testGroup
    "binding validation"
    [ invalidNameTest "" "rejects empty file names",
      invalidNameTest "a/b" "rejects path separators",
      invalidNameTest "." "rejects the current-directory name",
      invalidNameTest ".." "rejects the parent-directory name",
      invalidNameTest "..data" "rejects atomic-writer names",
      invalidNameTest (Text.pack ['a', '\NUL']) "rejects NUL in file names",
      testCase "rejects duplicate file names" $ do
        errors <-
          expectBindingErrors
            [fileBinding "value" passwordKey, fileBinding "value" hostKey]
        categories errors @?= [KubernetesDuplicateFileName],
      testCase "rejects duplicate target keys" $ do
        errors <-
          expectBindingErrors
            [fileBinding "first" passwordKey, fileBinding "second" passwordKey]
        categories errors @?= [KubernetesDuplicateTargetKey],
      testCase "rejects prefix-overlapping target keys" $ do
        errors <-
          expectBindingErrors
            [fileBinding "database" databaseKey, fileBinding "password" passwordKey]
        categories errors @?= [KubernetesConflictingTargetKeys],
      testCase "accumulates independent binding problems" $ do
        errors <-
          expectBindingErrors
            [ fileBinding "a/b" databaseKey,
              fileBinding "same" passwordKey,
              fileBinding "same" passwordKey
            ]
        categories errors
          @?= [ KubernetesInvalidFileName,
                KubernetesDuplicateFileName,
                KubernetesDuplicateTargetKey,
                KubernetesConflictingTargetKeys,
                KubernetesConflictingTargetKeys
              ],
      testCase "accepts an empty binding collection" $ do
        validated <- expectBindings []
        assertBool "empty bindings were not retained" (null (fileBindingsList validated))
    ]

missingAndErrorTests :: TestTree
missingAndErrorTests =
  testGroup
    "missing files and input failures"
    [ testCase "an absent bound file stays a resolver concern" $
        withSystemTempDirectory "settei-kubernetes" $ \root -> do
          validated <- expectBindings [fileBinding "missing" passwordKey]
          input <- expectSource =<< readMountedDirectorySource defaultOptions validated root
          case resolve defaultResolveOptions [input] (required passwordSetting) ^. #answer of
            Left errors -> case NonEmpty.toList errors of
              [MissingRequired problem] -> problem ^. #key @?= passwordKey
              _ -> fail "expected one missing-required error"
            Right _ -> fail "expected the required setting to be absent"
          optionalValue <- expectAnswer (resolve defaultResolveOptions [input] (optional passwordSetting))
          optionalValue @?= Nothing,
      testCase "invalid UTF-8 is categorized without retaining bytes" $
        withSystemTempDirectory "settei-kubernetes" $ \root -> do
          atomicWriterFixture root [("password", ByteString.pack [255, 254, 1])]
          validated <- expectBindings [fileBinding "password" passwordKey]
          problem <- expectSingleError =<< readMountedDirectorySource defaultOptions validated root
          kubernetesErrorCategory problem @?= KubernetesInvalidUtf8
          kubernetesErrorPath problem @?= Just (root </> "password")
          kubernetesErrorMessage problem @?= "file content is not valid UTF-8"
          let safeMessage = Text.toLower (kubernetesErrorMessage problem)
          assertBool "error message exposed hexadecimal content" (not ("ff" `Text.isInfixOf` safeMessage))
          assertBool "error message exposed decimal content" (not ("255" `Text.isInfixOf` safeMessage)),
      testCase "a regular file cannot be used as the mount directory" $
        withSystemTempDirectory "settei-kubernetes" $ \root -> do
          let regularFile = root </> "mount"
          ByteString8.writeFile regularFile "value"
          validated <- expectBindings []
          problem <- expectSingleError =<< readMountedDirectorySource defaultOptions validated regularFile
          kubernetesErrorCategory problem @?= KubernetesNotADirectory
          kubernetesErrorPath problem @?= Just regularFile,
      testCase "an unreadable entry is an accumulated IO error" $
        withSystemTempDirectory "settei-kubernetes" $ \root -> do
          Directory.createDirectory (root </> "password")
          validated <- expectBindings [fileBinding "password" passwordKey]
          problem <- expectSingleError =<< readMountedDirectorySource defaultOptions validated root
          kubernetesErrorCategory problem @?= KubernetesIoError
          kubernetesErrorPath problem @?= Just (root </> "password"),
      testCase "a dangling visible symlink behaves as an absent file" $
        withSystemTempDirectory "settei-kubernetes" $ \root -> do
          Directory.createFileLink ("..data" </> "missing") (root </> "broken")
          validated <- expectBindings [fileBinding "broken" passwordKey]
          input <- expectSource =<< readMountedDirectorySource defaultOptions validated root
          case lookupSource passwordKey input of
            Right Nothing -> pure ()
            _ -> fail "expected a dangling symlink to contribute no leaf"
    ]

newlineTests :: TestTree
newlineTests =
  testGroup
    "trailing newline policy"
    [ newlineCase "strips exactly one newline by default" defaultOptions "s3cr3t\n\n" "s3cr3t\n",
      newlineCase "preserves a trailing newline when requested" (keepTrailingNewline defaultOptions) "s3cr3t\n" "s3cr3t\n",
      newlineCase "leaves text without a newline unchanged" defaultOptions "s3cr3t" "s3cr3t"
    ]

provenanceTests :: TestTree
provenanceTests =
  testGroup
    "provenance"
    [ testCase "retains file location, Kubernetes identity, and caller annotations" $
        withSystemTempDirectory "settei-kubernetes" $ \root -> do
          atomicWriterFixture root [("password", ByteString8.pack "s3cr3t")]
          validated <-
            expectBindings
              [ annotateFileBinding
                  (Map.fromList [("owner", "payments"), ("kubernetes.object-name", "wrong")])
                  (fileBinding "password" passwordKey)
              ]
          input <- expectSource =<< readMountedDirectorySource annotatedOptions validated root
          let result = resolve defaultResolveOptions [input] (required passwordSetting)
          _ <- expectAnswer result
          origin <- case result ^. #report . #nodes . at passwordKey of
            Just node -> case node ^. #origin of
              Just value -> pure value
              Nothing -> fail "expected a chosen origin"
            Nothing -> fail "expected the password report node"
          origin ^. #kind @?= CustomSource "kubernetes-mounted-directory"
          origin ^? #location . _Just . #path @?= Just (Text.pack (root </> "password"))
          origin ^? #location . _Just . #line @?= Just Nothing
          origin ^? #location . _Just . #column @?= Just Nothing
          origin ^. #annotations . at "kubernetes.object-kind" @?= Just "Secret"
          origin ^. #annotations . at "kubernetes.namespace" @?= Just "prod"
          origin ^. #annotations . at "kubernetes.object-name" @?= Just "app-credentials"
          origin ^. #annotations . at "kubernetes.object-key" @?= Just "password"
          origin ^. #annotations . at "owner" @?= Just "payments"
          origin ^. #annotations . at "deployment" @?= Just "blue"
          assertBool
            "rendered report omitted Kubernetes mounted-directory provenance"
            ( "kubernetes-mounted-directory source app-secrets from Kubernetes Secret prod/app-credentials key password"
                `Text.isInfixOf` renderResolutionText (result ^. #report)
            ),
      testCase "option and binding accessors expose construction choices" $ do
        let bindingValue = annotateFileBinding (Map.singleton "owner" "payments") (fileBinding "password" passwordKey)
            options = annotateMountedDirectoryOptions (Map.singleton "deployment" "blue") defaultOptions
        fileBindingName bindingValue @?= "password"
        fileBindingKey bindingValue @?= passwordKey
        fileBindingAnnotations bindingValue @?= Map.singleton "owner" "payments"
        mountedDirectoryName options @?= "app-secrets"
        mountedDirectoryRef options @?= secretReference
        mountedDirectoryAnnotations options @?= Map.singleton "deployment" "blue"
        mountedDirectoryKeepsTrailingNewline options @?= False
        mountedDirectoryKeepsTrailingNewline (keepTrailingNewline options) @?= True
    ]

rendererTests :: TestTree
rendererTests =
  testGroup
    "error renderers"
    [ testCase "renders each binding category exactly" $ do
        invalid <- expectOnlyError [fileBinding "a/b" passwordKey]
        duplicateName <- expectOnlyError [fileBinding "tls.crt" passwordKey, fileBinding "tls.crt" hostKey]
        duplicateTarget <- expectOnlyError [fileBinding "one" passwordKey, fileBinding "two" passwordKey]
        overlap <- expectOnlyError [fileBinding "database" databaseKey, fileBinding "password" passwordKey]
        renderKubernetesErrorText invalid
          @?= "file bindings: file name \"a/b\" contains a path separator or is reserved"
        renderKubernetesErrorText duplicateName
          @?= "file bindings: file name \"tls.crt\" is bound more than once"
        renderKubernetesErrorText duplicateTarget
          @?= "file bindings: target key database.password is bound more than once"
        renderKubernetesErrorText overlap
          @?= "file bindings: target keys database and database.password overlap",
      testCase "renders read-time categories with source and path" $
        withSystemTempDirectory "settei-kubernetes" $ \root -> do
          let regularFile = root </> "mount"
          ByteString8.writeFile regularFile "value"
          validatedEmpty <- expectBindings []
          notDirectory <- expectSingleError =<< readMountedDirectorySource defaultOptions validatedEmpty regularFile
          renderKubernetesErrorText notDirectory
            @?= Text.pack ("app-secrets (" <> regularFile <> "): mounted path is not a directory")

          Directory.createDirectory (root </> "unreadable")
          validatedIo <- expectBindings [fileBinding "unreadable" passwordKey]
          ioProblem <- expectSingleError =<< readMountedDirectorySource defaultOptions validatedIo root
          renderKubernetesErrorText ioProblem
            @?= Text.pack ("app-secrets (" <> root </> "unreadable" <> "): ")
              <> kubernetesErrorMessage ioProblem

          withSystemTempDirectory "settei-kubernetes-utf8" $ \utf8Root -> do
            atomicWriterFixture utf8Root [("password", ByteString.pack [255])]
            validatedUtf8 <- expectBindings [fileBinding "password" passwordKey]
            invalidUtf8 <- expectSingleError =<< readMountedDirectorySource defaultOptions validatedUtf8 utf8Root
            renderKubernetesErrorText invalidUtf8
              @?= Text.pack ("app-secrets (" <> utf8Root </> "password" <> "): file content is not valid UTF-8"),
      testCase "plural renderer emits one line per problem" $ do
        errors <-
          expectBindingErrors
            [fileBinding "same" passwordKey, fileBinding "same" passwordKey]
        renderKubernetesErrorsText errors
          @?= Text.unlines
            [ "file bindings: file name \"same\" is bound more than once",
              "file bindings: target key database.password is bound more than once"
            ]
    ]

atomicWriterFixture :: FilePath -> [(FilePath, ByteString)] -> IO ()
atomicWriterFixture root entries = do
  let payloadName = "..2026_07_19_12_00_00.123"
      payload = root </> payloadName
  Directory.createDirectory payload
  mapM_ (\(name, bytes) -> ByteString.writeFile (payload </> name) bytes) entries
  Directory.createDirectoryLink payloadName (root </> "..data")
  mapM_ (\(name, _) -> Directory.createFileLink ("..data" </> name) (root </> name)) entries

invalidNameTest :: Text -> String -> TestTree
invalidNameTest fileName label =
  testCase label $ do
    errors <- expectBindingErrors [fileBinding fileName passwordKey]
    categories errors @?= [KubernetesInvalidFileName]

newlineCase :: String -> MountedDirectoryOptions -> ByteString -> Text -> TestTree
newlineCase label options bytes expected =
  testCase label $
    withSystemTempDirectory "settei-kubernetes" $ \root -> do
      atomicWriterFixture root [("password", bytes)]
      validated <- expectBindings [fileBinding "password" passwordKey]
      input <- expectSource =<< readMountedDirectorySource options validated root
      value <- expectAnswer (resolve defaultResolveOptions [input] (required passwordSetting))
      value @?= expected

expectBindings :: [FileBinding] -> IO FileBindings
expectBindings values = case fileBindings values of
  Left errors -> fail (Text.unpack (renderKubernetesErrorsText errors))
  Right validated -> pure validated

expectBindingErrors :: [FileBinding] -> IO (NonEmpty KubernetesSourceError)
expectBindingErrors values = case fileBindings values of
  Left errors -> pure errors
  Right _ -> fail "expected invalid file bindings"

expectOnlyError :: [FileBinding] -> IO KubernetesSourceError
expectOnlyError values = do
  errors <- expectBindingErrors values
  case NonEmpty.toList errors of
    [problem] -> pure problem
    _ -> fail "expected exactly one binding error"

expectSource :: Either (NonEmpty KubernetesSourceError) Source -> IO Source
expectSource = \case
  Left errors -> fail (Text.unpack (renderKubernetesErrorsText errors))
  Right input -> pure input

expectSingleError :: Either (NonEmpty KubernetesSourceError) Source -> IO KubernetesSourceError
expectSingleError = \case
  Left errors -> case NonEmpty.toList errors of
    [problem] -> pure problem
    _ -> fail "expected exactly one source error"
  Right _ -> fail "expected source construction to fail"

expectAnswer :: ResolveResult a -> IO a
expectAnswer result = case result ^. #answer of
  Left _ -> fail "expected configuration resolution to succeed"
  Right value -> pure value

categories :: NonEmpty KubernetesSourceError -> [KubernetesErrorCategory]
categories = fmap kubernetesErrorCategory . NonEmpty.toList

defaultOptions :: MountedDirectoryOptions
defaultOptions = mountedDirectoryOptions "app-secrets" secretReference

annotatedOptions :: MountedDirectoryOptions
annotatedOptions =
  annotateMountedDirectoryOptions (Map.singleton "deployment" "blue") defaultOptions

secretReference :: KubernetesRef
secretReference = kubernetesRef SecretObject (Just "prod") "app-credentials" (Just "ignored")

serviceConfig :: Config (Text, Text)
serviceConfig = (,) <$> required passwordSetting <*> required hostSetting

passwordSetting :: Setting Text
passwordSetting = secretSetting passwordKey "Database password" textDecoder

hostSetting :: Setting Text
hostSetting = publicSetting hostKey "HTTP host" textDecoder

databaseKey :: Key
databaseKey = unsafeKey "database"

passwordKey :: Key
passwordKey = unsafeKey "database.password"

hostKey :: Key
hostKey = unsafeKey "service.http.host"

unsafeKey :: Text -> Key
unsafeKey value = case parseKey value of
  Left problem -> error (show problem)
  Right key -> key
