{-# LANGUAGE ImportQualifiedPost #-}

-- |
-- Module: Settei.Yaml
-- Description: Strict, location-preserving YAML sources for Settei.
module Settei.Yaml
  ( YamlErrorCategory (..),
    YamlSourceError,
    YamlSourceOptions,
    annotateYamlSourceOptions,
    decodeYamlSource,
    fromKubernetesMountedFile,
    readYamlSource,
    withYamlSourcePath,
    yamlErrorCategory,
    yamlErrorColumn,
    yamlErrorContext,
    yamlErrorLine,
    yamlErrorMessage,
    yamlErrorName,
    yamlErrorPath,
    yamlSourceAnnotations,
    yamlSourceName,
    yamlSourceOptions,
    yamlSourcePath,
  )
where

import Control.Applicative ((<|>))
import Control.Exception (IOException, displayException, try)
import Control.Monad (when)
import Data.Attoparsec.Text qualified as Attoparsec
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Char (ord)
import Data.Conduit (runConduitRes, (.|))
import Data.Conduit.List qualified as ConduitList
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Ratio qualified as Ratio
import Data.Scientific (Scientific)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Settei
import Settei.Prelude
import System.IO.Unsafe (unsafePerformIO)
import Text.Libyaml qualified as Libyaml

-- | Stable classes of adapter failure. No constructor retains a raw YAML value.
data YamlErrorCategory
  = YamlSyntaxError
  | YamlIoError
  | YamlMultipleDocuments
  | YamlDuplicateKey
  | YamlNonStringKey
  | YamlDottedKey
  | YamlUnsupportedFeature
  | YamlInvalidScalar
  | YamlTopLevelType
  deriving stock (Generic, Eq, Ord, Show)

-- | A secret-safe YAML input failure.
data YamlSourceError = YamlSourceError
  { category :: !YamlErrorCategory,
    name :: !Text,
    path :: !(Maybe FilePath),
    line :: !(Maybe Int),
    column :: !(Maybe Int),
    context :: !Text,
    message :: !Text
  }
  deriving stock (Generic, Eq, Show)

-- | How one YAML document should be named and annotated in provenance.
data YamlSourceOptions = YamlSourceOptions
  { name :: !Text,
    path :: !(Maybe FilePath),
    annotations :: !(Map Text Text)
  }
  deriving stock (Generic, Eq)

data PathPiece = MappingKey !Text | SequenceIndex !Int
  deriving stock (Generic, Eq, Ord)

type LocationMap = Map [Text] SourceLocation

-- | Start options for an in-memory YAML document.
yamlSourceOptions :: Text -> YamlSourceOptions
yamlSourceOptions name = YamlSourceOptions {name, path = Nothing, annotations = Map.empty}

-- | Attach a real or logical file path to an in-memory document.
withYamlSourcePath :: FilePath -> YamlSourceOptions -> YamlSourceOptions
withYamlSourcePath path options = options & #path .~ Just path

-- | Add trusted, secret-safe origin metadata.
annotateYamlSourceOptions :: Map Text Text -> YamlSourceOptions -> YamlSourceOptions
annotateYamlSourceOptions annotations options = options & #annotations %~ (annotations <>)

-- | Attach a trusted Kubernetes reference for a mounted YAML file.
--
-- This performs no cluster lookup. Setting sensitivity remains the sole redaction policy.
fromKubernetesMountedFile :: KubernetesRef -> YamlSourceOptions -> YamlSourceOptions
fromKubernetesMountedFile reference =
  annotateYamlSourceOptions (kubernetesAnnotations reference)

-- | Return the stable source name.
yamlSourceName :: YamlSourceOptions -> Text
yamlSourceName options = options ^. #name

-- | Return the optional file path.
yamlSourcePath :: YamlSourceOptions -> Maybe FilePath
yamlSourcePath options = options ^. #path

-- | Return caller-supplied, secret-safe annotations.
yamlSourceAnnotations :: YamlSourceOptions -> Map Text Text
yamlSourceAnnotations options = options ^. #annotations

-- | Return an error's stable category.
yamlErrorCategory :: YamlSourceError -> YamlErrorCategory
yamlErrorCategory problem = problem ^. #category

-- | Return the source name associated with an error.
yamlErrorName :: YamlSourceError -> Text
yamlErrorName problem = problem ^. #name

-- | Return the file path associated with an error, when known.
yamlErrorPath :: YamlSourceError -> Maybe FilePath
yamlErrorPath problem = problem ^. #path

-- | Return the one-based line associated with an error, when known.
yamlErrorLine :: YamlSourceError -> Maybe Int
yamlErrorLine problem = problem ^. #line

-- | Return the one-based column associated with an error, when known.
yamlErrorColumn :: YamlSourceError -> Maybe Int
yamlErrorColumn problem = problem ^. #column

-- | Return a structural path such as @$.service.ports[0]@.
yamlErrorContext :: YamlSourceError -> Text
yamlErrorContext problem = problem ^. #context

-- | Return a concise message that never includes a raw scalar or source excerpt.
yamlErrorMessage :: YamlSourceError -> Text
yamlErrorMessage problem = problem ^. #message

-- | Decode exactly one YAML mapping into a Settei file source.
--
-- Duplicate keys, non-string keys, dotted keys, aliases, anchors, merge keys, custom
-- tags, special floating values, and multiple documents fail explicitly.
decodeYamlSource :: YamlSourceOptions -> ByteString -> Either (NonEmpty YamlSourceError) Source
decodeYamlSource options bytes =
  first NonEmpty.singleton $ do
    events <- decodeMarkedEvents options bytes
    (root, locations) <- parseDocument options events
    pure
      ( locateSource
          (locationFor locations)
          ( annotateSource
              (options ^. #annotations)
              (source (options ^. #name) (FileSource "YAML") root)
          )
      )

-- | Read one file and pass it through the same strict pure translator.
--
-- The supplied file path replaces any path already present in the options.
readYamlSource :: YamlSourceOptions -> FilePath -> IO (Either (NonEmpty YamlSourceError) Source)
readYamlSource options filePath = do
  let fileOptions = withYamlSourcePath filePath options
  contents <- try @IOException (ByteString.readFile filePath)
  pure $ case contents of
    Left exception ->
      Left
        ( NonEmpty.singleton
            ( yamlError
                fileOptions
                YamlIoError
                Nothing
                []
                (Text.pack (displayException exception))
            )
        )
    Right bytes -> decodeYamlSource fileOptions bytes

decodeMarkedEvents :: YamlSourceOptions -> ByteString -> Either YamlSourceError [Libyaml.MarkedEvent]
decodeMarkedEvents options bytes = unsafePerformIO $ do
  decoded <-
    try @Libyaml.YamlException
      (runConduitRes (Libyaml.decodeMarked bytes .| ConduitList.consume))
  pure $ first (syntaxError options) decoded
{-# NOINLINE decodeMarkedEvents #-}

syntaxError :: YamlSourceOptions -> Libyaml.YamlException -> YamlSourceError
syntaxError options = \case
  Libyaml.YamlParseException problem parserContext mark ->
    yamlError
      options
      YamlSyntaxError
      (Just mark)
      []
      ( Text.intercalate
          ": "
          (filter (not . Text.null) (fmap Text.pack [parserContext, problem]))
      )
  Libyaml.YamlException message ->
    yamlError options YamlSyntaxError Nothing [] (Text.pack message)

parseDocument :: YamlSourceOptions -> [Libyaml.MarkedEvent] -> Either YamlSourceError (RawValue, LocationMap)
parseDocument options events = case events of
  firstEvent : rest
    | eventOf firstEvent == Libyaml.EventStreamStart -> parseStream rest
  _ -> Left (unexpectedStructure options Nothing [])
  where
    parseStream = \case
      finalEvent : []
        | eventOf finalEvent == Libyaml.EventStreamEnd ->
            Right (RawObject Map.empty, Map.empty)
      documentStart : rest
        | eventOf documentStart == Libyaml.EventDocumentStart -> do
            (root, locations, remaining) <- case rest of
              documentEnd : trailing
                | eventOf documentEnd == Libyaml.EventDocumentEnd ->
                    Right (RawObject Map.empty, Map.empty, trailing)
              _ -> do
                (value, foundLocations, afterValue) <- parseNode options [] (Just []) rest
                afterEnd <- requireEvent options Libyaml.EventDocumentEnd afterValue
                Right (value, foundLocations, afterEnd)
            case remaining of
              next : _
                | eventOf next == Libyaml.EventDocumentStart ->
                    Left (yamlError options YamlMultipleDocuments (Just (startMark next)) [] "multiple YAML documents are not supported")
              streamEnd : []
                | eventOf streamEnd == Libyaml.EventStreamEnd ->
                    case root of
                      RawObject _ -> Right (root, locations)
                      RawNull -> Right (RawObject Map.empty, Map.empty)
                      _ -> Left (yamlError options YamlTopLevelType Nothing [] "the top-level YAML value must be a mapping")
              _ -> Left (unexpectedStructure options Nothing [])
      _ -> Left (unexpectedStructure options Nothing [])

parseNode ::
  YamlSourceOptions ->
  [PathPiece] ->
  Maybe [Text] ->
  [Libyaml.MarkedEvent] ->
  Either YamlSourceError (RawValue, LocationMap, [Libyaml.MarkedEvent])
parseNode options context keyPath = \case
  [] -> Left (unexpectedStructure options Nothing context)
  marked : rest -> case eventOf marked of
    Libyaml.EventScalar bytes tag style anchor -> do
      rejectAnchor options context marked anchor
      value <- scalarValue options context marked bytes tag style
      Right (value, locationMap options keyPath marked, rest)
    Libyaml.EventSequenceStart tag _ anchor -> do
      rejectAnchor options context marked anchor
      rejectCollectionTag options context marked Libyaml.SeqTag tag
      (values, remaining) <- parseSequence options context 0 rest
      Right (RawArray values, locationMap options keyPath marked, remaining)
    Libyaml.EventMappingStart tag _ anchor -> do
      rejectAnchor options context marked anchor
      rejectCollectionTag options context marked Libyaml.MapTag tag
      (object, childLocations, remaining) <- parseMapping options context keyPath Map.empty Map.empty rest
      Right
        ( RawObject object,
          locationMap options keyPath marked <> childLocations,
          remaining
        )
    Libyaml.EventAlias _ ->
      Left (yamlError options YamlUnsupportedFeature (Just (startMark marked)) context "YAML aliases are not supported")
    _ -> Left (unexpectedStructure options (Just (startMark marked)) context)

parseSequence ::
  YamlSourceOptions ->
  [PathPiece] ->
  Int ->
  [Libyaml.MarkedEvent] ->
  Either YamlSourceError ([RawValue], [Libyaml.MarkedEvent])
parseSequence options context position = \case
  [] -> Left (unexpectedStructure options Nothing context)
  marked : rest
    | eventOf marked == Libyaml.EventSequenceEnd -> Right ([], rest)
    | otherwise -> do
        (value, _, remaining) <- parseNode options (context <> [SequenceIndex position]) Nothing (marked : rest)
        (values, finalEvents) <- parseSequence options context (position + 1) remaining
        Right (value : values, finalEvents)

parseMapping ::
  YamlSourceOptions ->
  [PathPiece] ->
  Maybe [Text] ->
  Map Text RawValue ->
  LocationMap ->
  [Libyaml.MarkedEvent] ->
  Either YamlSourceError (Map Text RawValue, LocationMap, [Libyaml.MarkedEvent])
parseMapping options context keyPath object locations = \case
  [] -> Left (unexpectedStructure options Nothing context)
  marked : rest
    | eventOf marked == Libyaml.EventMappingEnd -> Right (object, locations, rest)
    | otherwise -> do
        key <- mappingKey options context marked
        let keyContext = context <> [MappingKey key]
        when (key == "<<") $
          Left (yamlError options YamlUnsupportedFeature (Just (startMark marked)) keyContext "YAML merge keys are not supported")
        when (Text.any (== '.') key) $
          Left (yamlError options YamlDottedKey (Just (startMark marked)) keyContext "mapping keys containing dots are not supported; use nested mappings")
        when (Map.member key object) $
          Left (yamlError options YamlDuplicateKey (Just (startMark marked)) keyContext "duplicate mapping key")
        let childKeyPath = fmap (<> [key]) keyPath
        (value, childLocations, remaining) <- parseNode options keyContext childKeyPath rest
        parseMapping
          options
          context
          keyPath
          (Map.insert key value object)
          (locations <> childLocations)
          remaining

mappingKey :: YamlSourceOptions -> [PathPiece] -> Libyaml.MarkedEvent -> Either YamlSourceError Text
mappingKey options context marked = case eventOf marked of
  Libyaml.EventScalar bytes tag style anchor -> do
    rejectAnchor options context marked anchor
    value <- scalarValue options context marked bytes tag style
    case value of
      RawText key -> Right key
      _ -> Left (yamlError options YamlNonStringKey (Just (startMark marked)) context "mapping keys must be strings")
  _ -> Left (yamlError options YamlNonStringKey (Just (startMark marked)) context "mapping keys must be scalar strings")

scalarValue ::
  YamlSourceOptions ->
  [PathPiece] ->
  Libyaml.MarkedEvent ->
  ByteString ->
  Libyaml.Tag ->
  Libyaml.Style ->
  Either YamlSourceError RawValue
scalarValue options context marked bytes tag style = do
  value <-
    first
      (const (yamlError options YamlInvalidScalar (Just (startMark marked)) context "scalar is not valid UTF-8"))
      (TextEncoding.decodeUtf8' bytes)
  case tag of
    Libyaml.StrTag -> Right (RawText value)
    Libyaml.NullTag -> Right RawNull
    Libyaml.BoolTag -> parseBoolean options context marked value
    Libyaml.IntTag -> parseTaggedInteger options context marked value
    Libyaml.FloatTag -> RawNumber . toRational <$> parseNumber options context marked value
    Libyaml.NoTag
      | style `elem` [Libyaml.SingleQuoted, Libyaml.DoubleQuoted, Libyaml.Literal, Libyaml.Folded] ->
          Right (RawText value)
      | isNull value -> Right RawNull
      | Just boolean <- yamlBoolean value -> Right (RawBool boolean)
      | Right number <- parseYamlNumber value -> Right (RawNumber (toRational number))
      | otherwise -> Right (RawText value)
    _ -> Left (yamlError options YamlUnsupportedFeature (Just (startMark marked)) context "this YAML scalar tag is not supported")

parseBoolean :: YamlSourceOptions -> [PathPiece] -> Libyaml.MarkedEvent -> Text -> Either YamlSourceError RawValue
parseBoolean options context marked value =
  maybe
    (Left (yamlError options YamlInvalidScalar (Just (startMark marked)) context "invalid boolean scalar"))
    (Right . RawBool)
    (yamlBoolean value)

parseTaggedInteger :: YamlSourceOptions -> [PathPiece] -> Libyaml.MarkedEvent -> Text -> Either YamlSourceError RawValue
parseTaggedInteger options context marked value = do
  number <- parseNumber options context marked value
  let rational = toRational number
  if Ratio.denominator rational == 1
    then Right (RawNumber rational)
    else Left (yamlError options YamlInvalidScalar (Just (startMark marked)) context "integer tag requires a whole number")

parseNumber :: YamlSourceOptions -> [PathPiece] -> Libyaml.MarkedEvent -> Text -> Either YamlSourceError Scientific
parseNumber options context marked value =
  first
    (const (yamlError options YamlInvalidScalar (Just (startMark marked)) context "invalid or non-finite numeric scalar"))
    (parseYamlNumber value)

parseYamlNumber :: Text -> Either String Scientific
parseYamlNumber = Attoparsec.parseOnly (yamlNumberParser <* Attoparsec.endOfInput)

yamlNumberParser :: Attoparsec.Parser Scientific
yamlNumberParser =
  (fromInteger <$> ("0x" *> Attoparsec.hexadecimal))
    <|> (fromInteger <$> ("0o" *> octal))
    <|> Attoparsec.scientific
  where
    octal = Text.foldl' step 0 <$> Attoparsec.takeWhile1 isOctalDigit
    isOctalDigit character = character >= '0' && character <= '7'
    step accumulator character = accumulator * 8 + fromIntegral (ord character - ord '0')

yamlBoolean :: Text -> Maybe Bool
yamlBoolean value = case Text.toCaseFold value of
  "y" -> Just True
  "yes" -> Just True
  "on" -> Just True
  "true" -> Just True
  "n" -> Just False
  "no" -> Just False
  "off" -> Just False
  "false" -> Just False
  _ -> Nothing

isNull :: Text -> Bool
isNull value = Text.toCaseFold value == "null" || value == "~" || Text.null value

rejectAnchor :: YamlSourceOptions -> [PathPiece] -> Libyaml.MarkedEvent -> Libyaml.Anchor -> Either YamlSourceError ()
rejectAnchor options context marked = \case
  Nothing -> Right ()
  Just _ -> Left (yamlError options YamlUnsupportedFeature (Just (startMark marked)) context "YAML anchors are not supported")

rejectCollectionTag ::
  YamlSourceOptions ->
  [PathPiece] ->
  Libyaml.MarkedEvent ->
  Libyaml.Tag ->
  Libyaml.Tag ->
  Either YamlSourceError ()
rejectCollectionTag options context marked expected actual
  | actual == Libyaml.NoTag || actual == expected = Right ()
  | otherwise = Left (yamlError options YamlUnsupportedFeature (Just (startMark marked)) context "this YAML collection tag is not supported")

requireEvent ::
  YamlSourceOptions ->
  Libyaml.Event ->
  [Libyaml.MarkedEvent] ->
  Either YamlSourceError [Libyaml.MarkedEvent]
requireEvent options expected = \case
  marked : rest
    | eventOf marked == expected -> Right rest
    | otherwise -> Left (unexpectedStructure options (Just (startMark marked)) [])
  [] -> Left (unexpectedStructure options Nothing [])

locationMap :: YamlSourceOptions -> Maybe [Text] -> Libyaml.MarkedEvent -> LocationMap
locationMap options keyPath marked = case keyPath of
  Just segments@(_ : _) -> Map.singleton segments (sourceLocation options (startMark marked))
  _ -> Map.empty

locationFor :: LocationMap -> Key -> Maybe SourceLocation
locationFor locations key = Map.lookup (NonEmpty.toList (keySegments key)) locations

sourceLocation :: YamlSourceOptions -> Libyaml.YamlMark -> SourceLocation
sourceLocation options (Libyaml.YamlMark _ zeroBasedLine zeroBasedColumn) =
  SourceLocation
    { path = maybe (options ^. #name) Text.pack (options ^. #path),
      line = Just (zeroBasedLine + 1),
      column = Just (zeroBasedColumn + 1)
    }

yamlError ::
  YamlSourceOptions ->
  YamlErrorCategory ->
  Maybe Libyaml.YamlMark ->
  [PathPiece] ->
  Text ->
  YamlSourceError
yamlError options category mark context message =
  YamlSourceError
    { category,
      name = options ^. #name,
      path = options ^. #path,
      line = oneBasedLine <$> mark,
      column = oneBasedColumn <$> mark,
      context = renderContext context,
      message
    }

unexpectedStructure :: YamlSourceOptions -> Maybe Libyaml.YamlMark -> [PathPiece] -> YamlSourceError
unexpectedStructure options mark context =
  yamlError options YamlSyntaxError mark context "unexpected YAML event sequence"

renderContext :: [PathPiece] -> Text
renderContext = foldl renderPiece "$"
  where
    renderPiece rendered (MappingKey key) = rendered <> "." <> key
    renderPiece rendered (SequenceIndex position) = rendered <> "[" <> Text.pack (show position) <> "]"

eventOf :: Libyaml.MarkedEvent -> Libyaml.Event
eventOf (Libyaml.MarkedEvent event _ _) = event

startMark :: Libyaml.MarkedEvent -> Libyaml.YamlMark
startMark (Libyaml.MarkedEvent _ mark _) = mark

oneBasedLine :: Libyaml.YamlMark -> Int
oneBasedLine (Libyaml.YamlMark _ line _) = line + 1

oneBasedColumn :: Libyaml.YamlMark -> Int
oneBasedColumn (Libyaml.YamlMark _ _ column) = column + 1
