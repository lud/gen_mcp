---
name: follow-mcp-schema
description: >-
  Triage an MCP schema update in the gen_mcp library after `just update-schema`
  has pulled a new modelcontextprotocol draft and regenerated the entities. Use
  this whenever the upstream MCP schema changed and left uncommitted diffs in the
  working tree — regenerated `entities.ex`, a bumped `@schemas_ref` in `mix.exs`,
  failing tests after a schema bump — or when the user says they ran
  `update-schema`, wants to "follow the schema", review schema evolution, or work
  out what a new draft of the MCP spec means for the code. Trigger it even if the
  user only says "the schema changed" or "see what the update broke".
---

# Follow the MCP schema

The gen_mcp library tracks an unreleased draft of the Model Context Protocol. The
spec moves; this skill is how you keep the code in step with it, one update at a
time, without over- or under-reacting to churn.

## Where this work sits

This is part of a larger effort: **upgrading the library to follow the 2026-07-28
MCP spec**. That spec reworks a lot from earlier revisions — the stateless
transport, the `subscriptions/listen` channel that replaces `resources/subscribe`
and the HTTP GET stream, capability changes, and more. You already know the broad
shape of these changes from your training data; lean on that to recognise what an
incoming diff *means* rather than reverse-engineering each one from the JSON.

The upgrade is **mostly done**. What's left is tracking upstream schema updates as
they land between now and the release date — i.e. exactly the one-update-at-a-time
triage this skill describes. Most diffs are small follow-on adjustments to spec
text that has already been implemented, not net-new features.

Before going deep, **load the `pm-guide` skill** and look at the `pm` specs to see
where the implementation stands. The specs written under `pm` tracking are the best
map of what's been built (stateless core, transport, the V2607 surface, guides),
so they tell you whether an incoming change touches finished work or something
still open — which is what decides whether a diff "needs to happen" or is already
handled. Don't re-derive that from the code when the spec tracking already records
it.

## How you got here

The user runs `just update-schema` themselves (see the `justfile` recipe). That
recipe:

1. pulls the latest `main` of the `modelcontextprotocol` dep and writes the new
   commit SHA into `@schemas_ref` in `mix.exs`,
2. regenerates `lib/gen_mcp/mcp/v2607/entities.ex` from the new
   `schema/draft/schema.json` via `tools/gen-rpc-schemas.exs`,
3. runs `mix test`.

`update-schema` stops at the first failing step, so when this skill runs the
working tree is in one of two states:

- **Generation succeeded** — `entities.ex` carries diffs (and `mix.exs` a new
  `@schemas_ref`). The user called you to work out what those changes mean.
- **Generation failed partway** — most commonly the regen hit a new schema that
  isn't configured yet, so it raised *before* rewriting `entities.ex`. In that case
  there may be **no `entities.ex` diff at all**, even though the schema very much
  changed. Don't read an empty diff as "nothing happened" — it usually means the
  generation is broken and needs fixing first.

So `git diff` and `git status` are your starting point, but treat them as a hint,
not a verdict. The authority on the real state is re-running the generation
(Step 1) — which you do next regardless of what the diff shows.

Your job is mostly to **understand and explain**, not to fix on your own. The user
writes the production code in this project, so your output is an analysis they can
act on:

- **Get tests green — minimally and on your own only when the fix is trivial.** A
  schema bump can break the suite. Fix it yourself only when the cause is a
  mechanical, no-decision change (a renamed key, a missing/extra key, an enum value
  spelled differently). Anything that touches behaviour or structure is an
  architecture decision — explain it and let the user make the call.
- **Explain what the change means.** Separate the changes that *need* to happen for
  the code to stay correct from the ones that *could* happen (new surface we might
  choose to support), and the churn that should be ignored. Bring that to the user
  and decide together what to do — don't start implementing the supported surface
  unilaterally.

## Workflow

### 1. Always regenerate entities first

Run it even though `update-schema` already did — it is idempotent (same input
schema always yields the same `entities.ex`), so it costs nothing, and it is both
the thing that surfaces a missing schema configuration and the way you find out the
real state of the tree (an empty `git diff` doesn't mean nothing changed — see
above):

```bash
just gen-entities
```

This runs the generator and then `tools/check-entities.exs`. Two outcomes:

- **It raises** `generating schemas requires configuring the <Name> schema used in
  <location>`. This is the common reason a `update-schema` run failed and left no
  `entities.ex` diff: a new `$ref` has entered the supported surface and `<Name>`
  has no entry in the generator's allow/deny table, so the regen aborted before
  rewriting the file. **This one you fix yourself** — the generation config is
  yours to own (it's codegen plumbing, not an architecture decision). Add an entry
  for `<Name>` to the `mod_config:` keyword list at the bottom of
  `tools/gen-rpc-schemas.exs`, then re-run until green. Pick the value by what the
  schema is — follow the patterns already in that list:
  - `[]` — generate a normal struct module (most request/result/param types).
  - `:nogen` — do not generate a module; a `$ref` to it stays inline. Used for
    envelope/union/error types the runtime never builds directly.
  - `:lax` — treat as accept-any (the various `*Schema` definitions).
  - `[content_block: true]`, `[keep_nils: [...]]`, etc. — see neighbouring entries
    for the modifiers and copy the one that matches the role of the new type.
  The comment above the list explains the rule: the generate-set is the transitive
  `$ref` closure of the supported RPC surface; everything else is `:nogen`.
- **It completes cleanly** → `entities.ex` is now up to date. `git diff` it to see
  what generation produced: either nothing new (the config was already complete and
  `update-schema` had done it) or the diff you just unlocked by adding the missing
  config. Either way the codegen is settled — move on to the analysis.

**When `gen-entities` succeeds, leave `tools/gen-rpc-schemas.exs` alone.** It is a
large body of codegen that just works when no config change is needed, and reading
it will only pull your attention into generation mechanics. The only reason to open
it is the *raise* above (an unconfigured schema). Once the command is green, the
codegen is done — turn your full attention to the spec change itself: features,
the supported request surface, errors, and what the diff means for clients.

### 2. Run the full suite

```bash
mix test
```

It's fast — run the whole thing. Read each failure against the diff so you
understand *why* the schema change broke it. Then judge the fix:

- **Trivial / mechanical** (a renamed or moved key, a missing or extra key, a
  reworded enum value) → fix it yourself, minimally.
- **Anything else** (behaviour changes, a type that's now shaped differently, a
  capability gained or lost) → that's an architecture decision. Don't patch it to
  green on your own; explain what broke and what the options are, and let the user
  decide. A red suite that needs a real decision is a finding to report, not a
  thing to silence.

### 3. Read the diff for intent, not noise

Go through `git diff` on `entities.ex`, and when useful the upstream
`deps/modelcontextprotocol/schema/draft/schema.json`. Separate:

- **Churn — ignore it.** Renamed keys, reordered `$defs`, reworded descriptions,
  formatting. Not worth acting on and not worth logging.
- **Semantic change — act on it.** New request/notification types, new or removed
  params and fields, new enum members, new/removed capabilities, changed required-ness.

### 4. Map each change to the surface it touches

Work out where each semantic change *would* land, so you can explain it precisely —
this is analysis to bring to the user, not a checklist to go implement:

| Change | Where it lands |
| --- | --- |
| A request/notification the server should now accept | `lib/gen_mcp/validator.ex` — the recognized-method list. Commented-out entries (e.g. `PingRequest`, `SubscribeRequest`) are the deliberately-unsupported surface; un-comment / add to support one. |
| A new result builder or option a handler returns | `lib/gen_mcp/mcp/v2607.ex` (the `GenMCP.MCP.V2607` module) — add or extend a builder function/option. |
| A new error condition reported to clients | `lib/gen_mcp/error.ex`. |
| A capability/type that was removed or renamed upstream | Support for it may now be dead — flag it as a candidate for removal. |
| Anything outside the supported surface | Nothing to do — note it and move on. |

Not every schema change requires a code change. "Nothing to do" is a valid and
common outcome — the supported surface is intentionally a subset of the spec.

### 5. Present findings and decide together

Bring the analysis to the user as two clearly separated lists, then discuss before
implementing:

- **Needs to happen** — changes required for the code to stay correct (e.g. a field
  the runtime relies on changed shape, a tightened constraint that now rejects what
  we send).
- **Could happen** — newly available surface we *might* choose to support (a new
  request type, a new optional field, a new capability), each with a short note on
  what supporting it would involve.

Then respect the division of labour:

- The user writes the **production code** (the `validator.ex` surface, `V2607`
  builders, `error.ex`). Propose the change and, where it helps, write tests that
  pin the desired behaviour — but let the user implement, unless they explicitly
  ask you to write it.
- You own the generation config (`tools/gen-rpc-schemas.exs`) and tests.
- **Docs** follow the production code. The documentation rewrite is done, so docs
  are expected on shipped code — fix or update docs when asked, and after the user
  has written a piece of production code, offer to add its `@doc`/`@moduledoc`.
  Don't pre-emptively document code the user hasn't written yet.

### 6. Log the decision

Record what you decided in the living log — see below. Keep it to decisions and
architecture changes only.

## The decision log

[schema-update-log.md](schema-update-log.md) is a living document. Maintain it as
you work:

- Add an entry whenever you make a **decision** or an **architecture change**:
  started supporting a new request, added/removed a generated schema, chose to
  ignore a class of change, removed a capability, etc.
- Keep entries short — one or two lines. Record *what changed and why*, not how.
- **Don't** log churn (a renamed key, a reworded description, a reordered def).
  If you wouldn't mention it in a standup, it doesn't belong in the log.
- Newest entries on top. Include the upstream `@schemas_ref` (or its short SHA)
  the decision was made against — find it in `mix.exs`.

## Quick reference — where things live

- `justfile` — `update-schema` (user runs), `gen-entities` (idempotent regen).
- `tools/gen-rpc-schemas.exs` — the generator; its `mod_config:` list is the
  allow/deny table for which schemas become modules.
- `tools/check-entities.exs` — fails the regen when a referenced schema is
  unconfigured.
- `lib/gen_mcp/mcp/v2607/entities.ex` — generated; never edit by hand.
- `lib/gen_mcp/mcp/v2607.ex` — `GenMCP.MCP.V2607` result/content builders.
- `lib/gen_mcp/validator.ex` — recognized request/notification surface.
- `lib/gen_mcp/error.ex` — client-facing errors.
- `mix.exs` — `@schemas_ref` pins the upstream commit.
