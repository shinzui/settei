# ADR 0005: Adopt a canonical span-preserving KDL v2 mapping

Status: Accepted

Date: 2026-07-17


## Context

Settei needs one KDL adapter that preserves the core declaration, resolution, provenance,
and redaction semantics used by every other source. KDL is structurally richer than the
core raw tree: nodes may have positional arguments, properties, children, repetition,
type annotations, and non-finite numbers. A durable mapping must say which combinations
represent scalars, arrays, and objects and must reject combinations that would discard or
invent data.

Mori resolves `brandonchinn178/kdl-hs` at
`/Users/shinzui/Keikaku/hub/kdl-hs-project`. The registered package is version 1.0.1 and
implements KDL v2. Its AST retains ordered entries, exact finite `Scientific` values,
explicit non-finite constructors, annotations, and one-based spans when requested. The
`getProps` convenience converts entries through `Map.fromList`, which would hide duplicate
properties, but direct `Node.entries` inspection preserves each occurrence and span. The
public parser renders failures as text containing both a location header and a source
excerpt.

The flake's nixpkgs package set contains `kdl-hs` 1.1.0, but that source is not present in
the registered corpus. Both Cabal and Nix therefore need one explicit version choice so
the build uses the API that was actually inspected.


## Decision

`settei-kdl` uses `kdl-hs` 1.0.1 and its KDL v2 parser. Cabal requires exactly 1.0.1, and
the flake pins the same Hackage archive for Nix. The adapter parses the AST directly and
does not use `KDL.Applicative`, `KDL.Arrow`, or a KDL-specific application schema.

One document becomes one root `RawObject`. A node name is a field name. One positional
argument without properties or children is a scalar; two or more positional arguments are
an array; no entries or children is explicit null. Properties become object fields, and
children may add non-colliding fields. Repeated sibling names become an array in document
order. A single sibling always retains its direct value.

This cardinality rule means an argument-style array cannot contain exactly one element in
adapter version one. The limitation is accepted because adding a reserved child name or
wrapper shape would invent syntax outside the approved mapping. A later extension must be
explicitly versioned and tested for compatibility.

Empty and dotted names, duplicate properties, positional arguments mixed with properties
or children, and property/child name collisions fail explicitly. Node and value type
annotations are rejected because the core has no annotation semantics. Finite
`Scientific` values convert exactly to `Rational`; `#inf`, `#-inf`, and `#nan` fail rather
than being coerced.

Successful candidates retain one-based start locations and complete start/end spans. The
full span is represented by safe `kdl.span.*` annotations, and repeated arrays span from
the first sibling's start through the last sibling's end. Syntax errors keep only the
line/column header parsed from the public parser's text; the source excerpt and detailed
rendered error are discarded because parsing precedes sensitivity classification.

Caller annotations, including Kubernetes ConfigMap and Secret references for mounted
files, are trusted metadata. They do not affect precedence or redaction. The core remains
the only merge and sensitivity authority.


## Consequences

Every accepted KDL document has one deterministic parser-neutral tree meaning. Duplicate
properties cannot disappear through the parser helper, repeated nodes preserve source
order, and reports can distinguish KDL origins by file, logical key, version, and span.
Equivalent KDL and YAML sources participate in the same low-to-high leaf precedence and
array replacement laws.

Applications cannot use type annotations, non-finite numbers, mixed node shapes, or a
one-element argument array through adapter version one. They must choose an unambiguous
supported shape or normalize input outside Settei. Parse diagnostics are intentionally
less verbose than `kdl-hs`' rendered message so structured failures cannot capture secret
source lines.

Pinning 1.0.1 keeps Cabal and Nix reproducible against inspected source. Moving to a newer
parser requires a new source audit of its AST, duplicate handling, spans, parser-error
rendering, and language-version behavior before widening the bound or changing the pin.


## Rejected Alternatives

Using `KDL.Applicative` as a second application schema was rejected because the core
`Config` declaration must work unchanged across all adapters. Calling `getProps` was
rejected because it collapses duplicate properties. Silently choosing between an argument,
property, or child was rejected because it discards data and makes provenance dishonest.

Erasing type annotations, coercing non-finite numbers to text, parsing detailed error
strings into a public message, and attaching synthetic spans were rejected as lossy or
unsafe. Using nixpkgs' uninspected 1.1.0 package was rejected until its source enters the
Mori corpus and receives the same audit.
