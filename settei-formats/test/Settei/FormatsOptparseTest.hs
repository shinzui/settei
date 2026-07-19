{-# LANGUAGE ImportQualifiedPost #-}

module Settei.FormatsOptparseTest (tests) where

import Options.Applicative qualified as Options
import Settei.Formats
import Settei.Formats.Optparse
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Formats.Optparse"
    [ testCase "repeated --config inputs preserve occurrence order" $ do
        parsed <-
          expectParse
            configInputOptions
            ["--config", "yaml:a.yaml", "--config", "kdl:b.kdl"]
        parsed
          @?= [ configInput YamlFormat "a.yaml",
                configInput KdlFormat "b.kdl"
              ],
      testCase "no --config occurrence produces an empty list" $ do
        parsed <- expectParse configInputOptions []
        parsed @?= [],
      testCase "an unsupported format fails option parsing" $ do
        let parsed = parse configInputOptions ["--config", "toml:x"]
        assertBool
          "unsupported format unexpectedly parsed"
          (Options.getParseResult parsed == Nothing),
      testCase "caller-supplied option metadata is honored" $ do
        parsed <-
          expectParse
            (configInputOption (Options.long "input" <> Options.metavar "FORMAT:PATH"))
            ["--input", "dhall:c.dhall"]
        parsed @?= [configInput DhallFormat "c.dhall"]
    ]

parse :: Options.Parser a -> [String] -> Options.ParserResult a
parse parser arguments =
  Options.execParserPure Options.defaultPrefs (Options.info parser mempty) arguments

expectParse :: Options.Parser a -> [String] -> IO a
expectParse parser arguments = case parse parser arguments of
  Options.Success value -> pure value
  _ -> fail "expected command-line parsing to succeed"
