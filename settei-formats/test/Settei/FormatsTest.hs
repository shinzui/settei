{-# LANGUAGE ImportQualifiedPost #-}

module Settei.FormatsTest (tests) where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Paths_settei_formats qualified as Paths
import Settei
import Settei.Dhall qualified as Dhall
import Settei.Formats
import Settei.Kdl qualified as Kdl
import Settei.Prelude
import Settei.Yaml qualified as Yaml
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Formats"
    [ testGroup
        "FORMAT:PATH grammar"
        [ testCase "accepts yaml, kdl, and dhall tags" $ do
            assertParsed "yaml:app.yaml" YamlFormat "app.yaml"
            assertParsed "kdl:app.kdl" KdlFormat "app.kdl"
            assertParsed "dhall:app.dhall" DhallFormat "app.dhall",
          testCase "splits only at the first colon" $
            assertParsed
              "yaml:dir:with:colons.yaml"
              YamlFormat
              "dir:with:colons.yaml",
          testCase "rejects missing separators and empty paths" $ do
            parseConfigInput "app.yaml" @?= Left "expected FORMAT:PATH"
            parseConfigInput "yaml:" @?= Left "expected FORMAT:PATH",
          testCase "rejects unsupported and empty format names" $ do
            parseConfigInput "toml:app.toml"
              @?= Left "FORMAT must be yaml, kdl, or dhall"
            parseConfigInput ":app.yaml"
              @?= Left "FORMAT must be yaml, kdl, or dhall"
        ],
      testGroup
        "adapter dispatch"
        [ testCase "loads YAML and resolves a typed value" $
            assertFixtureLoads YamlFormat "test/fixtures/app.yaml",
          testCase "loads KDL and resolves a typed value" $
            assertFixtureLoads KdlFormat "test/fixtures/app.kdl",
          testCase "loads Dhall and resolves a typed value" $
            assertFixtureLoads DhallFormat "test/fixtures/app.dhall"
        ],
      testCase "Kubernetes and caller annotations reach YAML and Dhall sources" $ do
        yamlPath <- Paths.getDataFileName "test/fixtures/app.yaml"
        dhallPath <- Paths.getDataFileName "test/fixtures/app.dhall"
        let reference =
              kubernetesRef
                ConfigMapObject
                Nothing
                "settei-formats-test"
                (Just "app.yaml")
            options =
              fromKubernetesMountedFile
                reference
                ( annotateLoadOptions
                    (Map.singleton "team" "platform")
                    defaultLoadOptions
                )
        yamlSource <- expectLoaded options (configInput YamlFormat yamlPath)
        assertAnnotations yamlSource
        dhallSource <- expectLoaded options (configInput DhallFormat dhallPath)
        assertAnnotations dhallSource,
      testCase "Dhall imports are denied by default and allowed explicitly" $ do
        importPath <- Paths.getDataFileName "test/fixtures/imports.dhall"
        fixturesDirectory <- Paths.getDataFileName "test/fixtures"
        loadOptionsDhallImportPolicy defaultLoadOptions @?= Dhall.NoImports
        denied <- loadConfigInput defaultLoadOptions (configInput DhallFormat importPath)
        case denied of
          Left outerErrors -> case NonEmpty.toList outerErrors of
            [DhallLoadError problems] ->
              fmap Dhall.dhallErrorCategory (NonEmpty.toList problems)
                @?= [Dhall.DhallImportPolicyError]
            _ -> fail "expected one Dhall load error"
          Right _ -> fail "expected the default Dhall policy to reject imports"
        imported <-
          expectLoaded
            ( withDhallImportPolicy
                (Dhall.LocalImportsWithin fixturesDirectory)
                defaultLoadOptions
            )
            (configInput DhallFormat importPath)
        assertResolvedEndpoint imported,
      testCase "a missing YAML file is a structured load error" $ do
        missing <-
          loadConfigInput
            defaultLoadOptions
            (configInput YamlFormat "settei-formats-missing.yaml")
        case missing of
          Left outerErrors -> case NonEmpty.toList outerErrors of
            [YamlLoadError problems] ->
              fmap Yaml.yamlErrorCategory (NonEmpty.toList problems)
                @?= [Yaml.YamlIoError]
            _ -> fail "expected one YAML load error"
          Right _ -> fail "expected a missing YAML file to fail",
      testCase "format load errors delegate to adapter renderers" $ do
        yamlError <- expectLoadError YamlFormat "settei-formats-missing.yaml"
        case yamlError of
          YamlLoadError problems ->
            renderFormatLoadErrorText yamlError @?= Yaml.renderYamlErrorsText problems
          _ -> fail "expected a YAML load error"
        kdlError <- expectLoadError KdlFormat "settei-formats-missing.kdl"
        case kdlError of
          KdlLoadError problems ->
            renderFormatLoadErrorText kdlError @?= Kdl.renderKdlErrorsText problems
          _ -> fail "expected a KDL load error"
        dhallError <- expectLoadError DhallFormat "settei-formats-missing.dhall"
        case dhallError of
          DhallLoadError problems ->
            renderFormatLoadErrorText dhallError @?= Dhall.renderDhallErrorsText problems
          _ -> fail "expected a Dhall load error"
    ]

assertParsed :: String -> ConfigFormat -> FilePath -> IO ()
assertParsed input expectedFormat expectedPath = case parseConfigInput input of
  Left problem -> fail problem
  Right parsed -> do
    configInputFormat parsed @?= expectedFormat
    configInputPath parsed @?= expectedPath

assertFixtureLoads :: ConfigFormat -> FilePath -> IO ()
assertFixtureLoads format relativePath = do
  fixturePath <- Paths.getDataFileName relativePath
  loaded <- expectLoaded defaultLoadOptions (configInput format fixturePath)
  assertResolvedEndpoint loaded

expectLoaded :: LoadOptions -> ConfigInput -> IO Source
expectLoaded options input = do
  result <- loadConfigInput options input
  case result of
    Left problems -> fail (show problems)
    Right loaded -> pure loaded

expectLoadError :: ConfigFormat -> FilePath -> IO FormatLoadError
expectLoadError format path = do
  result <- loadConfigInput defaultLoadOptions (configInput format path)
  case result of
    Left problems -> case NonEmpty.toList problems of
      [problem] -> pure problem
      _ -> fail "expected one format load error"
    Right _ -> fail "expected format loading to fail"

assertResolvedEndpoint :: Source -> IO ()
assertResolvedEndpoint input =
  case (resolve defaultResolveOptions [input] endpointConfig) ^. #answer of
    Left problems -> fail (show problems)
    Right endpoint -> endpoint @?= "https://example.test"

assertAnnotations :: Source -> IO ()
assertAnnotations input = do
  Map.lookup "kubernetes.object-kind" (sourceAnnotations input) @?= Just "ConfigMap"
  Map.lookup "kubernetes.object-name" (sourceAnnotations input)
    @?= Just "settei-formats-test"
  Map.lookup "team" (sourceAnnotations input) @?= Just "platform"

endpointConfig :: Config Text
endpointConfig =
  required (publicSetting endpointKey "Service endpoint" textDecoder)

endpointKey :: Key
endpointKey = either (error . show) id (parseKey "service.endpoint")
