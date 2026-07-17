module Settei.Key
  ( Key,
    KeyError (..),
    mkKey,
    parseKey,
    renderKey,
    keySegments,
  )
where

import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Settei.Prelude

-- | A validated, hierarchical configuration key.
newtype Key = Key
  { segments :: NonEmpty Text
  }
  deriving stock (Generic, Eq, Ord, Show)

-- | Why textual input could not be represented as a 'Key'.
data KeyError
  = KeyIsEmpty
  | KeySegmentIsEmpty
  | KeySegmentContainsDot !Text
  deriving stock (Generic, Eq, Show)

-- | Validate structural key segments.
mkKey :: NonEmpty Text -> Either KeyError Key
mkKey value
  | any Text.null segmentList = Left KeySegmentIsEmpty
  | Just part <- findWithDot segmentList = Left (KeySegmentContainsDot part)
  | otherwise = Right (Key value)
  where
    segmentList = NonEmpty.toList value
    findWithDot = find (Text.any (== '.'))

-- | Parse dot-separated text into a non-empty structural key.
parseKey :: Text -> Either KeyError Key
parseKey value
  | Text.null value = Left KeyIsEmpty
  | otherwise =
      maybe
        (Left KeyIsEmpty)
        mkKey
        (NonEmpty.nonEmpty (Text.splitOn "." value))

-- | Render a key using its canonical dot-separated spelling.
renderKey :: Key -> Text
renderKey value = Text.intercalate "." (NonEmpty.toList (value ^. #segments))

-- | Return the structural segments of a key.
keySegments :: Key -> NonEmpty Text
keySegments value = value ^. #segments

find :: (a -> Bool) -> [a] -> Maybe a
find predicate = \case
  [] -> Nothing
  value : rest
    | predicate value -> Just value
    | otherwise -> find predicate rest
