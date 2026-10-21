---
type: Improvement Request
title: Export a deployment configuration contract with bindings and defaults
description: Combine configuration declarations, environment bindings, default sources, and deployment requirements into a safe contract for authoring a service's first deployment.
requestId: IR-1
status: accepted
targetPlan: docs/plans/26-export-a-deployment-configuration-contract-with-bindings-and-defaults.md
origin: mori://tan/notification-hub
generated:
  by: process:codex
  at: "2026-10-21T12:09:29Z"
reviews:
  - kind: model
    reviewer: process:codex
    reviewed_at: "2026-10-21T12:09:29Z"
    document_timestamp: "2026-10-21T12:09:29Z"
    scope: content-and-metadata
    outcome: commented
    provider: openai
    model: gpt-6
    effort: unspecified
    context: Author self-check against the deployment-authoring discussion, Settei schema and environment APIs, and notification-hub configuration sources; no independent review or implementation acceptance claimed.
acceptanceCriteria:
  - id: AC-1
    statement: A public API and documented CLI integration export a deterministic, versioned JSON deployment contract joining setting keys, descriptions, sensitivity, requirement and presence metadata, and all declared environment bindings without duplicating the application's configuration definition.
    verification: Export a reference application's contract twice and compare outputs; assert that each declared binding joins to the correct setting, unbound settings are explicit, and inconsistent inputs produce useful diagnostics.
  - id: AC-2
    statement: The contract reports default availability and provenance from both declaration-level defaults and explicitly supplied default sources, shows safely renderable public defaults, and distinguishes known absence, deferred or conditional defaults, and unavailable metadata.
    verification: Cover constant, derived, conditional, source-based, invalid, and unknown defaults; use a fixture with required declarations backed by a built-in default source and prove those settings are not all reported as requiring external input.
  - id: AC-3
    statement: The contract distinguishes declaration requiredness, the need for external input after known defaults, conditional requirements, and application-declared deployment requirements that demand explicit input despite a default.
    verification: Compare a required setting without a default, one with a default, an optional setting, a conditional setting, and a setting whose development default is prohibited by an explicit deployment profile; preserve uncertainty when the condition or default cannot be established.
  - id: AC-4
    statement: Exporting a contract requires no live environment values, runtime configuration files, secret decryption, cluster access, database access, or successful application resolution, and never executes an arbitrary default computation to discover its value.
    verification: Export with required inputs missing and runtime paths nonexistent; instrument effectful boundaries and unsafe default computations so any invocation fails the check, while explicitly supplied pure default metadata remains exportable.
  - id: AC-5
    statement: Secret defaults expose availability metadata while their values remain absent or redacted in JSON, text, diagnostics, and failures, including metadata collisions and conflicting declarations.
    verification: Inject secret sentinels into declaration-level and source-based defaults and assert they never appear in any exported or diagnostic output; verify that conflicting sensitivity metadata cannot downgrade protection.
  - id: AC-6
    statement: A documented first-deployment example uses the exported contract to identify external inputs, environment names, public defaults, secret inputs, and deployment-required overrides, then validates proposed inputs through the application's existing check mode.
    verification: Use a notification-hub-shaped fixture with ENVIRONMENT, DATABASE_URL, public endpoint defaults, a defaulted secret, and distinct server and worker checks; show a valid contract without credentials and expected check-mode failures for incomplete proposed inputs.
  - id: AC-7
    statement: Documentation states the contract's uncertainty and validation limits and defines compatibility with the existing describe and explain JSON interfaces.
    verification: Review examples and compatibility tests to confirm the contract does not claim to validate provider credentials, connectivity, Kubernetes resources, arbitrary cross-setting invariants, or deployment wiring merely by being exported, and that existing JSON consumers retain a documented compatibility path.
---

# Export a deployment configuration contract with bindings and defaults

## Problem and originating use case

The first deployment of `mori://tan/notification-hub` needs a Pulumi program in
`mori://tan/tan-app-infrastructure`. The service already declares and validates its
configuration through Settei. The deployment author should be able to discover what
the application accepts, which environment variables supply those settings, what can
be left at a default, and what must be supplied explicitly before writing that program.

Today, `--describe-config-json` exports keys, descriptions, sensitivity, requiredness,
and presence. It does not include environment bindings or default availability and
values. A required declaration means a candidate must exist after source resolution;
it does not mean the deployment must supply the value. An application that puts its
defaults in a separate built-in `Source` can therefore describe nearly every setting
as required while needing only a few external inputs.

This is the shape used by
`mori://tan/notification-hub/packages/notification-hub-core`: configuration
declarations, built-in defaults, and environment bindings are separate program values.
For example, `runtime.environment` binds to `ENVIRONMENT` and defaults to
`development`, whereas `database.url` binds to `DATABASE_URL`, is secret, and has no
built-in default. Copying another service's `HASKELL_ENV` wiring would miss that
contract. A defaulted development webhook secret also needs a deliberate deployment
decision rather than being mistaken for a value suitable for every environment.

`--explain-config-json` shows resolved values and origins, but requires loading and
resolving inputs. It is useful for validating a proposed configuration after authoring;
it does not replace an export available before external inputs have been assembled.

The current Settei boundaries are visible in [schema metadata](../../settei/src/Settei/Schema.hs),
[schema JSON rendering](../../settei/src/Settei/Render.hs),
[default declarations](../../settei/src/Settei/Default.hs), and
[environment binding inspection](../../settei-env/src/Settei/Env.hs).

## Requested outcome

Provide a reusable deployment-contract API with CLI integration that combines the
application's existing declarations, bindings, and explicitly identified default
sources or metadata. The output should be suitable for a deployment checklist or a
tool-generated configuration skeleton without maintaining a second application schema
inside Pulumi. The API name and CLI flag are implementation decisions; this request
does not prescribe a breaking extension to `--describe-config-json`.

For each setting, make the following questions answerable:

- What is its structural key, description, and declared sensitivity?
- Which environment variable names, if any, supply it?
- Is a value required whenever the setting is selected, and is selection conditional?
- Does a default exist, where is it declared, and can its public value be displayed?
- Must the deployment supply a value after accounting for known defaults?
- Does an application-declared deployment profile require an explicit value despite
  an available default?

The application must explicitly identify sources intended to provide defaults. Do not
infer default status from source labels, read arbitrary runtime files, evaluate opaque
functions, or turn a failed default decode into a claim that the setting is covered.
Represent deferred computation, unresolved conditions, and unavailable metadata honestly.
Preserve default ordering where it affects the result. A typed default that lacks a
safe renderer may have known availability without an exported value.

Deployment requirements are distinct from `Required` and `Optional`. An application
may require an explicit environment, endpoint, or secret in a deployment profile even
though local development has a default. Such requirements must be supplied by the
application rather than guessed from key names, example values, or Kubernetes metadata.

## Acceptance and validation boundary

The structured AC-1 through AC-7 conditions above define completion. None is fulfilled
by filing this request. Settei owns the reusable API, safe renderers, CLI integration,
reference fixture, and documentation. Notification-hub and its Pulumi deployment remain
consumer-owned adoption work; this request does not require deploying either project.

The reference workflow must pair discovery with the application's actual check mode.
In `mori://tan/notification-hub/packages/notification-hub-server`, configuration checks
include event-webhook public-key validation. In
`mori://tan/notification-hub/packages/notification-hub-workers`, check mode also validates
worker capacity, replica relationships, and provider-account wiring. Those checks
remain necessary even when a static deployment contract has been exported.

Automatic Pulumi resource generation, Kubernetes schema validation, secret provisioning,
and live infrastructure checks are outside this request. Comparing supplied deployment
environment names with declared bindings is a useful later consumer of the contract;
rejecting unrelated process environment variables is not part of this export.
