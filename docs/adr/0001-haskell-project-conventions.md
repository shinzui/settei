# ADR 0001: Adopt the Haskell project conventions

Status: Accepted

Date: 2026-07-16


## Context

Settei is planned as one core Haskell library, five adapter libraries, two reference
applications, and shared tests. Without a repository-wide baseline, those components could
drift in language edition, extensions, imports, record design, deriving, and field access.
That drift would be especially visible in Settei's public metadata records, where every
adapter needs concepts such as a source name, key, location, and annotations.

The canonical convention corpus is the Mori project `shinzui/haskell-jitsurei`. During the
2026-07-16 audit, Mori's project-details and documentation commands for that qualified name
resolved the applicable `core-standards`, `core-custom-prelude`, `core-record-patterns`,
`core-multiline-strings`, `cli-option-groups`, and `cli-hierarchical-config` documents.
Mori resolved both `lens` and `generic-lens` through `ekmett/lens`; direct source inspection
found `lens` 5.3.6, `generic-lens` 2.3.0.0, `Control.Lens`, and the orphan `IsLabel` instance
exported by `Data.Generics.Labels`.


## Decision

Every Settei Cabal component uses GHC 9.12 or newer. Each package's `.cabal` file declares
the same package-local `common common` stanza with `default-language: GHC2024` and the
extensions `DeriveAnyClass`, `DuplicateRecordFields`, `OverloadedLabels`, and
`OverloadedStrings`; every component in that file imports the stanza. Cabal common stanzas
do not cross package-file boundaries, so adapter and example packages repeat the canonical
stanza rather than relying on the root package's declaration.

The core package exposes `Settei.Prelude`. That module uses a file-local `PackageImports`
pragma for unambiguous re-exports and re-exports the small common surface plus
`Control.Lens`. `PackageImports` is not a global extension. `Settei.Prelude` does not import
or re-export `Data.Generics.Labels`; each module that uses generic-lens `#label` syntax
imports `Data.Generics.Labels ()` locally.

Records use strict fields without type-name prefixes and derive instances with explicit
`stock`, `newtype`, or `anyclass` strategies. Record reads and updates use lens operators;
record-held maps use `at` and `ix` rather than direct map operations wrapped in record
updates. Qualified imports use postpositive `qualified`. Operators remain unqualified, and
an operator collision is resolved by hiding the unwanted operator from the
`Settei.Prelude` import.

The core package depends on `lens` and `generic-lens`. Any adapter, example, or test package
that imports `Data.Generics.Labels ()` declares `generic-lens` directly rather than relying
on transitive package visibility. `MultilineStrings` is enabled locally or for a narrowly
scoped component only when the source embeds a multi-line value.

For command-line components using optparse-applicative 0.19 or newer, related options are
wrapped in short, intent-based groups such as “Configuration” and “Diagnostics”. Other CLI
patterns from the corpus are adopted only when the component actually needs them. The
hierarchical-config guidance to keep independent concerns separate remains valid, but it
does not replace Settei's defining behavior: ordered sources for the same declared setting
schema are merged by core precedence rules.


## Consequences

Plan 1 owns the canonical Cabal stanza contents and `Settei.Prelude`; every later plan
repeats that package-local stanza and consumes the prelude. Public record sketches use
reusable labels such as `name`, `key`, `value`, `location`, and `annotations`, and nested
domain records replace flat type-prefixed fields when concepts would otherwise collide.
This adds `lens` and `generic-lens` to the baseline dependency surface, and it requires
direct `generic-lens` dependencies in non-core packages that use the label instance.

Implementation and release validation must inspect every component for the common stanza
and representative modules for strict fields, explicit deriving, local label-instance
imports, lens access, and postpositive qualified imports. CLI help tests also verify the
applicable option-group headings.


## Rejected Alternatives

Keeping type-prefixed selectors was rejected because it conflicts with the canonical
record convention and would make public APIs noisier. Re-exporting `Data.Generics.Labels`
from `Settei.Prelude` was rejected because its orphan `IsLabel` instance would leak into
every module and can conflict with other label-based DSLs. Creating a different prelude for
each adapter was rejected because the packages form one project and need a shared baseline.
Applying every CLI cookbook pattern to the small reference executable was rejected as
scope without a user requirement.
