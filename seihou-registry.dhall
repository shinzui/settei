{ repoName = "settei"
, repoDescription = Some
    "Typed, inspectable configuration with safe diagnostics for Haskell"
, modules =
  [] : List
       { name : Text
       , version : Optional Text
       , path : Text
       , description : Optional Text
       , tags : List Text
       }
, recipes =
  [] : List
       { name : Text
       , version : Optional Text
       , path : Text
       , description : Optional Text
       , tags : List Text
       }
, blueprints =
  [ { name = "settei-upgrade"
    , version = Some "0.1.0"
    , path = "blueprints/settei-upgrade"
    , description = Some
        "Upgrade guidance for Settei consumers: one agent-guided edge per released version window that needs judgement work"
    , tags = [ "haskell", "configuration", "settei", "migration" ]
    }
  ]
, prompts =
  [] : List
       { name : Text
       , version : Optional Text
       , path : Text
       , description : Optional Text
       , tags : List Text
       }
}
