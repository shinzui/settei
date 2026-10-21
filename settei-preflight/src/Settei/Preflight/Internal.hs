-- | Private implementation and injectable IO boundary. Raw inputs deliberately lack Show.
module Settei.Preflight.Internal where

import Control.Concurrent (forkFinally, killThread, newChan, newEmptyMVar, putMVar, readChan, readMVar, writeChan)
import Control.Exception (IOException, bracket, fromException, throwIO, try)
import Control.Monad (forM_, unless, void, when)
import Data.Aeson qualified as A
import Data.Aeson.Encoding qualified as E
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Generics.Labels ()
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (find, sortOn)
import Data.List.NonEmpty qualified as NE
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.Encoding.Error (lenientDecode)
import Settei (Sensitivity (..))
import Settei.Env (EnvName (..))
import Settei.Prelude
import System.Directory qualified as D
import System.Environment qualified as Env
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO qualified as IO
import System.IO.Temp (withSystemTempDirectory)
import System.Process qualified as P
import System.Timeout (timeout)

newtype RoleLabel = RoleLabel Text deriving stock (Generic, Eq, Show)

newtype FileName = FileName Text deriving stock (Generic, Eq, Ord, Show)

data ArgumentPart = LiteralPart !Text | FilePart !FileName | DirectoryPart !FileName deriving stock (Generic, Eq)

newtype Argument = Argument [ArgumentPart] deriving stock (Generic, Eq)

literalArgument :: Text -> Argument
literalArgument t = Argument [LiteralPart t]

fileArgument :: FileName -> Argument
fileArgument f = Argument [FilePart f]

data CheckCommand = CheckCommand {executable :: !FilePath, arguments :: ![Argument]} deriving stock (Generic, Eq)

data ProposedValue = SuppliedValue !Sensitivity !Text | SyntheticValue !Sensitivity !Text !Text | UnresolvedValue !Text | UnavailableSecret !Text deriving stock (Generic, Eq)

data ProposedFile = ProposedFile {name :: !FileName, content :: !ProposedValue} deriving stock (Generic, Eq)

data ProposedInputs = ProposedInputs {environment :: ![(EnvName, ProposedValue)], files :: ![ProposedFile], inherited :: ![EnvName], notes :: ![Text]} deriving stock (Generic, Eq)

defaultInherited :: [EnvName]
defaultInherited = fmap EnvName ["PATH", "LANG", "LC_ALL", "LC_CTYPE"]

emptyProposedInputs :: ProposedInputs
emptyProposedInputs = ProposedInputs [] [] defaultInherited []

data ExitCodeMapping = ExitCodeMapping {accepted :: !Int, usage :: ![Int], sourceFailure :: ![Int], rejected :: ![Int]} deriving stock (Generic, Eq, Show)

defaultExitCodes :: ExitCodeMapping
defaultExitCodes = ExitCodeMapping 0 [2] [3] [4]

data PreflightOptions = PreflightOptions {timeoutSeconds :: !Int, exitCodes :: !ExitCodeMapping} deriving stock (Generic, Eq, Show)

defaultPreflightOptions :: PreflightOptions
defaultPreflightOptions = PreflightOptions 60 defaultExitCodes

data InputRef = EnvironmentInput !EnvName | FileInput !FileName | ExtractionNote !Int deriving stock (Generic, Eq, Show)

data PreflightProblem
  = InvalidEnvironmentName !EnvName
  | DuplicateEnvironmentName !EnvName
  | InvalidEnvironmentValue !EnvName
  | InvalidFileName !FileName
  | DuplicateFileName !FileName
  | FilePathConflict !FileName !FileName
  | UnknownFileReference !Int !FileName
  | SecretInArgument !Int !InputRef
  | InvalidInheritedName !EnvName
  | InheritedNameProposed !EnvName
  | DuplicateInheritedName !EnvName
  | InvalidExecutable
  | InvalidArgument !Int
  | SecretInExecutable !InputRef
  | InvalidTimeout
  | InvalidExitCodeMapping
  | EmptyRoleLabel
  deriving stock (Generic, Eq, Show)

data CommandSummary = CommandSummary {executable :: !FilePath, arguments :: ![Text]} deriving stock (Generic, Eq, Show)

data InputSummary = InputSummary {input :: !InputRef, classification :: !Classification, passed :: !Bool} deriving stock (Generic, Eq, Show)

data Classification = SuppliedPublic | SuppliedSecret | SyntheticPublic | SyntheticSecret | Unresolved | UnavailableSecretInput deriving stock (Generic, Eq, Show)

data Outcome = Accepted | Rejected !RejectionCategory !Int | NotRun !NotRunReason deriving stock (Generic, Eq, Show)

data RejectionCategory = UsageError | SourceFailure | ConfigurationRejected | UnknownExitCode deriving stock (Generic, Eq, Show)

data NotRunReason = RequestInvalid !(NonEmpty PreflightProblem) | ExecutableNotFound !FilePath | SpawnFailed !Text | MaterializationFailed !Text | CaptureFailed !Text | CleanupFailed !Text | TimedOut !Int deriving stock (Generic, Eq, Show)

data Coverage = CompleteCoverage | PartialCoverage !(NonEmpty Limitation) deriving stock (Generic, Eq, Show)

data Limitation = Limitation {input :: !InputRef, kind :: !LimitationKind, reason :: !Text} deriving stock (Generic, Eq, Show)

data LimitationKind = SyntheticStandIn | NotYetResolved | SecretUnavailable | ExtractionIncomplete deriving stock (Generic, Eq, Show)

data Verdict = Pass | Inconclusive | Fail deriving stock (Generic, Eq, Show)

data Execution = Execution {exitCode :: !(Maybe Int), timedOut :: !Bool, standardOutput :: !Text, standardError :: !Text} deriving stock (Generic, Eq, Show)

-- Private captured bytes decoded as text, before redaction; deliberately no Show.
data CapturedExecution = CapturedExecution !(Maybe Int) !Bool !Text !Text

data PreflightReport = PreflightReport
  {role :: !RoleLabel, command :: !CommandSummary, inputs :: ![InputSummary], inherited :: ![(EnvName, Bool)], notes :: ![Text], outcome :: !Outcome, coverage :: !Coverage, verdict :: !Verdict, execution :: !(Maybe Execution)}
  deriving stock (Generic, Eq, Show)

validEnvironmentName :: EnvName -> Bool
validEnvironmentName (EnvName t) = case T.uncons t of
  Nothing -> False
  Just (c, rest) -> initial c && T.all (\x -> initial x || (isDigit x && x <= '9')) rest
  where
    initial c = isAsciiLower c || isAsciiUpper c || c == '_'

validFileName :: FileName -> Bool
validFileName (FileName t) = not (T.null t) && not (T.any (`elem` ['\0', '\\']) t) && all (\s -> s /= "" && s /= "." && s /= "..") (T.splitOn "/" t)

fileText :: FileName -> Text
fileText (FileName t) = t

envText :: EnvName -> Text
envText (EnvName t) = t

refText :: InputRef -> Text
refText = \case EnvironmentInput n -> envText n; FileInput f -> "file " <> fileText f; ExtractionNote n -> "extraction note " <> tshow n

entries :: ProposedInputs -> [(InputRef, ProposedValue)]
entries p = [(EnvironmentInput n, v) | (n, v) <- p ^. #environment] <> [(FileInput (f ^. #name), f ^. #content) | f <- p ^. #files]

valueText :: ProposedValue -> Maybe Text
valueText = \case SuppliedValue _ v -> Just v; SyntheticValue _ v _ -> Just v; _ -> Nothing

secretValues :: ProposedInputs -> [(Text, Text)]
secretValues p =
  sortOn
    (negate . T.length . fst)
    [(v, marker n ref) | (n, (ref, pv)) <- zip [0 :: Int ..] (entries p), Just v <- [secret pv], not (T.null v)]
  where
    secret = \case SuppliedValue Secret v -> Just v; SyntheticValue Secret v _ -> Just v; _ -> Nothing
    allSecrets = [v | (_, pv) <- entries p, Just v <- [secret pv], not (T.null v)]
    marker n ref = "[redacted:" <> (if any (`T.isInfixOf` refText ref) allSecrets then "input " <> tshow n else refText ref) <> "]"

-- | Match original text once; never rescan inserted markers, even for overlapping secrets.
redact :: [(Text, Text)] -> Text -> Text
redact secrets = T.concat . go
  where
    go t | T.null t = []
    go t = case find (\(s, _) -> s `T.isPrefixOf` t) secrets of
      Just (s, m) -> m : go (T.drop (T.length s) t)
      Nothing -> T.take 1 t : go (T.drop 1 t)

mapRef :: (Text -> Text) -> InputRef -> InputRef
mapRef f = \case EnvironmentInput n -> EnvironmentInput (EnvName (f (envText n))); FileInput n -> FileInput (FileName (f (fileText n))); ExtractionNote n -> ExtractionNote n

mapProblem :: (Text -> Text) -> PreflightProblem -> PreflightProblem
mapProblem f = \case
  InvalidEnvironmentName n -> InvalidEnvironmentName (en n)
  DuplicateEnvironmentName n -> DuplicateEnvironmentName (en n)
  InvalidEnvironmentValue n -> InvalidEnvironmentValue (en n)
  InvalidFileName n -> InvalidFileName (fn n)
  DuplicateFileName n -> DuplicateFileName (fn n)
  FilePathConflict a b -> FilePathConflict (fn a) (fn b)
  UnknownFileReference n a -> UnknownFileReference n (fn a)
  SecretInArgument n a -> SecretInArgument n (mapRef f a)
  InvalidInheritedName n -> InvalidInheritedName (en n)
  InheritedNameProposed n -> InheritedNameProposed (en n)
  DuplicateInheritedName n -> DuplicateInheritedName (en n)
  SecretInExecutable a -> SecretInExecutable (mapRef f a)
  a -> a
  where
    en = EnvName . f . envText; fn = FileName . f . fileText

validatePreflight :: PreflightOptions -> RoleLabel -> CheckCommand -> ProposedInputs -> Either (NonEmpty PreflightProblem) ()
validatePreflight opts role cmd p = case validatePreflightRaw opts role cmd p of
  Left ps -> Left (fmap (mapProblem (redact (secretValues p))) ps)
  Right () -> Right ()

validatePreflightRaw :: PreflightOptions -> RoleLabel -> CheckCommand -> ProposedInputs -> Either (NonEmpty PreflightProblem) ()
validatePreflightRaw opts (RoleLabel label) cmd p = maybe (Right ()) Left (NE.nonEmpty problems)
  where
    es = p ^. #environment
    fs = fmap (view #name) (p ^. #files)
    ins = p ^. #inherited
    problems =
      [EmptyRoleLabel | T.null (T.strip label)]
        <> [InvalidExecutable | null (cmd ^. #executable) || '\0' `elem` (cmd ^. #executable)]
        <> [InvalidTimeout | opts ^. #timeoutSeconds <= 0 || opts ^. #timeoutSeconds > maxBound `div` 1000000]
        <> [InvalidExitCodeMapping | not (validExitCodes (opts ^. #exitCodes))]
        <> concat [[InvalidEnvironmentName n | not (validEnvironmentName n)] <> [DuplicateEnvironmentName n | n `elem` take i (fmap fst es)] <> [InvalidEnvironmentValue n | maybe False (T.any (== '\0')) (valueText v)] | (i, (n, v)) <- zip [0 ..] es]
        <> concat [[InvalidFileName f | not (validFileName f)] <> [DuplicateFileName f | f `elem` take i fs] <> [FilePathConflict a f | a <- take i fs, parent a f || parent f a] | (i, f) <- zip [0 ..] fs]
        <> concat [[InvalidInheritedName n | not (validEnvironmentName n)] <> [DuplicateInheritedName n | n `elem` take i ins] <> [InheritedNameProposed n | n `elem` fmap fst es] | (i, n) <- zip [0 ..] ins]
        <> concat [[InvalidArgument i | T.any (== '\0') (summaryArgument a)] <> [UnknownFileReference i f | part <- argumentParts a, f <- case part of FilePart n -> [n | n `notElem` fs]; DirectoryPart n -> [n | not (validFileName n) || not (any (parent n) fs)]; _ -> []] | (i, a) <- zip [0 ..] (cmd ^. #arguments)]
        <> secretCommandProblems p (cmd ^. #executable) (fmap summaryArgument (cmd ^. #arguments))
    argumentParts (Argument ps) = ps
    parent a b = (fileText a <> "/") `T.isPrefixOf` fileText b

validExitCodes :: ExitCodeMapping -> Bool
validExitCodes m = all (\n -> n >= 0 && n <= 255) codes && length codes == length (unique codes)
  where
    codes = [m ^. #accepted] <> m ^. #usage <> m ^. #sourceFailure <> m ^. #rejected

unique :: (Eq a) => [a] -> [a]
unique = foldl (\xs x -> if x `elem` xs then xs else xs <> [x]) []

summaryArgument :: Argument -> Text
summaryArgument (Argument ps) = foldMap (\case LiteralPart t -> t; FilePart f -> "{file:" <> fileText f <> "}"; DirectoryPart f -> "{dir:" <> fileText f <> "}") ps

secretCommandProblems :: ProposedInputs -> FilePath -> [Text] -> [PreflightProblem]
secretCommandProblems p exe args = concatMap check (entries p)
  where
    check (ref, v) = case v of
      SuppliedValue Secret t -> matches ref t
      SyntheticValue Secret t _ -> matches ref t
      _ -> []
    matches _ t | T.null t = []
    matches ref t = [SecretInExecutable ref | t `T.isInfixOf` T.pack exe] <> [SecretInArgument i ref | (i, a) <- zip [0 ..] args, t `T.isInfixOf` a]

-- | Private operations make failures deterministic to test without weakening the public API.
data RunOperations = RunOperations
  { materializeInputs :: !(FilePath -> ProposedInputs -> CheckCommand -> IO ()),
    captureOutput :: !(IO.Handle -> IO BS.ByteString),
    removeInputs :: !(FilePath -> IO ()),
    createCheckProcess :: !(P.CreateProcess -> IO (Maybe IO.Handle, Maybe IO.Handle, Maybe IO.Handle, P.ProcessHandle))
  }
  deriving stock (Generic)

defaultRunOperations :: RunOperations
defaultRunOperations = RunOperations materialize (\h -> BS.hGetSome h 32768) D.removePathForcibly P.createProcess

materialize :: FilePath -> ProposedInputs -> CheckCommand -> IO ()
materialize root p cmd = do
  forM_ (p ^. #files) $ \f -> case valueText (f ^. #content) of
    Nothing -> pure ()
    Just v -> do
      let path = root </> T.unpack (fileText (f ^. #name))
      D.createDirectoryIfMissing True (takeDirectory path)
      BS.writeFile path (TE.encodeUtf8 v)
  mapM_ (\(Argument ps) -> mapM_ (\case DirectoryPart n -> D.createDirectoryIfMissing True (root </> T.unpack (fileText n)); _ -> pure ()) ps) (cmd ^. #arguments)

materializedArguments :: FilePath -> CheckCommand -> [Text]
materializedArguments root cmd = fmap (\(Argument ps) -> foldMap (\case LiteralPart t -> t; FilePart f -> path f; DirectoryPart f -> path f) ps) (cmd ^. #arguments)
  where
    path f = T.pack (root </> T.unpack (fileText f))

tryIO :: IO a -> IO (Either IOException a)
tryIO = try

runPreflight :: PreflightOptions -> RoleLabel -> CheckCommand -> ProposedInputs -> IO PreflightReport
runPreflight = runPreflightWith defaultRunOperations

runPreflightWith :: RunOperations -> PreflightOptions -> RoleLabel -> CheckCommand -> ProposedInputs -> IO PreflightReport
runPreflightWith ops opts label cmd p = do
  ambient <- Env.getEnvironment
  let inheritedValues = [(n, lookup (T.unpack (envText n)) ambient) | n <- p ^. #inherited]
      childEnv = [(T.unpack (envText n), v) | (n, Just v) <- inheritedValues] <> [(T.unpack (envText n), T.unpack v) | (n, pv) <- p ^. #environment, Just v <- [valueText pv]]
      finish exe started result = pure (makeReport opts label exe (cmd ^. #arguments) p (fmap (\(n, v) -> (n, maybe False (const True) v)) inheritedValues) started result)
  case validatePreflightRaw opts label cmd p of
    Left problems -> finish (cmd ^. #executable) False (Left (RequestInvalid problems), Nothing)
    Right () -> do
      resolved <-
        tryIO $
          if '/' `elem` (cmd ^. #executable)
            then do path <- D.makeAbsolute (cmd ^. #executable); exists <- D.doesFileExist path; pure (if exists then Just path else Nothing)
            else D.findExecutable (cmd ^. #executable) >>= traverse D.makeAbsolute
      case resolved of
        Left _ -> finish (cmd ^. #executable) False (Left (SpawnFailed "executable lookup failed"), Nothing)
        Right Nothing -> finish (cmd ^. #executable) False (Left (ExecutableNotFound (cmd ^. #executable)), Nothing)
        Right (Just exe) -> do
          attempted <- tryIO $ withSystemTempDirectory "settei-preflight" $ \root -> do
            written <- tryIO ((ops ^. #materializeInputs) root p cmd)
            result <- case written of
              Left _ -> pure (False, (Left (MaterializationFailed "input files could not be written"), Nothing))
              Right () -> case NE.nonEmpty (secretCommandProblems p exe (materializedArguments root cmd)) of
                Just ps -> pure (False, (Left (RequestInvalid ps), Nothing))
                Nothing -> execute ops opts root exe (materializedArguments root cmd) childEnv
            removed <- tryIO $ do
              (ops ^. #removeInputs) root
              remains <- D.doesPathExist root
              when remains (ioError (userError "cleanup incomplete"))
            pure $ case removed of
              Left _ -> (fst result, (Left (CleanupFailed "temporary input directory could not be removed"), snd (snd result)))
              Right () -> result
          case attempted of
            Left _ -> finish exe False (Left (MaterializationFailed "temporary input directory could not be created"), Nothing)
            Right (started, result) -> finish exe started result

-- Reader scopes are INSIDE the process bracket: cancellation joins before hClose.
execute :: RunOperations -> PreflightOptions -> FilePath -> FilePath -> [Text] -> [(String, String)] -> IO (Bool, (Either NotRunReason Int, Maybe CapturedExecution))
execute ops opts root exe args environmentValues = do
  out <- newIORef []
  err <- newIORef []
  spawned <- newIORef False
  events <- newChan
  let reader h buffer = do
        chunk <- (ops ^. #captureOutput) h
        unless (BS.null chunk) (modifyIORef' buffer (chunk :) >> reader h buffer)
      scoped action continuation =
        bracket
          ( do
              done <- newEmptyMVar
              tid <- forkFinally action (\result -> putMVar done () >> writeChan events result)
              pure (tid, done)
          )
          (\(tid, done) -> killThread tid >> void (readMVar done))
          (const continuation)
      collect 0 code = pure code
      collect remaining code =
        readChan events >>= \case
          Right found -> collect (remaining - 1 :: Int) (maybe code id found)
          Left e -> case fromException e of
            Just ioe -> throwIO (ioe :: IOException)
            Nothing -> throwIO e
      process = (P.proc exe (fmap T.unpack args)) {P.cwd = Just root, P.env = Just environmentValues, P.std_in = P.CreatePipe, P.std_out = P.CreatePipe, P.std_err = P.CreatePipe}
  result <- tryIO $ bracket ((ops ^. #createCheckProcess) process) P.cleanupProcess $ \(mi, mo, me, ph) -> do
    modifyIORef' spawned (const True)
    case (mi, mo, me) of
      (Just hi, Just ho, Just he) -> do
        mapM_ (`IO.hSetBinaryMode` True) [hi, ho, he]
        IO.hClose hi
        scoped (reader ho out >> pure Nothing) $
          scoped (reader he err >> pure Nothing) $
            scoped (Just . exitInt <$> P.waitForProcess ph) $
              timeout (opts ^. #timeoutSeconds * 1000000) (tryIO (collect 3 0))
      _ -> ioError (userError "missing pipes")
  didSpawn <- readIORef spawned
  stdout <- TE.decodeUtf8With lenientDecode . BS.concat . reverse <$> readIORef out
  stderr <- TE.decodeUtf8With lenientDecode . BS.concat . reverse <$> readIORef err
  let outcomeValue = case result of
        Left _ -> Left (if didSpawn then CaptureFailed "process output could not be captured" else SpawnFailed "process could not be started")
        Right Nothing -> Left (TimedOut (opts ^. #timeoutSeconds))
        Right (Just (Left _)) -> Left (CaptureFailed "process output could not be captured")
        Right (Just (Right ec)) -> Right ec
      executionValue = if didSpawn then Just (CapturedExecution (either (const Nothing) Just outcomeValue) (case outcomeValue of Left (TimedOut _) -> True; _ -> False) stdout stderr) else Nothing
  pure (didSpawn, (outcomeValue, executionValue))
  where
    exitInt ExitSuccess = 0
    exitInt (ExitFailure n) = n

makeReport :: PreflightOptions -> RoleLabel -> FilePath -> [Argument] -> ProposedInputs -> [(EnvName, Bool)] -> Bool -> (Either NotRunReason Int, Maybe CapturedExecution) -> PreflightReport
makeReport opts (RoleLabel label) exe args p inheritedValues started (result, ex) =
  PreflightReport (RoleLabel (safe label)) (CommandSummary (T.unpack (safe (T.pack exe))) (fmap (safe . summaryArgument) args)) summaries (fmap (\(n, b) -> (EnvName (safe (envText n)), b)) inheritedValues) (fmap safe (p ^. #notes)) outcomeValue coverageValue verdictValue executionValue
  where
    safe = redact (secretValues p)
    sorted = sortOn (\(r, _) -> case r of EnvironmentInput n -> (0 :: Int, envText n); FileInput n -> (1, fileText n); ExtractionNote n -> (2, tshow n)) (entries p)
    classify = \case SuppliedValue Public _ -> SuppliedPublic; SuppliedValue Secret _ -> SuppliedSecret; SyntheticValue Public _ _ -> SyntheticPublic; SyntheticValue Secret _ _ -> SyntheticSecret; UnresolvedValue _ -> Unresolved; UnavailableSecret _ -> UnavailableSecretInput
    summaries = [InputSummary (mapRef safe r) (classify v) (started && maybe False (const True) (valueText v)) | (r, v) <- sorted]
    limits =
      [Limitation (mapRef safe r) k (safe reason) | (r, v) <- sorted, (k, reason) <- case v of SyntheticValue _ _ why -> [(SyntheticStandIn, why)]; UnresolvedValue why -> [(NotYetResolved, why)]; UnavailableSecret why -> [(SecretUnavailable, why)]; _ -> []]
        <> [Limitation (ExtractionNote n) ExtractionIncomplete (safe note) | (n, note) <- zip [0 ..] (p ^. #notes)]
    coverageValue = maybe CompleteCoverage PartialCoverage (NE.nonEmpty limits)
    outcomeValue = either (NotRun . sanitizeNotRun safe) (classifyExit (opts ^. #exitCodes)) result
    verdictValue = case outcomeValue of Accepted -> if null limits then Pass else Inconclusive; _ -> Fail
    executionValue = fmap (\(CapturedExecution ec timed stdout stderr) -> Execution ec timed (safe stdout) (safe stderr)) ex

classifyExit :: ExitCodeMapping -> Int -> Outcome
classifyExit m n | n == m ^. #accepted = Accepted
classifyExit m n = Rejected (if n `elem` m ^. #usage then UsageError else if n `elem` m ^. #sourceFailure then SourceFailure else if n `elem` m ^. #rejected then ConfigurationRejected else UnknownExitCode) n

sanitizeNotRun :: (Text -> Text) -> NotRunReason -> NotRunReason
sanitizeNotRun f = \case
  RequestInvalid ps -> RequestInvalid (fmap (mapProblem f) ps)
  ExecutableNotFound p -> ExecutableNotFound (T.unpack (f (T.pack p)))
  SpawnFailed t -> SpawnFailed (f t)
  MaterializationFailed t -> MaterializationFailed (f t)
  CaptureFailed t -> CaptureFailed (f t)
  CleanupFailed t -> CleanupFailed (f t)
  TimedOut n -> TimedOut n

tshow :: (Show a) => a -> Text
tshow = T.pack . show

problemFields :: PreflightProblem -> (Text, Maybe Text, Maybe Int, Maybe Text)
problemFields = \case
  InvalidEnvironmentName n -> named "invalid-environment-name" (envText n)
  DuplicateEnvironmentName n -> named "duplicate-environment-name" (envText n)
  InvalidEnvironmentValue n -> named "invalid-environment-value" (envText n)
  InvalidFileName n -> named "invalid-file-name" (fileText n)
  DuplicateFileName n -> named "duplicate-file-name" (fileText n)
  FilePathConflict a b -> ("file-path-conflict", Just (fileText a), Nothing, Just (fileText b))
  UnknownFileReference i n -> ("unknown-file-reference", Just (fileText n), Just i, Nothing)
  SecretInArgument i r -> ("secret-in-argument", Just (refText r), Just i, Nothing)
  InvalidInheritedName n -> named "invalid-inherited-name" (envText n)
  InheritedNameProposed n -> named "inherited-name-proposed" (envText n)
  DuplicateInheritedName n -> named "duplicate-inherited-name" (envText n)
  SecretInExecutable r -> named "secret-in-executable" (refText r)
  InvalidExecutable -> bare "invalid-executable"
  InvalidArgument i -> ("invalid-argument", Nothing, Just i, Nothing)
  InvalidTimeout -> bare "invalid-timeout"
  InvalidExitCodeMapping -> bare "invalid-exit-code-mapping"
  EmptyRoleLabel -> bare "empty-role-label"
  where
    named k n = (k, Just n, Nothing, Nothing); bare k = (k, Nothing, Nothing, Nothing)

renderPreflightProblemText :: PreflightProblem -> Text
renderPreflightProblemText p = let (k, n, a, r) = problemFields p in k <> maybe "" ((": " <>) . oneLine) n <> maybe "" (\i -> " (argument " <> tshow i <> ")") a <> maybe "" ((" conflicts with " <>) . oneLine) r

-- Preserve the one-problem-per-line contract even for invalid names.
oneLine :: Text -> Text
oneLine = T.concatMap (\case '\n' -> "\\n"; '\r' -> "\\r"; '\t' -> "\\t"; '\0' -> "\\0"; c -> T.singleton c)

renderPreflightProblemsText :: NonEmpty PreflightProblem -> Text
renderPreflightProblemsText = T.unlines . fmap renderPreflightProblemText . NE.toList

verdictText :: Verdict -> Text
verdictText = \case Pass -> "pass"; Inconclusive -> "inconclusive"; Fail -> "fail"

categoryText :: RejectionCategory -> Text
categoryText = \case UsageError -> "usage"; SourceFailure -> "source-failure"; ConfigurationRejected -> "configuration-rejected"; UnknownExitCode -> "unknown-exit-code"

notRunFields :: NotRunReason -> (Text, Maybe Text, [PreflightProblem])
notRunFields = \case
  RequestInvalid ps -> ("request-invalid", Nothing, NE.toList ps)
  ExecutableNotFound p -> ("executable-not-found", Just (T.pack p), [])
  SpawnFailed t -> ("spawn-failed", Just t, [])
  MaterializationFailed t -> ("materialization-failed", Just t, [])
  CaptureFailed t -> ("capture-failed", Just t, [])
  CleanupFailed t -> ("cleanup-failed", Just t, [])
  TimedOut n -> ("timed-out", Just (tshow n <> " seconds"), [])

verdictExplanation :: PreflightReport -> Text
verdictExplanation r = case r ^. #outcome of
  Accepted -> if r ^. #verdict == Pass then "accepted with complete coverage" else "accepted with partial coverage; not a deployment validation"
  Rejected c n -> (case c of UsageError -> "usage error"; SourceFailure -> "source loading failed"; ConfigurationRejected -> "configuration rejected"; UnknownExitCode -> "unknown exit code") <> ", exit " <> tshow n
  NotRun why -> let (k, d, ps) = notRunFields why in "not run: " <> T.replace "-" " " k <> maybe "" (": " <>) d <> (if null ps then "" else ": " <> T.intercalate "; " (fmap renderPreflightProblemText ps))

classificationText :: Classification -> Text
classificationText = \case SuppliedPublic -> "supplied-public"; SuppliedSecret -> "supplied-secret"; SyntheticPublic -> "synthetic-public"; SyntheticSecret -> "synthetic-secret"; Unresolved -> "unresolved"; UnavailableSecretInput -> "unavailable-secret"

limitationText :: LimitationKind -> Text
limitationText = \case SyntheticStandIn -> "synthetic-stand-in"; NotYetResolved -> "not-yet-resolved"; SecretUnavailable -> "secret-unavailable"; ExtractionIncomplete -> "extraction-incomplete"

limitations :: Coverage -> [Limitation]
limitations = \case CompleteCoverage -> []; PartialCoverage ls -> NE.toList ls

renderPreflightReportText :: PreflightReport -> Text
renderPreflightReportText r =
  T.unlines $
    ["preflight " <> label <> ": " <> verdictText (r ^. #verdict) <> " (" <> verdictExplanation r <> ")", "coverage: " <> (case r ^. #coverage of CompleteCoverage -> "complete"; _ -> "partial")]
      <> ["  " <> refText (l ^. #input) <> ": " <> (case l ^. #kind of SyntheticStandIn -> "synthetic stand-in"; k -> T.replace "-" " " (limitationText k)) <> " (" <> l ^. #reason <> ")" | l <- limitations (r ^. #coverage)]
      <> (if null (r ^. #inputs) then ["inputs: (none)"] else "inputs:" : ["  " <> refText (s ^. #input) <> ": " <> T.replace "-" " " (classificationText (s ^. #classification)) <> (if s ^. #passed then "" else " (omitted)") | s <- r ^. #inputs])
      <> ["inherited: " <> (if null (r ^. #inherited) then "(none)" else T.intercalate ", " [envText n <> if present then " (present)" else " (absent)" | (n, present) <- r ^. #inherited]), "command: " <> T.unwords (T.pack (r ^. #command . #executable) : r ^. #command . #arguments)]
      <> (if null (r ^. #notes) then [] else "notes:" : fmap ("  " <>) (r ^. #notes))
      <> block "stdout" (maybe "" (view #standardOutput) (r ^. #execution))
      <> block "stderr" (maybe "" (view #standardError) (r ^. #execution))
  where
    RoleLabel label = r ^. #role
    block name t = (name <> ":") : if T.null t then ["  (empty)"] else fmap ("  " <>) (T.lines t)

encodingText :: A.Encoding -> Text
encodingText = TE.decodeUtf8 . BL.toStrict . E.encodingToLazyByteString

obj :: [(A.Key, A.Encoding)] -> A.Encoding
obj = E.pairs . foldMap (uncurry E.pair)

json :: (A.ToJSON a) => a -> A.Encoding
json = A.toEncoding

refFields :: InputRef -> [(A.Key, A.Encoding)]
refFields ref = [("channel", json channel), ("name", json name)]
  where
    (channel, name) = case ref of EnvironmentInput n -> ("environment" :: Text, envText n); FileInput f -> ("file", fileText f); ExtractionNote n -> ("extraction", tshow n)

renderPreflightReportJson :: PreflightReport -> Text
renderPreflightReportJson r =
  encodingText $
    obj
      [("schemaVersion", json (1 :: Int)), ("type", json ("settei.preflight" :: Text)), ("role", json label), ("verdict", json (verdictText (r ^. #verdict))), ("verdictExplanation", json (verdictExplanation r)), ("outcome", outcomeJson (r ^. #outcome)), ("coverage", obj [("kind", json (case r ^. #coverage of CompleteCoverage -> "complete" :: Text; _ -> "partial")), ("limitations", E.list limitJson (limitations (r ^. #coverage)))]), ("inputs", E.list inputJson (r ^. #inputs)), ("inherited", E.list (\(n, b) -> obj [("name", json (envText n)), ("present", json b)]) (r ^. #inherited)), ("notes", json (r ^. #notes)), ("command", obj [("executable", json (r ^. #command . #executable)), ("arguments", json (r ^. #command . #arguments))]), ("execution", maybe E.null_ executionJson (r ^. #execution))]
  where
    RoleLabel label = r ^. #role
    inputJson s = obj (refFields (s ^. #input) <> [("classification", json (classificationText (s ^. #classification))), ("passed", json (s ^. #passed))])
    limitJson l = obj (refFields (l ^. #input) <> [("limitation", json (limitationText (l ^. #kind))), ("reason", json (l ^. #reason))])
    executionJson e = obj [("exitCode", json (e ^. #exitCode)), ("timedOut", json (e ^. #timedOut)), ("stdout", json (e ^. #standardOutput)), ("stderr", json (e ^. #standardError))]
    outcomeJson = \case
      Accepted -> obj [("kind", json ("accepted" :: Text))]
      Rejected c n -> obj [("kind", json ("rejected" :: Text)), ("category", json (categoryText c)), ("exitCode", json n)]
      NotRun why -> let (k, d, ps) = notRunFields why in obj [("kind", json ("not-run" :: Text)), ("reason", json k), ("detail", json d), ("problems", E.list problemJson ps)]
    problemJson p = let (k, n, a, related) = problemFields p in obj ([("kind", json k), ("name", json n), ("argument", json a)] <> maybe [] (\v -> [("relatedName", json v)]) related)
