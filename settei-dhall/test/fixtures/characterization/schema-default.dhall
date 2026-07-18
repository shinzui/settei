let Input = { name : Text }

let Output = { name : Text, description : Optional Text, tags : List Text }

let default : { description : Optional Text, tags : List Text } =
      { description = None Text, tags = [] : List Text }

let make = \(input : Input) -> default // input

let value : Output = make { name = "my-service" }

in  { service = value }
