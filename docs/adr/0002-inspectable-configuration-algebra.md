# ADR 0002: Use an explicit inspectable selective configuration algebra

Status: Accepted

Date: 2026-07-17


## Context

Settei must let an application compose typed configuration declarations, inspect every
setting that the declaration may request before loading any source, and skip the unused
side of a runtime-dependent branch. Plan 2 will also need stable syntax locations for
branch decisions, named derived defaults, and provenance edges.

The `selective` 0.7.0.1 package provides `Control.Selective.Free.Select`, a Church-encoded
free selective functor. Its `getEffects` and `getNecessaryEffects` functions correctly
classify the proof declaration: `runtime.environment` is necessary, while
`database.password` is possible but conditional. The representation is a rank-n wrapper
around an interpreter function, however, so Settei cannot inspect syntax nodes or attach
its own durable metadata without building a parallel representation.

An explicit typed syntax tree can represent pure values, mapping, applicative application,
setting requests, and selective branching directly. Its constructors can remain private,
so the public API still exposes an algebra rather than construction details.


## Decision

`Config` uses a private generalized algebraic data type (GADT) with nodes for pure values,
mapping, applicative application, required or optional setting requests, and selective
branching. A GADT is a Haskell data type whose constructors can refine the result type;
here that property keeps every setting request and branch type-safe inside one syntax
tree.

The public `Config` type has `Functor`, `Applicative`, and `Selective` instances. It does
not have, and will not gain, a `Monad` instance or another operation with the same power as
monadic bind. A bind could inspect a resolved value and then construct an arbitrary new
key, making complete pre-execution schema inspection impossible.

`describe` is a source-free interpreter. It returns a `Schema` with these terms:

- A possible setting occurs somewhere in the static declaration.
- A necessary setting is conservatively known to be evaluated on every execution path.
- A conditional setting occurs on the effectful side of a selective branch and may be
  skipped after the selector is evaluated.
- Required versus optional describes whether absence is a runtime error. It is orthogonal
  to necessary versus conditional, which describes control flow.
- A `Condition` records the selector's possible setting keys as dependencies and the
  branch's possible keys as activated settings.

Applicative composition unions both schemas and keeps both sides necessary. Selective
composition unions the possible settings, keeps the selector's necessary settings
necessary, marks the effectful branch conditional, and records the relationship. If the
same key is necessary anywhere in the combined declaration, necessary wins over
conditional; required similarly wins over optional.

The private runtime fold evaluates nodes in declaration order. For a selective node it
evaluates the selector first, returns an available `Right` result immediately, and
evaluates the effectful function only for `Left`. This is the executable reason a
development configuration does not request a production-only password.

`Control.Selective.Free` remains in the test suite as an independent analysis oracle. It
is not part of the production representation and supplies no provenance semantics.


## Observable Laws

The following laws define the first-release inspection contract and are covered by the
EP-1 tests:

- Describing a pure declaration yields no settings.
- Mapping a pure function over a declaration does not change its schema.
- Applicative composition of independent requests reports both as necessary.
- Selective composition reports effects from both operands as possible and conservatively
  moves the effectful operand out of the necessary set.
- Interpreting a selective declaration does not execute the effectful operand when the
  selector produces `Right`.
- Key parsing and rendering round-trip for accepted dotted keys.
- Decode failures identify the validated setting key and never retain or render the
  rejected raw value.


## Consequences

Plan 2 can extend private syntax nodes or interpreter state with stable branch identifiers,
default-rule names, and provenance edges without changing adapters or exposing the GADT.
All adapters construct raw values and invoke the shared core; none implements its own
configuration algebra.

The schema is deliberately conservative. Future analysis may recognize more statically
known branches, but it must not omit a setting that can be requested at runtime or classify
a conditional request as unconditionally necessary without proof.

Because `Control.Lens` also defines a setter type alias called `Setting`,
`Settei.Prelude` hides that one alias while re-exporting the rest of the lens API. This
keeps Settei's public `Setting` unambiguous in declarations and examples.


## Rejected Alternatives

Using `Control.Selective.Free.Select` directly was rejected because the opaque
Church-encoded representation has no syntax nodes for Settei-specific metadata. Treating
the free representation as the algebra and maintaining a second metadata tree was
rejected because the two structures could drift and every combinator would need to update
both.

Exposing the explicit constructors was rejected because consumers should program against
the lawful public combinators and interpreters, leaving Settei free to extend private
metadata. Providing a `Monad Config` instance was rejected because runtime-generated
declarations contradict complete static enumeration. Treating Selective itself as the
provenance graph was rejected because its laws do not represent origins, shadowed
candidates, named defaults, redaction, or branch explanations.
