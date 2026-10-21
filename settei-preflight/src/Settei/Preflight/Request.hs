-- | Strict version-one request documents for deployment tooling.
-- Public values and fake stand-ins may be inline. Real secrets use references.
-- Parser diagnostics retain only schema paths and fixed messages, never input text.
module Settei.Preflight.Request
  ( PreflightRequest (..),
    RequestEntry (..),
    EntryForm (..),
    preflightRequest,
    parsePreflightRequest,
    renderPreflightRequestJson,
    RequestError,
    renderRequestErrorText,
    renderRequestErrorsText,
    RequestEnvironment (..),
    processRequestEnvironment,
    ResolvedRequest (..),
    resolveRequest,
  )
where

import Control.Monad (unless)
import Data.Aeson qualified as A
import Data.Aeson.Encoding qualified as E
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NE
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Settei (Sensitivity (..))
import Settei.Env (EnvName (..))
import Settei.Preflight.Internal
import Settei.Prelude
import System.Environment qualified as Env

-- No Show on any request-bearing type: callers must not log unresolved/raw inputs.
data PreflightRequest = PreflightRequest
  { role :: !RoleLabel,
    command :: !CheckCommand,
    environment :: ![RequestEntry],
    files :: ![RequestEntry],
    inherit :: !(Maybe [EnvName]),
    timeoutSeconds :: !Int,
    exitCodes :: !ExitCodeMapping,
    notes :: ![Text]
  }
  deriving stock (Generic, Eq)

data RequestEntry = RequestEntry {name :: !Text, form :: !EntryForm} deriving stock (Generic, Eq)

data EntryForm
  = InlineValue !Text
  | SecretFromEnvironment !EnvName
  | SecretFromFile !FilePath
  | SyntheticEntry !Sensitivity !Text !Text
  | UnresolvedEntry !Text
  | UnavailableSecretEntry !Text
  deriving stock (Generic, Eq)

newtype RequestError = RequestError Text deriving stock (Generic, Eq, Show)

renderRequestErrorText :: RequestError -> Text
renderRequestErrorText (RequestError t) = t

renderRequestErrorsText :: NonEmpty RequestError -> Text
renderRequestErrorsText = T.unlines . fmap renderRequestErrorText . NE.toList

preflightRequest :: RoleLabel -> CheckCommand -> [RequestEntry] -> [RequestEntry] -> PreflightRequest
preflightRequest r c es fs = PreflightRequest r c es fs Nothing 60 defaultExitCodes []

-- A deliberately small closed-schema parser. Aeson's syntax/type errors are never retained.
type Parsed a = Either RequestError a

bad :: Text -> Text -> Parsed a
bad path message = Left (RequestError (path <> ": " <> message))

objectAt :: Text -> [Text] -> A.Value -> Parsed A.Object
objectAt path allowed = \case
  A.Object o -> if all ((`elem` allowed) . K.toText) (KM.keys o) then Right o else bad path "unknown key"
  _ -> bad path "expected object"

required :: Text -> A.Object -> Text -> Parsed A.Value
required path o key = maybe (bad (path <> "." <> key) "required field is missing") Right (KM.lookup (K.fromText key) o)

textAt :: Text -> A.Value -> Parsed Text
textAt path = \case A.String t -> Right t; _ -> bad path "expected string"

intAt :: Text -> A.Value -> Parsed Int
intAt path v = case A.fromJSON v of A.Success n -> Right n; A.Error _ -> bad path "expected integer"

arrayAt :: Text -> (Text -> A.Value -> Parsed a) -> A.Value -> Parsed [a]
arrayAt path parse v = case A.fromJSON v of
  A.Success values -> sequence [parse (path <> "[" <> tshow i <> "]") value | (i, value) <- zip [0 :: Int ..] values]
  A.Error _ -> bad path "expected array"

optional :: Text -> A.Object -> Text -> a -> (Text -> A.Value -> Parsed a) -> Parsed a
optional path o key fallback parse = maybe (Right fallback) (parse (path <> "." <> key)) (KM.lookup (K.fromText key) o)

field :: Text -> A.Object -> Text -> (Text -> A.Value -> Parsed a) -> Parsed a
field path o key parse = required path o key >>= parse (path <> "." <> key)

parsePreflightRequest :: BS.ByteString -> Either (NonEmpty RequestError) PreflightRequest
parsePreflightRequest bytes = case A.eitherDecodeStrict bytes of
  Left _ -> Left (RequestError "request: invalid JSON" :| [])
  Right value -> case parseRequest value of Left e -> Left (e :| []); Right request -> Right request

parseRequest :: A.Value -> Parsed PreflightRequest
parseRequest value = do
  let path = "request"
  o <- objectAt path ["schemaVersion", "type", "role", "command", "environment", "files", "inherit", "timeoutSeconds", "exitCodes", "notes"] value
  version <- field path o "schemaVersion" intAt
  unless (version == 1) (bad "request.schemaVersion" "unsupported version")
  typ <- field path o "type" textAt
  unless (typ == "settei.preflight-request") (bad "request.type" "unexpected document type")
  label <- field path o "role" textAt
  unless (not (T.null (T.strip label))) (bad "request.role" "must not be empty")
  cmd <- field path o "command" parseCommand
  es <- field path o "environment" (\p -> arrayAt p parseEntry)
  fs <- optional path o "files" [] (\p -> arrayAt p parseEntry)
  inh <- case KM.lookup "inherit" o of Nothing -> Right Nothing; Just v -> Just <$> arrayAt "request.inherit" parseEnvName v
  seconds <- optional path o "timeoutSeconds" 60 intAt
  unless (seconds > 0 && seconds <= maxBound `div` 1000000) (bad "request.timeoutSeconds" "outside supported range")
  codes <- optional path o "exitCodes" defaultExitCodes parseCodes
  ns <- optional path o "notes" [] (\p -> arrayAt p textAt)
  pure (PreflightRequest (RoleLabel label) cmd es fs inh seconds codes ns)

parseEnvName :: Text -> A.Value -> Parsed EnvName
parseEnvName path v = do
  n <- EnvName <$> textAt path v
  if validEnvironmentName n then Right n else bad path "invalid environment variable name"

parseCommand :: Text -> A.Value -> Parsed CheckCommand
parseCommand path value = do
  o <- objectAt path ["executable", "arguments"] value
  exe <- field path o "executable" textAt
  args <- field path o "arguments" (\p -> arrayAt p parseArgument)
  pure (CheckCommand (T.unpack exe) args)

parseArgument :: Text -> A.Value -> Parsed Argument
parseArgument path value = do
  o <- objectAt path ["literal", "file", "directory", "parts"] value
  if KM.size o /= 1
    then bad path "expected exactly one argument form"
    else case KM.lookup "parts" o of
      Just v -> Argument <$> arrayAt (path <> ".parts") parsePart v
      Nothing -> Argument . pure <$> parsePart path value

parsePart :: Text -> A.Value -> Parsed ArgumentPart
parsePart path value = do
  o <- objectAt path ["literal", "file", "directory"] value
  if KM.size o /= 1
    then bad path "expected exactly one argument part"
    else case () of
      _
        | Just v <- KM.lookup "literal" o -> LiteralPart <$> textAt (path <> ".literal") v
        | Just v <- KM.lookup "file" o -> FilePart . FileName <$> textAt (path <> ".file") v
        | Just v <- KM.lookup "directory" o -> DirectoryPart . FileName <$> textAt (path <> ".directory") v
        | otherwise -> bad path "expected argument part"

parseEntry :: Text -> A.Value -> Parsed RequestEntry
parseEntry path value = do
  o <- objectAt path ["name", "value", "secretFromEnvironment", "secretFromFile", "synthetic", "reason", "sensitivity", "unresolved", "unavailableSecret"] value
  name <- field path o "name" textAt
  let forms = [k | k <- ["value", "secretFromEnvironment", "secretFromFile", "synthetic", "unresolved", "unavailableSecret"], KM.member k o]
  unless (length forms == 1) (bad path "expected exactly one value form")
  entry <- case forms of
    ["synthetic"] -> do
      standin <- field path o "synthetic" textAt
      reason <- field path o "reason" textAt
      sensitivity <- optional path o "sensitivity" Public (\p v -> textAt p v >>= \case "public" -> Right Public; "secret" -> Right Secret; _ -> bad p "expected public or secret")
      pure (SyntheticEntry sensitivity standin reason)
    [k] -> do
      unless (not (KM.member "reason" o || KM.member "sensitivity" o)) (bad path "reason and sensitivity require a synthetic entry; real secrets must use references")
      case k of
        "value" -> InlineValue <$> field path o "value" textAt
        "secretFromEnvironment" -> SecretFromEnvironment <$> field path o "secretFromEnvironment" parseEnvName
        "secretFromFile" -> SecretFromFile . T.unpack <$> field path o "secretFromFile" textAt
        "unresolved" -> UnresolvedEntry <$> field path o "unresolved" textAt
        _ -> UnavailableSecretEntry <$> field path o "unavailableSecret" textAt
    _ -> bad path "expected value form"
  pure (RequestEntry name entry)

parseCodes :: Text -> A.Value -> Parsed ExitCodeMapping
parseCodes path value = do
  o <- objectAt path ["accepted", "usage", "sourceFailure", "rejected"] value
  codes <- ExitCodeMapping <$> field path o "accepted" intAt <*> field path o "usage" (\p -> arrayAt p intAt) <*> field path o "sourceFailure" (\p -> arrayAt p intAt) <*> field path o "rejected" (\p -> arrayAt p intAt)
  if validExitCodes codes then Right codes else bad path "exit codes must be distinct integers in 0..255"

renderPreflightRequestJson :: PreflightRequest -> Text
renderPreflightRequestJson r =
  encodingText $
    obj $
      [("schemaVersion", json (1 :: Int)), ("type", json ("settei.preflight-request" :: Text)), ("role", json label), ("command", obj [("executable", json (r ^. #command . #executable)), ("arguments", E.list argumentJson (r ^. #command . #arguments))]), ("environment", E.list entryJson (r ^. #environment)), ("files", E.list entryJson (r ^. #files))]
        <> maybe [] (\names -> [("inherit", json (fmap envText names))]) (r ^. #inherit)
        <> [("timeoutSeconds", json (r ^. #timeoutSeconds)), ("exitCodes", obj [("accepted", json (codes ^. #accepted)), ("usage", json (codes ^. #usage)), ("sourceFailure", json (codes ^. #sourceFailure)), ("rejected", json (codes ^. #rejected))]), ("notes", json (r ^. #notes))]
  where
    RoleLabel label = r ^. #role
    codes = r ^. #exitCodes
    argumentJson (Argument [p]) = partJson p
    argumentJson (Argument ps) = obj [("parts", E.list partJson ps)]
    partJson = \case LiteralPart t -> obj [("literal", json t)]; FilePart n -> obj [("file", json (fileText n))]; DirectoryPart n -> obj [("directory", json (fileText n))]
    entryJson e =
      obj
        ( [("name", json (e ^. #name))] <> case e ^. #form of
            InlineValue t -> [("value", json t)]
            SecretFromEnvironment n -> [("secretFromEnvironment", json (envText n))]
            SecretFromFile p -> [("secretFromFile", json p)]
            SyntheticEntry sensitivity t reason -> [("synthetic", json t), ("reason", json reason), ("sensitivity", json (case sensitivity of Public -> "public" :: Text; Secret -> "secret"))]
            UnresolvedEntry t -> [("unresolved", json t)]
            UnavailableSecretEntry t -> [("unavailableSecret", json t)]
        )

data RequestEnvironment = RequestEnvironment {lookupVariable :: EnvName -> IO (Maybe Text), readSecretFile :: FilePath -> IO (Either Text Text)} deriving stock (Generic)

data ResolvedRequest = ResolvedRequest {role :: !RoleLabel, command :: !CheckCommand, inputs :: !ProposedInputs, options :: !PreflightOptions} deriving stock (Generic, Eq)

processRequestEnvironment :: RequestEnvironment
processRequestEnvironment =
  RequestEnvironment
    (\(EnvName n) -> fmap T.pack <$> Env.lookupEnv (T.unpack n))
    (\p -> tryIO (BS.readFile p) >>= \case Left _ -> pure (Left "secret file could not be read"); Right bytes -> pure (case TE.decodeUtf8' bytes of Left _ -> Left "secret file is not UTF-8"; Right t -> Right t))

resolveRequest :: RequestEnvironment -> PreflightRequest -> IO ResolvedRequest
resolveRequest env r = do
  es <- traverse (\e -> (EnvName (e ^. #name),) <$> resolve (e ^. #form)) (r ^. #environment)
  fs <- traverse (\e -> ProposedFile (FileName (e ^. #name)) <$> resolve (e ^. #form)) (r ^. #files)
  pure (ResolvedRequest (r ^. #role) (r ^. #command) (ProposedInputs es fs (maybe defaultInherited id (r ^. #inherit)) (r ^. #notes)) (PreflightOptions (r ^. #timeoutSeconds) (r ^. #exitCodes)))
  where
    resolve = \case
      InlineValue t -> pure (SuppliedValue Public t)
      SyntheticEntry sensitivity t reason -> pure (SyntheticValue sensitivity t reason)
      UnresolvedEntry t -> pure (UnresolvedValue t)
      UnavailableSecretEntry t -> pure (UnavailableSecret t)
      SecretFromEnvironment n -> do
        found <- if validEnvironmentName n then tryIO ((env ^. #lookupVariable) n) else pure (Right Nothing)
        pure $ case found of Right (Just t) -> SuppliedValue Secret t; _ -> UnavailableSecret ("harness environment variable " <> envText n <> " is not set")
      SecretFromFile path -> do
        found <- tryIO ((env ^. #readSecretFile) path)
        pure $ case found of Right (Right t) -> SuppliedValue Secret t; _ -> UnavailableSecret ("secret file " <> T.pack path <> " could not be read")
