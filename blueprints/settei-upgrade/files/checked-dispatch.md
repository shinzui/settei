## Dispatch migration

Before (unsafe selector composition; shown only to identify code to replace):

```haskell
case schemaDiagnostic mode schema of
  Just output -> emit output
  Nothing -> do
    result <- acquire
    case resolutionDiagnostic mode result of
      Just output -> emit output
      Nothing -> startResolvedApplication result
```

After (compiles against public modules):

```haskell
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
```

Applications keep ownership of streams, warnings and exit codes. The example returns
text dispositions for routing by the caller; preserve existing source-load exit 3 and
configuration rejection exit 4 in applications using those conventions. Applications
with invariants call `validate` inside the runtime branch and replace the final helper
with `validatedDiagnostic token validated`, preserving the same exhaustive decision match.
