---
id: 31
slug: validate-configuration-parity-during-deployment-promotion
title: "Validate configuration parity during deployment promotion"
kind: exec-plan
created_at: 2026-11-20T14:21:27Z
provenance:
  created_by:
    model: "gpt-6.2-sol"
    harness: "codex-cli"
    at: 2026-11-20T14:21:27Z
---

# Validate configuration parity during deployment promotion

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

An application can declare a setting that must have the same effective value in staging
and production for a given release. Before deploying to production, the pipeline compares
the production proposal with the staging inputs that passed for that same release. If
staging used `workers.visibilityTimeoutSeconds = 180` and production would use `120`, the
gate reports the setting key and rejects the promotion. A later release can use `240` in
both environments. Settings outside the policy can vary by environment.


## Progress

- [ ] Add a typed promotion policy that rejects invalid declarations and reports every mismatch between two validated configurations.
- [ ] Run the worker's promotion gate directly and through `settei-preflight`, with passing, mismatched, and incomplete-input cases.
- [ ] Document how pipelines reuse the accepted staging inputs and verify compatibility with existing diagnostics and preflight commands.


## Surprises & Discoveries

## Decision Log

On 2026-11-20, propose comparing typed values after each side passes its normal app
validation. Equivalent inputs can use different source formats, and declared defaults can
produce values that are absent from the raw inputs. The application declares the relevant
keys and their typed accessors. The pipeline chooses the two environments and the process
role by selecting a policy and providing both sets of inputs.

On 2026-11-20, propose replaying the immutable input bundle used for the accepted staging
check. The bundle is the ordered files, environment values or immutable secret references,
and overrides that determine the config for a release and role. CI already controls which
staging result qualifies a release. The promotion job consumes that result's bundle using
the same application release and role. This supports one comparison with no new snapshot
format or credential store in Settei. A service that cannot replay its exact accepted inputs
would need a separate design for capturing the accepted values.

On 2026-11-20, propose an application-owned promotion check command that the existing
preflight harness can run once. Resolving and comparing both sides in the app keeps typed
values in one process and uses the harness's existing coverage and exit-code semantics.


## Outcomes & Retrospective

## Context and Orientation

Promotion is deploying a release that already passed staging to production. Parity means
equality of the selected settings after resolution. The baseline is the exact staging input
bundle associated with that acceptance. The candidate is the proposed production input
bundle. A promotion gate is a check whose failure stops the deployment.

`settei/src/Settei/Resolve.hs` chooses inputs in source order, decodes the winning value,
and applies defaults. Its report can contain rendered source values or placeholders such
as `<derived>` and `<redacted>`. The typed answer carries the actual values. This distinction
is part of the resolution and redaction design. [ADR-3](../adr/0003-resolution-provenance-and-default-semantics.md)

`settei/src/Settei/Validate.hs` applies declared invariants to one typed answer and returns
`ValidatedResult`. Its checked collections validate key references against the declaration,
including conditional keys. The `answer` is `Left` on resolution or invariant failure.
The application owns diagnostic routing and process exit codes. [ADR-14](../adr/0014-application-invariant-validation.md)

`examples/settei-deployment/src/Settei/Example/Deployment.hs` provides the example's
`deploymentConfig`, ordered sources and `roleValidators`. The worker checks that the lease
duration covers concurrency. Its built-in declaration fallback for the duration is `180`.
The example accepts `test` as its runtime environment label. Use it for staging in the new
fixture. `settei-preflight/src/Settei/Preflight.hs` runs a single app command against supplied
files and environment entries. It reports `Pass` only when the command accepts and coverage
is complete. The deployment contract is a static discovery document. Neither path currently
compares two resolved configurations. [ADR-12](../adr/0012-deployment-contract-export-semantics.md) · [ADR-13](../adr/0013-deployment-preflight-harness-semantics.md)


## Plan of Work

### Milestone 1. Declare and compare settings in core

Add `settei/src/Settei/Promotion.hs`. Expose it in `settei/settei.cabal` and re-export it
from `settei/src/Settei.hs`. Follow the checked-collection pattern in `Settei.Validate`.
Each rule pairs a declared `Key` with a typed accessor on the application's config record.
Use the selected field's `Eq` instance so that defaults, decoded equivalents, and `Maybe`
fields compare according to their Haskell types. Require a nonempty policy to catch empty
gates. Reject duplicate and undeclared keys during construction. Reuse the shared default
cycle check before schema traversal and use `schemaPossible` for key membership. Require
the caller to use the same `Config` for both results and to keep each accessor aligned with
its declared key. Match the existing checked-collection convention of opaque constructors
without `Generic` or writable optics.

Run comparisons only after both validated answers succeed. Report both invalid sides if
neither has a valid answer. Otherwise accumulate mismatched keys in declaration order.
The result and text renderer carry keys and fixed messages. Include side names on input
failure. A policy can compare a secret in memory when the application deliberately selects
it. Treat the equality verdict itself as information and restrict access accordingly.
The test suite proves typed equality, complete mismatch reporting, and redaction.

### Milestone 2. Use the policy in the deployment example

Factor resolution and role validation into a shared pure helper in
`examples/settei-deployment/src/Settei/Example/Deployment.hs`. It accepts the role and
ordered external `Source`s and prepends the built-in defaults. Both the existing diagnostic
runner and the new promotion command call it. Add the worker's promotion policy there,
selecting `workers.visibilityTimeoutSeconds`. Keep the current single-environment flags
and handlers on their existing path.

Add `examples/settei-deployment/app/promote/Main.hs` and its Cabal executable
`settei-example-deployment-promote`. Require at least one `--staging-config PATH` and at
least one `--production-config PATH`. Repeated files are read in argument order for that
side, lowest to highest precedence. Use `Settei.Yaml.readYamlSource` with the normal parser
options. Each side gets only its explicitly supplied files plus the built-in defaults. This
reference command models file-based deployments. An application with environment and CLI
sources supplies its own ordered source stacks, using a separate environment snapshot and
override list for each side. Never share a single ambient environment overlay across two
scopes. Both paths stop after the check, before any application startup.

Add `proposed-staging.yaml` under `examples/settei-deployment/test/fixtures/`. Use
`runtime.environment: test`, a distinct dummy database URL and endpoint, and the duration
explicitly set to `180`. Use the existing `proposed-production.yaml` as the production
fixture with the default duration. The promotion command emits `configuration matches\n`
on stdout and exits 0 on a match. It names the sides with unreadable or unparseable files
on stderr and exits 3. Invalid configuration and mismatch exit 4 and write diagnostics to
stderr. Usage errors exit 2. Failure diagnostics from this command use fixed messages and
setting keys. For source and validation details, operators can use the existing app check
on the corresponding inputs. Its existing diagnostics may include public values.

Before expanding tests, prove the intended producer and consumer path with one existing
version-1 preflight request. In `examples/settei-deployment/test/Settei/Example/Deployment/PreflightTest.hs`,
run the built promotion command with `fileArgument` for `staging.yaml` and `production.yaml`
and literal arguments for the corresponding flags. Use inline safe fixture text or test
secret references. Assert `Pass` for matching supplied files, `Fail` with rejection for a
valid `120` production override, and `Inconclusive` for a matching synthetic staging file.
Cover missing or unreadable staging inputs. Register the new executable as a test build
tool and use the existing preflight coverage API. A missing baseline cannot be replaced
with the production inputs or with a synthetic value that passes the gate.

### Milestone 3. Document the pipeline contract

Update `docs/guides/deployment-preflight.md` and `examples/settei-deployment/README.md`
with the declaration, the two-file command, and the equivalent preflight request using
both file arguments. Explain how a staging job records the accepted input bundle reference
alongside the release identity and role. A promotion job selects the accepted record for
that release and role, replays its exact inputs, and deploys only the production proposal
the check exercised. Include versioned or pinned secret references when replay requires a
credential. For secret-bearing files, use `secretFromFile` with access-controlled inputs
and keep contents out of logs and inline request fields. The deployment system owns the
staging record, release identity, artifact integrity, input retention, and production input
binding. Add the durable two-input boundary to the repository's ADR bundle and record the
additive API in the core changelog. Keep automatic cluster access and independently
versioned snapshot artifacts outside this plan.


## Concrete Steps

From the repository root, run the focused suites and then the workspace checks. Add the
focused core cases in `settei/test/Settei/PromotionTest.hs` and register them in
`settei/test/Main.hs` and the Cabal test suite.

```bash
nix develop -c cabal test settei:settei-tests --test-show-details=direct
nix develop -c cabal test settei-example-deployment:settei-example-deployment-tests --test-show-details=direct
nix develop -c cabal test all --test-show-details=direct
okf validate docs/adr --strict --profile docs/adr/profile.dhall --profile-enforce --log-enforce
git diff --check
```

For an executable smoke test from the repository root, build the promotion tool and
check both fixtures. The second invocation adds a YAML file with a valid production
override and should exit 4.

```bash
nix develop -c cabal build exe:settei-example-deployment-promote
promote_bin=$(nix develop -c cabal list-bin exe:settei-example-deployment-promote)
fixture_dir=examples/settei-deployment/test/fixtures
probe_dir=$(mktemp -d)
printf 'workers:\n  visibilityTimeoutSeconds: 120\n' > "$probe_dir/override.yaml"

"$promote_bin" --staging-config "$fixture_dir/proposed-staging.yaml" \
  --production-config "$fixture_dir/proposed-production.yaml"
"$promote_bin" --staging-config "$fixture_dir/proposed-staging.yaml" \
  --production-config "$fixture_dir/proposed-production.yaml" \
  --production-config "$probe_dir/override.yaml"
```

The first command prints `configuration matches`. The second writes this line to stderr.

```text
workers.visibilityTimeoutSeconds: differs between baseline and candidate
```


## Validation and Acceptance

Core tests must show that explicit `180` matches a default of `180` and that equal decoded
values match when their raw representations or winning sources differ. A value in an
unselected setting, such as `database.url`, can differ without affecting the result. A
policy for `Maybe` values permits two absent values and rejects one-sided absence. Two
mismatches are returned once each in policy order. Duplicate and undeclared keys and
cyclic defaults yield construction failures. Validate both inputs with the role's normal
checks. Prove that a failure on either side suppresses every comparison, including when
an accessor would fail if called. A secret mismatch must produce only the key and a
fixed message. Check that neither secret sentinel appears in diagnostics.

The deployment and preflight suite must prove that two individually valid configs can
still fail the promotion check, that unrelated config differences are permitted, and that
an unavailable baseline or partial preflight coverage blocks promotion. The smoke test
must reproduce the match and mismatch through the public command. Existing diagnostic and
preflight tests must continue passing with their existing report and request goldens.


## Idempotence and Recovery

The check is read-only. A retry can use the same accepted staging bundle and production
proposal. If either bundle changes, run the gate on the new candidate and use a new
accepted staging result whenever the staging inputs change. If the accepted staging
bundle cannot be obtained or verified, fail promotion and repeat the staging check to
produce a usable record. The smoke test writes one synthetic fixture under `mktemp -d`.
The preflight harness owns the cleanup of the supplied files it materializes for the child.


## Interfaces and Dependencies

The proposed public API is additive in `Settei.Promotion`. The positional arguments to
`checkPromotion` are the staged baseline followed by the production candidate.

```haskell
mustMatch :: Eq b => Key -> (a -> b) -> PromotionRule a
promotionPolicy
  :: Config a
  -> NonEmpty (PromotionRule a)
  -> Either (NonEmpty PromotionPolicyError) (PromotionPolicy a)
checkPromotion
  :: PromotionPolicy a
  -> ValidatedResult a
  -> ValidatedResult a
  -> Either (NonEmpty PromotionProblem) ()
```

Expose structured construction failures for duplicate and undeclared keys and default
cycles, with a text renderer. `PromotionProblem` distinguishes an invalid baseline,
an invalid candidate, and a mismatch carrying a `Key`. Expose a text renderer for the
nonempty problems. The constructors of `PromotionRule` and `PromotionPolicy` stay
private. The caller supplies results produced by `Settei.Validate.validate` with the
same declared config and role validators. Standard equality applies to each projection.

Core uses existing dependencies. The example uses its existing YAML loader, argument
parser and preflight runner. The existing version-1 preflight request supports two
separately named file arguments and secret-file references. Use that API directly.
