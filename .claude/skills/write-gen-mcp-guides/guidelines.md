# Guide-writing guidelines for gen_mcp

These rules apply to every narrative guide under `guides/` in this repository.
They exist so the guides read with one voice, render correctly under ExDoc (the
`mix docs` output published to HexDocs), and stay accurate to the current
stateless core.

The guides and the module docs share one house style. The style and example
rules below are adapted from `.claude/skills/write-gen-mcp-docs/guidelines.md`;
the module-specific machinery (`@moduledoc`/`@doc`/`@typedoc`, doctests, the
worklist of modules) does not apply to guides and is not repeated here.

## Principles (read first)

1. **Accuracy from source.** Document the current code, and the `context/` specs
   when the purpose is unclear. Never trust the existing (stale) guide text. When
   still unsure, ask the user.
2. **Lead with the minimal path.** After a short introduction, show the easy path
   first, then the complexity. Stay honest, never oversimplify.
3. **Document what exists.** No "negative documentation", no rejected
   alternatives, no roads not taken.
4. **A guide is a narrative.** Unlike a module doc, a guide walks a reader from a
   goal to a working result. Prose carries the reader between examples; each
   example earns its place by moving that narrative forward.
5. **Plain, dash-free prose.** Short sentences, concrete directives, runnable or
   copy-pasteable examples.

## Golden rule: existing guides are outdated, ignore them

This repository finished a large hard fork to the MCP draft specification (future
version **2026-07-28**), moving to a **stateless core** with the session
machinery removed. **Any guide text already present is stale and must be treated
as if it were not there.**

- Do **not** trust the current guide prose as a description of what the code does.
  Read the actual code (and the `context/` specs) instead.
- **Write from scratch, do not "improve" the old text.** The library changed too
  much for targeted patches, and sniper-fixes silently inherit the old framing
  (sessions, `initialize`, `session_*` callbacks) and its mistakes.
- The only source of truth is the current code: behaviours and their callbacks,
  `@spec`s, the transport plug options, the `GenMCP.MCP.V2607` vocabulary, and the
  tests that exercise them.

Common stale framing to purge: anything about sessions or "a single session",
`Mcp-Session-Id`, the `initialize` handshake (replaced by `server/discover`),
`session_controller` / `session_*` callbacks, and "feature X is yet to come" when
X has since landed (multi-round-trip / `Input*`, subscriptions).

## Document what exists, not what doesn't

Document the library as it *is*. Do **not** write "negative documentation": text
describing what the library deliberately does **not** do, features considered and
rejected, or design alternatives not taken. If a capability does not exist, do not
mention it. Naming a missing feature oddly implies it was supposed to exist.

The `context/` specs especially record such decisions ("we chose not to provide
X", rationale for ruling something out), because weighing alternatives is their
job. Those are internal design notes, not guide material. Do not promote them into
a guide, however interesting the rationale.

Watch the line between two things that look similar:

- **An absence or a decision.** Example: "the framework does not include a pub/sub
  system." *Omit this.*
- **The developer's responsibility, or an integration point.** *Keep this*, but as
  a **clear, concrete directive**, not a vague abstraction. Name the real tools a
  developer would reach for so the sentence is actionable. Prefer "subscribe to
  your messaging system, for example `Phoenix.PubSub`, to receive the events you
  forward as notifications" over "the application provides the notification
  source".

## Accuracy comes first

Before writing, understand what you are documenting:

1. Read the relevant behaviour callbacks and their `@spec`s to learn the real
   arguments and return shapes. Document the *actual* parameters and returns.
2. Read enough of the bodies to know what they really do, including error returns
   and notable side effects.
3. When the topic touches the MCP protocol, make the guide protocol-aware (see
   "Protocol context" below). Do not invent protocol details. If unsure, describe
   only what the code guarantees.

When a topic's *purpose* (the "why") is unclear from the code alone, ground your
understanding in the spec documents under `context/` (a pm-managed
feature/spec tree). Start with `tree context`, then grep the tree for the module,
callback, or concept. Use that to write a guide that reflects the real purpose,
not a restatement of mechanics. If you still cannot determine what something does
or when it is used, **ask the user** rather than guess.

## House style

- **Dash-free prose.** No em-dashes or en-dashes (`—`, `–`). Restructure with a
  comma, a period, a colon, or parentheses. Keep sentences readable for people
  whose English is not strong, without over-correcting into terse, caveman
  phrasing or all-bullet text. Clear, plain prose with simple structure is the
  goal.
- **First sentence of a section** states what the section is about; do not bury it
  under throat-clearing.
- **Do not use the word "ride" (or "rides on") for state.** Use "the state is
  carried by" or "is handed to" the return/callback instead.
- Keep prose wrapped at roughly 90 columns, matching the existing files.
- Use Markdown headings to structure the guide. Guides are top-level pages, so
  they start at **h1** (`#`) for the title and use **h2** (`##`) / **h3** (`###`)
  for sections, matching the existing files. (This differs from module docs, whose
  sections start at h3 because they nest inside a module page.)
- **Avoid rhetorical/FAQ-style headings** like "Why does this matter?". Headings
  name a topic, not a question.
- Use admonitions where they help, in the existing style:

      > #### Heads up {: .info}
      >
      > Body text.

  Available kinds: `.info`, `.tip`, `.warning`, `.error`, `.neutral`.
- Document options/params as bullet lists, e.g. `* \`:option\` - what it does`.
- Cross-reference modules, functions, callbacks, and types with backticks so ExDoc
  autolinks them, **fully qualified** so the link resolves:
  - Module/function: `` `GenMCP.Suite` ``, `` `GenMCP.Suite.Tool.call/3` `` (not a
    bare or aliased `` `Suite.call/3` ``).
  - **Callbacks** use the `c:` prefix: `` `c:GenMCP.Suite.Tool.call/3` ``. Several
    modules export a function *and* a callback with the same name/arity, so `c:`
    disambiguates. Use `t:` for types.
  - Link between guides with a relative Markdown link, e.g.
    `[System Configuration](guides/009.system-configuration.md)`, matching how the
    existing guides cross-link.

## Examples

Examples are the heart of a guide. They must be code a reader would actually type.

- **Lead with the minimal example**, framed by at least one sentence saying what
  it demonstrates, then add complexity afterward, clearly marked as the advanced
  case. Do not bury the lede; do not oversimplify (the minimal example must
  actually work and hide no required step).
- **Write examples the way a user would, or leave them out.** Write from the
  caller's point of view, with the values the library hands them already in scope
  (the `channel` a callback was given, the `request`). Do not fabricate
  library-internal plumbing (building protocol structs the transport builds,
  receiving the framework's `{:"$gen_mcp", ...}` messages) to force an example to
  run. A good example is optional; no example beats a convoluted or misleading
  one.
- **Do not let example user-code look like a library feature.** Keep application
  code unmistakably the developer's own with the `MyApp` namespace, `:my_app`
  application, and `:some_queue_library`-style placeholder dependency names. Do not
  invent tuples or names a reader could mistake for a protocol construct (e.g. a
  `handle_message/4` clause matching `{:progress, done, total}` wrongly implies a
  built-in progress protocol; use an app-domain shape like
  `{:job_finished, job_id, result}`).
- **Prefer pattern matching over access syntax.** Destructure with a match
  (`%{"a" => a, "b" => b} = req.params.arguments`) rather than `map["key"]` or
  multiline `struct.field` chains. Match in a function *head* only for dispatch.
- **Use `GenMCP.MCP.V2607` helpers**, not raw struct literals, to build results
  and content (e.g. the result/content constructors). The tests show the idiomatic
  forms; read them and the `GenMCP.MCP.V2607` module.
- **Beware `#{}` interpolation in code blocks.** Plain fenced/indented code blocks
  in Markdown are not evaluated, so interpolation in them is fine as displayed
  text. But code inside a Readmix `:section` (see below) is real Elixir and is
  formatted, so it must compile.

## Readmix markers (`<!-- rdmx ... -->`)

The `docs` recipe in the `justfile` runs `Readmix` over `README.md` and every
`guides/**/*.md` at version-bump time (`mix.exs` `readmix/1`). Two marker kinds
appear in guides, and you treat them very differently:

- **`:section name:<name> format:true`** wraps a fenced code block. This code is
  **not generated**: you write and edit it freely. `format:true` means Readmix
  runs the Elixir formatter over it, so **the code must be valid, compilable
  Elixir** (it is also the code users copy). Keep the opening
  `<!-- rdmx :section ... -->` and closing `<!-- rdmx /:section -->` tags balanced
  around the block.
- **`:eval code:"..." as_text:true`** evaluates the given expression (e.g.
  `NimbleOptions.docs(GenMCP.Suite.init_opts_schema())`) and writes the result
  **between** its tags. That body is **generated**: do **not** hand-edit the text
  between the tags. If it is wrong, fix the source it derives from (the schema, the
  function) and re-run the `docs` recipe to regenerate it.

When you change a guide, leave every marker intact and balanced. After editing,
regenerate via the `docs` recipe so `:eval` bodies and `:section` formatting are
current.

## Guide files and registration

- Guides live in `guides/` and are named `NNN.slug.md` (e.g.
  `001.getting-started.md`). The numeric prefix orders them.
- Every guide must be listed in `mix.exs` `doc_extras/0`. `doc_extras/0` warns at
  compile time about any guide file on disk that is not referenced, so a **new
  guide must be added to that list** (and given a number). `groups_for_extras/0`
  groups all `guides/...` under "Introduction".
- When you add a new guide, pick an unused number, create `guides/NNN.slug.md`, and
  add it to the `defined_guides` list in `doc_extras/0`.

## Protocol context (2026-07-28 stateless core)

Keep these facts straight so guides are correct:

- The protocol version this library targets is **`2026-07-28`** (a draft or
  release candidate). The vocabulary modules live under `GenMCP.MCP.V2607`, with
  `GenMCP.MCP` as a facade.
- The transport core is **stateless**: there is **no `initialize` handshake** and
  no `Mcp-Session-Id`. The protocol version is carried by the
  `MCP-Protocol-Version` HTTP header and per-request `_meta`
  (`io.modelcontextprotocol/protocolVersion`). Capability discovery is
  `server/discover`.
- Servers run **per request**: per-request data arrives via the request and
  channel, not via long-lived session state. The replacement for server-held
  session state is the **explicit state-handle** pattern (a tool mints a handle
  like `basket_id`; the model passes it back as a normal argument).
- The Suite callback parameter order is: **subject first**, `channel`
  second-to-last, `arg` last. Describe parameters in that order.

## Checklist before you finish a guide

- [ ] Written from the current code and `context/` specs, not from the old guide
      text; no session / `initialize` / `Mcp-Session-Id` framing left.
- [ ] Leads with a minimal, honest, working example, framed by a sentence;
      complexity follows and is marked as such.
- [ ] Examples are written the way a user would write them, use `MyApp`/`:my_app`
      naming, and build results with `GenMCP.MCP.V2607` helpers.
- [ ] No negative documentation; responsibilities stated positively and concretely.
- [ ] No em/en-dashes; prose wrapped near 90 columns.
- [ ] Cross-references use backticks (with `c:`/`t:` where needed) and resolve;
      inter-guide links use relative paths.
- [ ] All `<!-- rdmx ... -->` markers are balanced; `:section` code compiles;
      `:eval` bodies were regenerated, not hand-edited.
- [ ] A new guide is added to `doc_extras/0`; `mix docs` renders with no
      unreferenced-guide warning.
