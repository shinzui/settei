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
          @?= ["service.hosts", "service.port"],
      testCase "source annotations compose across repeated calls" $
        sourceAnnotations
          ( annotateSource
              (Map.singleton "b" "2")
              (annotateSource (Map.singleton "a" "1") sampleSource)
          )
          @?= Map.fromList [("a", "1"), ("b", "2")],
      testCase "later source annotations win on collision" $
        sourceAnnotations
          ( annotateSource
              (Map.singleton "a" "new")
              (annotateSource (Map.singleton "a" "old") sampleSource)
          )
          ^. at "a"
          @?= Just "new",
      testCase "candidate origins observe merged source annotations" $ do
        let annotated =
              annotateSource
                (Map.singleton "b" "2")
                (annotateSource (Map.singleton "a" "1") sampleSource)
        case lookupSource servicePort annotated of
          Right (Just found) ->
            candidateOrigin found ^. #annotations
              @?= Map.fromList [("a", "1"), ("b", "2")]
          _ -> fail "expected the annotated source candidate",
      testCase "validated source pairs build addressable sibling leaves" $ do
        let serviceHost = validKey "service.host"
            result =
              sourceFromPairs
                "custom"
                BuiltInSource
                [ (servicePort, RawNumber 8080),
                  (serviceHost, RawText "db")
                ]
        case result of
          Left errors -> fail ("expected a valid source, got " <> show errors)
          Right built -> do
            fmap (renderKey . fst) (sourceLeaves built)
              @?= ["service.host", "service.port"]
            sourceUnaddressableLeaves built @?= []
            case (lookupSource servicePort built, lookupSource serviceHost built) of
              (Right (Just port), Right (Just host)) -> do
                assertBool "expected the inserted port" (candidateValue port == RawNumber 8080)
                assertBool "expected the inserted host" (candidateValue host == RawText "db")
              _ -> fail "expected both inserted candidates to be addressable",
      testCase "validated source pairs reject duplicate keys" $
        ( sourceFromPairs
            "custom"
            BuiltInSource
            [(servicePort, RawNumber 8080), (servicePort, RawNumber 9090)]
            & either id (const (error "expected duplicate rejection"))
        )
          @?= DuplicateSourceKey servicePort :| [],
      testCase "validated source pairs reject prefix overlaps" $
        let service = validKey "service"
         in ( sourceFromPairs
                "custom"
                BuiltInSource
                [(service, RawText "scalar"), (servicePort, RawNumber 8080)]
                & either id (const (error "expected overlap rejection"))
            )
              @?= OverlappingSourceKeys service servicePort :| [],
      testCase "unvalidated dotted leaves are visible to inspection" $
        let built =
              source
                "custom"
                BuiltInSource
                (RawObject (Map.singleton "a.b" (RawText "hidden")))
         in do
              assertBool "expected no addressable leaves" (null (sourceLeaves built))
              sourceUnaddressableLeaves built @?= [["a.b"]],
      testCase "per-key annotations reach only their matching origins" $ do
        let annotated =
              annotateSourceAt
                (\key -> if key == servicePort then Map.singleton "environment.variable" "PORT" else Map.empty)
                sampleSource
        case (lookupSource servicePort annotated, lookupSource serviceHosts annotated) of
          (Right (Just port), Right (Just hosts)) -> do
            port ^. to candidateOrigin . #annotations . at "environment.variable" @?= Just "PORT"
            hosts ^. to candidateOrigin . #annotations . at "environment.variable" @?= Nothing
          _ -> fail "expected both annotated source candidates"
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
