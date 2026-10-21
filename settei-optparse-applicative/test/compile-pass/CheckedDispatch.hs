module CheckedDispatch (dispatch) where

import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Settei
import Settei.Optparse

-- The caller owns stream routing, exit policy, and warning reporting.
dispatch :: DiagnosticMode -> Schema -> Maybe (Either (NonEmpty ConfigError) DeploymentContract) -> IO (ResolveResult a) -> (a -> IO ()) -> IO (Either Text Text)
dispatch mode schema contract acquire startup =
  case prepareDiagnostic mode schema contract of
    DiagnosticRejected problems -> pure (Left problems)
    DiagnosticRendered output -> pure (Right output)
    DiagnosticNeedsRuntime runtimeMode -> do
      result <- acquire
      case resolutionDiagnostic runtimeMode result of
        DiagnosticFailure problems -> pure (Left problems)
        DiagnosticOutput output -> pure (Right output)
        DiagnosticContinue config -> startup config >> pure (Right mempty)
