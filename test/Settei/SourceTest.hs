{-# LANGUAGE ImportQualifiedPost #-}

module Settei.SourceTest (tests) where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Settei
import Settei.Prelude
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Settei.Source"
    [ testCase "hierarchical keys traverse objects by segment" $ do
        let result = lookupSource servicePort sampleSource
        case result of
          Right (Just found) -> do
            assertBool "expected the nested port" (candidateValue found == RawNumber 8080)
            candidateOrigin found ^. #key @?= servicePort
          _ -> fail "expected one candidate",
      testCase "arrays are values at their exact declared key" $ do
        let result = lookupSource serviceHosts sampleSource
        case result of
          Right (Just found) ->
            assertBool
              "expected the complete array"
              (candidateValue found == RawArray [RawText "one", RawText "two"])
          _ -> fail "expected one array candidate",
      testCase "traversal through a scalar is a structural error" $ do
        let result = lookupSource servicePortChild sampleSource
        case result of
          Left structuralError -> do
            structuralError ^. #key @?= servicePortChild
            structuralError ^. #blockedAt @?= servicePort
            structuralError ^. #shape @?= ScalarShape
          _ -> fail "expected a structural error",
      testCase "leaf enumeration is ordered and treats arrays wholesale" $
        fmap (renderKey . fst) (sourceLeaves sampleSource)
          @?= ["service.hosts", "service.port"]
    ]

sampleSource :: Source
sampleSource =
  source
    "built-in"
    BuiltInSource
    ( RawObject
        ( Map.singleton
            "service"
            ( RawObject
                ( Map.fromList
                    [ ("hosts", RawArray [RawText "one", RawText "two"]),
                      ("port", RawNumber 8080)
                    ]
                )
            )
        )
    )

servicePort :: Key
servicePort = validKey "service.port"

serviceHosts :: Key
serviceHosts = validKey "service.hosts"

servicePortChild :: Key
servicePortChild = validKey "service.port.number"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
