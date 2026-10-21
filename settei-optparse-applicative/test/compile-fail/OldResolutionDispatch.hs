module OldResolutionDispatch (oldDispatch) where

import Settei
import Settei.Optparse

oldDispatch :: ResolveResult a -> DiagnosticDecision a
oldDispatch = resolutionDiagnostic DeploymentContractJson
