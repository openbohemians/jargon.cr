# TODO

## Completed

- **A positional given by name gives up its slot** (unreleased) — every property is an option, positionals included, but the words filled the positionals in order regardless, so `grep -e foo a.txt b.txt` read `pattern` as `a.txt`, `cp -t dir/ a b` read `dest` as `b`, and `myapp --file input.txt result.txt` dropped `input.txt` without a word. The words now go to the positionals with room, wherever the options are (`grep a.txt -e foo b.txt`): one that holds a single value is full once it's given, by name or by a word, and the variadic never is, so its words add to what an option gave it, in order (`cp --sources a b dir/` gives `sources` `[a, b]`, `dest` `dir/`; skipping it gave `dest` `b`). So the parser reads the options first and gives out the words after; a word left over is still applied in its place, so the last value wins as before. Options can now come anywhere among a variadic's words (`cat a -n b` was an error), as among single positionals. Help lists positionals under Options too (`-e, --pattern`), and completion offers them as flags and skips the ones a flag fills. The user wanted no exceptions (2026-10-28): a property is an option, and `positional` adds the words. They chose this over letting `short` mark a positional as an option, which they found exceptional, and after asking about defining positionals apart from `properties`, which would leave the schema not describing all of its data. jargon.rs does the same.
- **A variadic is marked with `*`, and positionals can follow it** (unreleased) — only the last positional could be variadic, and an array positional anywhere else took one word, so `positional: ["sources", "dest"]` read `cp a b dir/` as `sources` `["a"]` and `dest` `b`, and rejected `dir/`. A `*` after a name now marks the variadic (`["sources*", "dest"]`), wherever it is, and the positionals after it take the last words, one each; with too few words they fill first (`cp a` gives `sources` `[]`, `dest` `a`). One `*` per command, on an array; a second `*`, a `*` on a non-array, or one naming no property fails when the schema loads. An array positional without a `*` takes one word, split at its separator. A variadic also reads on past a `--` (`cat a -- -n b` lost `-n` and `b`). Help shows `[sources]...`, and completion gives the word under the cursor to the positional the parser would fill if the line ended there. The user chose the `*` (2026-10-28), and to require it rather than keep the last array implicitly variadic. Breaking: a schema whose last positional is an array adds `*`. jargon.rs does the same.
- **JSON from stdin is `-@`** (v0.25.0) — a lone `-` read options as JSON from stdin, so `cat -` couldn't name standard input. The JSON form is now `-@`, alone after the program or subcommand, as `zip -@` reads names from stdin; a lone `-` is a value everywhere. A schema that defines `"short": "@"` keeps it, as with `-h`, and `-@` among other arguments is an error. The user chose `-@` (2026-10-28) over a lone `--` (taken by a script's `prog -- "$@"` with no arguments, and already POSIX's end of options), a reserved long option, and `@-`; a file is `-@ < file.json`, so no file option. Breaking: callers of `prog -` switch to `prog -@`. jargon.rs does the same.

- **Lists name their separator** (v0.25.0) — every array option split its value at commas, so `grep -e 'a,b'` gave two patterns. A value is now one item, and a property's `separator` names where to split one into several: `comma`, `colon`, `semicolon`, or `whitespace`, or a list of them (`cut -f`, `ps -o`). Pieces are trimmed and empty ones dropped; it applies to option values, `key=value`, environment variables, and variadic words, not to arrays from defaults, config, or stdin. An unknown name, or a separator off an array or beside `$ref`, fails when the schema loads. Help shows it, and completion completes the item after the last one, from the items' `enum`. Names rather than characters, and only these four, as the user chose (2026-10-28). Breaking: a CLI relying on commas adds `"separator": "comma"`. jargon.rs does the same.

- **Repeated array options add up** (v0.25.0) — an array option given more than once kept only its last value, dropping the rest without a word (`-I '*.o' -I '*.a'` kept `*.a`). Each occurrence now adds its items, as getopt programs collect `-I`, `-e`, and `--exclude`. Any other option keeps its last value, and the command line's array still replaces one from the defaults. jargon.rs does the same.
- **A lone `-` is a value** (v0.25.0) — a variadic positional stopped at `-` and an option wouldn't take it (`cat a - b`, `tar -f -`), though `-` conventionally names standard input or output as a file. It's now a value wherever it appears with other arguments. A `-` that was the whole command line read JSON from stdin until `-@` took that over (above). jargon.rs does the same.
- **A value attached to a short flag** (v0.25.0) — `-w80` failed ("Cannot combine non-boolean flag"). A cluster now reads as getopt reads it: each letter is a flag until one that takes a value, which takes the rest of the cluster (`-lw80`), or the next argument when it ends it (`-lw 80`). An `=` is part of the value, as in getopt (`-o=x` is `=x`). Completion reads clusters the same way. jargon.rs does the same.

- **Config sections for subcommands** (v0.24.0) — a config was one flat hash handed to whichever subcommand ran, so a key meant for `fetch` turned up in `fmt`'s data and failed `additionalProperties: false` there. Now a mapping under a subcommand's name is that subcommand's section and any other key is global: a subcommand takes the global keys it has an option for, then its section's keys over them, all of them, so a misspelled one is still reported. A nested CLI's section holds its subcommands' sections. This applies to `defaults:` from any source, stdin JSON included; a CLI without subcommands is unchanged. The user chose the shape (2026-10-26). jargon.rs does the same.
- **Config formats** (v0.24.0) — `cli.config_format("toml") { |text| TOML.parse(text) }` reads `myapp.toml` with any parser, as jargon.rs's `config_format` does. The block returns anything that can be written as JSON. A format can have several extensions (`config_format("yaml", "yml")`), named explicitly rather than paired by Jargon (the user, 2026-10-26). An added format is looked for ahead of YAML and JSON; adding `yaml`, `yml`, or `json` replaces each extension named. YAML stays built in (the user, 2026-10-26).
- **Help in two columns** (v0.23.1) — `Arguments:` and `Options:` list each description beside its flag or argument, aligned like `Commands:`, where a description sat under its flag at the indent of a long-only flag and read as another option. The column starts two spaces past the widest flag, but no further than 32 characters in; a wider flag has its description on the next line. An enum's values follow the description (`Operation mode [fast|safe]`), then `(required)` and `[default: …]`. A description of several lines has each at the column, in `Commands:` too, and a trailing newline (as YAML's `description: |` leaves) no longer adds a blank line. An empty string shows as `""` (`[default: ""]`). jargon.rs lays help out the same.
- **Completion for the default subcommand** (v0.23.1) — when the first word names no subcommand, `parse` passes every word to the default subcommand, but completion offered nothing. It now completes them for the default, running its completers (`query.term`), and at the first word offers the default's flags and values alongside the subcommand names. jargon.rs does the same.
- **Completion after an abbreviated subcommand** (v0.23.1) — `parse` accepts an unambiguous prefix of 3 or more characters for a subcommand (`git fet` for `fetch`), but completion looked subcommands up by exact name, so it offered nothing after one. It now resolves them as `parse` does, and runs the full name's completers (`fetch.url`). jargon.rs does the same.
- **`help(subcommand)` raises for an unknown subcommand** (v0.23.0) — it returned the text "Unknown subcommand: x" as though that were the help, while `validate` raises `ArgumentError` for the same mistake. It now raises too. Found in jargon.rs's API review, where `help_for` returns an error for it.
- **One error for a value that doesn't convert** (v0.22.2) — `--count two` reported both "Invalid integer value 'two' for count" and "Invalid type for count: expected integer, got string" (and an `enum` error, if any). Validation now skips a field whose argument or environment variable didn't convert; values from defaults, config, and stdin JSON are validated as before. This covers a variadic item too (`nums 1 oops 3`). jargon.rs does the same.
- **Type errors name schema types** (v0.22.1) — "Invalid type for x: expected integer, got object" instead of "expected Integer, got Hash(String, JSON::Any)", so an end user sees the words the schema uses rather than Crystal's classes. jargon.rs says the same.
- **Fixes found by the Rust port** (v0.22.0) — porting to Rust (jargon.rs) turned up these, now fixed in both implementations where they applied:
  - Help shows a default that isn't a string as JSON (`[default: ["a",1]]`, `[default: null]`), not in Crystal's inspect form.
  - `nan`, `inf`, and numbers too large for a float are invalid numbers, since JSON can't hold them.
  - A whole-number bound beyond Int32 (`maximum: 3e9`) no longer raises OverflowError in its validation message.
  - Built-in formats no longer accept a trailing newline (`\z`, not `$`), and user `pattern`s compile with DOLLAR_ENDONLY, so `$` means the end of the value, as in JSON Schema. Dates, times, and ipv4 take ASCII digits only, and ipv4 no longer allows whitespace or a sign around a part.
  - A nested subcommand's help names the whole command (`Usage: git remote add ...`), as does a nested group's help.
  - YAML dates and times stay strings (`Jargon::YAMLReader`), instead of becoming timestamps that fail `format: date`.
- **No colon assignment; review hardening** (v0.21.0) — bare assignment is `key=value` only, so `key:value` and JSON-like operands pass through as positionals. Project-local configs (`./.config/`) are opt-in via `load_config(project: true)`; see "Config Loading Follow-ups". Fixes from a security and performance review:
  - Invalid UTF-8 and regex limits produce validation errors instead of raising.
  - Email and hostname regexes are linear, with RFC length caps.
  - Did-you-mean skips candidates that differ in length by more than 2.
  - Recursive `$ref` is safe in help and defaults; `flatten` raises on it.
  - Nested defaults merge key by key without aliasing or mutating.
  - Completion shims quote names, and bash rejoins COMP_WORDBREAKS splits.
  - `--flag=value` completes, and `--` ends options in completion and help.

  Ameba runs clean (`just ameba`, then `just lint`).
- **Mixin isolation and `required` union** (v0.20.1) — `merge_schema` copied a mixin's `properties` hash by reference, so options added to one subcommand after a `$ref` leaked into every other subcommand sharing that mixin (found via camelot). `required` lists are now unioned across mixins and the subcommand's own list instead of first/last-wins. Last-wins `properties` flattening is documented in the README as a deliberate approximation of `allOf`; see "Other Ideas".
- **Consistent positional parsing** (v0.20.0) — variadics are greedy (capture `:`/`=` tokens and negative numbers literally, stop only at a real flag); negative numbers parse as values everywhere (`short_flag?` exempts `-<digit>`); variadic items coerce to the array's `items` type; new `cli.bare_assignment(false)` opt-out for implicit `key:value`/`key=value` assignment. Remaining edges under "Positional Parsing Follow-ups" below.
- **Subcommand descriptions in top-level `--help`** (v0.19.1) — the command list shows each subcommand's `description:`, column-aligned. (transfs req #5)
- **Dynamic shell completions** (v0.19.0) — all-callback shim model; `cli.completer(path)` + `cli.handle_completion`; configurable target binary. See `notes/` and the v0.19.0 release. Remaining edges tracked under "Dynamic Completion Follow-ups" below.
- **POSIX `--` end-of-options passthrough** (v0.19.0) — everything after a bare `--` is a literal positional; variadic positional captures it verbatim. (transfs req #4)
- **`x-*` extension annotations** (v0.18.0) — consumer-defined keys preserved verbatim on `Property#extensions`, ignored by parsing/validation. (transfs req #1)
- **Structural type inference** (v0.18.0) — omitted `type:` inferred from `properties`/`items`; contradictory explicit type now errors instead of silently dropping the block. (bug fix)

### Schema Mixins with $id/$ref/allOf (v0.12.0)

Support for sharing properties across subcommands using standard JSON Schema keywords.

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

- `$id` schemas (no `name`) are mixins - not registered as subcommands
- `$ref` in `allOf` resolves to mixins in the same file
- Properties are merged; `type: object` is inferred if missing
- Subcommands opt-in explicitly via `allOf`

## Future Ideas

### Standalone JSON Schema Validator Library

Consider spinning off the validation logic as a separate shard. Jargon already supports:

- Type validation (string, integer, number, boolean, array, object, null)
- `minimum`/`maximum`, `exclusiveMinimum`/`exclusiveMaximum`, `multipleOf`
- `minLength`/`maxLength`, `pattern`
- `minItems`/`maxItems`, `uniqueItems`
- `enum`, `const`
- `format` (email, uri, uuid, date, time, date-time, ipv4, ipv6, hostname)
- `$ref` to `$defs`
- `allOf` with local `$id`/`$ref` resolution

To be spec-complete, would need:
- `anyOf`, `oneOf`, `not`
- `if`/`then`/`else`
- `dependentRequired`, `dependentSchemas`

See also:
- https://github.com/aarongodin/jsonschema (dormant since June 2022, has composite schemas but no `$ref` support)
- https://github.com/cyangle/json_schemer.cr (active, Draft 2020-12 compliant, has `$ref` - worth watching)

### Semantic Command Discovery ("Bash Spell Checker")

Use Jargon's JSON Schema definitions as a corpus for semantic search over CLI tools. Natural language → tool call translation without an LLM.

**Concept:**
```
$(repo push) → git push      # high confidence, auto-execute
$(delete old logs) → rm ...  # destructive, confirm first
```

**Techniques:**
- TF-IDF / co-occurrence vectors over tool schemas
- Embeddings over man pages and descriptions
- Salience scoring for match confidence

**Context signals to improve accuracy:**
- Current working directory (git repo? node project?)
- Recent bash history
- Cursor position in IDE/Vim
- Active file types

**Use case:** People who know what they want but forget exact syntax. Acts as a validator/refinement layer for LLM-generated commands - LLM gets close, system finds exact match, gates unsafe operations.

**Not a priority now** - Jargon is the foundation (self-describing tools). This layer can come later. See also: memo, xerp projects.

### Dynamic Completion Follow-ups

Scoped out of the initial dynamic-completion work (v0.19.0). All are refinements, not blockers. Assessed 2026-06-14; the one judged worth doing, #2 (completion after an abbreviated subcommand), is done (see Completed).

- **#3 bash 3.2 portability — will resolve itself.** The generated bash shim uses `readarray`/`mapfile` (bash 4+). macOS ships bash 3.2 as `/bin/bash`, so the shim fails there. But most macOS users have moved to zsh (default since Catalina), and bash 3.2 fades over time. Low urgency; a `read`-loop fallback is the fix if a user actually hits it.

- **#1 Nested-object field completers — SKIP (complexity > payoff).** Completer paths target schema-root fields (flags/positionals) and `subcommand.field`. A flag that is itself a nested object completed via dot notation (`--a.b`) can't have a completer attached to the inner `b`. Rare in practice; the path-resolution and engine changes outweigh the benefit.

- **#4 Streaming/lazy completer results — SKIP (illusory benefit).** Completer blocks return `Array(String)` (proc return type is pinned concretely; the whole engine collects to an array before printing). This is deliberate, not a v1 shortcut — laziness here doesn't actually buy anything:
  - The real goal of "lazy" is *don't enumerate the whole store per keypress*. That's already covered today by scoping the query with `ctx.partial` (`store.search(ctx.partial)`) and/or capping with `.first(N)` — both already return an `Array` that works.
  - There is no streaming completion protocol: the shell needs the full candidate list, so Jargon must `.to_a` before printing regardless. Accepting a raw lazy `Enumerable` would therefore (a) still materialize, and (b) **hang on an unbounded source** — a footgun. The caller has to bound it either way.
  - Candidate sets are inherently small (shells truncate/page at tens–hundreds); no memory-saving scenario exists.
  - Conclusion: `Array(String)` is the correct API, not a limitation to lift.

### Positional Parsing Follow-ups

An edge left after the v0.20.0 parsing work. It isn't a regression; it surfaced
during that work and is a low-priority refinement.

- **`bare_assignment` is per-CLI, not inherited.** The setting applies to a CLI and its directly-attached Schema subcommands, but a *nested* `CLI` keeps its own (default-on) setting. To turn it off across a deep subcommand tree today you must set it on each nested CLI. Fix if it bites: propagate the parent's setting into nested CLIs at parse/dispatch time (or expose a recursive setter). Low priority until a nested-CLI user actually needs it.

### Config Loading Follow-ups

Raised 2026-10-22, when v0.21.0 made project-local configs opt-in
(`load_config(project: true)`). Not scheduled; to be considered.

- **Per-subcommand control of project config — deferred** (the user, 2026-10-26, until a program needs it). `project:` is a single yes/no for the whole CLI. A tool might want project settings for some subcommands (`fmt`, `build`) but never for others (`deploy`, `login`), where a cloned repository's config could point the tool at another server. The app can do it today by checking the subcommand itself and picking `project:`, but that duplicates Jargon's subcommand resolution (abbreviations, default subcommand, nesting).
  - *With config sections, it fits in `load_config`:* read the project files, push their global keys down into the allowed subcommands' sections, and drop their other sections. `parse` then needs no idea where a key came from, which was the catch before (`load_config` runs before parsing, so it can't know the subcommand).
  - *Shape:* a registration call, `cli.project_config_for("fmt", "build")`, that `load_config(project: true)` honors, adds it in both implementations without changing anything that exists (jargon.rs's `ConfigOptions` is a `Copy` struct with a `bool` field, so a list there would change its type). A `project:` that takes a list is the other choice. jargonaut had no dependents when this was discussed, so compatibility needn't decide between them.
  - *Finer still, per option:* mark individual options as user-config-only, so a project file can set `style` but never `server`. More precise trust, but a new schema keyword.

### Conventions Existing Commands Use

Found 2026-10-27 by parsing real `ls`, `cat`, `cp`, and `sudo` command lines with schemas like those in `schemas/coreutils/`, toward a repository of schemas for common commands. Each is also a convention people expect of any CLI. jargon.rs, held to the same behavior, would change with each. The priorities are proposed, not decided.

**Must fix (proposed)**

All done (see Completed): repeated array options, `-` as an argument (with `-@` for JSON from stdin), and attached short values.

**Should fix (proposed)**

- **A command's arguments taken verbatim.** `sudo -u root ls -l` reads `-l` as sudo's own option; only `--` gets it through. `sudo`, `xargs`, `env`, `nice`, `time`, and `ssh` take a command, and everything after it is that command's. A positional could be marked as ending option parsing.
- **Options whose value is optional.** `ls --color` alone fails ("Missing value for --color"). GNU's `--color[=WHEN]` takes a value only after `=`, and uses one of its own when there's none. It needs a new keyword for that value. POSIX advises against optional values, so this matters mostly for GNU commands.
- **Counted flags.** `-vvv` fails. `ssh` and others count a repeated flag as a level; `--verbose=3` is the workaround today.
- **A shorter unknown-option error.** "Unknown option '--al'" lists every option, 60 for `ls`. For a large schema, the suggestion alone would read better.

**Opt-in at most (proposed)**

- **Long-option prefixes.** GNU accepts `--al` for `--all`. Jargon matches options by exact name (it abbreviates only subcommands), as the user prefers exact names.

**Out of scope:** `find` and `test`, whose arguments are expressions; old-style bundles (`tar xzf`, `ps aux`); single-dash long options (`gcc -Wall`, `java -jar`, `find -name`). A repository of schemas can mark these commands as only partly covered.

### Other Ideas

- Man page generation
- Config file generation from schema
- Shell completion for enum values with descriptions
- Strict `allOf` property intersection — `merge_allof` flattens with last-wins when the same property appears in multiple subschemas; true JSON Schema semantics would intersect the constraints (e.g. both `enum` lists must hold). Low priority, but noted in the README.
- Promo graphic for the docs site: `docs/assets/ad.webp` is a 2048×2048 "ad" image (green/orange circuit-board style, schema → generated CLI, feature icons), generated Jun 2026. It was a 6.5 MB PNG and is now a 266 KB WebP. Nothing references it yet; it could serve as a hero image or `og:image`. Known content flaws:
  - The schema snippet shows a bogus `"type": "user"`.
  - The terminal example (`--user 'Alex' --log`) doesn't reflect real usage.
  - Shell completions lists only bash and zsh, not fish.
  - The help label reads `–help` (en dash) instead of `--help`.
