-- |
-- Module: Settei.Setting
-- Description: Metadata and decoders for individual configuration settings.
module Settei.Setting
  ( Sensitivity (..),
    Setting,
    decodeSetting,
    publicShowSetting,
    publicSetting,
    publicSettingWithRenderer,
    secretSetting,
    settingDescription,
    settingKey,
    settingSensitivity,
    settingValueRenderer,
    withRenderer,
  )
where

import Data.Generics.Labels ()
import Data.Text qualified as Text
import Settei.Key (Key)
import Settei.Prelude
import Settei.Value (DecodeFailure, Decoder, RawValue, runDecoder)

-- | Whether reports may display a setting's resolved value.
data Sensitivity = Public | Secret
  deriving stock (Generic, Eq, Ord, Show)

-- | Metadata and decoding behavior for one logical setting.
--
-- The constructor stays private so callers use the explicit public or secret smart
-- constructors. The type has no 'Show' instance because its decoder will receive raw
-- values that may be sensitive.
data Setting a = Setting
  { key :: !Key,
    description :: !Text,
    sensitivity :: !Sensitivity,
    decoder :: !(Decoder a),
    renderer :: !(Maybe (a -> Text))
  }
  deriving stock (Generic)

-- | Declare a setting whose resolved value may appear in reports.
publicSetting :: Key -> Text -> Decoder a -> Setting a
publicSetting key description decoder =
  Setting {key, description, sensitivity = Public, decoder, renderer = Nothing}

-- | Declare a public setting with a renderer for typed default values.
--
-- Source candidates render directly from 'RawValue'; this renderer is used only after a
-- typed constant or derived default has been evaluated.
publicSettingWithRenderer :: Key -> Text -> Decoder a -> (a -> Text) -> Setting a
publicSettingWithRenderer key description decoder renderer =
  Setting {key, description, sensitivity = Public, decoder, renderer = Just renderer}

-- | Declare a public setting whose typed default values render via 'show'.
--
-- Equivalent to 'publicSettingWithRenderer' with @Text.pack . show@. Best for primitive
-- and enum-like types; a derived 'Show' of a rich type may be ugly in reports but is
-- never unsafe, because renderers only affect display of typed defaults and secret
-- settings always redact regardless of any renderer.
publicShowSetting :: (Show a) => Key -> Text -> Decoder a -> Setting a
publicShowSetting key description decoder =
  publicSettingWithRenderer key description decoder (Text.pack . show)

-- | Declare a setting whose resolved value must be redacted from reports.
secretSetting :: Key -> Text -> Decoder a -> Setting a
secretSetting key description decoder =
  Setting {key, description, sensitivity = Secret, decoder, renderer = Nothing}

-- | Attach or replace the typed-default renderer of an existing setting.
--
-- On a secret setting this is harmless: the stored renderer is ignored and reports keep
-- showing the redaction marker (see "Settei.Resolve").
withRenderer :: (a -> Text) -> Setting a -> Setting a
withRenderer renderValue settingSpec = settingSpec & #renderer ?~ renderValue

-- | Decode one raw candidate using the setting's validated key.
decodeSetting :: Setting a -> RawValue -> Either DecodeFailure a
decodeSetting settingSpec =
  runDecoder (settingSpec ^. #decoder) (settingSpec ^. #key)

-- | Inspect the setting's key.
settingKey :: Setting a -> Key
settingKey settingSpec = settingSpec ^. #key

-- | Inspect the setting's human-readable purpose.
settingDescription :: Setting a -> Text
settingDescription settingSpec = settingSpec ^. #description

-- | Inspect whether the setting is public or secret.
settingSensitivity :: Setting a -> Sensitivity
settingSensitivity settingSpec = settingSpec ^. #sensitivity

-- | Return the optional renderer for a public typed default.
settingValueRenderer :: Setting a -> Maybe (a -> Text)
settingValueRenderer settingSpec = settingSpec ^. #renderer
