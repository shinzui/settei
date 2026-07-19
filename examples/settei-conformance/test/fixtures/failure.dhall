{ runtime = { environment = "development" }
, http = { host = "0.0.0.0", port = 7000 }
, database = { port = 5433, poolSize = 7 }
, service =
    { tags = [ "api", "public" ]
    , endpoint = "https://api.example"
    , timeout = 30
    }
, output = { format = "text" }
}
