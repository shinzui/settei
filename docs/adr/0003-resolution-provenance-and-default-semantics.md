# ADR 0003: Define leaf-wise resolution, provenance, and default semantics

Status: Accepted

Date: 2026-07-17


## Context

Settei adapters need one shared answer to precedence, malformed overrides, hierarchical
shape conflicts, unknown keys, derived defaults, selective branches, and explanation
safety. If file, environment, and command-line packages each interpret those concerns,
their behavior will drift and an application cannot reason about one ordered source
stack.

The declaration algebra from ADR 0002 provides complete static inspection plus actual
Selective control flow. It does not itself define how a raw source tree becomes a typed
request or how a particular run is explained. Raw candidates may also contain secrets,
so provenance cannot be designed as an unrestricted debug dump.


## Decision

Applications pass sources from lowest to highest precedence. Precedence belongs to list
position, not to a field or annotation on `Source`; the same source can therefore be
placed differently by different applications. For each evaluated setting, the resolver
traverses every source structurally by `Key` segments, collects present candidates in
source order, and chooses the rightmost candidate. Earlier candidates become shadowed
origins. Shadowed origins are retained from highest to lowest losing precedence, so the
first entry is the candidate that would have won if the actual winner were absent.

Resolution is leaf-wise. Objects are traversed only to reach independently declared
keys. A scalar or array is a whole value at its exact key, arrays never concatenate, and
traversing through a scalar, array, or null is a structural conflict. Structural conflicts
are validated for every statically possible key before runtime branch evaluation because
they are source-document shape errors. Missing and decode errors remain branch-local.

Only the winning candidate is decoded. If it is malformed, resolution returns a
`DecodeError` at that origin and never falls back to a valid lower candidate. Independent
Applicative errors accumulate in declaration order. Selective evaluates the selector
first and evaluates only the chosen effectful branch; the runtime report records the
branch decision and marks omitted possible settings as not selected rather than missing.

Leaves that are not beneath any statically declared key are unknown. The default policy
returns them as warnings so an application can consume one section of a mixed document.
Strict resolution promotes the same structured problems to errors. Candidate contents are
not retained in unknown-key diagnostics.

Origins contain a source kind, stable source name, logical key, optional exact-key
location, and ordered annotations. Annotations are descriptive and never affect
precedence. Core supplies shared Kubernetes ConfigMap and Secret reference annotations;
adapter packages may add environment-variable, command-line-option, path, span, or import
metadata without introducing format cases into the resolver. `Source` supports both
source-wide annotations and composable per-key annotations; per-key entries take
precedence when names overlap. This lets one environment snapshot or parsed document
retain distinct metadata for each candidate without being split into artificial sources.
The text renderer recognizes core's Kubernetes annotation vocabulary and appends the
asserted object kind, namespace, name, and key; deterministic JSON retains the complete
ordered annotation map. Adapter annotations must never copy raw candidate values. In
particular, the command-line adapter records a safe option-and-key spelling plus an
occurrence number, while the potentially secret assignment remains only in `RawValue`
until setting sensitivity is known.

Defaults are syntax nodes with a `RuleName`, explanation, and either a constant value or
an explicit `Config` dependency. A finite case default is the same named dependency form
with a non-empty table and optional fallback. An explicit source candidate for the target
wins and the default dependency is not evaluated. If the target is absent, successful
dependency nodes remain in the report and the target receives a derived origin and
dependency edges. An unmatched case without a fallback is a structured error that does
not retain the rejected dependency value.

Before schema inspection or source lookup, the resolver walks default syntax with an
active `RuleName` stack. Re-entering an active name is a cycle. This validates mutually
recursive Haskell declarations without pointer identity and reports the ordered rule path.
A repeated name in an independent, non-nested declaration is not a cycle.

The static `Schema` and runtime `ResolutionReport` answer different questions. Schema is
the conservative set of every possible setting and condition. A report contains only the
actual evaluated nodes plus explicit not-selected placeholders, chosen and shadowed
origins, derivation edges, and branch decisions for one successful run.

Redaction is applied before data enters a report or structured error. `RawValue` and
`Candidate` have no `Show` instance. The constructors of `ReportedValue` are private;
public reporting functions can render it but cannot recover a redacted secret. Source
decode errors retain only an expected description and a sensitivity-aware rejected-value
representation. A public `Setting` may opt into a renderer for typed default values,
because an arbitrary `a` has no format-independent display. Secret settings ignore such
rendering and always store a redaction marker.

Text renderers use stable key order for human explanations. JSON renderers are compact,
deterministic documents with top-level `schemaVersion: 1` and a document type. Core emits
JSON directly from the closed safe report and error types; it does not add a parser or
Aeson dependency solely for serialization.


## Observable Laws

The EP-2 unit, exhaustive law, golden, and adversarial tests enforce these behaviors:

- For every permutation of three present sources, the rightmost candidate wins.
- Reversing a source stack predictably reverses the relevant winners.
- A high malformed candidate fails at its own origin without decoding a lower candidate.
- Arrays replace wholesale, and scalar/object traversal conflicts fail structurally.
- Independent missing settings accumulate in declaration order.
- Unknown leaves warn by default and become errors under strict policy.
- An unselected Selective branch has no missing or decode errors and is reported as not
  selected; a selected branch enforces its requests.
- Explicit target values skip default dependencies; derived and case defaults retain
  their actual dependency keys.
- Mutual default cycles fail before a source location function can be called.
- Text and JSON snapshots have stable ordering and JSON schema version 1.
- A secret sentinel containing quotes, backslashes, control characters, punctuation, and
  non-ASCII text is absent from schema, report, error, warning, JSON, text, and `Show`
  outputs.


## Consequences

Every adapter only parses input into `RawValue`, constructs `Source`, and attaches honest
origin metadata. It must not merge layers or decode settings. Applications can combine
adapters freely because source position has the same meaning for all of them.

Structural validation inspects possible key paths even when Selective later skips their
requests. This intentionally catches malformed documents early, while missing credentials
and malformed leaf values remain conditional on actual execution.

Reports do not contain application values. The typed result remains in `ResolveResult a`,
while the report carries only public display text, `<derived>`, or `<redacted>`. Consumers
that want an exact public typed-default display provide a renderer when declaring the
setting.

Versioned JSON can gain additive fields while preserving version 1 ordering and meaning.
A breaking representation change requires a new schema version and updated goldens.


## Rejected Alternatives

Assigning numeric precedence to a source was rejected because it duplicates list order
and makes source reuse surprising. Deep-merging whole raw trees was rejected because it
obscures per-leaf origins and gives arrays an arbitrary meaning. Falling back after a bad
winner was rejected because it hides deployment mistakes and can reactivate stale values.

Decoding every candidate was rejected because shadowed malformed or secret values do not
affect the result. Treating every unknown key as fatal was rejected because mixed
documents are useful; silently ignoring all unknown keys was rejected because typos need
diagnostics.

Defaults over a completed application record were rejected because their dependencies
cannot be inspected or explained. Pointer-identity cycle detection was rejected because
stable rule names already define the user-facing identity and permit a pure preflight.

Renderer-only redaction was rejected because an unsafe intermediate report, derived
`Show`, JSON encoder, or failed golden could leak a credential. Retaining raw values in
reports was rejected for the same reason. Adding Aeson only to emit four small closed JSON
documents was rejected in favor of the dependency-free deterministic encoder; adapter
plans may independently use parser libraries at their input boundaries.


## Amendment 2026-07-19: most-restrictive sensitivity and conflict errors

When one `Config` declaration names the same key with more than one sensitivity, schema
merging and every report representation use the most restrictive sensitivity: `Secret`
wins over `Public`. The merged schema retains every declared sensitivity for validation,
while its effective sensitivity remains a single Secret-biased value. Resolver evaluation
uses that effective value for source candidates, decode errors, missing nodes, derived
defaults, and skipped nodes. Duplicate report-node maps also combine with a
redaction-preferring rule, so a Secret node can never be weakened by union order.

For every acyclic declaration that contains both `Public` and `Secret` declarations of
one key, `resolve` returns the structured `SensitivityConflict` error before source-shape
validation or runtime evaluation. Default-cycle validation remains the first gate because
building the static schema follows default dependencies and cannot terminate for an
already-cyclic declaration. A declaration containing both defects therefore reports its
`DefaultCycle` first; sensitivity conflicts are then detected in deterministic key order
for every acyclic declaration.

This is defense in depth rather than error-only enforcement. The conflict error tells an
application owner that independently composed modules disagree, while most-restrictive
schema and report semantics keep the redaction guarantee intact even if a future internal
path constructs or combines nodes before handling that error.


## Amendment 2026-07-19: reports for every resolution attempt

`resolve` returns a total `ResolveResult`. Its `answer` field contains either the typed
application value or a non-empty collection of configuration errors, while `report` and
`warnings` remain available on both success and failure. A separate
`resolveWithReport` entry point was rejected because two resolver boundaries could drift
and adopting applications could standardize on the older lossy one.

For a failure reached during evaluation, the report retains every node and branch trace
that evaluation produced, including the winning origin and shadowed origins for a value
that failed to decode. The rejected candidate enters the report only through its
sensitivity-aware `ReportedValue`, so existing redaction rules are unchanged. The report
is completed with the same not-selected placeholders as a successful attempt, giving
operators one stable schema-shaped view.

Sensitivity and structural validation failures happen before evaluation and return the
complete static schema as `NotSelected` nodes with no origins, shadowed origins,
derivations, or branch traces. Unknown-key warnings are still available on these paths.
The default-cycle exit is stricter: it returns no warnings and never inspects a source,
preserving the observable cycle-preflight law. Because ordinary schema inspection follows
default dependencies and cannot terminate for a cyclic declaration, this exit builds its
not-selected skeleton with a `RuleName`-guarded declaration traversal and merges duplicate
sensitivities most-restrictively.

Under `RejectUnknownKeys`, unknown leaves remain errors in `answer` and `warnings` is
empty. JSON reports retain `schemaVersion: 1`: the report document representation is
unchanged, and failure merely makes an existing secret-safe document available on more
resolution paths.
