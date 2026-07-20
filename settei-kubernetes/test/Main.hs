module Main (main) where

import Test.Tasty qualified as Tasty

main :: IO ()
main = Tasty.defaultMain (Tasty.testGroup "settei-kubernetes" [])
