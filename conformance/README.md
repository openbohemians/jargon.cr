# Conformance cases

Language-neutral test cases for other implementations of Jargon, such as
[jargon.rs](../../jargon.rs). Each case is a public Jargon call made by the
spec suite, with its inputs and what this implementation returned, recorded
by `recorder.cr` during a spec run:

```sh
just conformance
```

The case files are regenerated, never edited by hand: to add a case, add a
spec. Each file holds one kind of call:

| File | Call | Inputs |
|---|---|---|
| `parse.json` | `CLI#parse` | `cli`, `args`, and optionally `env`, `stdin`, `defaults` |
| `validate.json` | `CLI#validate`, `Validator.validate` | `cli` with `subcommand`, or `schema`; and `data` |
| `load.json` | building a CLI or Schema that fails | `cli` or `schema` |
| `help.json` | `CLI#help` | `cli`, `subcommand` |
| `complete.json` | completion candidates | `cli`, `words`, `cword` |
| `shim.json` | completion scripts | `cli`, `shell`, `command` |
| `utility.json` | `Jargon.merge`, `Jargon.flatten` | `merge` (sub, global) or `flatten` |

A case's `cli` lists the calls that build its CLI, in order:

- `from_json`, `from_yaml`: `Jargon.cli` with `text` and `program`
- `from_file`: the same, with the file's `ext` and `text` in place of a path
- `from_schema`: `CLI.new(schema, program)`, the schema's JSON in `text`
- `new`: `Jargon.new(program)`, for subcommands
- `subcommand_json`, `subcommand_yaml`, `subcommand_schema`: a named subcommand from `text`
- `subcommand_file`: one from a file's `ext` and `text`; `name` is null for a multi-document file of named subcommands
- `subcommand_cli`: a nested CLI, whose own calls are in `cli`
- `default_subcommand` (`name`), `subcommand_key` (`key`), `bare_assignment` (`value`)

`expect` is the result: for a parse, `data`, `errors`, `subcommand`, `help`,
`help_subcommand` and `completion_shell`; `{"raises": message}` when the
call raised. `env` holds the variables the schema reads that were set. A
schema with a `format: path` field gets `HOME` set to `/home/jargon`, which
stands in for the home directory in expanded paths.

Cases with invalid UTF-8 are left out, since JSON can't carry it, and so
are completions that call dynamic completers, which are code.
