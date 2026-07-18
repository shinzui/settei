-- |
-- Module: Settei.Value
-- Description: Parser-neutral raw values and secret-safe typed decoders.
module Settei.Value
  ( RawValue (..),
    DecodeFailure,
    Decoder,
    boolDecoder,
    boundedIntegralDecoder,
    enumDecoder,
    decodeFailure,
    decodeFailureExpected,
    decoder,
    renderDecodeFailure,
    runDecoder,
    textDecoder,
  )
where

import Data.Generics.Labels ()
import Data.Ratio qualified as Ratio
import Data.Text qualified as Text
import Data.Text.Read qualified as TextRead
import Settei.Key (Key, renderKey)
import Settei.Prelude

-- | The parser-neutral value tree produced by source adapters.
--
-- 'RawValue' deliberately has no 'Show' instance: it may contain a secret before a
-- setting decoder has had a chance to redact it.
data RawValue
  = RawNull
  | RawText !Text
  | RawBool !Bool
  | RawNumber !Rational
  | RawArray ![RawValue]
  | RawObject !(Map Text RawValue)
  deriving stock (Generic, Eq)

-- | A secret-safe explanation of what a decoder expected.
--
-- The rejected raw input is intentionally absent.
data DecodeFailure = DecodeFailure
  { key :: !Key,
    expected :: !Text
  }
  deriving stock (Generic, Eq, Show)

-- | A reusable decoder that receives the owning setting key for safe errors.
newtype Decoder a = Decoder
  { decode :: Key -> RawValue -> Either DecodeFailure a
  }
  deriving stock (Generic)

-- | Construct a decoder whose failures carry only safe expectation metadata.
decoder :: (Key -> RawValue -> Either DecodeFailure a) -> Decoder a
decoder decode = Decoder {decode}

-- | Construct a rejection without retaining the rejected raw value.
decodeFailure :: Key -> Text -> DecodeFailure
decodeFailure key expected = DecodeFailure {key, expected}

-- | Inspect the safe expectation text for a failed decode.
decodeFailureExpected :: DecodeFailure -> Text
decodeFailureExpected value = value ^. #expected

-- | Run a decoder for one setting key.
runDecoder :: Decoder a -> Key -> RawValue -> Either DecodeFailure a
runDecoder value = value ^. #decode

-- | Decode a text scalar.
textDecoder :: Decoder Text
textDecoder = Decoder $ \key -> \case
  RawText value -> Right value
  _ -> failure key "text"

-- | Decode a boolean scalar or an exact, case-insensitive textual boolean.
boolDecoder :: Decoder Bool
boolDecoder = Decoder $ \key -> \case
  RawBool value -> Right value
  RawText value -> case Text.toCaseFold value of
    "true" -> Right True
    "false" -> Right False
    _ -> failure key "boolean"
  _ -> failure key "boolean"

-- | Decode a whole number that fits the requested bounded integral type.
boundedIntegralDecoder :: forall a. (Bounded a, Integral a) => Decoder a
boundedIntegralDecoder = Decoder $ \key value ->
  case integralValue value of
    Just candidate
      | candidate >= toInteger (minBound @a)
          && candidate <= toInteger (maxBound @a) ->
          Right (fromInteger candidate)
    _ -> failure key "bounded integer"

-- | Decode one of a finite set of exact text spellings.
enumDecoder :: [(Text, a)] -> Decoder a
enumDecoder choices = Decoder $ \key -> \case
  RawText value ->
    maybe
      (failure key expectedValues)
      Right
      (lookup value choices)
  _ -> failure key expectedValues
  where
    names = fmap fst choices
    expectedValues = case names of
      [] -> "an allowed value"
      _ -> "one of " <> Text.intercalate ", " names

-- | Render a failure without including the rejected value.
renderDecodeFailure :: DecodeFailure -> Text
renderDecodeFailure value =
  renderKey (value ^. #key) <> ": expected " <> value ^. #expected

failure :: Key -> Text -> Either DecodeFailure a
failure key expected = Left DecodeFailure {key, expected}

integralValue :: RawValue -> Maybe Integer
integralValue = \case
  RawNumber value
    | Ratio.denominator value == 1 -> Just (Ratio.numerator value)
  RawText value -> case TextRead.signed TextRead.decimal value of
    Right (candidate, rest)
      | Text.null rest -> Just candidate
    _ -> Nothing
  _ -> Nothing
