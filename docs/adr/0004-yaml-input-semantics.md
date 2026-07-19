# ADR 0004: Parse a strict marked-event YAML subset

Status: Accepted

Date: 2026-07-17

Amended: 2026-07-19


## Context

Settei's YAML adapter must reject duplicate mapping keys before they are collapsed and
must report honest source locations for successful candidates as well as syntax errors.
The package must also translate into core `RawValue` without adding YAML behavior to the
resolver or copying raw scalars into structured errors.

Mori had no registered general YAML, HsYAML, or libyaml source project. The EP-4 audit
therefore unpacked and inspected Hackage releases `yaml-0.11.11.2` and `libyaml-0.1.4`.
The high-level `Data.Yaml.decodeEither'` path builds an Aeson key map with `M.insert` and
discards its `DuplicateKey` warning list. By contrast, `Text.Libyaml.decodeMarked` emits
each mapping pair before conversion and attaches zero-based start and end marks to every
event.


## Decision

`settei-yaml` consumes `Text.Libyaml.decodeMarked` from the `libyaml` 0.1 series. It parses
the marked event sequence directly into core `RawValue`, rejects a repeated mapping name
before `Map.insert`, and converts each value's start mark to a one-based `SourceLocation`.
The actual file path is used when known; otherwise the caller's stable source name is the
logical location path.

Version one accepts exactly one top-level mapping. An empty stream or empty document is an
empty mapping. Nested mappings require scalar string keys without literal dots; a dot is
expressed only by mapping nesting. Null is a present `RawNull`, arrays remain whole
`RawArray` values, booleans are typed, and decimal, exponent, hexadecimal, and octal
numbers become exact `Rational` values through `Scientific`. Non-finite floating values
fail because core has no lossless representation for them.

Duplicate block and flow keys, non-string keys, multiple documents, anchors, aliases,
merge keys, custom tags, dotted keys, and unsupported scalar or collection tags fail with
a stable `YamlErrorCategory`. These failures contain only source name, optional path,
one-based mark, structural key/index context, and a fixed safe message. They never retain
a raw scalar or source excerpt.

The C binding exposes parsing through a resource-managed conduit even for an immutable
strict `ByteString`. `decodeYamlSource` therefore has one `NOINLINE` helper using
`unsafePerformIO` to collect marked events. This is a referentially transparent boundary:
the bytes and options fully determine the result, asynchronous exceptions are not caught,
and all filesystem effects remain explicit in `readYamlSource`. The inspected `yaml`
package uses the same technique for its pure byte decoders.

Caller annotations, including Kubernetes ConfigMap and Secret references for mounted
files, are trusted descriptive metadata. They never alter source precedence or setting
sensitivity; core resolution remains solely responsible for redaction.


## Consequences

Settei retains precise successful-leaf and parse-error locations without relying on an
Aeson intermediate form. Strict duplicate rejection applies equally to block and flow
syntax and also validates mappings nested inside arrays. The supported subset is smaller
than YAML's graph model, but every accepted document has one deterministic tree meaning
that maps directly to Settei keys and raw values.

The adapter directly depends on `libyaml`, `conduit`, `attoparsec`, and `scientific`.
Applications that require aliases, merge keys, custom tags, or multiple documents must
normalize them outside Settei or use another source adapter. Adding one of those features
later requires an explicit compatibility decision and tests for duplicate, provenance,
and redaction behavior.


## Rejected Alternatives

Using `Data.Yaml.decodeEither'` was rejected because it discards duplicate warnings and
successful-node marks. Accepting `decodeFileWithWarnings` only for files was rejected
because in-memory and file inputs would then have different validation contracts. A
textual duplicate-key pre-scan was rejected because YAML flow syntax, quoted keys,
indentation, anchors, and aliases make it unsound.

HsYAML was not selected because the marked libyaml API already meets the required behavior
with the existing BSD-licensed parser family; adding a second parser and its different
schema semantics would not improve the version-one contract. Silently applying aliases,
merge keys, or last-key-wins semantics was rejected because it hides configuration
ambiguity and weakens provenance.


## Amendment 2026-07-19: bounded numeric scalar exponents

Exact `Rational` conversion is now bounded: a numeric scalar whose parsed base-10
exponent has an absolute value greater than 4096 fails with `YamlInvalidScalar` and the
fixed message "numeric scalar exponent is out of the supported range". The guard covers
the float-tagged, integer-tagged, and untagged numeric paths, because `toRational`
materializes `10 ^ exponent` as an exact `Integer` and an unbounded exponent lets a
fourteen-character scalar hang or out-of-memory a process at load time. The bound is
per-scalar and adapter-local; core `RawNumber` remains an unbounded exact `Rational`, and
literal coefficients of any written length remain accepted because their cost is
proportional to input size.
(`docs/plans/10-bound-numeric-scalar-conversion-in-the-yaml-and-kdl-adapters.md`)


## Amendment 2026-07-19: YAML 1.2 core-schema booleans

The 2026-07-19 API review found that `yamlBoolean` accepted the YAML 1.1 boolean set
(`y`, `yes`, `on`, `n`, `no`, `off`, `true`, `false`), resurrecting the Norway problem:
an unquoted `country: no` became the boolean false, so a text setting failed to decode
with a baffling "expected text" error, and `enabled: on` silently type-shifted.

Untagged plain-scalar boolean recognition is now restricted to case-insensitive `true`
and `false`, per the YAML 1.2 core schema. Scalars explicitly tagged `!!bool` accept the
same restricted set, so `!!bool yes` is a `YamlInvalidScalar` error; the adapter has one
boolean vocabulary. Null spellings are unchanged: case-folded `null`, `~`, and the empty
plain scalar were already exactly the 1.2 core-schema null set. This also aligns the
adapter with core `boolDecoder`, which accepts only textual `true`/`false`.

Rejected alternative: keeping the YAML 1.1 boolean set for compatibility. Settei is
pre-release with no adopter files to protect, and strictness is this adapter's contract.
(`docs/plans/11-adopt-yaml-1-2-core-schema-boolean-scalars.md`)


## Amendment 2026-07-19: contain unexpected synchronous decode failures

The pure decode boundary originally caught only `YamlException`, so another synchronous
exception could escape `decodeYamlSource`. The boundary now catches `SomeException`, still
rethrows asynchronous exceptions (`SomeAsyncException` and `AsyncException`), and maps
unexpected synchronous exceptions to `YamlSyntaxError` with a fixed message that
deliberately includes no exception text, because rendered exception text could echo raw
input. The `unsafePerformIO` boundary decision is unchanged.
