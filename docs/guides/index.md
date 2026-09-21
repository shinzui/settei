---
okf_version: "0.2"
---

# Guide

- [Building a CLI application](cli-application.md) - Build a CLI application that layers files, environment variables, overrides, and safe diagnostics with Settei.
- [Dhall configuration](dhall.md) - Load typed Dhall configuration through explicit import policies and resolve it with Settei.
- [Environment and command-line configuration](environment-and-cli.md) - Bind environment variables and command-line overrides explicitly, then render Settei diagnostics safely.
- [Tagged multi-format configuration](formats.md) - Accept explicitly tagged YAML, KDL, and Dhall configuration inputs through one ordered loader.
- [KDL configuration](kdl.md) - Load canonical KDL v2 configuration with precise source spans and resolve it with Settei.
- [Deploying one image across Kubernetes namespaces](kubernetes-cookbook.md) - Deploy one unchanged service image across Kubernetes namespaces with explicit configuration and rollout diagnostics.
- [Building a Kubernetes service](kubernetes-service.md) - Build a Kubernetes service that resolves mounted files and environment variables through Settei.
- [YAML configuration](yaml.md) - Load strict YAML configuration with precise locations and resolve it with Settei.

# Navigation

- [Settei guides](README.md) - Navigate Settei guides for core declarations, supported inputs, and CLI and Kubernetes applications.

# Tutorial

- [Getting started with Settei](getting-started.md) - Build and resolve a typed Settei configuration while preserving provenance and diagnostics.

