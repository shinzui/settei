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
    PreflightReport (role, command, inputs, inherited, notes, outcome, coverage, verdict, execution),
    CommandSummary (executable, arguments),
    InputSummary (input, classification, passed),
    Classification (..),
    Outcome (..),
    RejectionCategory (..),
    NotRunReason (..),
    Coverage (..),
    Limitation (input, kind, reason),
    LimitationKind (..),
    Verdict (..),
    Execution (exitCode, timedOut, standardOutput, standardError),
    renderPreflightReportText,
    renderPreflightReportJson,
  )
where

import Settei.Preflight.Internal
