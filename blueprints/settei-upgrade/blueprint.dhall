let S =
      https://raw.githubusercontent.com/shinzui/seihou-schema/49ff1e5b353b171b1b52946f478623ee4423ea93/package.dhall
        sha256:cadacb688dd31ec39feb7f2fe599973a1ad58ef8fcc8ed1100bf3da22a1222cb

in  S.Blueprint::{
    , name = "settei-upgrade"
    , version = Some "0.1.0"
    , description = Some
        "Upgrade guidance for Settei consumers: one agent-guided edge per released version window that needs judgement work"
    , prompt = ./prompt.md as Text
    , versionProbe = Some
        "jq -r '.\"install-plan\"[] | select(.\"pkg-name\"==\"settei\") | .\"pkg-version\"' dist-newstyle/cache/plan.json 2>/dev/null | sort -u | tail -1 | grep ."
    , allowedTools = Some [ "Bash(cabal *)", "Bash(rg *)" ]
    , files =
      [ S.Blueprint.BlueprintFile::{
        , src = "checked-dispatch.md"
        , description = Some "Before-and-after diagnostic dispatch for the 0.3.0.0 checked boundary"
        }
      ]
    , migrations =
      [ S.BlueprintMigration::{
        , from = "0.2.0.0"
        , to = "0.3.0.0"
        , prompt = ./migrations/0.2.0.0-to-0.3.0.0.md as Text
        }
      ]
    , tags = [ "haskell", "configuration", "settei", "migration" ]
    }
