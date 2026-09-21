# Capability catalog log

## 2026-09-21

* **Adopt**: Authored the initial capability catalog under the shared
  `coordination.capabilities` profile from
  `mori://shinzui/okf-profiles/profiles/capabilities`. Derived thirteen capabilities
  from the eight public packages, exported modules, test suites, guides, security and
  compatibility contracts, and the 0.1.0.0 and 0.2.0.0 release history. Registered the
  bundle in `mori.dhall`. Records are machine-authored; no `reviews` or `verified`
  provenance is claimed.
* **Grouping**: Kept declarations, resolution, diagnostics, and custom source
  construction separate because consumers can inspect, resolve, render, or extend the
  core independently. Split command-line overrides (0.1.0.0) from reusable diagnostic
  modes (0.2.0.0), and split Kubernetes mounted files from reference-derived environment
  bindings because each has its own construction path and evidence.
* **Gaps found**: All eight public packages have direct tests and guides. The evidence
  did not expose an untested public package or an unknown release origin. The important
  bounds are behavioral: Dhall local-import enforcement has a documented preflight/read
  race, mounted directories are startup snapshots rather than watched inputs, Kubernetes
  identity is asserted rather than cluster-attested, and the format adapters deliberately
  accept strict subsets instead of every construct their source languages permit.
