{-# LANGUAGE GADTs #-}

-- |
-- Module: Settei.Resolve
-- Description: Deterministic interpretation of declarations against ordered sources.
module Settei.Resolve
  ( ResolveOptions (..),
    ResolveResult (..),
    UnknownKeyPolicy (..),
    defaultResolveOptions,
    resolve,
  )
where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Settei.Error
import Settei.Internal.Config (Config (..), Request (..), describeConfig)
import Settei.Internal.Schema (Schema)
import Settei.Key (Key, keySegments)
import Settei.Prelude
import Settei.Provenance
  ( Candidate,
    candidateOrigin,
    candidateValue,
    reportedValue,
  )
import Settei.Report
import Settei.Schema
  ( SchemaSetting,
    schemaPossible,
    schemaSettingKey,
    schemaSettingSensitivity,
  )
import Settei.Setting
  ( Setting,
    decodeSetting,
    settingKey,
    settingSensitivity,
  )
import Settei.Source (Source, lookupSource, sourceLeaves)
import Settei.Value (decodeFailureExpected)

-- | How undeclared source leaves affect resolution.
data UnknownKeyPolicy = WarnUnknownKeys | RejectUnknownKeys
  deriving stock (Generic, Eq, Ord, Show)

-- | Resolver behavior independent of any source adapter.
data ResolveOptions = ResolveOptions
  { unknownKeyPolicy :: !UnknownKeyPolicy
  }
  deriving stock (Generic, Eq, Show)

-- | The typed result plus its safe explanation and non-fatal diagnostics.
data ResolveResult a = ResolveResult
  { value :: !a,
    report :: !ResolutionReport,
    warnings :: ![ConfigWarning]
  }
  deriving stock (Generic)

defaultResolveOptions :: ResolveOptions
defaultResolveOptions = ResolveOptions {unknownKeyPolicy = WarnUnknownKeys}

-- | Resolve sources ordered from lowest to highest precedence.
--
-- Each request chooses its rightmost candidate and decodes it exactly once. Independent
-- applicative errors accumulate in declaration order; selective branches evaluate only
-- the branch selected by their resolved selector.
resolve :: ResolveOptions -> [Source] -> Config a -> Either (NonEmpty ConfigError) (ResolveResult a)
resolve options sources config =
  case NonEmpty.nonEmpty structuralErrors of
    Just errors -> Left errors
    Nothing ->
      case appendErrors (evaluation ^. #answer) strictUnknownErrors of
        Left errors -> Left (toNonEmpty errors)
        Right value ->
          Right
            ResolveResult
              { value,
                report = ResolutionReport {nodes = completeNodes, branches = evaluation ^. #branches},
                warnings = unknownWarnings
              }
  where
    schemaSettings = schemaPossible (describeEvaluation config)
    structuralErrors = validateStructure schemaSettings sources
    evaluation = evaluate sources config
    unknownProblems = findUnknownKeys schemaSettings sources
    unknownWarnings = case options ^. #unknownKeyPolicy of
      WarnUnknownKeys -> fmap UnknownKeyWarning unknownProblems
      RejectUnknownKeys -> []
    strictUnknownErrors = case options ^. #unknownKeyPolicy of
      WarnUnknownKeys -> Right ()
      RejectUnknownKeys -> errorsOnly (fmap UnknownKeyError unknownProblems)
    completeNodes = addNotSelected schemaSettings (evaluation ^. #nodes)

validateStructure :: [SchemaSetting] -> [Source] -> [ConfigError]
validateStructure schemaSettings sources =
  unique
    [ StructuralConflict structuralError
    | schemaSetting <- schemaSettings,
      sourceValue <- sources,
      Left structuralError <- [lookupSource (schemaSettingKey schemaSetting) sourceValue]
    ]

unique :: (Eq a) => [a] -> [a]
unique = foldl appendIfNew []
  where
    appendIfNew values value
      | value `elem` values = values
      | otherwise = values <> [value]

data Evaluation a = Evaluation
  { answer :: !(Either [ConfigError] a),
    nodes :: !(Map Key ResolutionNode),
    branches :: ![BranchTrace]
  }
  deriving stock (Generic)

evaluate :: [Source] -> Config a -> Evaluation a
evaluate sources = \case
  PureConfig value -> successful value
  MapConfig mapValue config -> mapEvaluation mapValue (evaluate sources config)
  ApplyConfig function inputConfig ->
    applyEvaluation (evaluate sources function) (evaluate sources inputConfig)
  RequestConfig request -> evaluateRequest sources request
  SelectConfig selector branch ->
    let selectorEvaluation = evaluate sources selector
        selectorKeys = Map.keys (selectorEvaluation ^. #nodes)
        branchKeys = fmap schemaSettingKey (schemaPossible (describeEvaluation branch))
     in case selectorEvaluation ^. #answer of
          Left errors -> selectorEvaluation & #answer .~ Left errors
          Right (Right value) ->
            selectorEvaluation
              & #answer
              .~ Right value
              & #branches
              %~ (<> [BranchTrace {dependencies = selectorKeys, settings = branchKeys, selected = False}])
          Right (Left input) ->
            let branchEvaluation = evaluate sources branch
                combined = mapEvaluation ($ input) branchEvaluation
             in Evaluation
                  { answer = combined ^. #answer,
                    nodes = Map.union (selectorEvaluation ^. #nodes) (branchEvaluation ^. #nodes),
                    branches =
                      selectorEvaluation ^. #branches
                        <> branchEvaluation ^. #branches
                        <> [BranchTrace {dependencies = selectorKeys, settings = branchKeys, selected = True}]
                  }

-- | Static inspection implemented locally to keep the raw constructors private from the
-- public resolver surface.
describeEvaluation :: Config a -> Schema
describeEvaluation = describeConfig

evaluateRequest :: [Source] -> Request a -> Evaluation a
evaluateRequest sources = \case
  RequiredRequest settingSpec ->
    case evaluateSetting sources settingSpec of
      SettingAbsent node ->
        failed
          [MissingRequired (MissingProblem {key = settingKey settingSpec})]
          (Map.singleton (settingKey settingSpec) node)
      SettingFailed errors node -> failed errors (Map.singleton (settingKey settingSpec) node)
      SettingPresent value node -> withNode value node
  OptionalRequest settingSpec ->
    case evaluateSetting sources settingSpec of
      SettingAbsent node -> withNode Nothing node
      SettingFailed errors node -> failed errors (Map.singleton (settingKey settingSpec) node)
      SettingPresent value node -> withNode (Just value) node

data SettingEvaluation a
  = SettingAbsent !ResolutionNode
  | SettingFailed ![ConfigError] !ResolutionNode
  | SettingPresent a !ResolutionNode

evaluateSetting :: [Source] -> Setting a -> SettingEvaluation a
evaluateSetting sources settingSpec =
  case collectCandidates (settingKey settingSpec) sources of
    Left structuralErrors ->
      SettingFailed
        (fmap StructuralConflict structuralErrors)
        (missingNode settingSpec)
    Right [] -> SettingAbsent (missingNode settingSpec)
    Right candidates ->
      let winner = last candidates
          lower = init candidates
          rawValue = candidateValue winner
          node =
            ResolutionNode
              { key = settingKey settingSpec,
                sensitivity = settingSensitivity settingSpec,
                outcome = Resolved (reportedValue (settingSensitivity settingSpec) rawValue),
                origin = Just (candidateOrigin winner),
                shadowed = fmap candidateOrigin lower,
                derivation = Nothing
              }
       in case decodeSetting settingSpec rawValue of
            Left decodeFailure ->
              SettingFailed
                [ DecodeError
                    DecodeProblem
                      { key = settingKey settingSpec,
                        expected = decodeFailureExpected decodeFailure,
                        origin = candidateOrigin winner,
                        rejected = reportedValue (settingSensitivity settingSpec) rawValue
                      }
                ]
                node
            Right value -> SettingPresent value node

collectCandidates :: Key -> [Source] -> Either [StructuralError] [Candidate]
collectCandidates key sources =
  case foldr collect ([], []) (fmap (lookupSource key) sources) of
    ([], candidates) -> Right candidates
    (errors, _) -> Left errors
  where
    collect (Left structuralError) (errors, candidates) = (structuralError : errors, candidates)
    collect (Right Nothing) result = result
    collect (Right (Just foundCandidate)) (errors, candidates) =
      (errors, foundCandidate : candidates)

missingNode :: Setting a -> ResolutionNode
missingNode settingSpec =
  ResolutionNode
    { key = settingKey settingSpec,
      sensitivity = settingSensitivity settingSpec,
      outcome = MissingValue,
      origin = Nothing,
      shadowed = [],
      derivation = Nothing
    }

withNode :: a -> ResolutionNode -> Evaluation a
withNode value node =
  Evaluation
    { answer = Right value,
      nodes = Map.singleton (node ^. #key) node,
      branches = []
    }

successful :: a -> Evaluation a
successful value = Evaluation {answer = Right value, nodes = Map.empty, branches = []}

failed :: [ConfigError] -> Map Key ResolutionNode -> Evaluation a
failed errors nodes = Evaluation {answer = Left errors, nodes, branches = []}

mapEvaluation :: (a -> b) -> Evaluation a -> Evaluation b
mapEvaluation mapValue evaluation = evaluation & #answer %~ fmap mapValue

applyEvaluation :: Evaluation (a -> b) -> Evaluation a -> Evaluation b
applyEvaluation function inputConfig =
  Evaluation
    { answer = applyAnswer (function ^. #answer) (inputConfig ^. #answer),
      nodes = Map.union (function ^. #nodes) (inputConfig ^. #nodes),
      branches = function ^. #branches <> inputConfig ^. #branches
    }

applyAnswer :: Either [ConfigError] (a -> b) -> Either [ConfigError] a -> Either [ConfigError] b
applyAnswer (Right function) (Right value) = Right (function value)
applyAnswer (Left leftErrors) (Left rightErrors) = Left (leftErrors <> rightErrors)
applyAnswer (Left errors) _ = Left errors
applyAnswer _ (Left errors) = Left errors

findUnknownKeys :: [SchemaSetting] -> [Source] -> [UnknownKeyProblem]
findUnknownKeys schemaSettings = concatMap unknownInSource
  where
    declared = fmap schemaSettingKey schemaSettings
    unknownInSource source =
      [ UnknownKeyProblem {key, origin = candidateOrigin foundCandidate}
      | (key, foundCandidate) <- sourceLeaves source,
        not (any (`declares` key) declared)
      ]

declares :: Key -> Key -> Bool
declares declared leaf =
  NonEmpty.toList (keySegments declared)
    `isPrefixOf` NonEmpty.toList (keySegments leaf)

isPrefixOf :: (Eq a) => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (left : leftRest) (right : rightRest) =
  left == right && isPrefixOf leftRest rightRest

addNotSelected :: [SchemaSetting] -> Map Key ResolutionNode -> Map Key ResolutionNode
addNotSelected schemaSettings existingNodes = foldl addNode existingNodes schemaSettings
  where
    addNode nodes schemaSetting =
      nodes
        & at (schemaSettingKey schemaSetting)
        %~ ( \case
               Just node -> Just node
               Nothing ->
                 Just
                   ResolutionNode
                     { key = schemaSettingKey schemaSetting,
                       sensitivity = schemaSettingSensitivity schemaSetting,
                       outcome = NotSelected,
                       origin = Nothing,
                       shadowed = [],
                       derivation = Nothing
                     }
           )

errorsOnly :: [ConfigError] -> Either [ConfigError] ()
errorsOnly [] = Right ()
errorsOnly errors = Left errors

appendErrors :: Either [ConfigError] a -> Either [ConfigError] () -> Either [ConfigError] a
appendErrors (Right value) (Right ()) = Right value
appendErrors (Left errors) (Right ()) = Left errors
appendErrors (Right _) (Left errors) = Left errors
appendErrors (Left leftErrors) (Left rightErrors) = Left (leftErrors <> rightErrors)

toNonEmpty :: [ConfigError] -> NonEmpty ConfigError
toNonEmpty errors =
  case NonEmpty.nonEmpty errors of
    Just values -> values
    Nothing -> error "Settei.Resolve: impossible empty error collection"
