# Upgrade a Settei consumer

Settei's nine public packages release under one shared version with exact intra-family
pins: settei, settei-env, settei-dhall, settei-kdl, settei-yaml, settei-kubernetes,
settei-optparse-applicative, settei-preflight, and settei-formats. Move every family
package this consumer depends on together; mixed versions are unsupported.

Inspect real declarations and decoders, file and environment sources, optparse-applicative
diagnostic dispatch, validators, deployment contracts, and preflight call sites before
editing. Search for added constructors in exhaustive matches: `-Wall` only warns about
incomplete patterns. Change only the surfaces named by this edge and preserve unrelated
work. Use the project's own build and tests to prove the migration.

Import supported public modules such as `Settei` and `Settei.Optparse`; never import
`Settei.Prelude` or `Settei.Internal` from consumer code. Never print or log the typed
configuration, raw credentials, environment values, or full command-line arguments.
Typed configurations retain real secrets; render reports through Settei's safe renderers.
