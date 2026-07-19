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
import Data.Set qualified as Set
import Settei.Error
import Settei.Internal.Config
  ( Config (..),
    Default (..),
    Request (..),
    RuleName,
    describeConfig,
    renderRuleName,
  )
import Settei.Internal.Schema (Schema)
import Settei.Key (Key, keySegments)
import Settei.Origin (Origin (..), SourceKind (DerivedSource))
import Settei.Prelude
import Settei.Provenance
  ( Candidate,
    ReportedValue,
    candidateOrigin,
    candidateValue,
    derivedReportedValue,
    reportedValue,
    visibleReportedValue,
  )
import Settei.Report
import Settei.Schema
  ( SchemaSetting,
    schemaPossible,
    schemaSettingKey,
    schemaSettingSensitivity,
  )
import Settei.Setting
  ( Sensitivity (..),
    Setting,
    decodeSetting,
    settingKey,
    settingSensitivity,
    settingValueRenderer,
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

-- | Warn about unknown keys while retaining all other default resolver semantics.
defaultResolveOptions :: ResolveOptions
defaultResolveOptions = ResolveOptions {unknownKeyPolicy = WarnUnknownKeys}

-- | Resolve sources ordered from lowest to highest precedence.
--
-- Each request chooses its rightmost candidate and decodes it exactly once. Independent
-- applicative errors accumulate in declaration order; selective branches evaluate only
-- the branch selected by their resolved selector.
resolve :: ResolveOptions -> [Source] -> Config a -> Either (NonEmpty ConfigError) (ResolveResult a)
resolve options sources config =
  case NonEmpty.nonEmpty (validateDefaultCycles config) of
    Just errors -> Left errors
    Nothing -> case NonEmpty.nonEmpty (validateSensitivityConflicts schemaSettings) of
      Just errors -> Left errors
      Nothing -> resolveValidated
  where
    resolveValidated =
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

validateSensitivityConflicts :: [SchemaSetting] -> [ConfigError]
validateSensitivityConflicts schemaSettings =
  [ SensitivityConflict (SensitivityConflictProblem {key = schemaSettingKey schemaSetting})
  | schemaSetting <- schemaSettings,
    Set.size (schemaSetting ^. #declaredSensitivities) > 1
  ]

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

validateDefaultCycles :: Config a -> [ConfigError]
validateDefaultCycles = go []
  where
    go :: [RuleName] -> Config b -> [ConfigError]
    go active = \case
      PureConfig _ -> []
      MapConfig _ config -> go active config
      ApplyConfig function inputConfig -> go active function <> go active inputConfig
      RequestConfig _ -> []
      DefaultConfig _ defaultSpec -> validateDefault active defaultSpec
      SelectConfig selector branch -> go active selector <> go active branch

    validateDefault :: [RuleName] -> Default b -> [ConfigError]
    validateDefault active defaultSpec =
      let rule = defaultRule defaultSpec
       in if rule `elem` active
            then [DefaultCycle (DefaultCycleProblem {rules = cycleRules rule active})]
            else case defaultSpec of
              ConstantDefault _ _ _ -> []
              DerivedDefault _ _ dependency _ -> go (active <> [rule]) dependency
              CaseDefault _ _ dependency _ _ -> go (active <> [rule]) dependency

    cycleRules rule active =
      case NonEmpty.nonEmpty (dropWhile (/= rule) active <> [rule]) of
        Just rules -> rules
        Nothing -> rule :| []

defaultRule :: Default a -> RuleName
defaultRule = \case
  ConstantDefault rule _ _ -> rule
  DerivedDefault rule _ _ _ -> rule
  CaseDefault rule _ _ _ _ -> rule

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
  DefaultConfig settingSpec defaultSpec ->
    evaluateDefaultRequest sources settingSpec defaultSpec
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

evaluateDefaultRequest :: [Source] -> Setting a -> Default a -> Evaluation a
evaluateDefaultRequest sources settingSpec defaultSpec =
  case evaluateSetting sources settingSpec of
    SettingFailed errors node -> failed errors (Map.singleton (settingKey settingSpec) node)
    SettingPresent value node -> withNode value node
    SettingAbsent _ -> evaluateFallback sources settingSpec defaultSpec

evaluateFallback :: [Source] -> Setting a -> Default a -> Evaluation a
evaluateFallback sources settingSpec = \case
  ConstantDefault rule explanation value ->
    derivedEvaluation settingSpec rule explanation [] value
  DerivedDefault rule explanation dependency derive ->
    let dependencyEvaluation = evaluate sources dependency
     in case dependencyEvaluation ^. #answer of
          Left errors -> evaluationFailure dependencyEvaluation errors
          Right dependencyValue ->
            derivedFromDependencies
              settingSpec
              rule
              explanation
              dependencyEvaluation
              (derive dependencyValue)
  CaseDefault rule explanation dependency choices fallback ->
    let dependencyEvaluation = evaluate sources dependency
     in case dependencyEvaluation ^. #answer of
          Left errors -> evaluationFailure dependencyEvaluation errors
          Right dependencyValue ->
            case lookup dependencyValue (NonEmpty.toList choices) of
              Just value ->
                derivedFromDependencies settingSpec rule explanation dependencyEvaluation value
              Nothing -> case fallback of
                Just value ->
                  derivedFromDependencies settingSpec rule explanation dependencyEvaluation value
                Nothing ->
                  evaluationFailure
                    dependencyEvaluation
                    [ DefaultError
                        DefaultProblem
                          { key = settingKey settingSpec,
                            rule,
                            message = "no case matched and no fallback was declared"
                          }
                    ]

derivedFromDependencies ::
  Setting a ->
  RuleName ->
  Text ->
  Evaluation d ->
  a ->
  Evaluation a
derivedFromDependencies settingSpec rule explanation dependencyEvaluation value =
  Evaluation
    { answer = Right value,
      nodes =
        dependencyEvaluation
          ^. #nodes
          & at (settingKey settingSpec)
          ?~ derivedNode settingSpec rule explanation dependencyKeys value,
      branches = dependencyEvaluation ^. #branches
    }
  where
    dependencyKeys = Map.keys (dependencyEvaluation ^. #nodes)

derivedEvaluation :: Setting a -> RuleName -> Text -> [Key] -> a -> Evaluation a
derivedEvaluation settingSpec rule explanation dependencies value =
  withNode value (derivedNode settingSpec rule explanation dependencies value)

derivedNode :: Setting a -> RuleName -> Text -> [Key] -> a -> ResolutionNode
derivedNode settingSpec rule explanation dependencies value =
  ResolutionNode
    { key = settingKey settingSpec,
      sensitivity = settingSensitivity settingSpec,
      outcome = Resolved (defaultReportedValue settingSpec value),
      origin =
        Just
          Origin
            { kind = DerivedSource,
              name = renderRuleName rule,
              key = settingKey settingSpec,
              location = Nothing,
              annotations = Map.singleton "settei.default-rule" (renderRuleName rule)
            },
      shadowed = [],
      derivation = Just Derivation {rule = renderRuleName rule, explanation, dependencies}
    }

defaultReportedValue :: Setting a -> a -> ReportedValue
defaultReportedValue settingSpec value =
  case settingSensitivity settingSpec of
    Secret -> derivedReportedValue Secret
    Public -> case settingValueRenderer settingSpec of
      Just renderValue -> visibleReportedValue (renderValue value)
      Nothing -> derivedReportedValue Public

evaluationFailure :: Evaluation d -> [ConfigError] -> Evaluation a
evaluationFailure dependencyEvaluation errors =
  Evaluation
    { answer = Left errors,
      nodes = dependencyEvaluation ^. #nodes,
      branches = dependencyEvaluation ^. #branches
    }

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
                shadowed = fmap candidateOrigin (reverse lower),
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
