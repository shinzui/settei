{-# LANGUAGE ImportQualifiedPost #-}

-- |
-- Module: Settei.Kdl
-- Description: Canonical, span-preserving KDL v2 sources for Settei.
module Settei.Kdl
  ( KdlErrorCategory (..),
    KdlSourceError,
    KdlSourceOptions,
    KdlSpan,
    annotateKdlSourceOptions,
    decodeKdlSource,
    fromKubernetesMountedFile,
    kdlErrorCategory,
    kdlErrorContext,
    kdlErrorMessage,
    kdlErrorName,
    kdlErrorPath,
    kdlErrorRelatedSpan,
    kdlErrorSpan,
    kdlSourceAnnotations,
    kdlSourceName,
    kdlSourceOptions,
    kdlSourcePath,
    kdlSpanColumn,
    kdlSpanEndColumn,
    kdlSpanEndLine,
    kdlSpanLine,
    readKdlSource,
    withKdlSourcePath,
  )
where

import Control.Exception (IOException, displayException, try)
import Control.Monad (foldM, when)
import Data.Bifunctor (first)
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Data.Text.Read qualified as TextRead
import KDL.Parser qualified as KDLParser
import KDL.Types qualified as KDL
import Settei
import Settei.Prelude

-- | Stable classes of adapter failure. No constructor retains a raw KDL value.
data KdlErrorCategory
  = KdlSyntaxError
  | KdlIoError
  | KdlDuplicateProperty
  | KdlInvalidName
  | KdlUnsupportedAnnotation
  | KdlUnsupportedValue
  | KdlMixedNodeShape
  | KdlPropertyChildCollision
  deriving stock (Generic, Eq, Ord, Show)

-- | A complete one-based KDL source span.
data KdlSpan = KdlSpan
  { line :: !Int,
    column :: !Int,
    endLine :: !Int,
    endColumn :: !Int
  }
  deriving stock (Generic, Eq, Ord, Show)

-- | A secret-safe KDL input failure.
data KdlSourceError = KdlSourceError
  { category :: !KdlErrorCategory,
    name :: !Text,
    path :: !(Maybe FilePath),
    location :: !(Maybe KdlSpan),
    relatedLocation :: !(Maybe KdlSpan),
    context :: !Text,
    message :: !Text
  }
  deriving stock (Generic, Eq, Show)

-- | How one KDL v2 document should be named and annotated in provenance.
data KdlSourceOptions = KdlSourceOptions
  { name :: !Text,
    path :: !(Maybe FilePath),
    annotations :: !(Map Text Text)
  }
  deriving stock (Generic, Eq)

type LocationMap = Map [Text] KdlSpan

-- | Start options for an in-memory KDL document.
kdlSourceOptions :: Text -> KdlSourceOptions
kdlSourceOptions name = KdlSourceOptions {name, path = Nothing, annotations = Map.empty}

-- | Attach a real or logical path to an in-memory KDL document.
withKdlSourcePath :: FilePath -> KdlSourceOptions -> KdlSourceOptions
withKdlSourcePath path options = options & #path .~ Just path

-- | Add trusted, secret-safe origin metadata.
annotateKdlSourceOptions :: Map Text Text -> KdlSourceOptions -> KdlSourceOptions
annotateKdlSourceOptions annotations options = options & #annotations %~ (annotations <>)

-- | Attach a trusted Kubernetes reference for a mounted KDL file.
--
-- This performs no cluster lookup. Setting sensitivity remains the sole redaction policy.
fromKubernetesMountedFile :: KubernetesRef -> KdlSourceOptions -> KdlSourceOptions
fromKubernetesMountedFile reference =
  annotateKdlSourceOptions (kubernetesAnnotations reference)

-- | Return the stable source name.
kdlSourceName :: KdlSourceOptions -> Text
kdlSourceName options = options ^. #name

-- | Return the optional file path.
kdlSourcePath :: KdlSourceOptions -> Maybe FilePath
kdlSourcePath options = options ^. #path

-- | Return caller-supplied, secret-safe annotations.
kdlSourceAnnotations :: KdlSourceOptions -> Map Text Text
kdlSourceAnnotations options = options ^. #annotations

-- | Return an error's stable category.
kdlErrorCategory :: KdlSourceError -> KdlErrorCategory
kdlErrorCategory problem = problem ^. #category

-- | Return the source name associated with an error.
kdlErrorName :: KdlSourceError -> Text
kdlErrorName problem = problem ^. #name

-- | Return the file path associated with an error, when known.
kdlErrorPath :: KdlSourceError -> Maybe FilePath
kdlErrorPath problem = problem ^. #path

-- | Return the smallest trustworthy primary span for an error.
kdlErrorSpan :: KdlSourceError -> Maybe KdlSpan
kdlErrorSpan problem = problem ^. #location

-- | Return a second trustworthy span for a collision, when available.
kdlErrorRelatedSpan :: KdlSourceError -> Maybe KdlSpan
kdlErrorRelatedSpan problem = problem ^. #relatedLocation

-- | Return the structural path associated with an error.
kdlErrorContext :: KdlSourceError -> Text
kdlErrorContext problem = problem ^. #context

-- | Return a concise message that never includes a raw scalar or source excerpt.
kdlErrorMessage :: KdlSourceError -> Text
kdlErrorMessage problem = problem ^. #message

-- | Return a span's one-based start line.
kdlSpanLine :: KdlSpan -> Int
kdlSpanLine value = value ^. #line

-- | Return a span's one-based start column.
kdlSpanColumn :: KdlSpan -> Int
kdlSpanColumn value = value ^. #column

-- | Return a span's one-based inclusive end line.
kdlSpanEndLine :: KdlSpan -> Int
kdlSpanEndLine value = value ^. #endLine

-- | Return a span's one-based inclusive end column.
kdlSpanEndColumn :: KdlSpan -> Int
kdlSpanEndColumn value = value ^. #endColumn

-- | Decode one KDL v2 document into a Settei file source.
--
-- Type annotations, non-finite numbers, duplicate properties, invalid key segments, and
-- ambiguous mixtures fail explicitly. The parser's rendered source excerpt is discarded
-- on syntax failure so structured errors remain safe before setting sensitivity is known.
decodeKdlSource :: KdlSourceOptions -> Text -> Either (NonEmpty KdlSourceError) Source
decodeKdlSource options input =
  first NonEmpty.singleton $ do
    document <- first (syntaxError options) (KDLParser.parseWith (parseConfig options) input)
    (root, locations) <- translateDocument options document
    pure
      ( annotateSourceAt
          (spanAnnotationsFor locations)
          ( locateSource
              (sourceLocationFor options locations)
              ( annotateSource
                  (Map.singleton "kdl.version" "2" <> options ^. #annotations)
                  (source (options ^. #name) (FileSource "KDL v2") root)
              )
          )
      )

-- | Read one file and pass it through the same strict pure translator.
--
-- The supplied file path replaces any path already present in the options.
readKdlSource :: KdlSourceOptions -> FilePath -> IO (Either (NonEmpty KdlSourceError) Source)
readKdlSource options filePath = do
  let fileOptions = withKdlSourcePath filePath options
  contents <- try @IOException (TextIO.readFile filePath)
  pure $ case contents of
    Left exception ->
      Left
        ( NonEmpty.singleton
            ( kdlError
                fileOptions
                KdlIoError
                Nothing
                Nothing
                []
                (Text.pack (displayException exception))
            )
        )
    Right input -> decodeKdlSource fileOptions input

parseConfig :: KdlSourceOptions -> KDLParser.ParseConfig
parseConfig options =
  KDLParser.ParseConfig
    { KDLParser.filepath = maybe "" id (options ^. #path),
      KDLParser.includeSpans = True
    }

syntaxError :: KdlSourceOptions -> Text -> KdlSourceError
syntaxError options rendered =
  kdlError
    options
    KdlSyntaxError
    (parseErrorLocation rendered)
    Nothing
    []
    "invalid KDL v2 syntax"

parseErrorLocation :: Text -> Maybe KdlSpan
parseErrorLocation rendered = do
  header <- listToMaybe (Text.lines rendered)
  case reverse (filter (not . Text.null) (Text.splitOn ":" header)) of
    columnText : lineText : _ -> do
      line <- parsePositiveInt lineText
      column <- parsePositiveInt columnText
      pure KdlSpan {line, column, endLine = line, endColumn = column}
    _ -> Nothing

parsePositiveInt :: Text -> Maybe Int
parsePositiveInt value = case TextRead.decimal value of
  Right (number, rest)
    | number > 0 && Text.null rest -> Just number
  _ -> Nothing

translateDocument :: KdlSourceOptions -> KDL.Document -> Either KdlSourceError (RawValue, LocationMap)
translateDocument options document =
  translateNodeList options [] (nodeListNodes document)

translateNodeList ::
  KdlSourceOptions ->
  [Text] ->
  [KDL.Node] ->
  Either KdlSourceError (RawValue, LocationMap)
translateNodeList options prefix nodes = do
  groups <- groupNodes options prefix nodes
  translated <- traverse (translateGroup options prefix) (Map.toAscList groups)
  pure
    ( RawObject (Map.fromList [(name, value) | (name, value, _) <- translated]),
      mconcat [locations | (_, _, locations) <- translated]
    )

groupNodes ::
  KdlSourceOptions ->
  [Text] ->
  [KDL.Node] ->
  Either KdlSourceError (Map Text [KDL.Node])
groupNodes options prefix = foldM addNode Map.empty
  where
    addNode groups node = do
      name <- validateIdentifier options prefix (nodeName node)
      pure
        ( groups
            & at name
            %~ \existing -> Just (maybe [node] (<> [node]) existing)
        )

translateGroup ::
  KdlSourceOptions ->
  [Text] ->
  (Text, [KDL.Node]) ->
  Either KdlSourceError (Text, RawValue, LocationMap)
translateGroup options prefix (name, nodes) = case nodes of
  [] -> pure (name, RawNull, Map.empty)
  [node] -> do
    (value, locations) <- translateNode options (prefix <> [name]) node
    pure (name, value, locations)
  firstNode : remainingNodes -> do
    values <- traverse (fmap fst . translateNode options (prefix <> [name])) (firstNode : remainingNodes)
    let groupSpan = coverSpans (nodeLocation firstNode :| fmap nodeLocation remainingNodes)
    pure
      ( name,
        RawArray values,
        Map.singleton (prefix <> [name]) groupSpan
      )

translateNode ::
  KdlSourceOptions ->
  [Text] ->
  KDL.Node ->
  Either KdlSourceError (RawValue, LocationMap)
translateNode options path node = do
  rejectNodeAnnotation options path node
  properties <- validateProperties options path (nodeEntries node)
  let arguments = [entryValue entry | entry <- nodeEntries node, entryName entry == Nothing]
      childNodes = nodeChildren node
  when (not (null arguments) && (not (Map.null properties) || not (null childNodes))) $
    Left
      ( kdlError
          options
          KdlMixedNodeShape
          (Just (nodeLocation node))
          Nothing
          path
          "positional arguments cannot be combined with properties or children"
      )
  case arguments of
    firstArgument : remainingArguments -> do
      values <- traverse (translateValue options path) (firstArgument : remainingArguments)
      let value = case values of
            [single] -> single
            many -> RawArray many
          location = coverSpans (valueLocation firstArgument :| fmap valueLocation remainingArguments)
      pure (value, Map.singleton path location)
    []
      | Map.null properties && null childNodes ->
          pure (RawNull, Map.singleton path (nodeLocation node))
      | otherwise -> translateObjectNode options path node properties childNodes

translateObjectNode ::
  KdlSourceOptions ->
  [Text] ->
  KDL.Node ->
  Map Text KDL.Entry ->
  [KDL.Node] ->
  Either KdlSourceError (RawValue, LocationMap)
translateObjectNode options path node properties childNodes = do
  childGroups <- groupNodes options path childNodes
  case firstCollision properties childGroups of
    Just (name, property, child) ->
      Left
        ( kdlError
            options
            KdlPropertyChildCollision
            (entryNameLocation property)
            (Just (identifierLocation (nodeName child)))
            (path <> [name])
            "a property and child use the same field name"
        )
    Nothing -> pure ()
  (propertyObject, propertyLocations) <- translateProperties options path properties
  (childValue, childLocations) <- translateNodeList options path childNodes
  let childObject = case childValue of
        RawObject object -> object
        _ -> Map.empty
  pure
    ( RawObject (propertyObject <> childObject),
      Map.singleton path (nodeLocation node) <> propertyLocations <> childLocations
    )

translateProperties ::
  KdlSourceOptions ->
  [Text] ->
  Map Text KDL.Entry ->
  Either KdlSourceError (Map Text RawValue, LocationMap)
translateProperties options path properties = do
  translated <-
    traverse
      ( \(name, entry) -> do
          value <- translateValue options (path <> [name]) (entryValue entry)
          pure (name, value, Map.singleton (path <> [name]) (valueLocation (entryValue entry)))
      )
      (Map.toAscList properties)
  pure
    ( Map.fromList [(name, value) | (name, value, _) <- translated],
      mconcat [locations | (_, _, locations) <- translated]
    )

validateProperties ::
  KdlSourceOptions ->
  [Text] ->
  [KDL.Entry] ->
  Either KdlSourceError (Map Text KDL.Entry)
validateProperties options path = foldM addProperty Map.empty
  where
    addProperty properties entry = case entryName entry of
      Nothing -> pure properties
      Just identifier -> do
        name <- validateIdentifier options path identifier
        case properties ^. at name of
          Just earlier ->
            Left
              ( kdlError
                  options
                  KdlDuplicateProperty
                  (Just (identifierLocation identifier))
                  (entryNameLocation earlier)
                  (path <> [name])
                  "duplicate property"
              )
          Nothing -> pure (properties & at name ?~ entry)

firstCollision :: Map Text KDL.Entry -> Map Text [KDL.Node] -> Maybe (Text, KDL.Entry, KDL.Node)
firstCollision properties childGroups =
  listToMaybe
    [ (name, property, child)
    | name <- Map.keys properties,
      Just property <- [properties ^. at name],
      Just (child : _) <- [childGroups ^. at name]
    ]

translateValue :: KdlSourceOptions -> [Text] -> KDL.Value -> Either KdlSourceError RawValue
translateValue options path value = do
  rejectValueAnnotation options path value
  case valueData value of
    KDL.String text -> Right (RawText text)
    KDL.Number number -> Right (RawNumber (toRational number))
    KDL.Bool boolean -> Right (RawBool boolean)
    KDL.Null -> Right RawNull
    KDL.Inf -> unsupported
    KDL.NegInf -> unsupported
    KDL.NaN -> unsupported
  where
    unsupported =
      Left
        ( kdlError
            options
            KdlUnsupportedValue
            (Just (valueLocation value))
            Nothing
            path
            "non-finite KDL numbers are not supported"
        )

rejectNodeAnnotation :: KdlSourceOptions -> [Text] -> KDL.Node -> Either KdlSourceError ()
rejectNodeAnnotation options path node = case nodeAnnotation node of
  Nothing -> Right ()
  Just annotation ->
    Left
      ( kdlError
          options
          KdlUnsupportedAnnotation
          (Just (annotationLocation annotation))
          Nothing
          path
          "KDL node type annotations are not supported"
      )

rejectValueAnnotation :: KdlSourceOptions -> [Text] -> KDL.Value -> Either KdlSourceError ()
rejectValueAnnotation options path value = case valueAnnotation value of
  Nothing -> Right ()
  Just annotation ->
    Left
      ( kdlError
          options
          KdlUnsupportedAnnotation
          (Just (annotationLocation annotation))
          Nothing
          path
          "KDL value type annotations are not supported"
      )

validateIdentifier ::
  KdlSourceOptions ->
  [Text] ->
  KDL.Identifier ->
  Either KdlSourceError Text
validateIdentifier options prefix identifier =
  case mkKey (NonEmpty.singleton name) of
    Right _ -> Right name
    Left _ ->
      Left
        ( kdlError
            options
            KdlInvalidName
            (Just (identifierLocation identifier))
            Nothing
            (prefix <> [name])
            "KDL names must be non-empty Settei key segments without dots"
        )
  where
    name = identifierText identifier

kdlError ::
  KdlSourceOptions ->
  KdlErrorCategory ->
  Maybe KdlSpan ->
  Maybe KdlSpan ->
  [Text] ->
  Text ->
  KdlSourceError
kdlError options category location relatedLocation context message =
  KdlSourceError
    { category,
      name = options ^. #name,
      path = options ^. #path,
      location,
      relatedLocation,
      context = renderContext context,
      message
    }

renderContext :: [Text] -> Text
renderContext = foldl (\rendered segment -> rendered <> "." <> segment) "$"

sourceLocationFor :: KdlSourceOptions -> LocationMap -> Key -> Maybe SourceLocation
sourceLocationFor options locations key = do
  found <- locations ^. at (NonEmpty.toList (keySegments key))
  pure
    SourceLocation
      { path = maybe (options ^. #name) Text.pack (options ^. #path),
        line = Just (found ^. #line),
        column = Just (found ^. #column)
      }

spanAnnotationsFor :: LocationMap -> Key -> Map Text Text
spanAnnotationsFor locations key = case locations ^. at (NonEmpty.toList (keySegments key)) of
  Nothing -> Map.empty
  Just found ->
    Map.fromList
      [ ("kdl.span.start-line", renderInt (found ^. #line)),
        ("kdl.span.start-column", renderInt (found ^. #column)),
        ("kdl.span.end-line", renderInt (found ^. #endLine)),
        ("kdl.span.end-column", renderInt (found ^. #endColumn))
      ]

renderInt :: Int -> Text
renderInt = Text.pack . show

coverSpans :: NonEmpty KdlSpan -> KdlSpan
coverSpans (firstSpan :| remaining) = foldl cover firstSpan remaining
  where
    cover start finish =
      KdlSpan
        { line = start ^. #line,
          column = start ^. #column,
          endLine = finish ^. #endLine,
          endColumn = finish ^. #endColumn
        }

nodeListNodes :: KDL.NodeList -> [KDL.Node]
nodeListNodes KDL.NodeList {KDL.nodes = nodes} = nodes

nodeAnnotation :: KDL.Node -> Maybe KDL.Ann
nodeAnnotation KDL.Node {KDL.ann = annotation} = annotation

nodeName :: KDL.Node -> KDL.Identifier
nodeName KDL.Node {KDL.name = name} = name

nodeEntries :: KDL.Node -> [KDL.Entry]
nodeEntries KDL.Node {KDL.entries = entries} = entries

nodeChildren :: KDL.Node -> [KDL.Node]
nodeChildren KDL.Node {KDL.children = childList} = maybe [] nodeListNodes childList

nodeLocation :: KDL.Node -> KdlSpan
nodeLocation KDL.Node {KDL.ext = KDL.NodeExtension {KDL.span = location}} = fromKdlSpan location

entryName :: KDL.Entry -> Maybe KDL.Identifier
entryName KDL.Entry {KDL.name = name} = name

entryNameLocation :: KDL.Entry -> Maybe KdlSpan
entryNameLocation entry = identifierLocation <$> entryName entry

entryValue :: KDL.Entry -> KDL.Value
entryValue KDL.Entry {KDL.value = value} = value

valueAnnotation :: KDL.Value -> Maybe KDL.Ann
valueAnnotation KDL.Value {KDL.ann = annotation} = annotation

valueData :: KDL.Value -> KDL.ValueData
valueData KDL.Value {KDL.data_ = value} = value

valueLocation :: KDL.Value -> KdlSpan
valueLocation KDL.Value {KDL.ext = KDL.ValueExtension {KDL.span = location}} = fromKdlSpan location

annotationLocation :: KDL.Ann -> KdlSpan
annotationLocation KDL.Ann {KDL.ext = KDL.AnnExtension {KDL.span = location}} = fromKdlSpan location

identifierText :: KDL.Identifier -> Text
identifierText KDL.Identifier {KDL.value = value} = value

identifierLocation :: KDL.Identifier -> KdlSpan
identifierLocation KDL.Identifier {KDL.ext = KDL.IdentifierExtension {KDL.span = location}} = fromKdlSpan location

fromKdlSpan :: KDL.Span -> KdlSpan
fromKdlSpan
  KDL.Span
    { KDL.startLine = line,
      KDL.startCol = column,
      KDL.endLine = endLine,
      KDL.endCol = endColumn
    } = KdlSpan {line, column, endLine, endColumn}
