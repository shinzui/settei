# libyaml 0.1.4 characterization

Settei uses `Text.Libyaml.decodeMarked` from `libyaml` 0.1.4 rather than converting
through `Data.Aeson.Value`. Direct inspection of `yaml` 0.11.11.2 showed that its common
`decodeEither'` entry point discards duplicate-key warnings, while `decodeMarked` retains
every mapping pair and one zero-based start and end mark per parser event.

The `Settei.Yaml.Characterization` tests prove the supported boundary. Block and flow
duplicates fail at the second key. Syntax errors and successful values retain marks, which
the public adapter reports as one-based positions. Multiple documents, anchors, aliases,
merge keys, custom tags, and non-string keys fail explicitly. Scalars support null,
YAML 1.2 core-schema booleans (`true`/`false` only, case-insensitive), exact finite
numbers, strings, arrays, and ordinary string-keyed mappings.

These fixtures are small review artifacts matching the inline executable cases:

- `duplicate-block.yaml` and `duplicate-flow.yaml` contain ambiguous mappings.
- `multiple-documents.yaml` contains two documents that must not be collapsed.
- `alias.yaml`, `merge-key.yaml`, and `custom-tag.yaml` exercise deliberately unsupported
  YAML graph and extension features.
- `nested.yaml` is the supported location and translation baseline.
