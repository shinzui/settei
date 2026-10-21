{-# LANGUAGE GADTs #-}

-- | Pure deployment inspection. Inputs are explicit metadata and default sources;
-- no source is read and no derived or case default computation is run.
module Settei.Contract
  ( InputChannel (..),
    InputBinding,
    inputBinding,
    annotateInputBinding,
    inputBindingChannel,
    inputBindingName,
    inputBindingKey,
    inputBindingAnnotations,
    DeploymentProfile,
    deploymentProfile,
    profileName,
    profileRequirements,
    ContractInputs (..),
    emptyContractInputs,
    deploymentContract,
    DeploymentContract,
    contractSettings,
    contractConditions,
    contractProfile,
    contractDiagnostics,
    ContractSetting (..),
    DeclaredDefault (..),
    DefaultShape (..),
    DefaultValue (..),
    SourceDefault (..),
    DefaultValidity (..),
    ExternalInput (..),
    InputReason (..),
    DefaultCoverage (..),
    ContractDiagnostic (..),
  )
where

import Data.Generics.Labels ()
import Data.List (isPrefixOf)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Set qualified as Set
import Settei.Error
import Settei.Internal.Config hiding (Request (..))
import Settei.Internal.Config qualified as Config
import Settei.Internal.DefaultValidation (validateDefaultCycles)
import Settei.Key (Key, keySegments)
import Settei.Origin (Origin)
import Settei.Prelude
import Settei.Provenance
import Settei.Schema
import Settei.Setting
import Settei.Source
import Settei.Value (decodeFailureExpected)

-- | Adapter-neutral external channel. Custom channel identity is descriptive.
data InputChannel = EnvironmentVariable | CustomInput !Text
  deriving stock (Generic, Eq, Show)

-- | One external input name mapped to a declared key. This is descriptive metadata,
-- not a value reader; names and annotations must be safe to publish.
data InputBinding = InputBinding
  {channel :: !InputChannel, name :: !Text, key :: !Key, annotations :: !(Map Text Text)}
  deriving stock (Generic, Eq, Show)

-- | Construct a binding with no annotations. No source is read or key membership checked.
inputBinding :: InputChannel -> Text -> Key -> InputBinding
inputBinding channel name key = InputBinding {channel, name, key, annotations = Map.empty}

-- | Later annotations win; metadata must never contain candidate values.
annotateInputBinding :: Map Text Text -> InputBinding -> InputBinding
annotateInputBinding additions binding = binding & #annotations %~ (additions <>)

-- | The adapter-neutral channel carrying this external input.
inputBindingChannel :: InputBinding -> InputChannel
inputBindingChannel binding = binding ^. #channel

-- | The external name, such as an environment-variable name.
inputBindingName :: InputBinding -> Text
inputBindingName binding = binding ^. #name

-- | The declaration key targeted by this binding.
inputBindingKey :: InputBinding -> Key
inputBindingKey binding = binding ^. #key

-- | Trusted descriptive metadata, without candidate values.
inputBindingAnnotations :: InputBinding -> Map Text Text
inputBindingAnnotations binding = binding ^. #annotations

-- | Explicit deployment policy: a name and reasons that selected keys need external
-- input even when defaults exist. Exporting a profile does not enforce it at runtime.
data DeploymentProfile = DeploymentProfile {name :: !Text, requirements :: !(Map Key Text)}
  deriving stock (Generic, Eq, Show)

-- | Build a named profile. Repeated keys keep the last reason; all text must be
-- safe to publish. Undeclared keys are diagnosed by 'deploymentContract'.
deploymentProfile :: Text -> [(Key, Text)] -> DeploymentProfile
deploymentProfile name requirements = DeploymentProfile {name, requirements = Map.fromList requirements}

-- | The operator-facing profile name.
profileName :: DeploymentProfile -> Text
profileName value = value ^. #name

-- | Keys requiring deliberate external input, mapped to their policy reasons.
profileRequirements :: DeploymentProfile -> Map Key Text
profileRequirements value = value ^. #requirements

-- | Default sources are lowest to highest precedence. This input container has
-- no Show instance because sources retain raw, potentially secret values.
data ContractInputs = ContractInputs
  {inputs :: ![InputBinding], defaultSources :: ![Source], profile :: !(Maybe DeploymentProfile)}
  deriving stock (Generic)

-- | No bindings, default sources, or deployment profile.
emptyContractInputs :: ContractInputs
emptyContractInputs = ContractInputs [] [] Nothing

-- | A deterministic, secret-redacted deployment description. Derived computations
-- are deferred; its verdicts do not establish runtime acceptance or connectivity.
data DeploymentContract = DeploymentContract
  {settings :: ![ContractSetting], conditions :: ![Condition], profile :: !(Maybe Text), diagnostics :: ![ContractDiagnostic]}
  deriving stock (Generic, Eq, Show)

-- | Per-key entries in deterministic key order.
contractSettings :: DeploymentContract -> [ContractSetting]
contractSettings value = value ^. #settings

-- | Conditional declaration relationships in declaration order.
contractConditions :: DeploymentContract -> [Condition]
contractConditions value = value ^. #conditions

-- | The selected profile name, when one was supplied.
contractProfile :: DeploymentContract -> Maybe Text
contractProfile value = value ^. #profile

-- | Nonfatal structural, sensitivity, or undeclared-input inconsistencies.
-- Default cycles instead fail construction with a configuration error.
contractDiagnostics :: DeploymentContract -> [ContractDiagnostic]
contractDiagnostics value = value ^. #diagnostics

-- | Merged schema metadata and every binding/default for one key. The external-input
-- verdict accounts for individual requests and may differ from merged requiredness.
data ContractSetting = ContractSetting
  { key :: !Key,
    description :: !Text,
    sensitivity :: !Sensitivity,
    requirement :: !Requirement,
    presence :: !Presence,
    inputs :: ![InputBinding],
    declaredDefaults :: ![DeclaredDefault],
    sourceDefault :: !(Maybe SourceDefault),
    deploymentRequirement :: !(Maybe Text),
    externalInput :: !ExternalInput
  }
  deriving stock (Generic, Eq, Show)

-- | A fallback rule and its safe static shape, without evaluating its computation.
data DeclaredDefault = DeclaredDefault {rule :: !RuleName, explanation :: !Text, shape :: !DefaultShape}
  deriving stock (Generic, Eq, Show)

-- | A constant display, derived dependency keys, or case dependency keys with
-- alternative count and fallback presence. Coverage does not prove evaluation succeeds.
data DefaultShape = ConstantShape !DefaultValue | DerivedShape ![Key] | CaseShape ![Key] !Int !Bool
  deriving stock (Generic, Eq, Show)

-- | A safe constant display: public rendered text, a redacted secret, or a public
-- value whose setting has no renderer.
data DefaultValue = VisibleDefault !Text | RedactedDefault | UnrenderableDefault
  deriving stock (Generic, Eq, Show)

-- | The winning explicit default candidate, its shadowed origins, safe reported
-- value, and decoder validity. Invalid winners never reveal a lower fallback.
data SourceDefault = SourceDefault
  {origin :: !Origin, shadowed :: ![Origin], value :: !ReportedValue, validity :: !DefaultValidity}
  deriving stock (Generic, Eq, Show)

-- | Whether all applicable decoders accept the winning default candidate.
-- Invalid text describes decoder expectations rather than rejected secret values.
data DefaultValidity = ValidDefault | InvalidDefault !Text
  deriving stock (Generic, Eq, Show)

-- | Whether external input is required, conditional, covered by a default, or optional.
-- A conditional input may still be required on the selected runtime path.
data ExternalInput = InputRequired !InputReason | InputConditional !InputReason | InputDefaulted !DefaultCoverage | InputOptional
  deriving stock (Generic, Eq, Show)

-- | Why the contract requires external input or marks it conditional.
data InputReason = NoDefault | InvalidSourceDefault | RequiredRequest | ProfileRequirement
  deriving stock (Generic, Eq, Show)

-- | Coverage from an explicit source or a declared fallback with dependency keys.
-- Declared coverage does not establish that dependencies or computations will succeed.
data DefaultCoverage = CoveredBySource | CoveredByDeclaration ![Key]
  deriving stock (Generic, Eq, Show)

-- | An inconsistency retained in a useful contract rather than a fatal cycle error.
data ContractDiagnostic
  = ConflictingSensitivity !Key
  | DefaultStructuralConflict !StructuralError
  | UndeclaredDefaultLeaf !UnknownKeyProblem
  | UndeclaredBindingKey !InputBinding
  | UndeclaredProfileKey !Key
  deriving stock (Generic, Eq, Show)

-- These records exist only during construction and never retain decoded values.
data Occurrence where
  Occurrence :: Presence -> Bool -> Setting a -> Occurrence

-- | Build a deterministic contract, rejecting cycles before inspecting sources.
-- Decoders check winning source candidates; declaration fallback coverage makes
-- no claim about successful computation or complete case coverage.
deploymentContract :: ContractInputs -> Config a -> Either (NonEmpty ConfigError) DeploymentContract
deploymentContract supplied declaration = case NonEmpty.nonEmpty (validateDefaultCycles declaration) of
  Just errors -> Left errors
  Nothing ->
    Right
      DeploymentContract
        { settings = fmap build entries,
          conditions = schemaConditions schema,
          profile = profileName <$> selectedProfile,
          diagnostics = sensitivityProblems <> structuralProblems <> leafProblems <> bindingProblems <> profileProblems
        }
  where
    schema = describeConfig declaration
    entries = schemaPossible schema
    declaredKeys = fmap schemaSettingKey entries
    selectedProfile = supplied ^. #profile
    requirements = maybe Map.empty profileRequirements selectedProfile
    sources = supplied ^. #defaultSources
    (occurrences, defaults) = inspect Necessary declaration
    occurrencesAt key = [entry | (target, entry) <- occurrences, target == key]
    defaultsAt key = [entry | (target, entry) <- defaults, target == key]
    effective key = maybe Secret schemaSettingSensitivity (findEntry key)
    findEntry key = case filter ((== key) . schemaSettingKey) entries of
      entry : _ -> Just entry
      [] -> Nothing
    sensitivityProblems =
      [ConflictingSensitivity (schemaSettingKey entry) | entry <- entries, Set.size (entry ^. #declaredSensitivities) > 1]
    lookups key = fmap (lookupSource key) sources
    structuralProblems = [DefaultStructuralConflict problem | key <- declaredKeys, Left problem <- lookups key]
    leafProblems =
      [ UndeclaredDefaultLeaf (UnknownKeyProblem key (candidateOrigin candidateValue'))
      | sourceValue <- sources,
        (key, candidateValue') <- sourceLeaves sourceValue,
        not (any (\declared -> NonEmpty.toList (keySegments declared) `isPrefixOf` NonEmpty.toList (keySegments key)) declaredKeys)
      ]
    bindingProblems = [UndeclaredBindingKey binding | binding <- supplied ^. #inputs, inputBindingKey binding `notElem` declaredKeys]
    profileProblems = [UndeclaredProfileKey key | key <- Map.keys requirements, key `notElem` declaredKeys]
    build entry =
      let key = schemaSettingKey entry
          requests = occurrencesAt key
          rules = defaultsAt key
          candidates = [found | Right (Just found) <- lookups key]
          winner = case reverse candidates of
            [] -> Nothing
            candidateValue' : rest -> Just (candidateValue', fmap candidateOrigin rest)
          failures = case winner of
            Nothing -> []
            Just (found, _) ->
              [ (presence, decodeFailureExpected problem)
              | Occurrence presence _ settingSpec <- requests,
                Left problem <- [decodeSetting settingSpec (candidateValue found)]
              ]
          sourceDefault =
            fmap
              ( \(found, shadowed) ->
                  SourceDefault
                    { origin = candidateOrigin found,
                      shadowed,
                      value = reportedValue (schemaSettingSensitivity entry) (candidateValue found),
                      validity = case failures of [] -> ValidDefault; (_, expected) : _ -> InvalidDefault expected
                    }
              )
              winner
          deploymentRequirement = Map.lookup key requirements
          requiredPresences = [presence | Occurrence presence True _ <- requests]
          reason = if null rules then NoDefault else RequiredRequest
          requiredVerdict
            | Necessary `elem` requiredPresences = InputRequired reason
            | Conditional `elem` requiredPresences = InputConditional reason
            | not (null rules) = InputDefaulted (CoveredByDeclaration (Set.toAscList (Set.fromList (concatMap dependencies rules))))
            | otherwise = InputOptional
          externalInput
            | isJust deploymentRequirement = InputRequired ProfileRequirement
            | isJust winner =
                if any ((== Necessary) . fst) failures
                  then InputRequired InvalidSourceDefault
                  else if null failures then InputDefaulted CoveredBySource else InputConditional InvalidSourceDefault
            | otherwise = requiredVerdict
       in ContractSetting
            { key,
              description = schemaSettingDescription entry,
              sensitivity = schemaSettingSensitivity entry,
              requirement = schemaSettingRequirement entry,
              presence = schemaSettingPresence entry,
              inputs = filter ((== key) . inputBindingKey) (supplied ^. #inputs),
              declaredDefaults = rules,
              sourceDefault,
              deploymentRequirement,
              externalInput
            }
    inspect :: Presence -> Config b -> ([(Key, Occurrence)], [(Key, DeclaredDefault)])
    inspect presence = \case
      PureConfig _ -> ([], [])
      MapConfig _ config -> inspect presence config
      ApplyConfig function inputConfig -> combine (inspect presence function) (inspect presence inputConfig)
      RequestConfig request -> case request of
        Config.RequiredRequest settingSpec -> ([(settingKey settingSpec, Occurrence presence True settingSpec)], [])
        Config.OptionalRequest settingSpec -> ([(settingKey settingSpec, Occurrence presence False settingSpec)], [])
      SelectConfig selector branch -> combine (inspect presence selector) (inspect Conditional branch)
      DefaultConfig settingSpec defaultSpec ->
        let key = settingKey settingSpec
            valueShape value =
              if effective key == Secret
                then RedactedDefault
                else
                  maybe UnrenderableDefault (\renderer -> VisibleDefault (renderer value)) (settingValueRenderer settingSpec)
            (entry, nested) = case defaultSpec of
              ConstantDefault rule explanation value -> (DeclaredDefault rule explanation (ConstantShape (valueShape value)), ([], []))
              DerivedDefault rule explanation dependency _ ->
                (DeclaredDefault rule explanation (DerivedShape (keys dependency)), inspect Conditional dependency)
              CaseDefault rule explanation dependency alternatives fallback ->
                (DeclaredDefault rule explanation (CaseShape (keys dependency) (NonEmpty.length alternatives) (isJust fallback)), inspect Conditional dependency)
         in combine ([(key, Occurrence presence False settingSpec)], [(key, entry)]) nested
    keys = fmap schemaSettingKey . schemaPossible . describeConfig
    combine (leftOccurrences, leftDefaults) (rightOccurrences, rightDefaults) =
      (leftOccurrences <> rightOccurrences, leftDefaults <> rightDefaults)
    dependencies entry = case entry ^. #shape of
      ConstantShape _ -> []
      DerivedShape keys' -> keys'
      CaseShape keys' _ _ -> keys'
