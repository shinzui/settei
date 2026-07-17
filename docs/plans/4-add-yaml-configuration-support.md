---
id: 4
slug: add-yaml-configuration-support
title: "Add YAML configuration support"
kind: exec-plan
created_at: 2026-07-16T23:50:07Z
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

- [ ] Inspect the current Haskell YAML parser source and prove its duplicate-key behavior.
- [ ] Add and register the `settei-yaml` package.
- [ ] Translate supported YAML values into the core raw tree and origin model.
- [ ] Add strict error handling, file IO, and mounted-file annotations.
- [ ] Test hierarchy, precedence, locations, duplicate keys, and redaction.
- [ ] Publish the YAML format guide and limitations.


## Surprises & Discoveries

(None yet.)


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

- Decision: Report a successful leaf as file plus logical key in version one, and report
  line and column whenever the parser substantiates them for an error.
  Rationale: common Aeson-oriented YAML APIs discard successful-node spans; Settei must not
  claim locations it cannot preserve.
  Date: 2026-07-16


## Outcomes & Retrospective

To be filled during and after implementation. If strict duplicate detection or successful
node spans require a parser change, record the evidence and final compatibility choice in
this plan and a format ADR if the constraint is durable.


## Context and Orientation

This plan depends on
`docs/plans/2-implement-hierarchical-resolution-provenance-and-derived-defaults.md`.
That plan supplies `RawValue`, `Source`, extensible `Origin`, hierarchical lookup,
structured errors, and redaction. Read its implementation and resolution ADR before
coding. This adapter must construct one source and leave all precedence and decoding to
the core.

At repository bootstrap, adapters are expected beneath `packages/` and registered in
`cabal.project`. There is no YAML implementation yet. Rei is useful consumer prior art for
YAML configuration and file discovery; locate its current registered source through Mori
before reading it. Do not transplant Rei-specific search paths into this adapter.

YAML's surface is wider than Settei's portable data model. Version one supports a single
document composed of null, booleans, numbers, strings, sequences, and mappings with string
keys. Anchors, aliases, tags, merge keys, duplicate handling, numeric precision, and
multi-document streams must be verified against the selected parser rather than inferred
from memory. Unsupported or lossy cases must fail with a documented error.


## Plan of Work

### Milestone 1: select and characterize the parser

Run the required Mori search for `yaml` and `aeson`. If the parser is still not registered,
obtain the exact released source selected by the Cabal solver from an upstream source
archive or repository, record its version and revision, and read the parsing and exception
types directly. Never search `/nix/store`.

Write a throwaway or test-only characterization executable before choosing an API. Feed it
duplicate mapping keys, multiple documents, aliases, merge keys, non-string keys, very
large integers, floats, explicit null, invalid UTF-8, and syntax errors. Capture whether
duplicate keys are rejected before conversion to `Data.Aeson.Value` and whether errors
retain line and column.

Select the narrowest official API that permits strict duplicate rejection. If the common
decode-to-Aeson entry point silently overwrites duplicates, use a lower-level event or
node API from the same inspected package or choose a maintained parser that exposes the
needed information. Do not implement a textual duplicate-key pre-scan because YAML keys,
anchors, indentation, and flow mappings make that unsound.

Record the characterization in `test/fixtures/characterization/README.md` and the selected
version and behavior in this plan's Decision Log. Milestone acceptance is executable tests
for every behavior the adapter will promise.

### Milestone 2: translate YAML into a Settei source

Create `packages/settei-yaml/settei-yaml.cabal` and module `Settei.Yaml`; use `Yaml` in the
module name to match normal Haskell capitalization. Register the package in `cabal.project`
and the Nix project.

Expose a pure bytes-to-source function and a file convenience:

```haskell
data YamlSourceOptions = YamlSourceOptions
  { yamlSourceName  :: Text
  , yamlAnnotations :: Map Text Text
  }

decodeYamlSource
  :: YamlSourceOptions
  -> ByteString
  -> Either (NonEmpty YamlSourceError) Source

readYamlSource
  :: YamlSourceOptions
  -> FilePath
  -> IO (Either (NonEmpty YamlSourceError) Source)
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
plus the parser and raw-value bridge selected through source inspection. If the core
`RawValue` is Aeson-based, prefer a parser path that preserves required validation before
producing `Data.Aeson.Value`.

The adapter consumes core `Source`, `Origin`, `RawValue`, `Key`, error, and report
extension points. It must not depend on `settei-env`, `settei-optparse-applicative`, KDL,
Dhall, file-discovery libraries, or a Kubernetes client.
