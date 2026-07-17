-- |
-- Module: Settei.Provenance
-- Description: Raw candidates paired with their structured origin.
module Settei.Provenance
  ( Candidate,
    ReportedValue,
    candidate,
    candidateOrigin,
    candidateValue,
    renderReportedValue,
    reportedValue,
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

candidate :: RawValue -> Origin -> Candidate
candidate value origin = Candidate {value, origin}

candidateValue :: Candidate -> RawValue
candidateValue value = value ^. #value

candidateOrigin :: Candidate -> Origin
candidateOrigin value = value ^. #origin

-- | A value safe to retain in reports and structured errors.
--
-- Constructors are private so reporting code can display a value but cannot unwrap a
-- supposedly redacted secret.
data ReportedValue = VisibleValue !Text | RedactedValue
  deriving stock (Generic, Eq, Ord, Show)

-- | Apply a setting's sensitivity before retaining any display representation.
reportedValue :: Sensitivity -> RawValue -> ReportedValue
reportedValue Public = VisibleValue . renderRawValue
reportedValue Secret = const RedactedValue

-- | Render a retained value. A redacted value has no recovery path.
renderReportedValue :: ReportedValue -> Text
renderReportedValue (VisibleValue value) = value
renderReportedValue RedactedValue = "<redacted>"

renderRawValue :: RawValue -> Text
renderRawValue = \case
  RawNull -> "null"
  RawText value -> "\"" <> escapeText value <> "\""
  RawBool True -> "true"
  RawBool False -> "false"
  RawNumber value
    | Ratio.denominator value == 1 -> Text.pack (show (Ratio.numerator value))
    | otherwise ->
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

escapeText :: Text -> Text
escapeText =
  Text.replace "\n" "\\n"
    . Text.replace "\r" "\\r"
    . Text.replace "\t" "\\t"
    . Text.replace "\"" "\\\""
    . Text.replace "\\" "\\\\"
