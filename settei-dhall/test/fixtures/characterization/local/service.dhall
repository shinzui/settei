let Database = ./database.dhall

in  { host = "api.internal", port = 8080, database = Database }
