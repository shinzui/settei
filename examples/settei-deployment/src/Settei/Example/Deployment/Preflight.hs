-- | Reference extractor, not a Kubernetes implementation. It accepts a normalized
-- JSON List, resolves env/envFrom precedence in the Deployment namespace, and maps
-- ConfigMap/Secret mounts into a virtual root. Secret values are never inspected.
-- Generated fields, unknown input forms, expansions, command overrides, subPath,
-- binaryData, optional volumes, and unsupported mounted volumes remain limitations.
-- The host executable's equivalence to the image entrypoint is a caller obligation.
module Settei.Example.Deployment.Preflight
  ( ExtractionOptions (..),
    extractionOptions,
    ExtractionError,
    renderExtractionErrorText,
    extractPreflightRequest,
  )
where

import Control.Monad (foldM, unless, when)
import Data.Aeson qualified as A
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Char (isAsciiLower, isAsciiUpper, isDigit, toUpper)
import Data.Generics.Labels ()
import Data.List (find, sortOn)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Settei (Sensitivity (..))
import Settei.Env (EnvName (..))
import Settei.Preflight qualified as P
import Settei.Preflight.Request qualified as R
import Settei.Prelude hiding (at, from)

data ExtractionOptions = ExtractionOptions
  { deploymentName :: !Text,
    role :: !P.RoleLabel,
    executable :: !FilePath,
    containerName :: !Text,
    secretPrefix :: !Text,
    syntheticPublic :: !(Map EnvName Text),
    syntheticSecret :: !(Map EnvName Text)
  }
  deriving stock (Generic, Eq)

extractionOptions :: Text -> P.RoleLabel -> FilePath -> ExtractionOptions
extractionOptions name role exe = ExtractionOptions name role exe "check-config" "SETTEI_PREFLIGHT_SECRET_" Map.empty Map.empty

newtype ExtractionError = ExtractionError Text deriving stock (Generic, Eq, Show)

renderExtractionErrorText :: ExtractionError -> Text
renderExtractionErrorText (ExtractionError t) = "manifest: " <> t

type Extract a = Either ExtractionError a

type Reference = (Text, (Text, Text))

type Piece = ([R.RequestEntry], [Text], [Reference])

data Mount = Mount !Text ![(Text, R.EntryForm)] ![Text] ![Reference]

-- These helpers never retain Aeson diagnostics or arbitrary input values.
err :: Text -> Extract a
err = Left . ExtractionError

at :: Text -> A.Value -> Maybe A.Value
at key (A.Object o) = KM.lookup (K.fromText key) o
at _ _ = Nothing

text :: A.Value -> Maybe Text
text (A.String t) = Just t
text _ = Nothing

string :: Text -> A.Value -> Extract Text
string key value = maybe (err "expected a named string field") Right (at key value >>= text)

strings :: Text -> A.Value -> Extract [Text]
strings key value = list key value >>= traverse (maybe (err "expected string array") Right . text)

array :: A.Value -> Extract [A.Value]
array v = case A.fromJSON v of A.Success xs -> Right xs; A.Error _ -> err "expected array"

list :: Text -> A.Value -> Extract [A.Value]
list key value = maybe (Right []) array (at key value)

object :: A.Value -> Extract A.Object
object (A.Object o) = Right o
object _ = err "expected object"

optionalString :: Text -> Text -> A.Value -> Extract Text
optionalString key fallback value = maybe (Right fallback) (maybe (err "expected string field") Right . text) (at key value)

flag :: Text -> A.Value -> Bool
flag key value = at key value == Just (A.Bool True)

metadata :: A.Value -> A.Value
metadata v = maybe A.Null id (at "metadata" v)

identity :: A.Value -> Extract (Text, Text, Text)
identity v = (,,) <$> string "kind" v <*> optionalString "namespace" "default" (metadata v) <*> string "name" (metadata v)

joinPieces :: [Piece] -> Piece
joinPieces ps = (concat [es | (es, _, _) <- ps], concat [ns | (_, ns, _) <- ps], concat [rs | (_, _, rs) <- ps])

lookupObject :: [A.Value] -> Text -> Text -> Text -> Maybe A.Value
lookupObject resources kind namespace name = find (\v -> identity v == Right (kind, namespace, name)) resources

validName :: Text -> Bool
validName n = case T.uncons n of Nothing -> False; Just (c, rest) -> initial c && T.all (\x -> initial x || isDigit x && x <= '9') rest
  where
    initial c = isAsciiLower c || isAsciiUpper c || c == '_'

validPath :: Text -> Bool
validPath p = not (T.null p) && not (T.any (`elem` ['\0', '\\']) p) && all (\s -> s /= "" && s /= "." && s /= "..") (T.splitOn "/" p)

keys :: Text -> A.Value -> Extract [Text]
keys key v = maybe (Right []) (fmap (fmap K.toText . KM.keys) . object) (at key v)

configValue :: Text -> A.Value -> Maybe Text
configValue key v = at "data" v >>= at key >>= text

secretKeys :: A.Value -> Extract [Text]
secretKeys v = Map.keys . Map.fromList . fmap (,()) <$> ((<>) <$> keys "data" v <*> keys "stringData" v)

secretReference :: ExtractionOptions -> Text -> Text -> (R.EntryForm, Reference)
secretReference opts name key = (R.SecretFromEnvironment (EnvName generated), (generated, (name, key)))
  where
    generated = opts ^. #secretPrefix <> sanitize name <> "_" <> sanitize key
    sanitize = T.map (\c -> if isAsciiLower c || isAsciiUpper c || (isDigit c && c <= '9') then toUpper c else '_')

extractPreflightRequest :: ExtractionOptions -> A.Value -> Extract (R.PreflightRequest, [Text])
extractPreflightRequest opts manifest = do
  kind <- string "kind" manifest
  unless (kind == "List") (err "expected a normalized Kubernetes List")
  resources <- maybe (err "List.items is required") array (at "items" manifest)
  ids <- traverse identity resources
  unless (length ids == Map.size (Map.fromList (fmap (,()) ids))) (err "duplicate resource identity")
  deployment <- case [v | v <- resources, at "kind" v == Just (A.String "Deployment"), at "name" (metadata v) == Just (A.String (opts ^. #deploymentName))] of
    [v] -> Right v
    [] -> err "Deployment was not found"
    _ -> err "Deployment name is ambiguous across namespaces"
  namespace <- optionalString "namespace" "default" (metadata deployment)
  pod <- maybe (err "Deployment pod template is missing") Right (at "spec" deployment >>= at "template" >>= at "spec")
  containers <- (<>) <$> list "initContainers" pod <*> list "containers" pod
  container <- case filter (\v -> at "name" v == Just (A.String (opts ^. #containerName))) containers of [v] -> Right v; _ -> err "expected exactly one named container"
  froms <- list "envFrom" container >>= traverse (extractEnvFrom opts resources namespace)
  explicit <- list "env" container >>= traverse (extractEnv opts resources namespace)
  let (es, environmentNotes, environmentRefs) = joinPieces (froms <> explicit)
      effective = Map.fromList [(e ^. #name, e ^. #form) | e <- es]
  substituted <- applySubstitutions opts effective
  volumes <- list "volumes" pod
  mounts <- list "volumeMounts" container >>= traverse (extractMount opts resources namespace volumes)
  let fileEntries = concat [fs | Mount _ fs _ _ <- mounts]
      fileNames = fmap fst fileEntries
      mountNotes = concat [ns | Mount _ _ ns _ <- mounts]
      refs = environmentRefs <> concat [rs | Mount _ _ _ rs <- mounts]
  unless (length fileNames == Map.size (Map.fromList (fmap (,()) fileNames))) (err "mounted file paths collide")
  when (or [a /= b && (a <> "/") `T.isPrefixOf` b | a <- fileNames, b <- fileNames]) (err "mounted file paths overlap structurally")
  unless (all validPath fileNames) (err "mounted file path is unsafe")
  _ <- foldM checkReference Map.empty refs
  args <- strings "args" container
  command <- strings "command" container
  let paths = sortOn (negate . T.length . fst) ([("/" <> n, P.FilePart (P.FileName n)) | (n, _) <- fileEntries] <> [(absolute, P.DirectoryPart (P.FileName (T.drop 1 absolute))) | Mount absolute fs _ _ <- mounts, not (null fs)])
      rewritten = fmap (rewriteArgument paths) args
      notes = environmentNotes <> mountNotes <> ["container command override is unsupported; host executable equivalence is unverified" | not (null command)] <> concatMap snd rewritten
      request = R.preflightRequest (opts ^. #role) (P.CheckCommand (opts ^. #executable) (fmap fst rewritten)) [R.RequestEntry n f | (n, f) <- Map.toAscList substituted] [R.RequestEntry n f | (n, f) <- sortOn fst fileEntries]
  pure (request & #notes .~ notes, notes)
  where
    checkReference seen (generated, original) = case Map.lookup generated seen of
      Just previous | previous /= original -> err "secret-reference name sanitization collision"
      _ -> if validName generated then Right (Map.insert generated original seen) else err "secret prefix produces an invalid environment reference"

unsupportedFields :: Text -> [Text] -> A.Value -> [Text]
unsupportedFields location allowed value = case value of
  A.Object o -> ["unsupported fields in " <> location | any ((`notElem` allowed) . K.toText) (KM.keys o)]
  _ -> ["unsupported input object in " <> location]

referenceNotes :: Text -> [Text] -> A.Value -> [Text]
referenceNotes location allowed value =
  unsupportedFields location allowed value <> case at "optional" value of
    Nothing -> []
    Just (A.Bool _) -> []
    _ -> ["unsupported optional reference value"]

extractEnvFrom :: ExtractionOptions -> [A.Value] -> Text -> A.Value -> Extract Piece
extractEnvFrom opts resources namespace source = do
  prefix <- optionalString "prefix" "" source
  result <- case (at "configMapRef" source, at "secretRef" source) of
    (Just ref, Nothing) -> do
      name <- string "name" ref
      case lookupObject resources "ConfigMap" namespace name of
        Nothing -> pure ([], ["envFrom ConfigMap is absent; its keys cannot be enumerated"], [])
        Just cm -> do
          names <- keys "data" cm
          values <- traverse (\key -> maybe (err "ConfigMap data must contain strings") (\v -> pure (R.RequestEntry (prefix <> key) (R.InlineValue v))) (configValue key cm)) names
          pure (values, concatMap entryNotes values <> ["ConfigMap binaryData is unsupported" | at "binaryData" cm /= Nothing], [])
    (Nothing, Just ref) -> do
      name <- string "name" ref
      case lookupObject resources "Secret" namespace name of
        Nothing -> pure ([], ["envFrom Secret is absent; its keys cannot be enumerated"], [])
        Just secret -> do
          names <- secretKeys secret
          let pairs = [(R.RequestEntry (prefix <> key) form, reference) | key <- names, let (form, reference) = secretReference opts name key]
          pure (fmap fst pairs, concatMap (entryNotes . fst) pairs, fmap snd pairs)
    _ -> pure ([], ["unsupported envFrom source"], [])
  let (es, ns, rs) = result
      extra =
        unsupportedFields "envFrom" ["prefix", "configMapRef", "secretRef"] source
          <> concat [referenceNotes "envFrom reference" ["name", "optional"] ref | key <- ["configMapRef", "secretRef"], Just ref <- [at key source]]
  pure (es, ns <> extra, rs)

extractEnv :: ExtractionOptions -> [A.Value] -> Text -> A.Value -> Extract Piece
extractEnv opts resources namespace value = do
  name <- string "name" value
  result <- case (at "value" value, at "valueFrom" value) of
    (Just v, Nothing) -> do t <- maybe (err "env.value must be a string") Right (text v); pure ([R.RequestEntry name (R.InlineValue t)], [], [])
    (Nothing, Just from) -> do
      o <- object from
      if KM.size o /= 1
        then unknown name
        else case () of
          _
            | Just ref <- at "configMapKeyRef" from -> do
                objName <- string "name" ref
                key <- string "key" ref
                case lookupObject resources "ConfigMap" namespace objName >>= configValue key of
                  Just v -> pure ([R.RequestEntry name (R.InlineValue v)], [], [])
                  Nothing -> if flag "optional" ref then pure ([], ["optional ConfigMap key is absent; input omitted"], []) else pure ([R.RequestEntry name (R.UnresolvedEntry "ConfigMap object or key is absent")], [], [])
            | Just ref <- at "secretKeyRef" from -> do
                objName <- string "name" ref
                key <- string "key" ref
                available <- maybe (Right False) (fmap (key `elem`) . secretKeys) (lookupObject resources "Secret" namespace objName)
                if flag "optional" ref && not available
                  then pure ([], ["optional Secret key is absent; input omitted"], [])
                  else
                    let (form, reference) = secretReference opts objName key in pure ([R.RequestEntry name form], [], [reference])
            | Just ref <- at "fieldRef" from -> do
                path <- string "fieldPath" ref
                pure ([R.RequestEntry name (R.UnresolvedEntry ("downward API fieldPath " <> path))], [], [])
            | otherwise -> unknown name
    (Nothing, Nothing) -> pure ([R.RequestEntry name (R.InlineValue "")], [], [])
    _ -> err "env entry has conflicting value forms"
  let (es, ns, rs) = result
  pure
    ( es,
      ns
        <> concatMap entryNotes es
        <> unsupportedFields "env entry" ["name", "value", "valueFrom"] value
        <> concat [referenceNotes "env key reference" ["name", "key", "optional"] ref | Just source <- [at "valueFrom" value], key <- ["configMapKeyRef", "secretKeyRef"], Just ref <- [at key source]],
      rs
    )
  where
    unknown name = pure ([R.RequestEntry name (R.UnresolvedEntry "unsupported valueFrom")], ["unsupported env.valueFrom input"], [])

entryNotes :: R.RequestEntry -> [Text]
entryNotes e = ["environment name is unsupported by the harness" | not (validName (e ^. #name))] <> case e ^. #form of R.InlineValue v -> ["environment variable expansion is unsupported" | "$(" `T.isInfixOf` v]; _ -> []

applySubstitutions :: ExtractionOptions -> Map Text R.EntryForm -> Extract (Map Text R.EntryForm)
applySubstitutions opts entries = do
  unless (Map.null (Map.intersection (opts ^. #syntheticPublic) (opts ^. #syntheticSecret))) (err "conflicting synthetic substitutions")
  public <- foldM (apply False) entries (Map.toList (opts ^. #syntheticPublic))
  foldM (apply True) public (Map.toList (opts ^. #syntheticSecret))
  where
    apply secret accumulated (EnvName n, value) = case Map.lookup n accumulated of
      Just (R.UnresolvedEntry reason) | not secret -> Right (Map.insert n (R.SyntheticEntry Public value reason) accumulated)
      Just (R.SecretFromEnvironment _) | secret -> replaceSecret
      Just (R.SecretFromFile _) | secret -> replaceSecret
      Just (R.UnavailableSecretEntry _) | secret -> replaceSecret
      _ -> err "synthetic substitution names an unknown input or incompatible classification"
      where
        replaceSecret = Right (Map.insert n (R.SyntheticEntry Secret value "explicit synthetic secret substitution") accumulated)

extractMount :: ExtractionOptions -> [A.Value] -> Text -> [A.Value] -> A.Value -> Extract Mount
extractMount opts resources namespace volumes mount = do
  volumeName <- string "name" mount
  path <- string "mountPath" mount
  unless (T.isPrefixOf "/" path && validPath (T.drop 1 path)) (err "mount path must be canonical and absolute")
  volume <- case filter (\v -> at "name" v == Just (A.String volumeName)) volumes of [v] -> Right v; _ -> err "mounted volume must have exactly one definition"
  if at "subPath" mount /= Nothing || at "subPathExpr" mount /= Nothing
    then pure (Mount path [] ["subPath/subPathExpr mounts are unsupported"] [])
    else case (at "configMap" volume, at "secret" volume) of
      (Just ref, Nothing) -> supported False path ref
      (Nothing, Just ref) -> supported True path ref
      _ -> pure (Mount path [] ["unsupported mounted volume (projected/downwardAPI/csi/emptyDir/persistentVolumeClaim)"] [])
  where
    supported secret path ref = do
      name <- string (if secret then "secretName" else "name") ref
      let resource = lookupObject resources (if secret then "Secret" else "ConfigMap") namespace name
      (items, itemNotes) <- case at "items" ref of
        Just v -> do
          xs <- array v >>= traverse (\item -> (,) <$> string "key" item <*> string "path" item)
          pure (xs, [])
        Nothing -> case resource of
          Nothing -> pure ([], ["mounted object is absent; all keys cannot be enumerated"])
          Just v -> do names <- if secret then secretKeys v else keys "data" v; pure (fmap (\k -> (k, k)) names, [])
      unless (all (validPath . snd) items) (err "volume item path is unsafe")
      let fileEntry (key, relative) =
            let filename = T.drop 1 path <> "/" <> relative
             in if secret
                  then let (form, reference) = secretReference opts name key in ((filename, form), [reference], [])
                  else case resource >>= configValue key of
                    Just value -> ((filename, R.InlineValue value), [], [])
                    Nothing -> ((filename, R.UnresolvedEntry "mounted ConfigMap object or key is absent"), [], ["mounted ConfigMap key is unknown"])
          extracted = fmap fileEntry items
          notes = itemNotes <> ["mounted Secret key is unknown" | secret, Just secretObject <- [resource], (key, _) <- items, Right names <- [secretKeys secretObject], key `notElem` names] <> ["optional volume semantics are unsupported" | flag "optional" ref] <> ["ConfigMap binaryData is unsupported" | not secret, maybe False (\v -> at "binaryData" v /= Nothing) resource] <> concat [ns | (_, _, ns) <- extracted]
      pure (Mount path [f | (f, _, _) <- extracted] notes (concat [rs | (_, rs, _) <- extracted]))

-- Match longest path at token boundaries, retaining literal runs around file/dir parts.
rewriteArgument :: [(Text, P.ArgumentPart)] -> Text -> (P.Argument, [Text])
rewriteArgument paths original =
  ( P.Argument (coalesce (go True original)),
    ["argument expansion is unsupported" | "$(" `T.isInfixOf` original] <> ["argument contains an absolute path outside supported mounts" | unknown True original]
  )
  where
    match t = find (\(p, _) -> p `T.isPrefixOf` t && let rest = T.drop (T.length p) t in T.null rest || maybe False (\(c, _) -> c == '/' || boundary c) (T.uncons rest)) paths
    go _ t | T.null t = []
    go start t = case if start then match t else Nothing of
      Just (path, part) -> part : go False (T.drop (T.length path) t)
      Nothing -> let c = T.head t in P.LiteralPart (T.singleton c) : go (boundary c) (T.tail t)
    unknown _ t | T.null t = False
    unknown start t = case if start then match t else Nothing of
      Just (path, _) -> unknown False (T.drop (T.length path) t)
      Nothing -> (start && T.isPrefixOf "/" t) || unknown (boundary (T.head t)) (T.tail t)
    boundary c = c `elem` (" =:\t\n\"'" :: String)
    coalesce (P.LiteralPart a : P.LiteralPart b : rest) = coalesce (P.LiteralPart (a <> b) : rest)
    coalesce (p : rest) = p : coalesce rest
    coalesce [] = []
