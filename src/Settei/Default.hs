-- |
-- Module: Settei.Default
-- Description: Named constant and dependency-aware fallback rules.
module Settei.Default
  ( Default,
    RuleName (..),
    caseDefault,
    constantDefault,
    derivedDefault,
    renderRuleName,
  )
where

import Settei.Internal.Config
  ( Config,
    Default,
    RuleName (..),
    caseDefaultConfig,
    constantDefaultConfig,
    derivedDefaultConfig,
    renderRuleName,
  )
import Settei.Prelude

-- | A fallback value with a stable name and human-readable rationale.
constantDefault :: RuleName -> Text -> a -> Default a
constantDefault = constantDefaultConfig

-- | A fallback derived from an explicit, statically inspectable declaration.
derivedDefault :: RuleName -> Text -> Config d -> (d -> a) -> Default a
derivedDefault = derivedDefaultConfig

-- | A finite named derivation with an optional catch-all fallback.
--
-- An unmatched value without a fallback becomes a structured resolver error; the
-- rejected dependency value is never retained in that error.
caseDefault ::
  (Ord d, Show d) =>
  RuleName ->
  Text ->
  Config d ->
  NonEmpty (d, a) ->
  Maybe a ->
  Default a
caseDefault = caseDefaultConfig
