{-# LANGUAGE GADTs #-}

-- | Shared preflight for interpreters that must reject recursive defaults before inspection.
module Settei.Internal.DefaultValidation (validateDefaultCycles, defaultRule) where

import Data.List.NonEmpty qualified as NonEmpty
import Settei.Error
import Settei.Internal.Config
import Settei.Prelude

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
