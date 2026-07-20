# ADR 0010: Validate environment bindings at construction

Status: Accepted

Date: 2026-07-19

Amended: 2026-07-20


## Context

Environment bindings are static application data: each `EnvBinding` maps one explicitly
supported environment-variable name to one Settei key. The original `settei-env` API
accepted `[EnvBinding]` in every call to `envSource` and `readEnvSource`, then rechecked
invalid names, duplicate names, duplicate targets, and structurally overlapping targets
each time a source was assembled.

That shape forced applications to handle an error that depends only on program text at a
runtime source-assembly boundary. Both reference applications either raised an exception
or converted the impossible branch into an input failure. The same literal source label,
`"environment"`, was repeated by every observed caller. `prefixedBindings` already
validated generated names but returned a plain list that `envSource` validated again.


## Decision

`Settei.Env` exposes an opaque `Bindings` collection. Callers obtain it through
`bindings :: [EnvBinding] -> Either (NonEmpty EnvError) Bindings` or through
`prefixedBindings`; both paths share the same validation rules. The constructor is not
exported and `Bindings` does not derive `Generic`, so public generic conversion cannot
bypass the invariant. `bindingsList` provides read-only inspection.

Applications validate static binding lists once, normally in a top-level definition that
fails fast with `renderEnvErrorsText`, and force that definition in their test suite. No
unchecked or partial `unsafeBindings` constructor is provided.

Because every `Bindings` value is valid by construction, `envSource` and `readEnvSource`
are total over their public inputs and return `Source` and `IO Source` directly.
`environmentSource` and `readEnvironmentSource` provide the conventional
`"environment"` label; the labeled functions remain available for tests and deployments
that need a distinct name. The label is not stored in `Bindings` because validation and
source identity are separate concerns.

The raw-tree builder retains its internal
`error "validated environment keys cannot overlap"` sentinel. `Bindings` construction
proves that branch unreachable for public inputs; encoding structural non-overlap more
deeply in the type system is outside the adapter's intended boundary.


## Consequences

Application source assembly has no binding-validation branch, and invalid static lists
surface once as programming errors. Generated bindings pass directly to source builders
without redundant validation. The API change is breaking for the pre-release
`settei-env` package: callers must construct `Bindings` before calling the source
builders.

Validation behavior and the secret-safety contract are unchanged. `EnvError` continues
to retain only names and keys, environment values remain absent from diagnostics, and
`fromKubernetesObject` still annotates one `EnvBinding` before collection validation.


## Rejected Alternatives

Keeping per-assembly validation was rejected because static program errors would remain
in every runtime call path. Adding `unsafeBindings` was rejected because it would create
an unchecked hole in the invariant for a small one-time convenience. A public default
label constant was rejected because it saves no ceremony over the convenience functions.
Storing a label inside `Bindings` was rejected because one valid collection may be reused
under different source identities. Replacing the internal sentinel with a more elaborate
type-level tree proof was rejected as disproportionate to a branch already excluded by
the opaque smart constructor.


## Amendment 2026-07-20: validated composition and Kubernetes reference derivation

`mergeBindings :: [Bindings] -> Either (NonEmpty EnvError) Bindings` concatenates
validated collections in order and passes the result through the same `bindings`
validator. Two collections that are valid separately can still repeat a variable name
or target structurally overlapping keys, so composition remains explicitly fallible. An
empty list produces the valid empty collection. A `Semigroup Bindings` instance was
rejected because a total `(<>)` cannot report these cross-collection conflicts without
discarding the construction-time invariant or becoming partial.

`Settei.Kubernetes.Bindings` derives validated environment bindings from one ConfigMap
or Secret reference. Each `ObjectKeyBinding` row holds a Kubernetes data key, an
`EnvName`, and a target `Key`; the generated `EnvBinding` and its
`kubernetes.object-key` annotation are produced from that same row before the full list
is validated. Reusing one Kubernetes data key for multiple distinct variables is legal,
while duplicate environment names and duplicate or overlapping target keys retain the
ordinary `EnvError` behavior. The definitions live in `settei-kubernetes`, which is the
adapter package allowed to depend on both core `settei` and `settei-env`; core and
`settei-env` do not depend on Kubernetes-specific construction vocabulary.
