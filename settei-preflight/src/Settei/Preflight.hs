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

-- | The sanitized executable and symbolic command arguments.
preflightCommand :: PreflightReport -> CommandSummary
preflightCommand value = value ^. #command

-- | Input summaries ordered by channel and name.
preflightInputs :: PreflightReport -> [InputSummary]
preflightInputs value = value ^. #inputs

-- | Inherited execution-context names and whether each was present; never their values.
preflightInherited :: PreflightReport -> [(EnvName, Bool)]
preflightInherited value = value ^. #inherited

-- | Sanitized extraction notes; every version-one note reduces coverage.
preflightNotes :: PreflightReport -> [Text]
preflightNotes value = value ^. #notes

-- | Application acceptance/rejection or the harness failure reason.
preflightOutcome :: PreflightReport -> Outcome
preflightOutcome value = value ^. #outcome

-- | Whether every proposed input was supplied without coverage limitations.
preflightCoverage :: PreflightReport -> Coverage
preflightCoverage value = value ^. #coverage

-- | The gate decision. Only 'Pass' passes; 'Inconclusive' also blocks a gate.
preflightVerdict :: PreflightReport -> Verdict
preflightVerdict value = value ^. #verdict

-- | Captured execution details when a child was successfully spawned.
preflightExecution :: PreflightReport -> Maybe Execution
preflightExecution value = value ^. #execution

-- | The sanitized resolved executable path, or attempted path when lookup failed.
commandExecutable :: CommandSummary -> FilePath
commandExecutable value = value ^. #executable

-- | Sanitized symbolic arguments using file/directory references instead of temporary paths.
commandArguments :: CommandSummary -> [Text]
commandArguments value = value ^. #arguments

-- | The sanitized environment name or relative file name.
inputReference :: InputSummary -> InputRef
inputReference value = value ^. #input

-- | The input's supplied, synthetic, unresolved, or unavailable classification.
inputClassification :: InputSummary -> Classification
inputClassification value = value ^. #classification

-- | True only for a present value supplied to a successfully spawned child.
-- It does not establish that the application consumed the input.
inputPassed :: InputSummary -> Bool
inputPassed value = value ^. #passed

-- | The affected input or zero-based extraction-note index.
limitationInput :: Limitation -> InputRef
limitationInput value = value ^. #input

-- | The category preventing complete coverage.
limitationKind :: Limitation -> LimitationKind
limitationKind value = value ^. #kind

-- | The sanitized reason for incomplete coverage.
limitationReason :: Limitation -> Text
limitationReason value = value ^. #reason

-- | The child exit code, if captured before a timeout or harness failure.
executionExitCode :: Execution -> Maybe Int
executionExitCode value = value ^. #exitCode

-- | Whether the timeout expired during child completion or pipe draining.
executionTimedOut :: Execution -> Bool
executionTimedOut value = value ^. #timedOut

-- | Captured stdout with exact known nonempty secrets redacted.
executionStandardOutput :: Execution -> Text
executionStandardOutput value = value ^. #standardOutput

-- | Captured stderr with exact known nonempty secrets redacted.
executionStandardError :: Execution -> Text
executionStandardError value = value ^. #standardError
