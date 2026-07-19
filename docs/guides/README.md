# Settei guides

These guides show how to add Settei to a Haskell application, declare typed settings,
load configuration from supported inputs, and expose safe diagnostics to developers and
operators.

Start with [Getting started](getting-started.md). It covers the core `settei` package and
the complete declaration-to-resolution workflow. Then choose the source adapters and
application guide that match your program:

| Guide | Use it when |
| --- | --- |
| [Getting started](getting-started.md) | You are adding Settei to an application or learning its core types. |
| [Environment and command-line configuration](environment-and-cli.md) | You need explicit environment bindings, `--set` overrides, or configuration diagnostics. |
| [YAML configuration](yaml.md) | You want strict YAML files with line and column provenance. |
| [KDL configuration](kdl.md) | You want KDL v2 files with exact source spans. |
| [Dhall configuration](dhall.md) | You want typed Dhall input with an explicit import policy. |
| [Building a CLI application](cli-application.md) | You are assembling files, environment variables, overrides, and exit behavior in a command-line program. |
| [Building a Kubernetes service](kubernetes-service.md) | You are loading mounted configuration and Secret-backed environment variables in a service. |

All source lists in these guides are ordered from lowest to highest precedence. A later
source wins for a key, while Settei retains the earlier origins for explanations.

For security guarantees and format-independent operational guidance, also read the
[security model](../security.md). Supported compiler and dependency ranges are listed in
the [compatibility matrix](../compatibility.md).
