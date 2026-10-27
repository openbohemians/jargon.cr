# Jargon requirements from transfs

**Closed 2026-10-27: all five have shipped.** See the last update, at the end.

> Source: the **transfs** project (`~/Projects/transfs`), a content-addressable
> file store. transfs has chosen Jargon as its CLI library, specifically because
> "the CLI is the API": every transfs operation must be expressible as a core
> command, and a future GUI must drive the *same* core with no GUI-only magic.
> Jargon's schema-as-contract model makes that structural. This note lists what
> transfs would like from Jargon as it builds out. Written 2026-06-12.
>
> None of these are blocking — transfs can adopt Jargon today. They are
> dogfooding feedback: features a GUI-bound, content-driven, subcommand-heavy
> CLI surfaces that a simpler CLI wouldn't.

---

## Why Jargon fits (context)

transfs's hard rule is *every GUI action = a CLI/core operation, no GUI-only
magic*. Because Jargon defines each command as a JSON Schema, that schema is a
single machine-readable contract both the CLI and the future GUI consume — the
GUI renders forms from the same schemas it validates against, and can drive the
core by piping JSON to `-`. That's a stronger guarantee than "keep them in
sync." The asks below all push on that GUI-contract edge.

Division of labor transfs assumes: **Jargon owns syntax** (shape, types,
required, enums, paths); **transfs owns semantic resolution** (a document
"query handle" → an actual document, with an interactive recognition list on
ambiguity). The asks respect that line.

---

## 1. Custom UI-hint annotations for GUI consumers — **most valuable**

**Context.** Jargon already has `service: true` as a UI hint ("long-running
service"). transfs's GUI will want a richer, open vocabulary of hints so it can
render the *right control* for each field/command without hardcoding knowledge
of transfs:

- a positional is a **document query** → render a search/typeahead box, not a
  bare text field
- a command is **destructive** (e.g. forget/gc) → confirm before running
- a command is the **inbox add** → render a drag-and-drop zone
- a field is a **tag** → render a tag chooser with existing-tag completion
- a value is **content/large** → render a file picker

**Ask.** A general, namespaced **`x-ui` (or `ui:`) annotation** keyword on
schema properties and commands that Jargon **passes through untouched** to
consumers (and ignores for validation). Effectively: "arbitrary
consumer-defined metadata, preserved and exposed via the introspection API."
This generalizes `service` from a fixed hint into an open extension point.
transfs would define its own hint vocabulary on top; Jargon just needs to carry
it. (Aligns with JSON Schema's own `x-` extension convention.)

**Why it matters:** this is the mechanism that lets a generic GUI render a
*specific* app's commands well — arguably the highest-leverage thing Jargon
could offer any tool that wants a "CLI now, GUI later" path.

---

## 2. Live, app-driven shell completions — **wanted**

**Context.** Jargon generates static shell completions from the schema (enums,
flag names). But transfs's most useful completions are **dynamic**: complete a
document-query positional against the *actual* document names/tags in the live
store, which only the running app knows.

**Ask.** A way for a schema to declare that a positional/option completes by
**calling back into the app** (analogous to bash `complete -F` / a
"completer command"). E.g. the generated completion script invokes
`transfs __complete <command> <partial>` and the app returns candidates. Jargon
would generate the dispatching shim; the app supplies the candidates at runtime.

**Why it matters:** for a content-driven CLI, static completions cover flags but
miss the thing users most want to complete — their own data.

---

## 3. An interactive disambiguation / resolver seam — **nice to have, may be out of scope**

**Context.** transfs's central UX move (Innovation 2) is: a fuzzy query handle
resolves against the index; if it matches **multiple** documents, drop into a
recognition picker ("did you mean: `report.pdf · Mar 3` / `report.pdf · from
email`?") and let the user choose. This is *post-validation, mid-command*
interactivity: the argument is a syntactically valid string, but its final
*semantic* value needs runtime resolution that may prompt.

**Ask (soft).** Is there — or could there be — a clean seam for a "resolver"
callback on a positional, invoked after validation, that may return one value,
or signal ambiguity so the app prompts? This is very possibly **out of Jargon's
scope** (Jargon is a *parser*; resolution is app logic), and transfs can simply
do it downstream of `parse`. Raising it only to confirm the intended boundary:
**Jargon stops at "valid string," transfs resolves "which document" after.** If
that's the intended line, no change needed — just documenting the seam so the
two layers compose cleanly.

---

## Priority summary

| # | Item | Status | Likely scope |
|---|------|--------|--------------|
| 1 | Pass-through `x-ui`/`ui:` annotations for GUI consumers | Wanted (high value) | small — preserve + expose arbitrary keys |
| 2 | App-driven dynamic completions (callback shim) | Wanted | medium |
| 3 | Interactive resolver seam for positionals | Maybe out of scope | clarify boundary; possibly no change |

#1 is the standout: it's small, generalizes the existing `service` hint, and is
the lever that makes "schema drives both CLI and GUI" actually deliver. #2 is
the natural want of any content-driven CLI. #3 is mostly a boundary
confirmation — transfs will likely own resolution regardless.

(Same symbiosis as crystalfuse and C0DATA: a demanding real consumer hardens the
tool. transfs is a good stress test for Jargon's GUI-contract story specifically,
since it's explicitly designed "CLI now, GUI on the same core later.")

---

## Update 2026-06-14: findings from actually integrating Jargon into transfs

Jargon 0.18.1 wired into transfs (compile-time `read_file` of per-subcommand
YAML schemas; `subcommand(name, yaml:)`; dispatch on `result.subcommand`). The
`x-` passthrough (#1) works and transfs now carries `x-ui` render hints on every
command/field. Two real frictions surfaced in use:

### 4. No way to pass a positional value containing `=` / `:` or starting with `-` — **REQUESTED**

transfs has a `tag <id> <tags...>` command (variadic positional). Real tag
values collide with Jargon's option/arg syntax:

- `tag <id> -draft` → `-draft` is parsed as a short flag ("Unknown option '-d'").
- `tag <id> stars=4` → `collect_variadic` *breaks* on any item containing `=` or
  `:` (treated as the equals/colon arg style), so `stars=4` falls through to
  "Unknown option 'stars'". transfs's `key=value` tag convention (which the
  design relies on — `stars=4` becomes a rangeable facet at index time) can't be
  expressed as a CLI positional at all.

So there is currently **no way to feed a variadic positional a literal value**
that contains `=`/`:` or begins with `-`. Two standard escape hatches would fix
it; either suffices:

- **(a) `--` end-of-options marker.** After `--`, treat every remaining arg as a
  literal positional (POSIX convention). `tag <id> -- stars=4 -weird`. Most
  general; widely expected.
- **(b) Per-property opt-out of `=`/`:`/dash parsing** for a variadic positional
  (e.g. an `x-`/schema flag like `raw: true` or `literal-items: true`), so its
  items are collected verbatim. More targeted.

Workaround transfs took meanwhile: split `tag` (add) / `untag` (remove) so the
removal case no longer needs a `-` prefix; and bare tags (`finance`, `q2`) work
fine. But `key=value` tags via the CLI remain blocked until one of the above
lands. (a) is probably the right general fix.

### 5. (minor) Subcommand `--help` lists names without their descriptions

`transfs2 --help` lists the commands but not their one-line `description:` from
each schema. Showing the description beside each name would make the top-level
help self-documenting. Small nicety, not blocking.

| # | Item | Status | Likely scope |
|---|------|--------|--------------|
| 4 | `--` (or per-prop opt-out) for literal positional values | **Requested** (blocks `key=value` tags) | small |
| 5 | Show subcommand descriptions in top-level `--help` | nice-to-have | small |

### Update 2026-06-14 (later): #4 RESOLVED in Jargon 0.19.0

`--` literal-positional support shipped in 0.19.0. Verified in transfs:
`tag <id> -- stars=4` and `tag <id> -- -weird` now pass through to the variadic
`tags` positional verbatim; bare tags still work without `--`; `untag <id> --
-weird` handles leading-dash removal too. transfs pinned to `jargon >= 0.19.0`.
Thanks! #5 (subcommand descriptions in top-level --help) still open, minor.

### Update 2026-10-27: closed, all five shipped

| # | Item | Shipped |
|---|------|---------|
| 1 | `x-*` annotations passed through, on `Property#extensions` | 0.18.0 |
| 2 | App-driven dynamic completions | 0.19.0 |
| 3 | The resolver boundary: Jargon stops at a valid value, and resolving it is the app's work after `parse` | 0.23.1, the README's "Where Parsing Stops" |
| 4 | `--` for literal positional values | 0.19.0 |
| 5 | Subcommand descriptions in top-level `--help` | 0.19.1 |

#5 needs jargon 0.19.1 or later; transfs's `shard.lock` still has 0.19.0
(its `>= 0.19.0` allows the update). Making `ui:` a first-class keyword,
alongside `x-ui`, is still a proposal, not decided.
