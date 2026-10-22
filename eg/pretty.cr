require "../src/jargon"

cli = Jargon.cli("pretty", json: <<-JSON)
  {
    "type": "object",
    "description": "Example CLI that pretty prints parsed arguments as JSON",
    "positional": ["files"],
    "properties": {
      "name": {
        "type": "string",
        "short": "n",
        "description": "Your name"
      },
      "count": {
        "type": "integer",
        "short": "c",
        "default": 1,
        "description": "A count value"
      },
      "verbose": {
        "type": "boolean",
        "short": "v",
        "description": "Enable verbose output"
      },
      "tags": {
        "type": "array",
        "short": "t",
        "description": "List of tags"
      },
      "files": {
        "type": "array",
        "description": "Input files"
      }
    }
  }
  JSON

result = cli.run

unless result.valid?
  STDERR.puts result.errors.join("\n")
  exit 1
end

puts result.to_pretty_json
