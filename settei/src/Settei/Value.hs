-- |
-- Module: Settei.Value
-- Description: Parser-neutral raw values and secret-safe typed decoders.
module Settei.Value
  ( RawValue (..),
    DecodeFailure,
    Decoder,
    boolDecoder,
    boundedIntegralDecoder,
    doubleDecoder,
    enumDecoder,
    decodeFailure,
    decodeFailureExpected,
    decoder,
    listDecoder,
    nonEmptyDecoder,
    parsedDecoder,
    rationalDecoder,
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

-- | Mapping transforms only a successfully decoded result; failures pass
-- through unchanged.
--
-- The instance is lawful: 'fmap' merely post-composes over the 'Either'
-- result of the wrapped function, so identity and composition follow
-- directly from the 'Functor' laws of @'Either' 'DecodeFailure'@ and of
-- functions.
instance Functor Decoder where
  fmap f (Decoder run) = Decoder (\key raw -> fmap f (run key raw))

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

-- | Decode an array by applying the element decoder to every element.
--
-- Elements are decoded left to right and the first failing element stops
-- decoding. An element failure keeps the owning setting key (arrays are
-- whole values at one key) and wraps the element's expectation as
-- @\"an array of \<expectation\>\"@; a non-array input fails with
-- @\"an array\"@. Failures carry only expectation text, never the
-- rejected raw value.
listDecoder :: Decoder a -> Decoder [a]
listDecoder elementDecoder = Decoder $ \key -> \case
  RawArray values ->
    traverse (runDecoder elementDecoder key) values
      & _Left
      . #expected
      %~ ("an array of " <>)
  _ -> failure key "an array"

-- | Decode a non-empty array with the element decoder.
--
-- An empty array -- and any non-array input -- fails with
-- @\"a non-empty array\"@; a failing element wraps its expectation as
-- @\"a non-empty array of \<expectation\>\"@.
nonEmptyDecoder :: Decoder a -> Decoder (NonEmpty a)
nonEmptyDecoder elementDecoder = Decoder $ \key -> \case
  RawArray (firstValue : rest) ->
    traverse (runDecoder elementDecoder key) (firstValue :| rest)
      & _Left
      . #expected
      %~ ("a non-empty array of " <>)
  _ -> failure key "a non-empty array"

-- | Decode a text scalar through a caller-supplied parser.
--
-- The first argument is the safe expectation description reported on any
-- failure, for example @\"an absolute URI\"@ or @\"a duration such as 30s\"@.
-- The parser's own error message is deliberately discarded: parser messages
-- routinely echo the offending input, and decode failures must never retain
-- the raw value. Non-text inputs fail with the same description.
parsedDecoder :: Text -> (Text -> Either Text a) -> Decoder a
parsedDecoder expected parse = Decoder $ \key -> \case
  RawText value -> case parse value of
    Right parsed -> Right parsed
    Left _ -> failure key expected
  _ -> failure key expected

-- | Decode an exact rational number.
--
-- Accepts a native number or, for environment-variable and command-line
-- friendliness, a textual number such as @\"2.5\"@, @\"-3\"@, or @\"1e-3\"@
-- (mirroring how 'boundedIntegralDecoder' accepts textual integers).
-- Decimal text converts exactly; no rounding occurs.
rationalDecoder :: Decoder Rational
rationalDecoder = Decoder $ \key value ->
  maybe (failure key "a number") Right (numberValue value)

-- | Decode an IEEE double-precision number.
--
-- Equivalent to @'fromRational' \<\$\> 'rationalDecoder'@: the exact source
-- value is rounded to the nearest representable 'Double'. That rounding is
-- acceptable for configuration values such as timeouts and ratios; use
-- 'rationalDecoder' or 'boundedIntegralDecoder' when exactness matters.
doubleDecoder :: Decoder Double
doubleDecoder = fromRational <$> rationalDecoder

-- | Decode a whole number that fits the requested bounded integral type.
--
-- Accepts a native whole number or a textual integer. Failures state the
-- accepted range, for example @\"integer between -32768 and 32767\"@.
boundedIntegralDecoder :: forall a. (Bounded a, Integral a) => Decoder a
boundedIntegralDecoder = Decoder $ \key value ->
  case integralValue value of
    Just candidate
      | candidate >= lower && candidate <= upper -> Right (fromInteger candidate)
    _ -> failure key expectedRange
  where
    lower = toInteger (minBound @a)
    upper = toInteger (maxBound @a)
    expectedRange =
      "integer between "
        <> Text.pack (show lower)
        <> " and "
        <> Text.pack (show upper)

-- | Decode one of a finite set of exact text spellings.
--
-- Matching is case-sensitive: @\"Production\"@ does not match a declared
-- @\"production\"@ choice. This is deliberate -- enumeration spellings are
-- part of an application's configuration vocabulary. Note the asymmetry
-- with 'boolDecoder', which case-folds its textual @true@/@false@ forms
-- for environment-variable convention; enumerations do not follow it.
-- Applications wanting case-insensitive enumerations can normalize input
-- via 'parsedDecoder'.
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

numberValue :: RawValue -> Maybe Rational
numberValue = \case
  RawNumber value -> Just value
  RawText value -> case TextRead.rational value of
    Right (candidate, rest)
      | Text.null rest -> Just candidate
    _ -> Nothing
  _ -> Nothing
