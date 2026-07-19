{-# LANGUAGE PackageImports #-}

-- |
-- Module: Settei.Prelude
-- Description: Internal shared prelude for the settei package family.
--
-- __Internal to the settei package family — not part of the PVP-stable API.__
--
-- This module exists so that the settei core, its sibling adapter packages,
-- and the reference applications share one import baseline. It re-exports
-- the full "Control.Lens" surface (hiding the lens @Setting@ type alias,
-- which collides with Settei's own 'Settei.Setting.Setting') together with
-- "Prelude" and a few common types. Because its exports track the @lens@
-- package, they may change in any settei release, including patch releases.
-- Code outside this repository must not import this module; the supported
-- adoption surface is listed in the compatibility matrix
-- (@docs/compatibility.md@ in the source distribution).
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
