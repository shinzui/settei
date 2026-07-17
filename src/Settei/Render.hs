{-# LANGUAGE ImportQualifiedPost #-}

-- |
-- Module: Settei.Render
-- Description: Deterministic text and versioned JSON presentation.
module Settei.Render
  ( renderErrorsJson,
    renderErrorsText,
    renderResolutionJson,
    renderResolutionText,
    renderSchemaJson,
    renderSchemaText,
    renderWarningsJson,
    renderWarningsText,
  )
where

import Data.Char (ord)
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Numeric (showHex)
import Settei.Default (renderRuleName)
import Settei.Error
import Settei.Key (Key, renderKey)
import Settei.Origin
import Settei.Prelude
import Settei.Provenance (renderReportedValue)
import Settei.Report
import Settei.Schema
import Settei.Setting (Sensitivity (..))

-- | Render a static schema in stable key order.
renderSchemaText :: Schema -> Text
renderSchemaText schema =
  Text.unlines
    ( fmap renderSchemaSettingText (schemaPossible schema)
        <> concatMap renderConditionText (zip [1 :: Int ..] (schemaConditions schema))
    )

renderSchemaSettingText :: SchemaSetting -> Text
renderSchemaSettingText schemaEntry =
  renderKey (schemaSettingKey schemaEntry)
    <> " ["
    <> requirementText (schemaSettingRequirement schemaEntry)
    <> ", "
    <> presenceText (schemaSettingPresence schemaEntry)
    <> ", "
    <> sensitivityText (schemaSettingSensitivity schemaEntry)
    <> "] "
    <> schemaSettingDescription schemaEntry

renderConditionText :: (Int, Condition) -> [Text]
renderConditionText (conditionNumber, condition) =
  [ "condition "
      <> Text.pack (show conditionNumber)
      <> ": "
      <> commaKeys (Set.toAscList (conditionDependencies condition))
      <> " -> "
      <> commaKeys (Set.toAscList (conditionSettings condition))
  ]

-- | Render one successful resolution, including skipped settings and branch decisions.
renderResolutionText :: ResolutionReport -> Text
renderResolutionText report =
  Text.concat (fmap (renderNodeText report) (reportNodes report))
    <> Text.concat (fmap renderBranchText (zip [1 :: Int ..] (reportBranches report)))

renderNodeText :: ResolutionReport -> ResolutionNode -> Text
renderNodeText report node =
  renderKey (node ^. #key)
    <> " = "
    <> outcomeValueText (node ^. #outcome)
    <> "\n"
    <> maybe "" (renderOriginText "  from ") (node ^. #origin)
    <> maybe "" (renderDerivationText report) (node ^. #derivation)
    <> Text.concat (fmap (renderOriginText "  shadowed: ") (node ^. #shadowed))

renderDerivationText :: ResolutionReport -> Derivation -> Text
renderDerivationText report derivation =
  Text.concat (fmap renderDependency (derivation ^. #dependencies))
  where
    renderDependency key =
      case report ^. #nodes . at key of
        Nothing -> "  because " <> renderKey key <> " = <not evaluated>\n"
        Just node ->
          "  because "
            <> renderKey key
            <> " = "
            <> outcomeValueText (node ^. #outcome)
            <> "\n"
            <> maybe "" (renderOriginText "    from ") (node ^. #origin)

renderBranchText :: (Int, BranchTrace) -> Text
renderBranchText (branchNumber, branch) =
  "branch "
    <> Text.pack (show branchNumber)
    <> " ["
    <> (if branch ^. #selected then "selected" else "not selected")
    <> "]: "
    <> commaKeys (branch ^. #dependencies)
    <> " -> "
    <> commaKeys (branch ^. #settings)
    <> "\n"

renderOriginText :: Text -> Origin -> Text
renderOriginText prefix origin = prefix <> originDescription origin <> "\n"

originDescription :: Origin -> Text
originDescription origin =
  baseDescription <> kubernetesSuffix origin
  where
    baseDescription = case origin ^. #kind of
      BuiltInSource -> "built-in source " <> origin ^. #name
      FileSource formatName -> "file source " <> origin ^. #name <> " (" <> formatName <> ")"
      EnvironmentSource ->
        maybe
          ("environment source " <> origin ^. #name)
          ("environment variable " <>)
          (origin ^. #annotations . at "environment.variable")
      CommandLineSource ->
        maybe
          ("command-line source " <> origin ^. #name)
          ("command-line option " <>)
          (origin ^. #annotations . at "command-line.option")
      DerivedSource -> "default rule " <> origin ^. #name
      CustomSource customKind -> customKind <> " source " <> origin ^. #name

kubernetesSuffix :: Origin -> Text
kubernetesSuffix origin =
  case ( origin ^. #annotations . at "kubernetes.object-kind",
         origin ^. #annotations . at "kubernetes.object-name"
       ) of
    (Just objectKind, Just objectName) ->
      " from Kubernetes "
        <> objectKind
        <> " "
        <> maybe "" (<> "/") (origin ^. #annotations . at "kubernetes.namespace")
        <> objectName
        <> maybe "" (" key " <>) (origin ^. #annotations . at "kubernetes.object-key")
    _ -> ""

-- | Render structured failures without access to rejected secret values.
renderErrorsText :: NonEmpty ConfigError -> Text
renderErrorsText = Text.unlines . fmap renderErrorText . NonEmpty.toList

renderErrorText :: ConfigError -> Text
renderErrorText = \case
  MissingRequired problem -> renderKey (problem ^. #key) <> ": required value is missing"
  DecodeError problem ->
    renderKey (problem ^. #key)
      <> ": expected "
      <> problem ^. #expected
      <> " from "
      <> originDescription (problem ^. #origin)
      <> ", rejected "
      <> renderReportedValue (problem ^. #rejected)
  StructuralConflict problem ->
    renderKey (problem ^. #key)
      <> ": cannot traverse "
      <> renderKey (problem ^. #blockedAt)
      <> " through "
      <> rawShapeText (problem ^. #shape)
      <> " in "
      <> originDescription (problem ^. #origin)
  UnknownKeyError problem ->
    renderKey (problem ^. #key)
      <> ": unknown key in "
      <> originDescription (problem ^. #origin)
  DefaultError problem ->
    renderKey (problem ^. #key)
      <> ": default rule "
      <> renderRuleName (problem ^. #rule)
      <> " failed: "
      <> problem ^. #message
  DefaultCycle problem ->
    "default cycle: "
      <> Text.intercalate " -> " (fmap renderRuleName (NonEmpty.toList (problem ^. #rules)))

-- | Render non-fatal diagnostics in deterministic source and key order.
renderWarningsText :: [ConfigWarning] -> Text
renderWarningsText = Text.unlines . fmap renderWarningText

renderWarningText :: ConfigWarning -> Text
renderWarningText = \case
  UnknownKeyWarning problem ->
    renderKey (problem ^. #key)
      <> ": unknown key in "
      <> originDescription (problem ^. #origin)

-- | Render a schema as versioned deterministic JSON.
renderSchemaJson :: Schema -> Text
renderSchemaJson schema =
  versionedJson
    "settei.schema"
    [ ("settings", jsonArray (fmap schemaSettingJson (schemaPossible schema))),
      ("conditions", jsonArray (fmap conditionJson (schemaConditions schema)))
    ]

schemaSettingJson :: SchemaSetting -> Text
schemaSettingJson schemaEntry =
  jsonObject
    [ ("key", jsonString (renderKey (schemaSettingKey schemaEntry))),
      ("description", jsonString (schemaSettingDescription schemaEntry)),
      ("sensitivity", jsonString (sensitivityText (schemaSettingSensitivity schemaEntry))),
      ("requirement", jsonString (requirementText (schemaSettingRequirement schemaEntry))),
      ("presence", jsonString (presenceText (schemaSettingPresence schemaEntry)))
    ]

conditionJson :: Condition -> Text
conditionJson condition =
  jsonObject
    [ ("dependencies", jsonKeyArray (Set.toAscList (conditionDependencies condition))),
      ("settings", jsonKeyArray (Set.toAscList (conditionSettings condition)))
    ]

-- | Render a successful resolution as versioned deterministic JSON.
renderResolutionJson :: ResolutionReport -> Text
renderResolutionJson report =
  versionedJson
    "settei.resolution"
    [ ("nodes", jsonArray (fmap resolutionNodeJson (reportNodes report))),
      ("branches", jsonArray (fmap branchJson (reportBranches report)))
    ]

resolutionNodeJson :: ResolutionNode -> Text
resolutionNodeJson node =
  jsonObject
    [ ("key", jsonString (renderKey (node ^. #key))),
      ("sensitivity", jsonString (sensitivityText (node ^. #sensitivity))),
      ("outcome", jsonString (outcomeTag (node ^. #outcome))),
      ("value", outcomeValueJson (node ^. #outcome)),
      ("origin", maybe "null" originJson (node ^. #origin)),
      ("shadowed", jsonArray (fmap originJson (node ^. #shadowed))),
      ("derivation", maybe "null" derivationJson (node ^. #derivation))
    ]

derivationJson :: Derivation -> Text
derivationJson derivation =
  jsonObject
    [ ("rule", jsonString (derivation ^. #rule)),
      ("explanation", jsonString (derivation ^. #explanation)),
      ("dependencies", jsonKeyArray (derivation ^. #dependencies))
    ]

branchJson :: BranchTrace -> Text
branchJson branch =
  jsonObject
    [ ("dependencies", jsonKeyArray (branch ^. #dependencies)),
      ("settings", jsonKeyArray (branch ^. #settings)),
      ("selected", if branch ^. #selected then "true" else "false")
    ]

originJson :: Origin -> Text
originJson origin =
  jsonObject
    [ ("kind", jsonString (sourceKindTag (origin ^. #kind))),
      ("kindDetail", maybe "null" jsonString (sourceKindDetail (origin ^. #kind))),
      ("name", jsonString (origin ^. #name)),
      ("key", jsonString (renderKey (origin ^. #key))),
      ("location", maybe "null" locationJson (origin ^. #location)),
      ("annotations", jsonTextMap (origin ^. #annotations))
    ]

locationJson :: SourceLocation -> Text
locationJson location =
  jsonObject
    [ ("path", jsonString (location ^. #path)),
      ("line", maybe "null" jsonInt (location ^. #line)),
      ("column", maybe "null" jsonInt (location ^. #column))
    ]

-- | Render failures as a versioned deterministic JSON document.
renderErrorsJson :: NonEmpty ConfigError -> Text
renderErrorsJson errors =
  versionedJson
    "settei.errors"
    [("errors", jsonArray (fmap errorJson (NonEmpty.toList errors)))]

errorJson :: ConfigError -> Text
errorJson = \case
  MissingRequired problem ->
    jsonObject
      [ ("kind", jsonString "missing-required"),
        ("key", jsonString (renderKey (problem ^. #key)))
      ]
  DecodeError problem ->
    jsonObject
      [ ("kind", jsonString "decode-error"),
        ("key", jsonString (renderKey (problem ^. #key))),
        ("expected", jsonString (problem ^. #expected)),
        ("origin", originJson (problem ^. #origin)),
        ("rejected", jsonString (renderReportedValue (problem ^. #rejected)))
      ]
  StructuralConflict problem ->
    jsonObject
      [ ("kind", jsonString "structural-conflict"),
        ("key", jsonString (renderKey (problem ^. #key))),
        ("blockedAt", jsonString (renderKey (problem ^. #blockedAt))),
        ("shape", jsonString (rawShapeText (problem ^. #shape))),
        ("origin", originJson (problem ^. #origin))
      ]
  UnknownKeyError problem ->
    jsonObject
      [ ("kind", jsonString "unknown-key"),
        ("key", jsonString (renderKey (problem ^. #key))),
        ("origin", originJson (problem ^. #origin))
      ]
  DefaultError problem ->
    jsonObject
      [ ("kind", jsonString "default-error"),
        ("key", jsonString (renderKey (problem ^. #key))),
        ("rule", jsonString (renderRuleName (problem ^. #rule))),
        ("message", jsonString (problem ^. #message))
      ]
  DefaultCycle problem ->
    jsonObject
      [ ("kind", jsonString "default-cycle"),
        ("rules", jsonArray (fmap (jsonString . renderRuleName) (NonEmpty.toList (problem ^. #rules))))
      ]

-- | Render warnings as a versioned deterministic JSON document.
renderWarningsJson :: [ConfigWarning] -> Text
renderWarningsJson warnings =
  versionedJson
    "settei.warnings"
    [("warnings", jsonArray (fmap warningJson warnings))]

warningJson :: ConfigWarning -> Text
warningJson = \case
  UnknownKeyWarning problem ->
    jsonObject
      [ ("kind", jsonString "unknown-key"),
        ("key", jsonString (renderKey (problem ^. #key))),
        ("origin", originJson (problem ^. #origin))
      ]

outcomeValueText :: ResolutionOutcome -> Text
outcomeValueText = \case
  Resolved value -> renderReportedValue value
  MissingValue -> "<missing>"
  NotSelected -> "<not selected>"

outcomeTag :: ResolutionOutcome -> Text
outcomeTag = \case
  Resolved _ -> "resolved"
  MissingValue -> "missing"
  NotSelected -> "not-selected"

outcomeValueJson :: ResolutionOutcome -> Text
outcomeValueJson = \case
  Resolved value -> jsonString (renderReportedValue value)
  MissingValue -> "null"
  NotSelected -> "null"

requirementText :: Requirement -> Text
requirementText Required = "required"
requirementText Optional = "optional"

presenceText :: Presence -> Text
presenceText Necessary = "necessary"
presenceText Conditional = "conditional"

sensitivityText :: Sensitivity -> Text
sensitivityText Public = "public"
sensitivityText Secret = "secret"

rawShapeText :: RawShape -> Text
rawShapeText NullShape = "null"
rawShapeText ScalarShape = "scalar"
rawShapeText ArrayShape = "array"

sourceKindTag :: SourceKind -> Text
sourceKindTag BuiltInSource = "built-in"
sourceKindTag (FileSource _) = "file"
sourceKindTag EnvironmentSource = "environment"
sourceKindTag CommandLineSource = "command-line"
sourceKindTag DerivedSource = "derived"
sourceKindTag (CustomSource _) = "custom"

sourceKindDetail :: SourceKind -> Maybe Text
sourceKindDetail (FileSource value) = Just value
sourceKindDetail (CustomSource value) = Just value
sourceKindDetail _ = Nothing

commaKeys :: [Key] -> Text
commaKeys = Text.intercalate ", " . fmap renderKey

jsonKeyArray :: [Key] -> Text
jsonKeyArray = jsonArray . fmap (jsonString . renderKey)

jsonTextMap :: Map Text Text -> Text
jsonTextMap =
  jsonObject . fmap (\(key, value) -> (key, jsonString value)) . Map.toAscList

jsonInt :: Int -> Text
jsonInt = Text.pack . show

versionedJson :: Text -> [(Text, Text)] -> Text
versionedJson documentType fields =
  jsonObject
    ( [ ("schemaVersion", "1"),
        ("type", jsonString documentType)
      ]
        <> fields
    )

jsonObject :: [(Text, Text)] -> Text
jsonObject fields =
  "{"
    <> Text.intercalate
      ","
      [jsonString key <> ":" <> value | (key, value) <- fields]
    <> "}"

jsonArray :: [Text] -> Text
jsonArray values = "[" <> Text.intercalate "," values <> "]"

jsonString :: Text -> Text
jsonString value = "\"" <> Text.concatMap escapeJsonChar value <> "\""

escapeJsonChar :: Char -> Text
escapeJsonChar = \case
  '"' -> "\\\""
  '\\' -> "\\\\"
  '\b' -> "\\b"
  '\f' -> "\\f"
  '\n' -> "\\n"
  '\r' -> "\\r"
  '\t' -> "\\t"
  character
    | ord character < 0x20 -> "\\u" <> paddedHex (ord character)
    | otherwise -> Text.singleton character

paddedHex :: Int -> Text
paddedHex value =
  let rendered = Text.pack (showHex value "")
   in Text.replicate (4 - Text.length rendered) "0" <> rendered
