# TODO

## Completed

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

- **Per-subcommand control of project config — TO CONSIDER.** `project:` is a single yes/no for the whole CLI. A tool might want project settings for some subcommands (`fmt`, `build`) but never for others (`deploy`, `login`). Most tools are probably fine with yes/no, so the open question is whether this is worth supporting at all, and if so, how:
  - *App does it today:* the app can already peek at `ARGV` for the subcommand and pick `project:` itself. That works, but means duplicating Jargon's subcommand resolution (abbreviations, default subcommand, nesting).
  - *Declarative, on the subcommand:* a schema keyword or a registration call (shaped like `cli.completer(path)`) naming which subcommands accept project config. The catch: `load_config` runs *before* parsing, so it can't know the subcommand. Jargon would have to load config itself after dispatch, which couples config loading into `parse`/`run` (today the two stay separate, joined only by `defaults:`).
  - *Finer still, per option:* mark individual options as user-config-only, so a project file can set `style` but never `server`. More precise trust, but a new schema keyword.
- **Config keys cross subcommands (related, confirmed).** A config file is one flat hash handed to whichever subcommand runs, and `defaults:` copies *every* key into the result. So a key meant for `fetch` (`url`) appears in `fmt`'s data, and fails validation there if `fmt` has `additionalProperties: false`. Options: drop default keys the dispatched schema doesn't define, and/or support per-subcommand sections in the file (`fetch: {url: ...}`). Either is worth settling together with the item above, since both decide how config maps onto subcommands.

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
