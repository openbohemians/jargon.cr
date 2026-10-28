# Jargon

[![CI](https://github.com/openbohemians/jargon.cr/actions/workflows/ci.yml/badge.svg)](https://github.com/openbohemians/jargon.cr/actions/workflows/ci.yml)

*Define your CLI jargon with JSON Schema.*

A Crystal library that generates CLI interfaces from JSON Schema definitions. Define your data structure once in JSON Schema, get a CLI parser with validation for free.

Jargon is also available for Rust, as [jargon.rs](https://github.com/openbohemians/jargon.rs). The project's site is [jargon.openbohemians.org](https://jargon.openbohemians.org), and the API docs are at [openbohemians.org/jargon.cr](https://openbohemians.org/jargon.cr/).

## Features

- **Validation**: Required fields, enum values, strict type checking, `additionalProperties`
- **Standalone validator**: Use `Jargon::Validator` to validate data without the CLI parser
- **Defaults**: Schema defaults, config file defaults, environment variables
- **Config files**: Load from `~/.config/` (XDG spec), optionally project `.config/`, with deep merge support, sections for subcommands, and any format you add
- **Help text**: Generated from schema descriptions
- **Auto help flags**: `--help` and `-h` detected automatically
- **Shell completions**: Generate completion shims for bash, zsh, and fish, with optional app-driven dynamic completers for live data
- **Positional args**: Non-flag arguments assigned by position and variadic support.
- **Short flags**: Single-character flag aliases (`-v`, `-n 5`), combined as getopt combines them (`-vn5`)
- **Boolean flags**: Support both `--verbose` and `--verbose false` styles
- **Subcommands**: Named sub-parsers with independent schemas (supports abbreviated invocations)
- **Default subcommand**: Fall back to a subcommand when none specified
- **Stdin JSON**: Read arguments as JSON from stdin with `-`
- **Typo suggestions**: "Did you mean?" for mistyped options
- **$ref support**: Reuse definitions with `$ref: "#/$defs/typename"`
- **Extension annotations**: `x-*` keys pass through untouched for GUI/tooling consumers

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  jargon:
    github: openbohemians/jargon.cr
```

Then run `shards install`.

## Usage

```crystal
require "jargon"

# Define your schema
schema = %({
  "type": "object",
  "properties": {
    "name": {"type": "string", "description": "User name"},
    "age": {"type": "integer"},
    "verbose": {"type": "boolean"}
  },
  "required": ["name"]
})

# Create CLI and run
cli = Jargon.cli("myapp", json: schema)
cli.run do |result|
  puts result.to_pretty_json
end
```

The `run` method automatically handles:
- `--help` / `-h`: prints help and exits
- `--completions <shell>`: prints shell completion script and exits
- Validation errors: prints errors to STDERR and exits with code 1

## YAML Schemas

YAML schemas are supported directly:

```yaml
# schema.yaml
type: object
properties:
  name:
    type: string
    description: User name
  verbose:
    type: boolean
    short: v
required:
  - name
```

```crystal
schema = File.read("schema.yaml")
cli = Jargon.cli("myapp", yaml: schema)
```

YAML (schemas and config files alike) is read by the YAML 1.1 core schema, as `YAML.parse` reads it (`yes` is true, `0x1F` is 31), except that a date or time stays the string it was written as: `default: 2026-10-22` is `"2026-10-22"`.

## Argument Styles

Two styles are supported interchangeably:

```sh
# Equals style (minimal)
myapp name=John age=30 verbose=true

# Traditional style
myapp --name John --age 30 --verbose
```

Mix and match as you like:
```sh
myapp name=John --age 30 verbose=true
```

Only `=` separates a key from its value. A colon has no special meaning, so
operands like `host:8080`, `12:30`, `Expenses:Food`, or JSON such as
`{"id":1}` are always ordinary tokens.

The bare `key=value` style (no leading dashes) is an *implicit assignment*
convenience. If your operands legitimately contain `=` — say, `name=value`
pairs passed through to another tool — you can turn the implicit assignment
off so those tokens are always taken literally:

```crystal
cli = Jargon.cli("myapp", json: schema)
cli.bare_assignment(false)   # only --flag / --flag=value set properties now
```

With it off, a bare `key=value` token is never read as an assignment: it falls
to positional capture if a slot is open, otherwise it's an unexpected argument.
The `--flag=value` long-option form is unaffected and always honored. (Note that
an open positional slot already captures `=`-bearing operands literally, so
this switch only governs the implicit-assignment fallback.)

## Nested Objects

Use dot notation for nested properties:

```crystal
schema = %({
  "type": "object",
  "properties": {
    "user": {
      "type": "object",
      "properties": {
        "name": {"type": "string"},
        "email": {"type": "string"}
      }
    }
  }
})

cli = Jargon.cli("myapp", json: schema)
result = cli.parse(["user.name=John", "user.email=john@example.com"])
# => {"user": {"name": "John", "email": "john@example.com"}}
```

## Supported Types

| JSON Schema Type | CLI Example | Notes |
|------------------|-------------|-------|
| `string` | `name=John` | Default type |
| `integer` | `count=42` | Parsed as Int64, strict validation |
| `number` | `rate=3.14` | Parsed as Float64, strict validation |
| `boolean` | `verbose=true` or `--verbose` | Flag style supported |
| `array` | `tags=a,b,c` | Comma-separated, and each time it's given adds to it (`-I a -I b`); variadic positionals coerce items to the `items` type |
| `object` | `user.name=John` | Dot notation |

### Validation Constraints

Standard JSON Schema validation keywords are supported:

```json
{
  "properties": {
    "port": {"type": "integer", "minimum": 1, "maximum": 65535},
    "ratio": {"type": "number", "exclusiveMinimum": 0, "exclusiveMaximum": 1},
    "password": {"type": "string", "minLength": 8, "maxLength": 64},
    "email": {"type": "string", "format": "email"},
    "website": {"type": "string", "format": "uri"},
    "config": {"type": "string", "format": "path"},
    "level": {"type": "string", "enum": ["debug", "info", "warn", "error"]},
    "files": {"type": "array", "minItems": 1, "maxItems": 10, "uniqueItems": true},
    "apiVersion": {"type": "string", "const": "v1"},
    "tags": {
      "type": "array",
      "items": {"type": "string", "enum": ["alpha", "beta", "stable"]}
    }
  }
}
```

- `minimum`/`maximum`: numeric range (inclusive)
- `exclusiveMinimum`/`exclusiveMaximum`: numeric range (exclusive)
- `multipleOf`: value must be divisible by this number
- `minLength`/`maxLength`: string length
- `minItems`/`maxItems`: array length
- `uniqueItems`: no duplicate values in array
- `pattern`: regex validation for strings. As in JSON Schema, `$` matches only at the end of the value, not before a final newline
- `format`: semantic formats (`email`, `uri`, `uuid`, `date`, `time`, `date-time`, `ipv4`, `ipv6`, `hostname`, `path`). The `path` format expands `~` to the user's home directory
- `enum`: allowed values (works for array items too)
- `const`: exact value match
- `additionalProperties`: when `false`, rejects unknown keys in objects
- `service`: when `true`, marks the command as a long-running service (UI hint for consumers)
- `x-*`: any key starting with `x-` is preserved verbatim as an extension annotation (see [Extension Annotations](#extension-annotations-x-))

### Boolean Flags

Boolean flags support multiple styles:

```sh
# Flag style (sets to true)
myapp --verbose

# Explicit value
myapp --verbose true
myapp --verbose false
myapp --enabled no

# Equals style
myapp verbose=true
myapp --verbose=false
```

Recognized boolean values: `true`/`false`, `yes`/`no`, `on`/`off`, `1`/`0` (case-insensitive).

When a boolean flag is followed by a non-boolean value, the value is not consumed:

```sh
# --verbose is true, output.txt is a positional arg
myapp --verbose output.txt
```

### Strict Numeric Validation

Invalid numeric values produce clear error messages:

```sh
$ myapp --count abc
Error: Invalid integer value 'abc' for count

$ myapp --count 10x
Error: Invalid integer value '10x' for count
```

### Typo Suggestions

Mistyped options get helpful "did you mean?" suggestions:

```sh
$ myapp --verbos
Error: Unknown option '--verbos'. Did you mean '--verbose'?

$ myapp --formt json
Error: Unknown option '--formt'. Did you mean '--format'?
```

## Positional Arguments

Define positional arguments with the `positional` array:

```crystal
schema = %({
  "type": "object",
  "positional": ["file", "output"],
  "properties": {
    "file": {"type": "string", "description": "Input file"},
    "output": {"type": "string", "description": "Output file"},
    "verbose": {"type": "boolean"}
  },
  "required": ["file"]
})

cli = Jargon.cli("myapp", json: schema)
result = cli.parse(["input.txt", "output.txt", "--verbose"])
# => {"file": "input.txt", "output": "output.txt", "verbose": true}
```

```sh
myapp input.txt output.txt --verbose
```

### Variadic Positionals

When the last positional has `type: array`, it collects all remaining arguments:

```crystal
schema = %({
  "type": "object",
  "positional": ["files"],
  "properties": {
    "files": {"type": "array", "description": "Input files"},
    "number": {"type": "boolean", "short": "n"}
  }
})

cli = Jargon.cli("cat", json: schema)
result = cli.parse(["-n", "a.txt", "b.txt", "c.txt"])
# => {"number": true, "files": ["a.txt", "b.txt", "c.txt"]}
```

```sh
cat -n a.txt b.txt c.txt
```

A variadic positional is **greedy**: it captures every remaining token
literally, including ones that look like assignments (`k=v`) or negative
numbers (`-50`). It stops only at a genuine
flag, so put flags before the variadic:

```sh
cat -n a.txt b.txt c.txt      # ok: flag first
cat a.txt -n b.txt            # -n stops collection; b.txt is then unexpected
```

A lone `-` is a value, not a flag, so `cat a.txt - b.txt` collects it with
the rest, as the conventional name for standard input. Only a `-` that is
the whole command line reads JSON (see [JSON from Stdin](#json-from-stdin)).

When the array declares an `items` type, each collected token is coerced to it:

```crystal
schema = %({
  "type": "object",
  "positional": ["values"],
  "properties": {
    "values": {"type": "array", "items": {"type": "number"}}
  }
})

cli = Jargon.cli("stats", json: schema)
result = cli.parse(["1", "-50", "3.14"])
# => {"values": [1.0, -50.0, 3.14]}
```

### Negative Numbers

A token like `-50` or `-3.14` is treated as a value, not a flag — so negative
numbers work as flag values (`--offset -50`), as scalar positionals, and inside
variadic positionals. Only `-<letter>` tokens are parsed as short flags, so a
short flag is never confused with a negative number.

### End of Options (`--`)

A bare `--` marks the end of options (POSIX convention). Everything after it is treated as a positional argument, even if it looks like a flag — useful for passing flags through to another program. The `--` marker itself is discarded, and a variadic positional captures the rest verbatim:

```crystal
schema = %({
  "type": "object",
  "positional": ["argv"],
  "properties": {
    "verbose": {"type": "boolean", "short": "v"},
    "argv": {"type": "array"}
  }
})

cli = Jargon.cli("run", json: schema)
result = cli.parse(["--verbose", "--", "ls", "-la", "--color"])
# => {"verbose": true, "argv": ["ls", "-la", "--color"]}
```

Options before `--` parse normally; only the first `--` is special (a second one is a literal operand).

## Short Flags

Define short flag aliases with the `short` property:

```crystal
schema = %({
  "type": "object",
  "properties": {
    "verbose": {"type": "boolean", "short": "v"},
    "count": {"type": "integer", "short": "n"},
    "output": {"type": "string", "short": "o"}
  }
})

cli = Jargon.cli("myapp", json: schema)
result = cli.parse(["-v", "-n", "5", "-o", "out.txt"])
# => {"verbose": true, "count": 5, "output": "out.txt"}
```

```sh
myapp -v -n 5 -o out.txt
myapp -vn5 -oout.txt                         # equivalent
myapp --verbose --count 5 --output out.txt  # equivalent
```

Short flags combine as getopt combines them: each letter is a flag until one
that takes a value, which takes the rest of the word (`-vn5`), or the next
argument when it ends the word (`-vn 5`). An `=` there is part of the value,
as in getopt, so `-o=x` gives `=x`; `--output=x` gives `x`.

An option given more than once keeps its last value, unless it's an array,
which collects each one's items: `-I '*.o' -I '*.a'` gives
`["*.o", "*.a"]`.

## Help Flags

Jargon automatically detects `--help` and `-h` flags. When using `run`, help is printed and the program exits automatically:

```crystal
cli = Jargon.cli("myapp", json: schema)
cli.run do |result|
  # This block only runs if --help was NOT passed
  puts result.to_pretty_json
end
```

```sh
myapp --help           # top-level help
myapp -h               # same
myapp fetch --help     # subcommand help
myapp config set -h    # nested subcommand help
```

If you need manual control, use `parse` instead:

```crystal
result = cli.parse(ARGV)

if result.help_requested?
  if subcmd = result.help_subcommand
    puts cli.help(subcmd)
  else
    puts cli.help
  end
  exit 0
end
```

If you define a `help` property or use `-h` as a short flag for something else, Jargon won't intercept those flags:

```crystal
# User-defined help property takes precedence
schema = %({
  "type": "object",
  "properties": {
    "help": {"type": "string", "description": "Help topic"},
    "host": {"type": "string", "short": "h"}
  }
})

cli = Jargon.cli("myapp", json: schema)
result = cli.parse(["--help", "topic"])
result.help_requested?  # => false
result["help"].as_s     # => "topic"

result = cli.parse(["-h", "localhost"])
result["host"].as_s     # => "localhost"
```

## Shell Completions

Jargon can generate shell completion scripts for bash, zsh, and fish. When using `run`, the `--completions <shell>` flag is handled automatically.

The generated scripts are small, fixed **shims**: on every Tab they forward the cursor position and typed words back to your program (a hidden `__complete` verb that `run` and `handle_completion` recognize), and the program computes the candidates from the schema. This means one code path serves both static completion (subcommand names, flags, enum values) and [dynamic completion](#dynamic-completions) (live data only your app knows) — and the installed script never needs regenerating when your CLI changes.

### Installing Completions

Generate the completion shim once and save it to your shell's completions directory:

```sh
# Bash
myapp --completions bash > ~/.local/share/bash-completion/completions/myapp

# Zsh (ensure ~/.zfunc is in your fpath)
myapp --completions zsh > ~/.zfunc/_myapp

# Fish
myapp --completions fish > ~/.config/fish/completions/myapp.fish
```

Out of the box you get completion for subcommand names (including nested), long and short flags, and `enum` values (both `--mode <Tab>` and `--mode=<Tab>`) — all derived from the schema, no extra code. Values containing `:` (`Expenses:Food`) complete as whole words in every shell, including bash, where the shim undoes readline's splitting at `=` and `:`.

### Dynamic Completions

For values the schema can't know — a document name, a tag, a key in a live store — register a **completer** against a field. It runs inside your program at completion time and returns the candidates:

```crystal
cli = Jargon.cli("transfs", yaml: schema)

# Field path: the field name for a flat CLI, or `subcommand.field`
# (`a.b.field` when nested). Raises if the path isn't a real field.
cli.completer("forget.query") do |ctx|
  store.search(ctx.partial).map(&.name)   # candidates (Array(String))
end

cli.run { |result| ... }   # `run` answers the __complete verb automatically
```

The block receives a `Completion::Context`:

| Field | Description |
|-------|-------------|
| `ctx.partial` | the token being completed (use it to scope your query) |
| `ctx.subcommand` | the resolved subcommand path, or `nil` at top level |
| `ctx.arguments` | a lenient parse of what's already typed, for filtering |
| `ctx.words` | the raw tokens, as an escape hatch |

A registered field completes dynamically; everything else stays static. You never write the `__complete` verb yourself — the shim supplies it.

#### Answering completion from a separate binary

Each Tab spawns whatever the shim calls. If your main program is heavy to start, point the shim at a small dedicated binary instead of paying full startup per keypress:

```crystal
# generate a shim that calls `transfs-complete` rather than `transfs`
File.write(path, cli.bash_completion(command: "transfs-complete"))
```

```crystal
# transfs-complete.cr — a minimal helper that only answers completion
cli = build_cli
cli.completer("forget.query") { |ctx| index.search(ctx.partial) }
exit cli.handle_completion   # answers __complete and exits
```

`handle_completion` returns immediately for a normal invocation, so you can also call it at the very top of your existing `main` to answer completion *before* heavy initialization runs, without a second binary. (The separate-binary win only materializes if your candidate source has a light access path — an on-disk index, a cache, a daemon — rather than requiring the full app to boot.)

### Manual Completion Handling

If you need manual control, use `parse`:

```crystal
cli = Jargon.cli("myapp", json: schema)
result = cli.parse(ARGV)

if result.completion_requested?
  case result.completion_shell
  when "bash" then puts cli.bash_completion
  when "zsh"  then puts cli.zsh_completion
  when "fish" then puts cli.fish_completion
  end
  exit 0
end
```

## Subcommands

Create CLIs with subcommands, each with their own schema:

```crystal
cli = Jargon.new("myapp")

cli.subcommand("fetch", json: %({
  "type": "object",
  "positional": ["url"],
  "properties": {
    "url": {"type": "string", "description": "Resource URL"},
    "depth": {"type": "integer", "short": "d"}
  },
  "required": ["url"]
}))

cli.subcommand("save", json: %({
  "type": "object",
  "properties": {
    "message": {"type": "string", "short": "m"},
    "all": {"type": "boolean", "short": "a"}
  },
  "required": ["message"]
}))

cli.run do |result|
  case result.subcommand
  when "fetch"
    url = result["url"].as_s
    depth = result["depth"]?.try(&.as_i64)
  when "save"
    message = result["message"].as_s
    all = result["all"]?.try(&.as_bool) || false
  end
end
```

```sh
myapp fetch https://example.com/resource -d 1
myapp save -m "Updated config" -a
```

### Nested Subcommands

Create nested subcommands by passing a `CLI` instance as the subcommand:

```crystal
config = Jargon.new("config")
config.subcommand("set", json: %({
  "type": "object",
  "positional": ["key", "value"],
  "properties": {
    "key": {"type": "string"},
    "value": {"type": "string"}
  },
  "required": ["key", "value"]
}))
config.subcommand("get", json: %({
  "type": "object",
  "positional": ["key"],
  "properties": {
    "key": {"type": "string"}
  }
}))

cli = Jargon.new("myapp")
cli.subcommand("config", config)
cli.subcommand("status", json: %({"type": "object", "properties": {}}))

cli.run do |result|
  case result.subcommand
  when "config set"
    key = result["key"].as_s
    value = result["value"].as_s
  when "config get"
    key = result["key"].as_s
  when "status"
    # ...
  end
end
```

```sh
myapp config set api_url https://api.example.com
myapp config get api_url
myapp status
```

The `result.subcommand` returns the full path as a space-separated string (e.g., `"config set"`).

### Default Subcommand

Set a default subcommand to use when no subcommand name is given:

```crystal
cli = Jargon.new("xerp")

cli.subcommand("index", json: %({...}))
cli.subcommand("query", json: %({
  "type": "object",
  "positional": ["query_text"],
  "properties": {
    "query_text": {"type": "string"},
    "top": {"type": "integer", "default": 10, "short": "n"}
  }
}))

cli.default_subcommand("query")
```

```sh
# These are equivalent:
xerp query "search term" -n 5
xerp "search term" -n 5
```

Note: If the first argument matches a subcommand name, it's treated as a subcommand, not as input to the default. Use the explicit form if you need to search for a term that matches a subcommand name.

### Subcommand Abbreviations

Subcommands can be abbreviated to any unique prefix (minimum 3 characters):

```sh
$ myapp checkout main   # full name
$ myapp check main      # abbreviated (if unambiguous)
$ myapp che main        # still works

$ myapp ch main         # too short (< 3 chars) - error
$ myapp co main         # ambiguous (commit? config?) - error
```

### Global Options

Use `Jargon.merge` to add common options to all subcommands:

```crystal
global = %({
  "type": "object",
  "properties": {
    "verbose": {"type": "boolean", "short": "v", "description": "Verbose output"},
    "config": {"type": "string", "short": "c", "description": "Config file path"}
  }
})

cli = Jargon.new("myapp")

cli.subcommand("fetch", json: Jargon.merge(%({
  "type": "object",
  "positional": ["url"],
  "properties": {
    "url": {"type": "string"},
    "depth": {"type": "integer", "short": "d"}
  }
}), global))

cli.subcommand("sync", json: Jargon.merge(%({
  "type": "object",
  "properties": {
    "force": {"type": "boolean", "short": "f"}
  }
}), global))
```

```sh
myapp fetch https://example.com/data -v
myapp sync --force --config myconfig.json
```

Subcommand properties take precedence if there's a conflict with global properties.

### File-Based Subcommands

Load subcommands from external files for cleaner organization:

```crystal
cli = Jargon.new("myapp")
cli.subcommand("fetch", file: "schemas/fetch.yaml")
cli.subcommand("save", file: "schemas/save.json")
```

Or define all subcommands in a single multi-document file:

```yaml
# commands.yaml
---
name: fetch
type: object
properties:
  url: {type: string}
---
name: save
type: object
properties:
  file: {type: string}
```

```crystal
# Load as top-level subcommands
cli = Jargon.cli("myapp", file: "commands.yaml")
# or
cli = Jargon.new("myapp")
cli.subcommand(file: "commands.yaml")
```

Load multi-doc as nested subcommands by providing a parent name:

```crystal
cli = Jargon.new("myapp")
cli.subcommand("config", file: "config_commands.yaml")  # config get, config set, etc.
```

Multi-document format is auto-detected for `json:`, `yaml:`, and `file:` parameters. Each document must have a `name` field.

JSON uses relaxed JSONL (consecutive objects with whitespace):

```json
{
  "name": "fetch",
  "type": "object",
  "properties": {"url": {"type": "string"}}
}
{
  "name": "save",
  "type": "object",
  "properties": {"file": {"type": "string"}}
}
```

### Schema Mixins

Share properties across subcommands using standard JSON Schema `$id`, `$ref`, and `allOf`:

```yaml
---
$id: global
properties:
  verbose: {type: boolean, short: v}
  config: {type: string, short: c}
---
$id: output
properties:
  format: {type: string, enum: [json, yaml, csv]}
---
name: fetch
allOf:
  - {$ref: global}
  - properties:
      url: {type: string}
---
name: export
allOf:
  - {$ref: global}
  - {$ref: output}
  - properties:
      file: {type: string}
```

- Schemas with `$id` (no `name`) are mixins - not registered as subcommands
- `$ref` in `allOf` resolves to mixins defined in the same file
- Properties are merged; `type: object` is inferred if missing
- `required` lists are unioned across every mixin and the subcommand itself
- Subcommands explicitly opt-in via `allOf`

This approach uses standard JSON Schema keywords while keeping mixin definitions alongside subcommands in a single file.

Note that Jargon *flattens* `allOf` rather than evaluating it as a true conjunction: if the same property is defined in more than one subschema, the last definition wins. Strict JSON Schema would intersect the constraints instead. This rarely matters for CLI schemas, but it is a deliberate approximation.

### JSON from Stdin

Use `-`, alone after the program or subcommand, to read JSON input from
stdin:

```sh
# JSON with subcommand field
echo '{"subcommand": "query", "query_text": "search term", "top": 5}' | xerp -

# JSON args for explicit subcommand
echo '{"result_id": "abc123", "useful": true}' | xerp mark -
```

If no `subcommand` field is present in `xerp -`, the default subcommand is used (if set).

The field name is configurable:

```crystal
cli.subcommand_key("op")  # default is "subcommand"
```

```sh
echo '{"op": "query", "query_text": "search"}' | xerp -
```

## Environment Variables

Map schema properties to environment variables with the `env` property:

```crystal
schema = %({
  "type": "object",
  "properties": {
    "api-key": {"type": "string", "env": "MY_APP_API_KEY"},
    "host": {"type": "string", "env": "MY_APP_HOST", "default": "localhost"},
    "debug": {"type": "boolean", "env": "MY_APP_DEBUG"}
  }
})

cli = Jargon.cli("myapp", json: schema)
cli.run do |result|
  # result contains api-key, host from env, debug from CLI
end
```

```sh
export MY_APP_API_KEY=secret123
export MY_APP_HOST=prod.example.com
myapp --debug  # api-key and host from env, debug from CLI
```

Merge order (highest priority first):
1. CLI arguments
2. Environment variables
3. Config file defaults
4. Schema defaults

Nested objects merge key by key, so `--server.port 1` overrides only that key
and keeps a `server.host` from the config file. Parsing never modifies the
`defaults:` you pass in.

## Config Files

Load configuration from standard XDG locations with `load_config`. Supports YAML and JSON, and
any format you add (see [Other Formats](#other-formats)):

```crystal
cli = Jargon.cli("myapp", json: schema)
config = cli.load_config  # Returns JSON::Any or nil
cli.run(defaults: config) do |result|
  # ...
end
```

Paths searched (merged by default, or first found wins with `merge: false`):
1. `./.config/myapp.yaml` / `.yml` / `.json` (project local, `project: true` only)
2. `./.config/myapp/config.yaml` / `.yml` / `.json` (project local, directory style, `project: true` only)
3. `$XDG_CONFIG_HOME/myapp.yaml` / `.yml` / `.json` (user global, typically `~/.config`)
4. `$XDG_CONFIG_HOME/myapp/config.yaml` / `.yml` / `.json` (user global, directory style)

YAML is preferred over JSON when both exist at the same location, and an added
format over both. An empty or
relative `$XDG_CONFIG_HOME` is ignored in favor of `~/.config`, as the XDG spec
requires.

### Project-Local Configs

By default only the user's own config is read. Project-local configs are opt-in:

```crystal
config = cli.load_config(project: true)
```

They are off by default because they are read from the *current directory*
and take precedence over the user's config. Running your tool inside a
directory someone else controls, such as a freshly cloned repository, would
otherwise let that directory set any option your schema defines. Opt in when
per-project settings are the point (a formatter's style rules, a build tool's
targets), and think twice if an option can point the tool at a server, a
credential, or a command to run.

When enabled, configs are deep-merged with project overriding user:

```crystal
# Merge all found configs (default) - project wins over user
config = cli.load_config(project: true)

# Or first-found wins
config = cli.load_config(merge: false, project: true)
```

### Deep Merge

Nested objects are recursively merged, not overwritten:

```yaml
# User config (~/.config/myapp.yaml)
database:
  host: localhost
  port: 5432
  user: default_user

# Project config (.config/myapp.yaml, read with project: true)
database:
  host: production.example.com

# Result after merge:
database:
  host: production.example.com  # from project
  port: 5432                    # preserved from user
  user: default_user            # preserved from user
```

### Sections for Subcommands

With subcommands, a config can set options for all of them and for each one:

```yaml
verbose: true    # global: for any subcommand with a verbose option
fetch:           # fetch's own section
  depth: 1
remote:          # a nested CLI's section holds its subcommands' sections
  add:
    name: upstream
```

A mapping under a subcommand's name is that subcommand's section, and every
other key is global. A subcommand takes the global keys it has an option for,
so a global `depth` doesn't reach a subcommand without one, then its own
section's keys over them, nested objects merged key by key. Every key in a
section is passed on, as every key is for a CLI without subcommands, so a
misspelled one is reported if the schema has `additionalProperties: false`.

A key that names a subcommand but doesn't hold a mapping (`remote: origin`)
is an ordinary global. An object option named after a subcommand, though,
can only be set in a section. Sections apply to `defaults:` from any
source, not only `load_config`.

### Other Formats

Add a config format with `config_format` and a block that turns a file's
text into anything that can be written as JSON, such as a TOML library's
result:

```crystal
cli.config_format("toml") { |text| TOML.parse(text) }
config = cli.load_config  # now also finds ~/.config/myapp.toml
```

A format can have several extensions, looked for in the order given:

```crystal
cli.config_format("conf", "cfg") { |text| MyConf.parse(text) }
```

An added format is looked for ahead of YAML and JSON. Adding `yaml`, `yml`,
or `json` replaces Jargon's own parser for each extension named, so
`config_format("yaml", "yml")` replaces it for both.

### Config Warnings

Invalid config files (unparseable, or not a mapping at the top level) are
skipped with a warning to STDERR by default; an empty file is simply ignored.
To suppress the warnings:

```crystal
Jargon.config_warnings = false
config = cli.load_config
Jargon.config_warnings = true
```

Example config (`~/.config/myapp.yaml`):
```yaml
host: localhost
port: 8080
debug: true
```

Or JSON (`~/.config/myapp.json`):
```json
{
  "host": "localhost",
  "port": 8080,
  "debug": true
}
```

The `defaults:` parameter accepts a JSON object (`JSON::Any` or
`Hash(String, JSON::Any)`), so you can load config however you prefer:

```crystal
# From YAML
config = JSON.parse(YAML.parse(File.read("config.yaml")).to_json)
cli.run(defaults: config) { |result| ... }

# From JSON
config = JSON.parse(File.read("settings.json"))
cli.run(defaults: config) { |result| ... }
```

## Extension Annotations (x-*)

Schema keys starting with `x-` are treated as consumer-defined metadata,
following the JSON Schema / OpenAPI extension convention. Jargon preserves
them verbatim — on commands (doc level) and on individual properties — and
ignores them completely for parsing and validation. This gives downstream
consumers (a GUI, a docs generator, an AI tool layer) an open vocabulary of
hints carried by the same schema that drives the CLI:

```yaml
---
name: forget
description: Remove a document from the store
x-ui:
  destructive: true        # GUI: confirm before running
properties:
  query:
    type: string
    x-ui:
      control: typeahead   # GUI: render a search box, not a text field
      source: documents
```

Annotations are exposed through the schema introspection API:

```crystal
schema = cli.subcommands["forget"].as(Jargon::Schema)

schema.root.extensions             # => {"x-ui" => {"destructive" => true}}
schema.root.extensions["x-ui"]?    # => keys are stored exactly as written

query = schema.root.properties.not_nil!["query"]
query.extensions["x-ui"]["control"]  # => "typeahead"
```

Jargon assigns no meaning to any `x-` key — define whatever vocabulary your
consumers need. (The built-in `service` hint predates this mechanism and
remains first-class.)

## Standalone Validator

Use `Jargon::Validator` to validate data against a schema without the CLI parser. This is useful for validating JSON from APIs, config files, or other sources:

```crystal
require "jargon"

schema = Jargon::Schema.from_json(%({
  "type": "object",
  "properties": {
    "name": {"type": "string", "minLength": 1},
    "age": {"type": "integer", "minimum": 0},
    "role": {"type": "string", "enum": ["admin", "user"]}
  },
  "required": ["name"],
  "additionalProperties": false
}))

data = {"name" => JSON::Any.new("Alice"), "age" => JSON::Any.new(30_i64)}
errors = Jargon::Validator.validate(data, schema)
# => [] (empty = valid)

bad_data = {"name" => JSON::Any.new(""), "extra" => JSON::Any.new("?")}
errors = Jargon::Validator.validate(bad_data, schema)
# => ["Value for name must be at least 1 characters",
#     "Unknown property 'extra': additionalProperties is false"]
```

The validator supports all the same constraints as CLI parsing: types, required fields, enums, numeric ranges, string patterns, formats, array constraints, `const`, `$ref`, nested objects, and `additionalProperties`.

## Where Parsing Stops

Jargon's job ends at a valid value: one with the type, format, and constraints its schema gives it. What that value refers to is up to your program. If a positional `query` names a document, Jargon checks that it's a string; finding the document, saying that none matches, or asking the user to choose between several is your program's work, once `parse` returns or inside `run`:

```crystal
cli.run do |result|
  query = result["query"].as_s   # Jargon's part ends here: a valid string
  matches = store.search(query)  # resolving it is the program's
  abort "No document matches '#{query}'" if matches.empty?
  doc = matches.size == 1 ? matches.first : choose(matches) # e.g. ask the user
end
```

A [completer](#dynamic-completions) helps the user type such a value, but it doesn't resolve it.

## API

```crystal
# Create CLI (program name first, named schema parameter)
cli = Jargon.cli(program_name, json: json_string)
cli = Jargon.cli(program_name, yaml: yaml_string)
cli = Jargon.cli(program_name, file: "schema.json")

# For subcommands (no root schema)
cli = Jargon.new(program_name)
cli.subcommand("name", json: schema_string)
cli.subcommand("name", yaml: schema_string)
cli.subcommand("name", file: "schema.yaml")      # single-doc file
cli.subcommand(file: "commands.yaml")            # multi-doc as top-level
cli.subcommand("parent", file: "commands.yaml")  # multi-doc as nested

# Merge global options into subcommand schema
merged = Jargon.merge(subcommand_schema, global_schema)

# Run with automatic help/completions/error handling (recommended)
cli.run { |result| puts result.to_pretty_json }
cli.run(ARGV) { |result| ... }
result = cli.run                      # without block, returns Result

# Parse arguments - returns Result with errors array
result = cli.parse(ARGV)
result = cli.parse(ARGV, defaults: config)

# Get data as JSON - returns JSON::Any, raises ParseError on errors
data = cli.json(ARGV)
data = cli.json(ARGV, defaults: config)

# Config file loading
config = cli.load_config                # merge user configs found
config = cli.load_config(project: true) # also ./.config/ (project wins)
config = cli.load_config(merge: false)  # first found wins
paths = cli.config_paths                # list of paths searched (takes project: too)
cli.config_format("toml") { |text| TOML.parse(text) } # read myapp.toml too

# Result methods (from parse or run)
result.valid?      # => true/false
result.errors      # => Array(String)
result.data        # => JSON::Any
result.to_json         # => compact JSON string
result.to_pretty_json  # => formatted JSON string
result["key"]          # => access values
result.subcommand      # => String? (nil if no subcommands)

# Help/completion detection (when using parse)
result.help_requested?  # => true if --help/-h was passed
result.help_subcommand  # => String? (which subcommand's help, nil for top-level)
result.completion_requested?  # => true if --completions was passed
result.completion_shell       # => String? ("bash", "zsh", or "fish")

# Help text
cli.help              # => usage string with all options
cli.help("fetch")     # => help for specific subcommand
cli.help("config set") # => help for nested subcommand
cli.help("nope")      # raises ArgumentError: Unknown subcommand: nope

# Completion shims (pass command: to target a separate helper binary)
cli.bash_completion                       # => bash completion shim
cli.zsh_completion                        # => zsh completion shim
cli.fish_completion                       # => fish completion shim
cli.bash_completion(command: "app-complete")

# Dynamic completers
cli.completer("forget.query") { |ctx| ... }  # register; returns Array(String)
cli.handle_completion                         # answer __complete + exit (no-op otherwise)

# Standalone validation (no CLI needed)
errors = Jargon::Validator.validate(data_hash, schema)  # => Array(String)

# Schema introspection (for GUI/tooling consumers)
schema = cli.schema                    # => Jargon::Schema? (root schema, if any)
schema = cli.subcommands["name"]       # => Jargon::Schema | Jargon::CLI
schema.root                            # => Jargon::Property (command-level)
schema.root.properties                 # => Hash(String, Property)?
schema.positional                      # => Array(String)
property.extensions                    # => Hash(String, JSON::Any) (x-* annotations, keys as written)
property.extensions["x-ui"]?           # => JSON::Any?
```

## Development

### Prerequisites

- Crystal >= 1.18.2

### Running Tests

```sh
shards install
crystal spec
```

### Project Structure

```
src/
├── jargon.cr              # Main module, convenience methods
└── jargon/
    ├── cli.cr             # Core CLI parser
    ├── schema.cr          # JSON Schema parsing
    ├── schema/property.cr # Property definitions
    ├── result.cr          # Parse result container
    ├── validator.cr       # Standalone schema validator
    ├── config.cr          # Config file loading (XDG)
    ├── help.cr            # Help text generation
    └── completion.cr      # Shell completion scripts
spec/
└── jargon_spec.cr         # Test suite
```

### Building Docs

```sh
crystal docs
open docs/index.html
```

## License

MIT
