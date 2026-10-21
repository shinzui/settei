module OldValidatedDispatch (oldDispatch) where

import Settei
import Settei.Optparse

oldDispatch :: ValidatedResult a -> DiagnosticDecision a
oldDispatch = validatedDiagnostic DescribeConfigJson
