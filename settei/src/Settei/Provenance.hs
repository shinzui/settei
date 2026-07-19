-- |
-- Module: Settei.Provenance
-- Description: Raw candidates paired with their structured origin.
module Settei.Provenance
  ( Candidate,
    ReportedValue,
    candidate,
    candidateOrigin,
    candidateValue,
    derivedReportedValue,
    redactReportedValue,
    renderReportedValue,
    reportedValue,
    visibleReportedValue,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Ratio qualified as Ratio
import Data.Text qualified as Text
import Settei.Origin (Origin)
import Settei.Prelude
import Settei.Setting (Sensitivity (..))
import Settei.Value (RawValue (..))

-- | One source's value for one declared key.
--
-- There is deliberately no 'Show' instance: the raw value may be secret.
data Candidate = Candidate
  { value :: !RawValue,
    origin :: !Origin
  }
  deriving stock (Generic, Eq)

-- | Pair one raw source value with its exact origin.
candidate :: RawValue -> Origin -> Candidate
candidate value origin = Candidate {value, origin}

-- | Return the candidate's raw value for core decoding.
candidateValue :: Candidate -> RawValue
candidateValue value = value ^. #value

-- | Return the candidate's structured origin.
candidateOrigin :: Candidate -> Origin
candidateOrigin value = value ^. #origin

-- | A value safe to retain in reports and structured errors.
--
-- Constructors are private so reporting code can display a value but cannot unwrap a
-- supposedly redacted secret.
data ReportedValue
  = VisibleValue !Text
  | RedactedValue
  | DerivedValue
  deriving stock (Generic, Eq, Ord, Show)

-- | Apply a setting's sensitivity before retaining any display representation.
reportedValue :: Sensitivity -> RawValue -> ReportedValue
reportedValue Public = VisibleValue . renderRawValue
reportedValue Secret = const RedactedValue

-- | Collapse any retained display representation to the redaction marker.
redactReportedValue :: ReportedValue -> ReportedValue
redactReportedValue _ = RedactedValue

-- | Render a retained value. A redacted value has no recovery path.
renderReportedValue :: ReportedValue -> Text
renderReportedValue (VisibleValue value) = value
renderReportedValue RedactedValue = "<redacted>"
renderReportedValue DerivedValue = "<derived>"

-- | Represent a typed default when no format-independent encoder exists.
derivedReportedValue :: Sensitivity -> ReportedValue
derivedReportedValue Public = DerivedValue
derivedReportedValue Secret = RedactedValue

-- | Retain an already-rendered public value.
visibleReportedValue :: Text -> ReportedValue
visibleReportedValue = VisibleValue

renderRawValue :: RawValue -> Text
renderRawValue = \case
  RawNull -> "null"
  RawText value -> "\"" <> escapeText value <> "\""
  RawBool True -> "true"
  RawBool False -> "false"
  RawNumber value
    | Ratio.denominator value == 1 -> Text.pack (show (Ratio.numerator value))
    | otherwise ->
        case renderDecimal value of
          Just decimal -> decimal
          Nothing ->
            Text.pack (show (Ratio.numerator value))
              <> "/"
              <> Text.pack (show (Ratio.denominator value))
  RawArray values -> "[" <> Text.intercalate ", " (fmap renderRawValue values) <> "]"
  RawObject values ->
    "{"
      <> Text.intercalate
        ", "
        [ "\"" <> escapeText key <> "\": " <> renderRawValue value
        | (key, value) <- Map.toAscList values
        ]
      <> "}"

renderDecimal :: Rational -> Maybe Text
renderDecimal value =
  let numerator = Ratio.numerator value
      denominator = Ratio.denominator value
      (twos, afterTwos) = countFactor 2 denominator
      (fives, residual) = countFactor 5 afterTwos
   in if residual /= 1
        then Nothing
        else
          let scale = max twos fives
              scaled = abs numerator * (10 ^ scale) `quot` denominator
              digits = Text.pack (show scaled)
              padded = Text.replicate (max 0 (scale + 1 - Text.length digits)) "0" <> digits
              (whole, fractional) = Text.splitAt (Text.length padded - scale) padded
              sign = if numerator < 0 then "-" else ""
           in Just (sign <> whole <> "." <> fractional)

countFactor :: Integer -> Integer -> (Int, Integer)
countFactor factor = go 0
  where
    go count remaining
      | remaining `rem` factor == 0 = go (count + 1) (remaining `quot` factor)
      | otherwise = (count, remaining)

escapeText :: Text -> Text
escapeText =
  Text.replace "\n" "\\n"
    . Text.replace "\r" "\\r"
    . Text.replace "\t" "\\t"
    . Text.replace "\"" "\\\""
    . Text.replace "\\" "\\\\"
