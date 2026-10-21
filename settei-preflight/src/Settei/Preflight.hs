-- | Run an application's configuration check against explicitly proposed inputs.
-- Only 'Pass' passes a deployment gate. This runner is not a sandbox and does not
-- establish connectivity, deployed image identity, or readiness. Known nonempty
-- secrets are redacted by exact match; transformed or unclassified secrets cannot
-- be recognized. Supported execution platforms are Linux and macOS.
module Settei.Preflight
  ( RoleLabel (..),
    FileName (..),
    ArgumentPart (..),
    Argument (..),
    literalArgument,
    fileArgument,
    CheckCommand (..),
    ProposedValue (..),
    ProposedFile (..),
    ProposedInputs (..),
    defaultInherited,
    emptyProposedInputs,
    ExitCodeMapping (..),
    defaultExitCodes,
    PreflightOptions (..),
    defaultPreflightOptions,
    PreflightProblem (..),
    InputRef (..),
    validatePreflight,
    renderPreflightProblemText,
    renderPreflightProblemsText,
    runPreflight,
    PreflightReport,
    CommandSummary,
    InputSummary,
    Classification (..),
    Outcome (..),
    RejectionCategory (..),
    NotRunReason (..),
    Coverage (..),
    Limitation,
    LimitationKind (..),
    Verdict (..),
    Execution,
    preflightRole,
    preflightCommand,
    preflightInputs,
    preflightInherited,
    preflightNotes,
    preflightOutcome,
    preflightCoverage,
    preflightVerdict,
    preflightExecution,
    commandExecutable,
    commandArguments,
    inputReference,
    inputClassification,
    inputPassed,
    limitationInput,
    limitationKind,
    limitationReason,
    executionExitCode,
    executionTimedOut,
    executionStandardOutput,
    executionStandardError,
    renderPreflightReportText,
    renderPreflightReportJson,
  )
where

import Data.Generics.Labels ()
import Settei.Env (EnvName)
import Settei.Preflight.Internal
import Settei.Prelude (Text, (^.))

-- | Read-only accessors keep reports usable without a lens dependency.
preflightRole :: PreflightReport -> RoleLabel
preflightRole value = value ^. #role

preflightCommand :: PreflightReport -> CommandSummary
preflightCommand value = value ^. #command

preflightInputs :: PreflightReport -> [InputSummary]
preflightInputs value = value ^. #inputs

preflightInherited :: PreflightReport -> [(EnvName, Bool)]
preflightInherited value = value ^. #inherited

preflightNotes :: PreflightReport -> [Text]
preflightNotes value = value ^. #notes

preflightOutcome :: PreflightReport -> Outcome
preflightOutcome value = value ^. #outcome

preflightCoverage :: PreflightReport -> Coverage
preflightCoverage value = value ^. #coverage

preflightVerdict :: PreflightReport -> Verdict
preflightVerdict value = value ^. #verdict

preflightExecution :: PreflightReport -> Maybe Execution
preflightExecution value = value ^. #execution

commandExecutable :: CommandSummary -> FilePath
commandExecutable value = value ^. #executable

commandArguments :: CommandSummary -> [Text]
commandArguments value = value ^. #arguments

inputReference :: InputSummary -> InputRef
inputReference value = value ^. #input

inputClassification :: InputSummary -> Classification
inputClassification value = value ^. #classification

inputPassed :: InputSummary -> Bool
inputPassed value = value ^. #passed

limitationInput :: Limitation -> InputRef
limitationInput value = value ^. #input

limitationKind :: Limitation -> LimitationKind
limitationKind value = value ^. #kind

limitationReason :: Limitation -> Text
limitationReason value = value ^. #reason

executionExitCode :: Execution -> Maybe Int
executionExitCode value = value ^. #exitCode

executionTimedOut :: Execution -> Bool
executionTimedOut value = value ^. #timedOut

executionStandardOutput :: Execution -> Text
executionStandardOutput value = value ^. #standardOutput

executionStandardError :: Execution -> Text
executionStandardError value = value ^. #standardError
