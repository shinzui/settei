-- |
-- Module: Settei.Setting
-- Description: Metadata and decoders for individual configuration settings.
module Settei.Setting
  ( Sensitivity (..),
    Setting,
    decodeSetting,
    publicSetting,
    publicSettingWithRenderer,
    secretSetting,
    settingDescription,
    settingKey,
    settingSensitivity,
    settingValueRenderer,
  )
where

import Data.Generics.Labels ()
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

-- | Declare a setting whose resolved value must be redacted from reports.
secretSetting :: Key -> Text -> Decoder a -> Setting a
secretSetting key description decoder =
  Setting {key, description, sensitivity = Secret, decoder, renderer = Nothing}

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
