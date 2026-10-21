{-# LANGUAGE ImportQualifiedPost #-}

-- |
-- Module: Settei.Render
-- Description: Deterministic text and versioned JSON presentation.
module Settei.Render
  ( renderContractText,
    renderContractJson,
    renderErrorsJson,
    renderErrorsText,
    renderResolutionJson,
    renderResolutionText,
    renderValidationText,
    renderValidatedResolutionJson,
    renderSchemaJson,
    renderSchemaText,
    renderWarningsJson,
    renderWarningsText,
  )
where

import Control.Applicative ((<|>))
import Data.Char (ord)
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Numeric (showHex)
import Settei.Contract
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

-- | Render one resolution attempt, including skipped settings and branch decisions.
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
  baseDescription <> dhallSuffix origin <> kubernetesSuffix origin
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
        "command-line option "
          <> fromMaybe
            (origin ^. #name)
            ( origin ^. #annotations . at "command-line.spelling"
                <|> origin ^. #annotations . at "command-line.option"
            )
          <> maybe
            ""
            (" occurrence " <>)
            (origin ^. #annotations . at "command-line.occurrence")
      DerivedSource -> "default rule " <> origin ^. #name
      CustomSource customKind -> customKind <> " source " <> origin ^. #name

dhallSuffix :: Origin -> Text
dhallSuffix origin = case origin ^. #kind of
  FileSource "Dhall" ->
    case origin ^. #annotations . at "dhall.root" of
      Nothing -> ""
      Just root ->
        " rooted at "
          <> root
          <> " evaluated with "
          <> fromMaybe "0" (origin ^. #annotations . at "dhall.import-count")
          <> " local imports; leaf-level import attribution unavailable after normalization"
  _ -> ""

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
        <> maybe
          ""
          (\modified -> " (modified " <> modified <> ")")
          (origin ^. #annotations . at "kubernetes.file-modified")
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
  SensitivityConflict problem ->
    renderKey (problem ^. #key)
      <> ": declared with both public and secret sensitivity; treated as secret"
  InvariantError problem ->
    commaKeys (problem ^. #keys)
      <> ": invariant "
      <> renderInvariantRule (problem ^. #rule)
      <> " failed: "
      <> problem ^. #expectation
      <> maybe "" (\detail -> " (" <> detail <> ")") (problem ^. #detail)

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

-- | Render a resolution attempt as versioned deterministic JSON.
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
  SensitivityConflict problem ->
    jsonObject
      [ ("kind", jsonString "sensitivity-conflict"),
        ("key", jsonString (renderKey (problem ^. #key)))
      ]
  InvariantError problem ->
    jsonObject
      [ ("kind", jsonString "invariant"),
        ("rule", jsonString (renderInvariantRule (problem ^. #rule))),
        ("keys", jsonKeyArray (problem ^. #keys)),
        ("expectation", jsonString (problem ^. #expectation)),
        ("detail", maybe "null" jsonString (problem ^. #detail))
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

-- | Render deployment inputs, defaults, and deferred dependency information.
renderContractText :: DeploymentContract -> Text
renderContractText contract =
  Text.unlines
    ( concatMap settingLines (contractSettings contract)
        <> concatMap renderConditionText (zip [1 :: Int ..] (contractConditions contract))
        <> fmap (("diagnostic: " <>) . contractDiagnosticText) (contractDiagnostics contract)
    )
  where
    settingLines entry =
      [ renderKey (entry ^. #key)
          <> " ["
          <> requirementText (entry ^. #requirement)
          <> ", "
          <> presenceText (entry ^. #presence)
          <> ", "
          <> sensitivityText (entry ^. #sensitivity)
          <> "] "
          <> entry ^. #description,
        "  input: " <> inputText entry
      ]
        <> fmap (\value -> "  default: declaration rule " <> renderRuleName (value ^. #rule) <> ", " <> shapeText (value ^. #shape)) (entry ^. #declaredDefaults)
        <> maybe
          []
          ( \value ->
              [ "  default: "
                  <> renderReportedValue (value ^. #value)
                  <> " from "
                  <> originDescription (value ^. #origin)
                  <> case value ^. #validity of ValidDefault -> ""; InvalidDefault expected -> " (invalid; expected " <> expected <> ")"
              ]
                <> fmap (\origin -> "  shadowed: " <> originDescription origin) (value ^. #shadowed)
          )
          (entry ^. #sourceDefault)
        <> fmap (\binding -> "  bound: " <> channelText (inputBindingChannel binding) <> " " <> inputBindingName binding <> bindingAnnotationsText binding) (entry ^. #inputs)
    bindingAnnotationsText binding
      | Map.null (inputBindingAnnotations binding) = ""
      | otherwise = " [" <> Text.intercalate ", " [key <> "=" <> value | (key, value) <- Map.toAscList (inputBindingAnnotations binding)] <> "]"
    channelText EnvironmentVariable = "environment variable"
    channelText (CustomInput detail) = detail
    inputText entry = case entry ^. #externalInput of
      InputRequired reason -> "required (" <> reasonText entry reason <> ")"
      InputConditional reason -> "conditional (" <> reasonText entry reason <> ")"
      InputDefaulted CoveredBySource -> case entry ^? #sourceDefault . _Just . #origin . #kind of
        Just BuiltInSource -> "defaulted (built-in source)"
        _ -> "defaulted (source)"
      InputDefaulted (CoveredByDeclaration _) -> "defaulted (declaration fallback)"
      InputOptional -> "optional"
    reasonText entry = \case
      NoDefault -> "no default"
      InvalidSourceDefault -> "invalid source default"
      RequiredRequest -> "required request despite declaration default"
      ProfileRequirement -> "deployment profile " <> fromMaybe "" (contractProfile contract) <> ": " <> fromMaybe "" (entry ^. #deploymentRequirement)
    shapeText = \case
      ConstantShape (VisibleDefault value) -> "constant " <> value
      ConstantShape RedactedDefault -> "constant <redacted>"
      ConstantShape UnrenderableDefault -> "constant <unrenderable>"
      DerivedShape dependencies -> "derived from " <> commaKeys dependencies <> "; value not computed"
      CaseShape dependencies count fallback -> "case on " <> commaKeys dependencies <> ", " <> jsonInt count <> " alternatives, " <> (if fallback then "fallback" else "no fallback") <> "; value not computed"

contractDiagnosticText :: ContractDiagnostic -> Text
contractDiagnosticText = \case
  ConflictingSensitivity key -> renderKey key <> ": declared with both public and secret sensitivity; treated as secret"
  DefaultStructuralConflict problem -> renderErrorText (StructuralConflict problem)
  UndeclaredDefaultLeaf problem -> renderErrorText (UnknownKeyError problem)
  UndeclaredBindingKey binding -> inputBindingName binding <> ": binding targets undeclared key " <> renderKey (inputBindingKey binding)
  UndeclaredProfileKey key -> renderKey key <> ": deployment profile targets undeclared key"

-- | Version 1 deployment contract. Existing schema and resolution encodings are unchanged.
renderContractJson :: DeploymentContract -> Text
renderContractJson contract =
  versionedJson
    "settei.contract"
    [ ("profile", maybe "null" jsonString (contractProfile contract)),
      ("settings", jsonArray (fmap contractSettingJson (contractSettings contract))),
      ("conditions", jsonArray (fmap conditionJson (contractConditions contract))),
      ("diagnostics", jsonArray (fmap contractDiagnosticJson (contractDiagnostics contract)))
    ]

contractSettingJson :: ContractSetting -> Text
contractSettingJson entry =
  jsonObject
    [ ("key", jsonString (renderKey (entry ^. #key))),
      ("description", jsonString (entry ^. #description)),
      ("sensitivity", jsonString (sensitivityText (entry ^. #sensitivity))),
      ("requirement", jsonString (requirementText (entry ^. #requirement))),
      ("presence", jsonString (presenceText (entry ^. #presence))),
      ("bindings", jsonArray (fmap inputBindingJson (entry ^. #inputs))),
      ("declaredDefaults", jsonArray (fmap declaredDefaultJson (entry ^. #declaredDefaults))),
      ("sourceDefault", maybe "null" sourceDefaultJson (entry ^. #sourceDefault)),
      ("deploymentRequirement", maybe "null" jsonString (entry ^. #deploymentRequirement)),
      ("externalInput", externalInputJson (entry ^. #externalInput))
    ]

inputBindingJson :: InputBinding -> Text
inputBindingJson binding =
  jsonObject
    [ ("channel", jsonString (case inputBindingChannel binding of EnvironmentVariable -> "environment"; CustomInput _ -> "custom")),
      ("channelDetail", case inputBindingChannel binding of EnvironmentVariable -> "null"; CustomInput detail -> jsonString detail),
      ("name", jsonString (inputBindingName binding)),
      ("annotations", jsonTextMap (inputBindingAnnotations binding))
    ]

declaredDefaultJson :: DeclaredDefault -> Text
declaredDefaultJson entry =
  let (kind, value, availability, dependencies, alternatives, fallback) = case entry ^. #shape of
        ConstantShape value' ->
          let (rendered, available) = case value' of
                VisibleDefault textValue -> (jsonString textValue, "visible")
                RedactedDefault -> ("null", "redacted")
                UnrenderableDefault -> ("null", "unrenderable")
           in ("constant", rendered, jsonString available, [], "null", "null")
        DerivedShape keys -> ("derived", "null", "null", keys, "null", "null")
        CaseShape keys count hasFallback -> ("case", "null", "null", keys, jsonInt count, if hasFallback then "true" else "false")
   in jsonObject
        [ ("rule", jsonString (renderRuleName (entry ^. #rule))),
          ("explanation", jsonString (entry ^. #explanation)),
          ("kind", jsonString kind),
          ("value", value),
          ("valueAvailability", availability),
          ("dependencies", jsonKeyArray dependencies),
          ("alternatives", alternatives),
          ("fallback", fallback)
        ]

sourceDefaultJson :: SourceDefault -> Text
sourceDefaultJson value =
  jsonObject
    [ ("origin", originJson (value ^. #origin)),
      ("shadowed", jsonArray (fmap originJson (value ^. #shadowed))),
      ("value", jsonString (renderReportedValue (value ^. #value))),
      ("validity", jsonString (case value ^. #validity of ValidDefault -> "valid"; InvalidDefault _ -> "invalid")),
      ("expected", case value ^. #validity of ValidDefault -> "null"; InvalidDefault expected -> jsonString expected)
    ]

externalInputJson :: ExternalInput -> Text
externalInputJson input =
  let (verdict, reason, coverage, dependencies) = case input of
        InputRequired why -> ("required", Just why, Nothing, [])
        InputConditional why -> ("conditional", Just why, Nothing, [])
        InputDefaulted CoveredBySource -> ("defaulted", Nothing, Just "source", [])
        InputDefaulted (CoveredByDeclaration keys) -> ("defaulted", Nothing, Just "declaration", keys)
        InputOptional -> ("optional", Nothing, Nothing, [])
      reasonTag = \case NoDefault -> "no-default"; InvalidSourceDefault -> "invalid-source-default"; RequiredRequest -> "required-request"; ProfileRequirement -> "deployment-profile"
   in jsonObject
        [ ("verdict", jsonString verdict),
          ("reason", maybe "null" (jsonString . reasonTag) reason),
          ("coverage", maybe "null" jsonString coverage),
          ("dependencies", jsonKeyArray dependencies)
        ]

contractDiagnosticJson :: ContractDiagnostic -> Text
contractDiagnosticJson diagnostic = jsonObject $ case diagnostic of
  ConflictingSensitivity key -> [("kind", jsonString "conflicting-sensitivity"), ("key", jsonString (renderKey key))]
  DefaultStructuralConflict problem ->
    [ ("kind", jsonString "default-structural-conflict"),
      ("key", jsonString (renderKey (problem ^. #key))),
      ("blockedAt", jsonString (renderKey (problem ^. #blockedAt))),
      ("shape", jsonString (rawShapeText (problem ^. #shape))),
      ("origin", originJson (problem ^. #origin))
    ]
  UndeclaredDefaultLeaf problem -> [("kind", jsonString "undeclared-default-leaf"), ("key", jsonString (renderKey (problem ^. #key))), ("origin", originJson (problem ^. #origin))]
  UndeclaredBindingKey binding -> [("kind", jsonString "undeclared-binding-key"), ("key", jsonString (renderKey (inputBindingKey binding))), ("binding", inputBindingJson binding)]
  UndeclaredProfileKey key -> [("kind", jsonString "undeclared-profile-key"), ("key", jsonString (renderKey key))]

-- | Render every invariant outcome in declaration order.
renderValidationText :: ValidationReport -> Text
renderValidationText = Text.concat . fmap renderOutcome . validationOutcomes
  where
    renderOutcome entry =
      "invariant "
        <> renderInvariantRule (entry ^. #rule)
        <> " ["
        <> statusText (entry ^. #status)
        <> "]: "
        <> commaKeys (entry ^. #keys)
        <> "\n  expects "
        <> entry ^. #expectation
        <> "\n"
        <> (if null (entry ^. #prerequisites) then "" else "  after " <> commaRules (entry ^. #prerequisites) <> "\n")
    statusText = \case
      InvariantPassed -> "passed"
      InvariantFailed n -> "failed (" <> Text.pack (show n) <> (if n == 1 then " violation)" else " violations)")
      InvariantSkipped unmet -> "skipped after " <> commaRules (NonEmpty.toList unmet)
      InvariantNotRun -> "not run"

commaRules :: [InvariantRule] -> Text
commaRules = Text.intercalate ", " . fmap renderInvariantRule

-- | Version-1 resolution document extended with an optional invariant trace.
-- 'renderResolutionJson' retains its original representation.
renderValidatedResolutionJson :: ResolutionReport -> ValidationReport -> Text
renderValidatedResolutionJson report validation =
  versionedJson
    "settei.resolution"
    [ ("nodes", jsonArray (fmap resolutionNodeJson (reportNodes report))),
      ("branches", jsonArray (fmap branchJson (reportBranches report))),
      ("invariants", jsonArray (fmap invariantOutcomeJson (validationOutcomes validation)))
    ]

invariantOutcomeJson :: InvariantOutcome -> Text
invariantOutcomeJson entry =
  let (tag, count, blocked) = case entry ^. #status of
        InvariantPassed -> ("passed", 0, [])
        InvariantFailed n -> ("failed", n, [])
        InvariantSkipped unmet -> ("skipped", 0, NonEmpty.toList unmet)
        InvariantNotRun -> ("not-run", 0, [])
   in jsonObject
        [ ("rule", jsonString (renderInvariantRule (entry ^. #rule))),
          ("keys", jsonKeyArray (entry ^. #keys)),
          ("expectation", jsonString (entry ^. #expectation)),
          ("prerequisites", ruleArray (entry ^. #prerequisites)),
          ("status", jsonString tag),
          ("violations", jsonInt count),
          ("blockedBy", ruleArray blocked)
        ]
  where
    ruleArray = jsonArray . fmap (jsonString . renderInvariantRule)
