---
name: write-gen-mcp-docs
description: Write ExDoc documentation for the gen_mcp library, one module at a time, working through the worklist in tools/docs-to-write.txt. Use when the user wants to document modules/functions, continue the doc rewrite, or asks for the next module's docs.
user-invocable: true
disable-model-invocation: false
---

# Write gen_mcp documentation

Your role: document **one** module of the `gen_mcp` Elixir library, then move its
section to the "Documented" list so the next invocation picks up the following
module. You do exactly one module per run.

**IMPORTANT**: Never perform any git operations (commit, push, branch, etc.).
The user manages git themselves.

## Inputs

- **Worklist**: `tools/docs-to-write.txt`. Each `## ModuleName` is a **level-2
  heading naming a module to document**, followed by a bullet list of the
  functions/callbacks of that module still to document:

      ## GenMCP.Application

      - def env/0
      - def start/2
      - def stop/1

  The heading itself is the module: documenting it includes writing its
  `@moduledoc`, even though only functions/callbacks are listed as bullets.

  The file ends with a `# Documented` (level-1) section. Everything under it is
  already done; finished modules are **moved** there instead of being deleted,
  so later runs have real, current examples to draw inspiration from. Look at a
  module of a *similar kind* to the one you are writing (a behaviour for a
  behaviour, a plain struct module for a struct module), not just the most
  recent one, and take inspiration from it rather than copying its shape: the
  guidelines are the authority, and an earlier module may predate a guideline
  change. The section may not exist yet on the first run.

- **Guidelines**: `.claude/skills/write-gen-mcp-docs/guidelines.md`, the rules
  for *how* to write the docs. Read this before writing anything, and follow it
  exactly. The most important rule: existing docs are outdated, so ignore them
  and write from the current code.

## Procedure

1. **Read the guidelines** at `.claude/skills/write-gen-mcp-docs/guidelines.md`.

2. **Read the worklist** `tools/docs-to-write.txt` and take the **first**
   `## ModuleName` section that appears **above** the `# Documented` marker. If
   there are no such sections left, tell the user the worklist is done and stop.

3. **Find the source file** for that module. Convert the module name to its
   conventional path under `lib/` (e.g. `GenMCP.Suite.Tool` →
   `lib/gen_mcp/suite/tool.ex`). Search for `defmodule <ModuleName>` if the
   conventional path does not exist (several worklist modules can share one
   file).

4. **Strip the stale docs first, in a sub-agent.** Do not read the source file
   yet. The existing docs are stale, and reading them tempts you into small
   "fixes" instead of a clean rewrite, so have a sub-agent remove them and report
   only counts, keeping the old doc text out of your context. Spawn a
   `general-purpose` agent with a prompt like the one below (fill in the path and
   project dir):

   > Mechanically strip stale documentation from one Elixir file. Change nothing
   > else.
   >
   > File: `<lib/path/to/module.ex>`
   >
   > Remove every `@moduledoc`, `@doc`, and `@typedoc` attribute together with its
   > value, in all prose forms: the `"""..."""` heredoc (and the `~S"""..."""`
   > sigil variant) and the single-line `"..."` string form. Collapse the
   > whitespace left behind so at most one blank line remains where a doc was.
   >
   > Do **NOT** remove or alter anything else:
   > - **Keep every code comment (`#` lines) untouched. They belong to the user,
   >   never strip them.**
   > - **Keep `@doc false`, `@moduledoc false`, and `@typedoc false`** exactly as
   >   they are (they mark intentionally hidden items).
   > - Keep `@spec`, `@type`, all other attributes, and every line of code byte
   >   for byte.
   >
   > Then run `cd <project dir> && mix compile` to confirm it still compiles.
   >
   > In your reply include **NO file contents, doc text, code, or quotes** of any
   > kind. Report only: how many `@moduledoc`, `@doc`, and `@typedoc` you removed,
   > and whether `mix compile` succeeded. Nothing else.

   Proceed once the sub-agent reports success. You now have a doc-free file (with
   comments and any `*false` markers preserved) to write against.

5. **Understand the module and each listed function/callback** from the actual
   code, its `@spec`, and the `context/` specs when purpose is unclear. The old
   doc text is gone by now, which is the point: build understanding from code.

6. **Write the docs**: add the module's `@moduledoc`, plus a `@doc` for each
   listed function/callback, following the guidelines. **Do not add `@typedoc`**
   (the strip removed them on purpose; do not re-add them). If you find a
   preserved `@doc false`/`@moduledoc false`, ask the user before replacing it.
   Documentation only, never change code.

7. **Make the doctests run, then run `mix test`** (the suite is fast). A doctest
   executes only if a test module invokes `doctest <ModuleName>`. You may add
   that line to the module's genuine test file, or create a test module that does
   nothing but invoke `doctest <ModuleName>`, when one is needed (see the
   guidelines, which also cover that doctests are documentation, not a way to
   grow unit-test coverage). Run `mix test` and fix doc problems until it is
   green. Beyond enabling doctests, do not edit tests to force a pass, and never
   change `lib/`.

8. **Move the finished section** under the `# Documented` marker at the bottom of
   `tools/docs-to-write.txt` (create the marker if it does not exist), instead of
   deleting it. Remove it from its old position, leaving the other pending
   sections intact.

9. **Report** what you documented and confirm the section was moved.

## Notes

- Keep edits scoped to documentation. If you notice a code bug while reading,
  mention it to the user, but do not fix it (per project convention, the user
  implements production code).
- A quick `mix docs` is a reasonable optional check that the Markdown renders,
  but is not required.
