{-# LANGUAGE PackageImports #-}

-- |
-- Module: Settei.Prelude
-- Description: Small shared project prelude and lens operator surface.
module Settei.Prelude
  ( module X,
    module Control.Lens,
  )
where

import "base" Data.List.NonEmpty as X (NonEmpty (..))
import "base" GHC.Generics as X (Generic)
import "containers" Data.Map.Strict as X (Map)
import "containers" Data.Set as X (Set)
import "lens" Control.Lens hiding (Setting)
import "text" Data.Text as X (Text)
import "base" Prelude as X
