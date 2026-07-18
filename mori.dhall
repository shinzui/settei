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
        , name = "settei-env"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "settei-env"
        , description = Some "Environment-variable sources for Settei"
        }
      , Schema.Package::{
        , name = "settei-kdl"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "settei-kdl"
        , description = Some "Canonical span-preserving KDL v2 sources for Settei"
        }
      , Schema.Package::{
        , name = "settei-optparse-applicative"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "settei-optparse-applicative"
        , description = Some "optparse-applicative configuration sources for Settei"
        }
      , Schema.Package::{
        , name = "settei-yaml"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "settei-yaml"
        , description = Some "Strict location-preserving YAML sources for Settei"
        }
      ]
    }
