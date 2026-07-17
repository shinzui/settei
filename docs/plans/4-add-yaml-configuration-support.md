---
id: 4
slug: add-yaml-configuration-support
title: "Add YAML configuration support"
kind: exec-plan
created_at: 2026-07-16T23:50:07Z
intention: intention_01kxr36cqgem8tmxjjtnq0t6ns
master_plan: "docs/masterplans/1-build-settei-as-a-provenance-aware-configuration-library-for-haskell.md"
---

# Add YAML configuration support

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture

After this plan, an application can parse a YAML document or read a YAML file into a
Settei source, place it anywhere in the application's precedence stack, and receive typed
errors and explanations that identify the file and logical key. Nested YAML mappings map
to Settei key segments, while arrays and scalars remain values for the setting decoder.
The adapter rejects ambiguous duplicate keys instead of silently choosing one.

The package is `settei-yaml`. It translates one YAML document; it does not discover files,
merge documents, resolve environment variables in YAML text, or implement application
defaults.


## Progress

- [x] (2026-07-17 08:41 PDT) Inspect the current Haskell YAML parser source and prove its duplicate-key behavior.
- [x] (2026-07-17 08:41 PDT) Add and register the `settei-yaml` package.
- [x] (2026-07-17 08:41 PDT) Translate supported YAML values into the core raw tree and origin model.
- [x] (2026-07-17 08:41 PDT) Add strict error handling, file IO, and mounted-file annotations.
- [x] (2026-07-17 08:41 PDT) Test hierarchy, precedence, locations, duplicate keys, and redaction.
- [ ] Publish the YAML format guide and limitations.


## Surprises & Discoveries

- Observation: no standalone YAML, HsYAML, or libyaml project is registered in Mori;
  `dhall-yaml` is the only package found by the initial YAML search.
  Evidence: `mori registry search yaml`, `mori registry search HsYAML`, and
  `mori registry search libyaml` returned no general YAML parser project, so the audit
  unpacked the exact Hackage releases `yaml-0.11.11.2` and `libyaml-0.1.4`.
  Impact: the characterization README records the inspected release sources, while the
  package bounds the selected parser to the compatible `libyaml` 0.1 series.

- Observation: `Data.Yaml.decodeEither'` converts pairs to an Aeson key map and discards
  the parser's duplicate-key warnings, but `Text.Libyaml.decodeMarked` exposes every event
  together with zero-based start and end marks.
  Evidence: `Data.Yaml.Internal.parseM` adds `DuplicateKey` only to a warning list before
  `M.insert`, while `decodeEither'` maps away that list. The 20-test adapter suite rejects
  duplicate block and flow mappings and reports a successful nested host at line 3,
  column 11.
  Impact: the adapter consumes marked events directly, rejects ambiguity before map
  construction, and provides trustworthy one-based locations for successful candidates.

- Observation: the marked parser is exposed as a `MonadResource` conduit even for an
  immutable strict `ByteString`.
  Evidence: `libyaml-0.1.4` defines `decodeMarked` in `ConduitM`, and `yaml-0.11.11.2`
  implements its own pure byte decoders with `unsafePerformIO` around the same resource
  runner.
  Impact: `decodeYamlSource` contains one `NOINLINE` pure wrapper around event collection;
  all file IO remains explicit in `readYamlSource`.


## Decision Log

- Decision: Require YAML mapping keys to be strings and reject duplicate keys before
  constructing a core source.
  Rationale: non-string and duplicate keys cannot be mapped to stable Settei paths without
  surprising or lossy coercion.
  Date: 2026-07-16

- Decision: Treat YAML `null` as a present raw value rather than absence.
  Rationale: only an absent mapping path means a source has no candidate; the declared
  setting decoder decides whether explicit null is valid.
  Date: 2026-07-16

- Decision: Report each successful candidate and parser error with the one-based line and
  column substantiated by the selected marked-event parser.
  Rationale: marked events retain exact node starts, so Settei can provide stronger honest
  provenance than the common Aeson-oriented YAML APIs.
  Date: 2026-07-16

- Decision: Inherit Plan 1's shared Haskell conventions and expose YAML option metadata
  through strict unprefixed labels.
  Rationale: `DuplicateRecordFields` and local generic-lens access let every adapter reuse
  `name` and `annotations` consistently without format-prefixed selectors.
  Date: 2026-07-16

- Decision: Parse with `libyaml` 0.1.4's `decodeMarked` event API instead of converting
  through `Data.Aeson.Value`.
  Rationale: event pairs permit strict duplicate detection, and marked values provide the
  successful-node provenance that the high-level map conversion discards.
  Date: 2026-07-17

- Decision: Accept exactly one top-level mapping and a strict portable YAML subset;
  reject aliases, anchors, merge keys, custom tags, non-string or dotted mapping keys,
  multiple documents, and non-finite numbers.
  Rationale: the rejected features either introduce graph semantics, hide duplicate
  precedence, cannot become Settei key segments, or cannot be represented by `RawValue`
  without loss.
  Date: 2026-07-17

- Decision: Convert libyaml's zero-based marks to one-based public locations and isolate
  the parser's resource effect behind a `NOINLINE` pure bytes boundary.
  Rationale: human-facing positions conventionally start at one, and parsing an immutable
  `ByteString` is referentially transparent even though the C binding uses resource-managed
  IO internally.
  Date: 2026-07-17


## Outcomes & Retrospective

To be filled during and after implementation. If strict duplicate detection or successful
node spans require a parser change, record the evidence and final compatibility choice in
this plan and a format ADR if the constraint is durable. Completion also requires the
package to declare the canonical package-local GHC2024 common stanza, every component to
import it, and the code to pass the shared prelude, record, deriving, lens, and
qualified-import audit.


## Context and Orientation

This plan depends on
`docs/plans/2-implement-hierarchical-resolution-provenance-and-derived-defaults.md`.
That plan supplies `RawValue`, `Source`, extensible `Origin`, hierarchical lookup,
structured errors, and redaction. Read its implementation and resolution ADR before
coding. This adapter must construct one source and leave all precedence and decoding to
the core.

The adapter lives at `packages/settei-yaml`, is registered in `cabal.project`, and exposes
`Settei.Yaml`. Rei remains useful consumer prior art for YAML configuration and file
discovery, but its registered source is used only to verify application-boundary patterns;
Rei-specific search paths are not part of this adapter.

YAML's surface is wider than Settei's portable data model. Version one supports a single
document composed of null, booleans, numbers, strings, sequences, and mappings with string
keys. Anchors, aliases, tags, merge keys, duplicate handling, numeric precision, and
multi-document streams must be verified against the selected parser rather than inferred
from memory. Unsupported or lossy cases must fail with a documented error.

Plan 1 owns the applicable conventions from registered project
`shinzui/haskell-jitsurei`. Import `Settei.Prelude`, import
`Data.Generics.Labels ()` only in modules that use `#label`, keep fields strict and free of
type-name prefixes, use explicit deriving strategies, and read or update records through
lenses. Qualified parser imports use postpositive syntax. The package declares
`generic-lens` directly when it imports the label instance instead of relying on a
transitive core dependency. [ADR 0001](../adr/0001-haskell-project-conventions.md) records
the durable rationale and rejected alternatives for this baseline.
[ADR 0003](../adr/0003-resolution-provenance-and-default-semantics.md) defines the
adapter-neutral source, precedence, provenance, and redaction contract.
[ADR 0004](../adr/0004-yaml-input-semantics.md) records the strict marked-event YAML
subset and its rejected alternatives.


## Plan of Work

### Milestone 1: select and characterize the parser

Run the required Mori search for `yaml` and `aeson`. If the parser is still not registered,
obtain the exact released source selected by the Cabal solver from an upstream source
archive or repository, record its version and revision, and read the parsing and exception
types directly. Never search `/nix/store`.

The test-only `Settei.Yaml.CharacterizationTest` suite characterizes the selected API. It
feeds the parser duplicate mapping keys, multiple documents, aliases, merge keys,
non-string keys, very large integers, floats, explicit null, invalid UTF-8, and syntax errors. Capture whether
duplicate keys are rejected before conversion to `Data.Aeson.Value` and whether errors
retain line and column.

The selected narrow API is `Text.Libyaml.decodeMarked`. The common decode-to-Aeson entry
point overwrites duplicates after returning them only as warnings, so Settei consumes the
lower-level marked event stream. It does not implement a textual duplicate-key pre-scan;
YAML keys, anchors, indentation, and flow mappings make that unsound.

Record the characterization in `test/fixtures/characterization/README.md` and the selected
version and behavior in this plan's Decision Log. Milestone acceptance is executable tests
for every behavior the adapter will promise.

### Milestone 2: translate YAML into a Settei source

Create `packages/settei-yaml/settei-yaml.cabal` and module `Settei.Yaml`; use `Yaml` in the
module name to match normal Haskell capitalization. Register the package in `cabal.project`
and the Nix project. Repeat Plan 1's canonical package-local `common common` stanza and
import it from the library and test components.

Expose a pure bytes-to-source function and a file convenience:

```haskell
data YamlSourceOptions = YamlSourceOptions
  { name :: !Text
  , path :: !(Maybe FilePath)
  , annotations :: !(Map Text Text)
  }
  deriving stock (Generic, Eq)

decodeYamlSource
  :: YamlSourceOptions
  -> ByteString
  -> Either (NonEmpty YamlSourceError) Source

readYamlSource
  :: YamlSourceOptions
  -> FilePath
  -> IO (Either (NonEmpty YamlSourceError) Source)

yamlSourceOptions :: Text -> YamlSourceOptions
withYamlSourcePath :: FilePath -> YamlSourceOptions -> YamlSourceOptions
annotateYamlSourceOptions :: Map Text Text -> YamlSourceOptions -> YamlSourceOptions
fromKubernetesMountedFile :: KubernetesRef -> YamlSourceOptions -> YamlSourceOptions
```

If the selected parser already exposes an equivalent strict error type, wrap it rather
than leaking parser-specific exceptions throughout application APIs. `readYamlSource`
must distinguish IO failure from YAML syntax or translation failure and include the path.

Translate mappings recursively to raw objects. Each nested mapping name is one `Key`
segment: YAML `service: { http: { port: 8080 } }` supplies
`service.http.port`. Arrays remain arrays and replace wholesale when a higher source wins.
Reject a mapping key containing a literal dot under the version-one key grammar and tell
the user to use nested mappings. Do not interpret dots as implicit nesting.

Preserve YAML number meaning only as far as the core raw type can represent it without
loss. If `RawValue` uses Aeson `Scientific`, document that very large integers and finite
decimals follow that representation. Reject special floating values or tags that cannot be
represented. Never interpolate `${...}` or read environment variables in YAML strings.

### Milestone 3: origins, mounted files, and errors

For each lookup, construct an origin containing source name, file path when present, and
logical key. Preserve line and column for errors and successful leaves only when the
selected parser exposes trustworthy node spans. Otherwise make the successful-location
field absent and document it.

Allow caller-supplied origin annotations so a mounted file can say it came from Kubernetes
ConfigMap or Secret, including namespace, object name, and object key. Treat these as
metadata, not verified cluster facts. Sensitivity still comes from the Settei setting:
annotating a source as a Secret does not automatically make every unrelated value public
or secret, and it can never disable core redaction.

Errors must include a stable category, source name or path, parse line and column when
known, and concise context. Do not include the raw scalar for a key that the core schema
marks secret. Because parsing happens before the schema is interpreted, syntax errors
should quote only a short structural context or no source excerpt; never echo an entire
configuration file into an exception.

### Milestone 4: tests and documentation

Add fixtures for nested values, arrays, null, duplicate keys in block and flow syntax,
invalid mappings, aliases and tags according to the chosen support policy, multi-document
input, and malformed syntax. Integration tests place two YAML sources in order and prove
leaf-wise override through core resolution.

Add `docs/guides/yaml.md` with the canonical mapping, one complete example, explicit source
ordering, duplicate-key policy, null semantics, location precision, mounted-file
annotations, and unsupported features. Make it clear that file discovery and source
precedence are application policy.


## Concrete Steps

Run from `/Users/shinzui/Keikaku/bokuno/settei`. Refresh dependency and prior-art source:

```bash
mori show --full
mori registry search yaml
mori registry search aeson
mori registry search rei
mori registry search generic-lens
mori registry show ekmett/lens --full
mori registry show shinzui/haskell-jitsurei --full
mori registry docs shinzui/haskell-jitsurei
```

For every relevant result, inspect the returned qualified project before using its API:

```bash
mori registry show QUALIFIED_PROJECT_NAME --full
mori registry docs QUALIFIED_PROJECT_NAME
```

If no YAML parser is registered, record that fact and inspect the exact upstream release
chosen for the package; do not proceed from remembered `Data.Yaml` signatures. After
implementation, run:

```bash
nix fmt
cabal build settei-yaml
cabal test settei-yaml-tests --test-show-details=direct
cabal test all --test-show-details=direct
nix flake check
```

Expected behavior-focused output includes:

```text
Settei.Yaml
  nested mappings become segmented keys: OK
  duplicate block mapping keys fail: OK
  duplicate flow mapping keys fail: OK
  explicit null remains present: OK
  arrays replace across ordered sources: OK
  errors identify path and available location: OK
All tests passed
```


## Validation and Acceptance

Parse a document containing `service.http.host`, `service.http.port`, a string list, a
boolean, and explicit null. Resolve matching settings and assert the expected typed values.
The explanation must identify the YAML source, path, and each logical key. Null must reach
the target decoder as a present value.

Parse a low-priority YAML source containing both host and port and a high-priority YAML
source containing only port. Resolution must retain the low source's host and use the high
source's port, with shadowed port provenance. Arrays in the high source must replace, not
concatenate with, low-source arrays.

Both block-style and flow-style duplicate keys must fail before resolution. A syntax error
must name its file and include the parser's line and column when available. Multiple YAML
documents and unsupported tags or key types must either have tested, documented semantics
or fail explicitly; they must never be silently dropped.

Use a secret sentinel in YAML and resolve it through a secret setting. The typed result may
contain the sentinel, but no explanation, warning, error, JSON report, test snapshot, or
`Show` output may contain it.


## Idempotence and Recovery

Parser characterization, formatters, builds, and tests are safe to repeat. Fixtures are
immutable inputs. Keep parser experiments under tests until the dependency choice is
recorded, then remove unused experimental dependencies.

If strict duplicate detection is unavailable in the first candidate, do not weaken the
requirement or publish a silently lossy adapter. Return to Milestone 1, inspect another
maintained parser or a lower-level supported API, update the Decision Log, and keep the
public `decodeYamlSource` boundary stable.


## Interfaces and Dependencies

Package `settei-yaml` depends on `settei`, `base`, `bytestring`, `containers`, and `text`,
plus `libyaml` 0.1.4 for marked events, `conduit` for collecting the event stream,
`attoparsec` for finite number syntax, and `scientific` for exact decimal conversion.
It declares `generic-lens` directly because the module uses `#label`. Core `RawValue`
stores exact `Rational` numbers and has no Aeson dependency, so the adapter translates
marked events directly rather than constructing `Data.Aeson.Value`.

The adapter consumes core `Source`, `Origin`, `RawValue`, `Key`, error, and report
extension points. It must not depend on `settei-env`, `settei-optparse-applicative`, KDL,
Dhall, file-discovery libraries, or a Kubernetes client.


## Revision Note

2026-07-16: Aligned the YAML adapter plan with the registered core Haskell conventions.
The public option sketch now uses strict unprefixed fields and explicit deriving, and the
plan carries forward the custom-prelude, local generic-lens import, lens access, direct
dependency, and postpositive qualified-import requirements.

2026-07-17: Reconciled the plan with the source-inspected `yaml-0.11.11.2` and
`libyaml-0.1.4` implementations. The adapter now uses marked events for strict duplicate
detection and successful-node locations, documents its strict subset and localized pure
wrapper, and records the 20-test characterization evidence.
