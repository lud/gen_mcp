---
name: write-gen-mcp-guides
description: Rewrite the narrative ExDoc guides for the gen_mcp library (the files under guides/), one guide at a time, working through the worklist in tools/guides-to-write.txt. Use when the user wants to rewrite or write a guide, continue the guide rewrite, or asks for the next guide.
user-invocable: true
disable-model-invocation: false
---

# Write gen_mcp guides

Your role: rewrite **one** narrative guide of the `gen_mcp` Elixir library (a file
under `guides/`), then move its entry to the "Done" list so the next invocation
picks up the following guide. You do exactly one guide per run.

This is the narrative-guide counterpart of the `write-gen-mcp-docs` skill, which
documents library *modules*. Guides are top-level pages (install walkthroughs,
the Suite component model, configuration), not module `@moduledoc`/`@doc`. They
share one house style but a different procedure: there are no doctests, no
`@moduledoc`/`@doc`/`@typedoc` attributes, and no stale-doc strip step.

**IMPORTANT**: Never perform any git operations (commit, push, branch, etc.). The
user manages git themselves.

## Inputs

- **Worklist**: `tools/guides-to-write.txt`. Each `## NNN.slug.md` is a level-2
  heading naming a guide to rewrite, optionally followed by notes about that
  guide's scope. The file ends with a `# Done` (level-1) section; finished guides
  are **moved** there instead of being deleted, so later runs have current
  examples to draw on. The section may not exist yet on the first run.

- **Guidelines**: `.claude/skills/write-gen-mcp-guides/guidelines.md`, the rules
  for *how* to write the guides. Read this before writing anything and follow it
  exactly. The most important rule: existing guide text is outdated, so ignore it
  and write from the current code.

## Procedure

1. **Read the guidelines** at
   `.claude/skills/write-gen-mcp-guides/guidelines.md`.

2. **Read the worklist** `tools/guides-to-write.txt` and take the **first**
   `## NNN.slug.md` entry that appears **above** the `# Done` marker. If there are
   none left, tell the user the worklist is done and stop. The entry may name a
   guide that does not exist yet (a new guide to author); if so, pick an unused
   number, plan to create `guides/NNN.slug.md`, and add it to `doc_extras/0` in
   `mix.exs` (see the guidelines, "Guide files and registration").

3. **Understand the topic from the current code**, not from the old guide text.
   The existing prose is stale (pre-fork, session-based) and must be treated as if
   it were not there. Read the relevant behaviours, their callbacks and `@spec`s,
   the transport plug options, the `GenMCP.MCP.V2607` helpers, and the tests that
   exercise them. Consult the `context/` specs (`tree context`, then grep) when a
   topic's *purpose* is unclear. If you still cannot tell what something does or
   when it is used, **ask the user**.

4. **Rewrite the guide** following the guidelines: lead with a minimal honest
   example, write examples the way a user would (with `MyApp`/`:my_app` naming and
   `GenMCP.MCP.V2607` helpers), document what exists, keep prose dash-free and
   wrapped near 90 columns, and cross-reference with autolinking backticks. Purge
   all stale framing (sessions, `initialize`, `Mcp-Session-Id`, `session_*`).

5. **Preserve the Readmix markers.** Keep every `<!-- rdmx ... -->` tag balanced.
   You may freely edit code inside a `:section name:... format:true` block, but it
   must be **valid, compilable Elixir** (Readmix formats it and users copy it). Do
   **not** hand-edit the generated body between `:eval` tags; if it is wrong, fix
   the source it derives from.

6. **Regenerate and verify.** Run the `docs` recipe in the `justfile` (this runs
   Readmix over the guides to format `:section` code and regenerate `:eval`
   bodies), then `mix docs`. Confirm the guide renders, the `:section` code
   compiled/formatted, and `doc_extras/0` reports **no unreferenced-guide
   warning** (a new guide must be in the `defined_guides` list). Fix any problems.

7. **Move the finished entry** under the `# Done` marker at the bottom of
   `tools/guides-to-write.txt` (create the marker if it does not exist), instead of
   deleting it. Leave the other pending entries intact.

8. **Report** which guide you rewrote, what changed at a high level, and confirm
   the entry was moved.

## Notes

- Keep edits scoped to the guide (and, for a new guide, its `doc_extras/0`
  registration). If you notice a code bug while reading, mention it to the user,
  but do not fix it (per project convention, the user implements production code).
- A guide example inside a `:section` is real code: prefer making it compile over
  making it clever. If a faithful example cannot be made to compile without
  fabricating library-internal plumbing, use a plain (non-`:section`) fenced block
  instead, or omit the example.
