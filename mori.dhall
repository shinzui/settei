let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/143b3138e697e211249f094eddaf8248c590a5a0/package.dhall
        sha256:da11f2da781dca8824039c41ef27177193c060099800221c490d961fd07061c2

in  Schema.Project::{
    , project = Schema.ProjectIdentity::{
      , name = "settei"
      , namespace = "shinzui"
      , type = Schema.PackageType.Library
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Experimental
      , description = Some "Typed, layered, provenance-aware configuration for Haskell"
      , domains = [ "Configuration", "Haskell" ]
      , owners = [ "shinzui" ]
      }
    , repos = [ Schema.Repo::{ name = "settei", github = Some "shinzui/settei" } ]
    , packages =
      [ Schema.Package::{
        , name = "settei"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "settei"
        , description = Some "Inspectable configuration algebra, resolution, provenance, defaults, and reporting"
        }
      , Schema.Package::{
        , name = "settei-dhall"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "settei-dhall"
        , description = Some "Typed Dhall sources with enforceable import policies and honest import provenance"
        , dependencies = [ Schema.Dependency.ByName "settei" ]
        }
      , Schema.Package::{
        , name = "settei-env"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "settei-env"
        , description = Some "Environment-variable sources for Settei"
        , dependencies = [ Schema.Dependency.ByName "settei" ]
        }
      , Schema.Package::{
        , name = "settei-formats"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "settei-formats"
        , description = Some "Tagged multi-format configuration inputs and a shared adapter loader for Settei"
        , dependencies =
          [ Schema.Dependency.ByName "settei"
          , Schema.Dependency.ByName "settei-dhall"
          , Schema.Dependency.ByName "settei-kdl"
          , Schema.Dependency.ByName "settei-optparse-applicative"
          , Schema.Dependency.ByName "settei-yaml"
          ]
        }
      , Schema.Package::{
        , name = "settei-kdl"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "settei-kdl"
        , description = Some "Canonical span-preserving KDL v2 sources for Settei"
        , dependencies = [ Schema.Dependency.ByName "settei" ]
        }
      , Schema.Package::{
        , name = "settei-kubernetes"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "settei-kubernetes"
        , description = Some "Kubernetes mounted-directory (projected volume) sources for Settei"
        , dependencies =
          [ Schema.Dependency.ByName "settei"
          , Schema.Dependency.ByName "settei-env"
          ]
        }
      , Schema.Package::{
        , name = "settei-optparse-applicative"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "settei-optparse-applicative"
        , description = Some "optparse-applicative configuration sources for Settei"
        , dependencies = [ Schema.Dependency.ByName "settei" ]
        }
      , Schema.Package::{
        , name = "settei-yaml"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "settei-yaml"
        , description = Some "Strict location-preserving YAML sources for Settei"
        , dependencies = [ Schema.Dependency.ByName "settei" ]
        }
      , Schema.Package::{
        , name = "settei-example-cli"
        , type = Schema.PackageType.Application
        , language = Schema.Language.Haskell
        , path = Some "examples/settei-cli"
        , description = Some "Layered command-line reference application for Settei"
        , visibility = Schema.Visibility.Internal
        , dependencies =
          [ Schema.Dependency.ByName "settei"
          , Schema.Dependency.ByName "settei-dhall"
          , Schema.Dependency.ByName "settei-env"
          , Schema.Dependency.ByName "settei-kdl"
          , Schema.Dependency.ByName "settei-optparse-applicative"
          , Schema.Dependency.ByName "settei-yaml"
          ]
        }
      , Schema.Package::{
        , name = "settei-example-service"
        , type = Schema.PackageType.Application
        , language = Schema.Language.Haskell
        , path = Some "examples/settei-service"
        , description = Some "Kubernetes-shaped reference service for Settei"
        , visibility = Schema.Visibility.Internal
        , dependencies =
          [ Schema.Dependency.ByName "settei"
          , Schema.Dependency.ByName "settei-env"
          , Schema.Dependency.ByName "settei-formats"
          , Schema.Dependency.ByName "settei-kubernetes"
          , Schema.Dependency.ByName "settei-optparse-applicative"
          , Schema.Dependency.ByName "settei-yaml"
          ]
        }
      , Schema.Package::{
        , name = "settei-example-conformance"
        , type = Schema.PackageType.Other "TestSuite"
        , language = Schema.Language.Haskell
        , path = Some "examples/settei-conformance"
        , description = Some "Cross-format value, provenance, ordering, and redaction conformance suite"
        , visibility = Schema.Visibility.Internal
        , dependencies =
          [ Schema.Dependency.ByName "settei"
          , Schema.Dependency.ByName "settei-dhall"
          , Schema.Dependency.ByName "settei-env"
          , Schema.Dependency.ByName "settei-example-cli"
          , Schema.Dependency.ByName "settei-example-service"
          , Schema.Dependency.ByName "settei-kdl"
          , Schema.Dependency.ByName "settei-yaml"
          ]
        }
      ]
    }
