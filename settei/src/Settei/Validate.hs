-- |
-- Module: Settei.Validate
-- Description: Pure, structured application invariants after resolution.
--
-- Validators receive the typed configuration. They must be total and return finite
-- lists; this API cannot catch exceptions or stop divergence. All rule metadata must
-- be safe to publish. Expectations are fixed at declaration time; expectations and
-- details used in line-oriented text must be single-line. Details are for public
-- labels only: never interpolate a Secret setting or log the typed record. Settei
-- cannot sanitise author-supplied text.
module Settei.Validate
  ( Violation,
    violation,
    violationWithDetail,
    Validator,
    invariant,
    check,
    requires,
    ValidatorError (..),
    renderValidatorErrorText,
    renderValidatorErrorsText,
    Validators,
    validators,
    describeValidators,
    runValidators,
    ValidatedResult (..),
    validate,
  )
where

import Data.Char (isControl, isSpace)
import Data.Generics.Labels ()
import Data.List (mapAccumL, nub)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Settei.Config (Config, describe)
import Settei.Default (renderRuleName)
import Settei.Error
import Settei.Internal.DefaultValidation (validateDefaultCycles)
import Settei.Key (Key, renderKey)
import Settei.Prelude
import Settei.Report
import Settei.Resolve (ResolveResult)
import Settei.Schema (schemaPossible, schemaSettingKey)

-- | One failing instance, optionally carrying author-supplied public text.
newtype Violation = Violation (Maybe Text)
  deriving stock (Generic, Eq, Show)

-- | A failure with no per-run detail: prefer this for ordinary rules.
violation :: Violation
violation = Violation Nothing

-- | Retain a public label verbatim. Never embed secret values here; Settei cannot
-- sanitise this channel. Keep the label single-line for line-oriented diagnostics.
violationWithDetail :: Text -> Violation
violationWithDetail = Violation . Just

-- No Generic instance: generic conversion would expose private implementation.
data Validator a = Validator !InvariantRule ![Key] !Text ![InvariantRule] (a -> [Violation])

-- | Declare a named rule over declared setting keys, with a fixed expectation.
invariant :: InvariantRule -> [Key] -> Text -> (a -> [Violation]) -> Validator a
invariant rule keys expectation = Validator rule keys expectation []

-- | A boolean rule fails with one detail-free violation when its predicate is false.
check :: InvariantRule -> [Key] -> Text -> (a -> Bool) -> Validator a
check rule keys expectation predicate =
  invariant rule keys expectation (\value -> if predicate value then [] else [violation])

-- | Append prerequisites, preserving their first occurrence across repeated calls.
-- Every prerequisite must name an earlier rule in the same checked collection.
requires :: [InvariantRule] -> Validator a -> Validator a
requires additional (Validator rule keys expectation prerequisites run) =
  Validator rule keys expectation (nub (prerequisites <> additional)) run

-- | Static declaration errors; no validator function is applied during construction.
data ValidatorError
  = InvalidInvariantRule !InvariantRule
  | DuplicateInvariantRule !InvariantRule
  | EmptyInvariantKeys !InvariantRule
  | UndeclaredInvariantKey !InvariantRule !Key
  | UnknownPrerequisite !InvariantRule !InvariantRule
  | CyclicDeclaration !DefaultCycleProblem
  deriving stock (Generic, Eq, Show)

renderValidatorErrorText :: ValidatorError -> Text
renderValidatorErrorText = \case
  InvalidInvariantRule rule -> "invalid invariant rule " <> escapedRule rule
  DuplicateInvariantRule rule -> "duplicate invariant rule " <> escapedRule rule
  EmptyInvariantKeys rule -> "invariant " <> escapedRule rule <> ": no declared keys"
  UndeclaredInvariantKey rule key -> "invariant " <> escapedRule rule <> ": undeclared key " <> renderKey key
  UnknownPrerequisite rule prerequisite ->
    "invariant " <> escapedRule rule <> ": prerequisite is not an earlier rule: " <> escapedRule prerequisite
  CyclicDeclaration problem ->
    "default cycle: " <> Text.intercalate " -> " (fmap renderRuleName (NonEmpty.toList (problem ^. #rules)))

escapedRule :: InvariantRule -> Text
escapedRule = Text.pack . show . renderInvariantRule

renderValidatorErrorsText :: NonEmpty ValidatorError -> Text
renderValidatorErrorsText = Text.unlines . fmap renderValidatorErrorText . NonEmpty.toList

-- Opaque and deliberately without Generic or writable optics: all public values
-- have passed the construction checks below.
newtype Validators a = Validators [Validator a]

-- | Check every rule and possible key, including conditional keys, without sources.
-- Cycles precede other problems and suppress only key-membership checks.
validators :: Config a -> [Validator a] -> Either (NonEmpty ValidatorError) (Validators a)
validators config declarations =
  case NonEmpty.nonEmpty (cycleErrors <> concat problems) of
    Nothing -> Right (Validators declarations)
    Just errors -> Left errors
  where
    cycleErrors = [CyclicDeclaration problem | DefaultCycle problem <- validateDefaultCycles config]
    possible = if null cycleErrors then Just (Set.fromList (fmap schemaSettingKey (schemaPossible (describe config)))) else Nothing
    (_, problems) = mapAccumL inspect (Set.empty, Set.empty) declarations
    inspect (earlier, duplicates) (Validator rule keys _ prerequisites _) =
      ( (Set.insert rule earlier, if Set.member rule earlier then Set.insert rule duplicates else duplicates),
        [InvalidInvariantRule rule | let name = renderInvariantRule rule, Text.null name || Text.any (\c -> isSpace c || isControl c) name]
          <> [DuplicateInvariantRule rule | Set.member rule earlier, Set.notMember rule duplicates]
          <> [EmptyInvariantKeys rule | null keys]
          <> [UndeclaredInvariantKey rule key | key <- keys, Just known <- [possible], Set.notMember key known]
          <> [UnknownPrerequisite rule prerequisite | prerequisite <- prerequisites, Set.notMember prerequisite earlier]
      )

-- | Inspect declarations with every rule marked not run. No rule function is forced.
describeValidators :: Validators a -> ValidationReport
describeValidators (Validators declarations) =
  ValidationReport [validatorOutcome declaration InvariantNotRun | declaration <- declarations]

validatorOutcome :: Validator a -> InvariantStatus -> InvariantOutcome
validatorOutcome (Validator rule keys expectation prerequisites _) status =
  InvariantOutcome {rule, keys, expectation, prerequisites, status}

-- | Run eligible rules in declaration order, accumulating independent violations.
-- Failed or skipped prerequisites block a rule without evaluating its function.
runValidators :: Validators a -> a -> (ValidationReport, [InvariantProblem])
runValidators (Validators declarations) value =
  (ValidationReport (fmap fst results), concatMap snd results)
  where
    (_, results) = mapAccumL runOne Map.empty declarations
    runOne statuses declaration@(Validator rule keys expectation prerequisites run) =
      let blocked = filter (\prerequisite -> Map.lookup prerequisite statuses /= Just InvariantPassed) prerequisites
          (status, problems) = case NonEmpty.nonEmpty blocked of
            Just unmet -> (InvariantSkipped unmet, [])
            Nothing ->
              let violations = run value
                  failures = [InvariantProblem {rule, keys, expectation, detail} | Violation detail <- violations]
               in (if null failures then InvariantPassed else InvariantFailed (length failures), failures)
       in (Map.insert rule status statuses, (validatorOutcome declaration status, problems))

-- | A typed answer with unchanged resolution provenance and validation outcomes.
-- No Show or Eq instance: the answer may contain secrets.
data ValidatedResult a = ValidatedResult
  { answer :: !(Either (NonEmpty ConfigError) a),
    report :: !ResolutionReport,
    warnings :: ![ConfigWarning],
    validation :: !ValidationReport
  }
  deriving stock (Generic)

-- | Validate only a successful answer. Use the collection checked against the same
-- declaration that produced this result; the type alone cannot prove that pairing.
-- Conditional membership does not imply evaluation: handle optional values totally.
validate :: Validators a -> ResolveResult a -> ValidatedResult a
validate declarations result =
  let (answer, validation) = case result ^. #answer of
        Left errors -> (Left errors, describeValidators declarations)
        Right value ->
          let (validationReport, problems) = runValidators declarations value
           in (maybe (Right value) (Left . fmap InvariantError) (NonEmpty.nonEmpty problems), validationReport)
   in ValidatedResult {answer, report = result ^. #report, warnings = result ^. #warnings, validation}
