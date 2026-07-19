# ADR 0006: Bound Dhall evaluation to observable import policies

Status: Accepted

Date: 2026-07-18


## Context

Settei needs typed Dhall input without moving merge or redaction semantics out of the core.
The registered `dhall-lang/dhall-haskell` source provides `dhall` 1.42.3 and `dhall-json`
1.7.12. `Dhall.Import.Status` exposes the visited graph, successful cache, and replaceable
remote fetches, but it does not expose a maintained interception hook for local-file or
environment reads. `IgnoreSemanticCache` also leaves a separate semi-semantic cache active,
so current-run status alone cannot always recover a complete transitive closure.

Unrestricted Dhall evaluation can read local files and process environment variables,
consult caches, and access the network. A provenance claim is only useful if the adapter
can enforce the named capability policy before access and substantiate the import set it
reports. Normalization also prevents generally truthful attribution of each final leaf to
one imported expression.

The Hackage revision of `dhall-json` 1.7.12 retains older Aeson, bytestring, and text upper
bounds than the source-inspected monorepo copy. The registered copy widens them for the
GHC 9.12 dependency set without changing the 1.7.12 API.


## Decision

Version one exposes `NoImports` and `LocalImportsWithin FilePath`. It does not expose an
unrestricted standard-import constructor. `NoImports` calls the upstream no-import
assertion before resolution. `LocalImportsWithin` preflights every embedded import,
resolves Dhall's chained relative paths through the public import API, requires existing
local files, canonicalizes `..` and symlinks, and rejects paths outside the canonical root.
It also rejects environment, remote, missing, and alternative imports before upstream
evaluation.

Import alternatives are excluded because preflighting both branches would report or read
resources the upstream evaluator might not choose, while waiting for upstream resolution
would surrender the before-access policy guarantee. A no-alternative Dhall syntax tree is
fully traversed before normalization, so preflight can collect a cache-independent,
sorted, de-duplicated closure. Structured import records retain canonical paths,
interpretation modes, and semantic hashes.

The adapter follows the lower-level path used by `Dhall.JSON.codeToValue`: parse, resolve,
type-check, apply special-double handling, normalize, and call `dhallToJSON`. It uses
`NoConversion` so association lists remain arrays and duplicate map keys cannot disappear.
It converts the resulting Aeson value directly into core `RawValue`; rendered Dhall or JSON
text is never an intermediate. The top-level value must be a record, and record labels must
be valid Settei key segments.

Successful origins report the root, policy, complete local closure, and the explicit
precision statement that leaf-level import attribution is unavailable after normalization.
`loadDhallSourceDetailed` returns structured imports directly, while ordinary core reports
carry deterministic indexed annotations. Parse, import, type, and conversion failures use
stable adapter categories and fixed messages without source snippets or retained upstream
exceptions.

Cabal relaxes only the stale `dhall-json` ceilings for Aeson, bytestring, and text. The
GHC 9.12 Nix package set supplies the source-inspected `dhall` 1.42.3 and `dhall-json`
1.7.12 releases, but its transitive CLI and Tasty graph still selects
optparse-applicative 0.18. Reference applications require the maintained 0.19 API, so Nix
overrides Dhall and dhall-json to the existing pinned 0.19 derivation and builds affected
artifacts without the older Tasty test closure. The coherent Cabal workspace remains the
complete test authority.


## Consequences

Applications can make import capability explicit and can audit every local resource used
by a successful evaluation. No Settei test contacts the network or reads a real environment
import. Tests set `XDG_CACHE_HOME` to a process-local temporary directory, and preflight
closure collection remains correct even when the upstream semi-semantic cache is active.

The local-root policy is not an operating-system sandbox. It validates canonical paths
before evaluation, but an actor able to mutate files or symlinks concurrently could race
the preflight and upstream read. Applications must not treat a hostile writable directory
as a safe import root.

Exact leaf-to-import attribution remains unavailable. Reports name the root and closure
honestly instead. Root labels, paths, and caller annotations are trusted secret-safe
metadata; actual values remain protected by core setting sensitivity.

Association-list users receive arrays of `{ mapKey, mapValue }` records and must opt into
their own duplicate-aware map decoding. Bytes, functions, types, non-finite doubles, and
other values without a JSON representation fail conversion. Dhall record fields remain
required, so evolving schemas should separate stable input types from complete output
types and constructor-applied defaults.


## Rejected Alternatives

Publishing unrestricted standard imports was rejected because the maintained upstream API
cannot intercept every capability and recover a complete cache-independent closure at the
same time. Copying the upstream import interpreter was rejected because it would fork
security-sensitive semantics and cache behavior. Treating current-run `Status` as complete
was rejected because semi-semantic cache hits can hide transitive work.

Following import alternatives during preflight was rejected because it would overstate the
actual chosen graph and could access a branch the evaluator would skip. Fabricating one
origin file per normalized leaf was rejected because normalization does not preserve that
evidence. Default homogeneous-map conversion was rejected because duplicate association
keys could be collapsed silently. Rendering upstream exceptions was rejected because
parse and type diagnostics may echo source text before Settei knows which fields are
secret.


## Amendment 2026-07-19: positioned parse failures

Parse failures now carry an optional one-based line and column extracted structurally
from the Megaparsec error bundle, matching the YAML and KDL adapters. Positions are not
secrets; rendered snippets remain excluded, and messages remain fixed. The adapter uses
the bundle's error offset and position state directly and never renders or retains the
offending line.
