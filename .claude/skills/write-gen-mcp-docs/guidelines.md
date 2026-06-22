# Documentation guidelines for gen_mcp

These rules apply to every `@moduledoc` and `@doc` you write in this repository.
They exist so that all docs read with one voice and render correctly under ExDoc
(the `mix docs` output published to HexDocs).

## Principles (read first)

1. **Accuracy from source.** Document the current code, and the `context/` specs
   when the purpose is unclear. Never trust the existing (stale) docs. When still
   unsure, ask the user.
2. **Lead with the minimal example.** After a short introduction, show the easy
   path first, then the complexity. Stay honest, never oversimplify.
3. **Document what exists.** No "negative documentation", no rejected
   alternatives, no roads not taken.
4. **Behaviours are the priority.** Their callback docs, and "how to wire the
   implementation into the library", are what users rely on most.
5. **Plain, dash-free prose.** Short sentences, concrete directives, and runnable
   doctests where possible.

The rest of this document expands each of these.

## Golden rule: existing docs are outdated, ignore them

This repository just finished a large rewrite to follow the MCP draft
specification (future version **2026-07-28**). **Any documentation already
present is stale and must be treated as if it were not there.**

- Do **not** trust an existing `@doc`/`@moduledoc` as a description of what the
  code does if the given module/function is still listed in the worklist file.
  Read the actual code instead.
- **Write from scratch, do not "improve" the old text.** Resist the urge to read
  the current docs and patch them with small, targeted edits. The library changed
  too much for that, and sniper-fixes silently inherit the old framing and its
  mistakes. Build your understanding from the code (and the `context/` specs),
  then write fresh prose. The best outcome is that you never read the old docs at
  all.
- Freely **replace** existing doc content for the functions you are assigned.
- The only source of truth is the current code: the function head, its `@spec`,
  the body, the types it references, and the surrounding module.
- `@spec` attributes are validated with dialyzer and can be trusted, but the
  actual algorithm is always the single source of truth.

## What you may and may not change

- You may add or replace `@moduledoc` and `@doc` attributes.
- **Do not add `@typedoc`.** This pass does not document types with `@typedoc`.
  The strip step removes any that already exist, and you must not write new ones,
  nor be tempted to add one because the strip removed it. Types still surface in
  the docs through their `@type`/`@spec`, and `t:` links still resolve. The user
  will add a `@typedoc` by hand later if one is ever needed.
- **Do not change code on your own initiative**: by default, no edits to function
  bodies, signatures, specs, guards, module attributes (other than the doc
  attributes above), or formatting of code. Documentation only. The one
  exception is when the user **explicitly tells you** to change production code
  during the run, then you may make exactly the change they ask for (and a small
  `# TODO`/comment they direct you to leave). Absent that instruction, never touch
  code; flag bugs you notice instead of fixing them.
- Never touch private functions, and do not add `@doc` to them.
- If a listed function already carries `@doc false`, or the module carries
  `@moduledoc false`, **do not** silently replace it with prose. Stop and ask the
  user whether the `false` should remain. In most cases it should (it marks an
  intentionally hidden function or module). Only write real docs for it if the
  user confirms. The skill's strip step preserves these `false` markers
  precisely so you still see them.

## Accuracy comes first

Before writing a single word, understand the thing you are documenting:

1. Read the function head and its `@spec` (if any) to learn the real arguments
   and return shape. Document the *actual* parameters and return values.
2. Read the body enough to know what it really does, including error/`{:error,
   _}` returns and notable side effects.
3. For behaviours, read the `@callback` definition and any default
   implementation, and explain *when* the callback is invoked and *what it must
   return*.
4. When the behaviour relates to the MCP protocol, make the doc protocol-aware
   (see "Protocol context" below). Do not invent protocol details. If unsure,
   describe only what the code guarantees.

The code tells you *what* a function does. When its *purpose* (the "why") is
unclear from the code alone, **ground your understanding in the spec documents**
before writing. These live under `context/` (a pm-managed feature/spec tree) and
explain the goals behind the rewrite:

- Start with `tree context` to see what is there.
- Search the spec files for the module or function name (e.g. grep the
  `context/` tree) to find the spec that motivated it. The specs describe intent,
  constraints, and decisions that the code does not state outright.
- Use that context to write a doc that reflects the real *purpose*, not just a
  restatement of the code mechanics.

If, even after consulting the code and the specs, you cannot determine what a
function does or when it is used, **ask the user**. They are available to help
and would rather clarify than have you guess. Never hesitate to ask. Only as a
last resort, when an answer is not forthcoming, fall back to a faithful, minimal
description and note the uncertainty briefly.

## Document what exists, not what doesn't

Document the library as it *is*. Do **not** write "negative documentation":
text describing what the library deliberately does **not** do, features that
were considered and rejected, or design alternatives not taken. If a capability
does not exist, simply do not mention it. A reader needs to know how to use what
is there. Cataloguing absent features is noise, and naming a missing feature
oddly implies it was supposed to exist.

Be warned: **the code, tests, and spec documents often record such decisions**
("we chose not to provide X", "no built-in Y", rationale for ruling something
out), and the `context/` specs especially so, since weighing alternatives is
their job. Those are internal design notes, useful to maintainers, but **not**
documentation material. Do not promote them into `@doc`/`@moduledoc`, no matter
how interesting the rationale seems. When an existing doc already contains such a
section, drop it during the rewrite (keep only the actionable part below).

Watch the line between two things that look similar:

- **An absence or a decision.** Example: "the framework does not include a
  pub/sub system." *Omit this.*
- **The developer's responsibility, or an integration point.** *Keep this*, but
  make it a **clear, concrete directive**, not a vague abstraction. Name the
  real tools a developer would reach for so the sentence is immediately
  actionable.

State responsibilities and integration points **positively**, in terms of what
the developer does, without dwelling on what the framework declined to build.

**Be concrete.** "The application provides the notification source" is too vague
to act on. Prefer something like: "This is the right place to subscribe to your
messaging system, for example `Phoenix.PubSub`, so you receive the events to
forward as notifications." Naming a common, concrete tool (like `Phoenix.PubSub`)
makes the directive obvious to newcomers while remaining perfectly clear to
people running more complex setups (their own `GenStage` pipeline, RabbitMQ,
etc.). They will map it to their stack without needing every option spelled out.

## House style

For a concrete style reference, look at a module of a *similar kind* already
listed under `# Documented` at the bottom of `tools/docs-to-write.txt` (a
behaviour to model a behaviour, a struct module to model a struct module), not
simply the most recently finished one. Those were written under these rules, so
they are good examples to take inspiration from. Take inspiration, do not copy
their shape: these guidelines are the authority, and an earlier module may
predate a guideline change. Until a module has been documented (you may be the
first), rely on these guidelines.

- Use heredoc strings: `@doc """ ... """`.
- **Beware `#{}` interpolation in heredocs.** `@doc """ ... """` is a normal
  double-quoted string, so any `#{...}` inside example code is interpolated at
  compile time, which usually breaks the build. When a doc contains code with
  interpolation, write the attribute with the `~S` sigil (`@doc ~S"""..."""`,
  `@moduledoc ~S"""..."""`), which turns off interpolation and escaping. If you
  need interpolation in the prose but a literal `#{` somewhere, escape it as
  `\#{`.
- **First line** is a single, concise summary sentence ending with a period.
  Prefer declarative phrasing: "Returns the ...", "Builds a ...", "Called
  when ...".
- **No em-dashes or en-dashes** (`—`, `–`) in documentation prose. Restructure
  the sentence instead: deliver purpose, precision, or causality with a comma, a
  plain period, a colon, or parentheses. This keeps sentences readable for people
  whose English is not strong. Do not over-correct into terse, caveman phrasing
  or all-bullet text. Clear, plain prose with simple sentence structure is the
  goal.
- **Do not use the word "ride" (or "rides on") for state.** Use wording like "the state
  is carried by" or "is handed to" the return/callback instead.
- **Prefer pattern matching over access syntax in example code.** Avoid
  `map["key"]` or multiline `struct.field` chains to pull values out; destructure with a
  match in the function body instead, e.g. `%{"a" => a, "b" => b} =
  request.params.arguments`. Match in the function *head* only for dispatch (such
  as routing on a tool name), not to bind every value the body needs.
- Leave a blank line after the summary, then add detail paragraphs as needed.
- Keep prose wrapped at roughly 90 columns, matching the existing files.
- Use Markdown: `### Examples` headers (see "Layout and headings" for the
  heading level rule), bullet lists for options and parameters, and indented
  (4-space) or fenced code blocks for examples.
- Cross-reference other modules and functions with backticks so ExDoc autolinks
  them: `` `GenMCP.Suite` ``, `` `handle_request/3` ``, `` `t:GenMCP.MCP...` ``.
  - **Fully qualify** module references so the link resolves: write
    `` `GenMCP.Suite.my_function/3` ``, not `` `Suite.my_function/3` ``. A bare
    or aliased name will not autolink.
  - Reference a **callback** (as opposed to a function) with the `c:` prefix:
    `` `c:GenMCP.Suite.Tool.call/3` ``, as in "see callback `c:MyModule.my_fun/3`".
    This matters here because several modules export a function *and* a callback
    with the same name/arity, so the `c:` prefix disambiguates and links to the
    right one. Likewise use `t:` for types.
- Use admonitions where they help, in the existing style:

      > #### Deprecated {: .warning}
      >
      > Body text.

  Available kinds: `.info`, `.tip`, `.warning`, `.error`, `.neutral`.

- Document options/params as bullet lists, e.g.:

      * `:min_log_level` - description of the option.

- Examples: see "Examples and doctests" below for the rules on what to show and
  when to use the doctest syntax.

## Layout and headings

- **Heading level**: sections inside a `@doc`/`@moduledoc` use **h3** (`###`).
  Sub-sections may use **h4** (`####`) when it genuinely helps, but prefer
  conciseness over nesting. Reach for an h4 only when an h3 section is long
  enough to warrant splitting.
- **Sections are topical, not per-callback.** Only add sections when a moduledoc
  is long because the module covers a lot of ground, and then split by *aspect,
  topic, or use case*. For example, `GenMCP.Suite.Tool` might have a general
  section, an asynchronous-tools section, and an error-handling section. Do
  **not** add one section per callback or per function.
- **Avoid rhetorical/FAQ-style headings** like "Why does this matter?" or "Who
  handles this?". Headings name a topic, not a question.
- **The minimal example lives in the main body**, not under a heading. "First"
  means first *among the examples*, not the first thing on the page: at least an
  introductory sentence, and ideally a short explanatory paragraph, comes before
  it so the reader knows what they are about to see.
- **Additional examples** can be grouped under a single `### Examples` section
  when they follow one another with little prose between them. Every example,
  whether inline or under the section, needs **at least one descriptive sentence
  above it** saying what it demonstrates.

## Conciseness by function kind

- **Trivial constant accessors** (e.g. a `method/0` that returns the JSON-RPC
  method string for a request struct): one short sentence is enough. Example:
  "Returns the MCP method name (`tools/call`) for this request." Do not pad.
- **Behaviour / OTP callbacks that are implementation details** (e.g. GenServer
  `handle_call/3`, `code_change/3`, `child_spec/1` on internal servers): if the
  function is not part of the public API, prefer `@doc false` over an invented
  description. Use a real `@doc` only when a caller genuinely benefits.
- **Public API functions**: full treatment, meaning summary, parameters, return
  values, errors, and an example when it aids understanding.

## Documenting behaviour modules

For a behaviour module, split responsibilities cleanly between the `@moduledoc`
and the individual `@doc` on each callback:

- The **`@moduledoc` documents the behaviour as a whole**: its purpose, why it
  exists, and when a developer reaches for it. Lead ("lede") with a **minimal
  viable implementation**, the smallest module that satisfies the behaviour and
  does something useful, then give implementation tips and rules for developers
  (what each callback is responsible for, invariants, ordering, gotchas). More
  complex, end-to-end examples can be added when they genuinely help, but in most
  cases the per-callback examples carry that weight, so keep the moduledoc
  focused on the overall picture.
  - **Minimal must still be useful, not vacuous.** "Minimal" means the fewest
    moving parts, *not* a server that does nothing. A handler returning an empty
    catalog or only rejecting requests teaches the shape but leaves the reader
    unsure how a real implementation looks. Prefer the smallest example that
    actually *does* something a reader recognizes: one working tool (an `add`
    calculator, say) that is listed and called, over an empty stub. Some function may
    remain empty, return only errors, etc. as long as at least one function is useful
    and confers some value to the example implementation.
  - **Push the domain logic into a separate plain module.** Keep the behaviour
    implementation a thin adapter, and delegate the real work (the computation,
    the tool's schema) to an ordinary module with no library concern. This shows
    the intended separation and stops the example from conflating "implement the
    behaviour" with "write the feature". For example, an `add` tool's `MyServer`
    only routes the request, while a `Calculator` module owns `tool/0` and
    `add/2`.
- The **per-callback `@doc` stays focused on that one callback**: its specific
  contract, arguments, return values, and an example targeted at *that* callback
  (see "Documenting callbacks" below).

A moduledoc-level example is worth adding when behaviour spans multiple callbacks
and the *interaction* is the point. For instance, showing how `GenMCP.Suite.Tool`
and `GenMCP.Suite.SubscriptionHandler` carry state from the
`c:GenMCP.Suite.Tool.call/3` (or `c:GenMCP.Suite.SubscriptionHandler.subscribe/3`)
callback through to `handle_message/4` is the kind of cross-callback flow that
belongs in the moduledoc, because no single callback doc can show it.

### Show how the implementation is wired into the library

A developer who implements a behaviour also needs to know **how to hand that
implementation to the library**. The moduledoc must show this.

- **Before writing, find out how the behaviour is actually wired.** Search the
  code and tests (the `test/` tree and the `GenMCP.TestWeb` routers are good
  sources) for where implementations of this behaviour get passed in. Document
  what you find. Do not guess the wiring.
- **Most behaviours are consumed by `GenMCP.Suite`**, which is the default
  `:server` for the transport plug. So their moduledoc example should show
  passing the implementation to `GenMCP.Suite` via its options. This typically
  happens in a Plug router. Show that router/option wiring.
- **`GenMCP` is the notable exception**: `GenMCP.Suite` itself *implements* the
  `GenMCP` behaviour. A custom `GenMCP` implementation is still handed to the
  transport plug the same way Suite is, as the plug's `:server` option in a
  router. Show that.
- These **wiring and implementation examples must not be doctests**. They are
  module/router definitions and option keywords, not REPL expressions, so do not
  use the `iex>` prefix. Use a plain fenced or indented Elixir code block.

### Use V2607 helpers in examples

Many behaviour callbacks return structs from the `GenMCP.MCP.V2607` vocabulary.
Examples should build those results with the **helper functions from that
module** (e.g. the result/content constructors) rather than hand-writing raw
struct literals. The tests contain many examples of using these helpers. Read
them, and read the `GenMCP.MCP.V2607` module itself, to use the idiomatic form.

## Documenting callbacks

Callback docs are **the most valuable documentation in this library**. They are
what people read to learn how to use it. Invest the most effort here.

Every callback doc should include:

- **A minimal example, almost always.** This is the single most important part:
  it gets people started quickly and shows how easy the common case is. Lead with
  it. Skip it only when an honest example cannot be shown without fabricating
  setup the user never writes (see "Write examples the way a user would" below); a
  missing example beats a misleading one.
- **A description of each option**, when the callback takes options, as a
  bullet list (`* \`:option\` - what it does, default, allowed values`).
- **Further examples for meaningful variations**, when they exist. To keep the
  docs short, prefer grouping several variations into a *single* example rather
  than many tiny separate ones.
- **A fully-featured example** for callbacks with many options or possibilities,
  shown to contrast with the minimal one, so readers see both the easy path and
  the full surface.

Balance two things:

- **Do not oversimplify.** This library has real complexity and that is fine.
  The minimal example must stay honest. It should actually work and not hide
  required steps. Honesty matters more than apparent simplicity.
- **Do not bury the lede.** The minimal example comes first among the examples,
  after a brief introduction that frames it. Complexity comes after, clearly
  marked as the advanced or edge case.

## Examples and doctests

The same principle applies to plain functions: a simple example demonstrating
the most commonly used inputs and outputs first, then more complex examples for
edge cases.

**Write examples the way a user would, or leave them out.** An example exists to
show the reader the code they would actually type, so write it from the caller's
point of view, with the values the library hands them already in scope (the
`channel` a callback was given, the `request`, the `state`). Do not fabricate
library-internal plumbing to force an example to run: building protocol structs
that the transport builds, or `receive`-ing the framework's own `{:"$gen_mcp",
...}` messages, parades machinery the reader never touches and quietly turns the
example back into a unit test. When a faithful example would need that plumbing to
be runnable, do not contort it into a doctest. Prefer a short illustrative
(non-doctest) block in the natural calling context, for example a handler clause
calling the function on the `channel` it was given, or omit the example entirely.
**A good example is optional, and no example is better than a convoluted or
misleading one.** Reserve runnable doctests for call sites that are themselves
simple and self-contained, typically pure helpers called with plain data.

**Do not let example user-code look like a library feature.** When an example
shows application code (a message the handler receives, a struct it builds, a
function it calls), keep it unmistakably the developer's own by using `MyApp` namespace, `:my_app` application, or `:some_queue_library` libraries (for a message queue system in this example). Do not invent tuples or names that a reader could mistake for a
protocol construct or a built-in subsystem the library does not provide. For
instance, a `handle_message/4` clause matching `{:progress, done, total}` wrongly
implies the library has a progress-tracking message protocol; use a plainly
app-domain shape like `{:job_finished, job_id, result}` instead. The reader must
be able to tell at a glance what the library gives them from what they wrote
themselves.

**Prefer the doctest syntax** whenever the example can be expressed as one.
Doctests are executable, so they cannot drift out of date. Format (see
<https://ex-unit.hexdocs.pm/1.20.1/ExUnit.DocTest.md>):

    ### Examples

        iex> GenMCP.protocol_version()
        "2026-07-28"

    Multi-line expressions continue with `...>`:

        iex> result =
        ...>   MyServer.build(:thing)
        iex> result.ok
        true

Rules for doctests:

- The last unprefixed line is the **expected result**. You do not need to know
  the exact comparison rules: write the example, then run `mix test --warnings-as-errors` to confirm. (Whole test suite is fast.)
- **Make sure the doctests actually run.** A doctest only runs if a test module
  invokes `doctest TheModule`. If the module's genuine test file already has that
  line, you are set. If it does not, or the module has no test file, you **may**
  enable the doctests yourself: add `doctest TheModule` to the genuine test
  module, or create a small test module whose only job is to invoke
  `doctest TheModule` (no other test cases). Match the project's existing test
  conventions. This is the one test-code change the skill permits. Production
  code under `lib/` stays untouched.
- **No doctest for a pure constant.** A function that takes no input and has no side
  effects, returning a fixed value (e.g. `protocol_version/0` → `"2026-07-28"`, a
  `method/0` returning a static string), does not get a doctest example. Doctests are for
  showing how to *use* something with real inputs.
- **Do NOT state constant functions return values** in prose unless the function returns a
  module attribute that you can interpolate. We don't want the docs and code to drift.
- **Doctests document, they do not unit-test.** Their purpose is to prove the
  examples in the docs are correct, so the role of each one is clear, readable
  documentation. Do not use the "you may add doctests" permission as a backdoor
  to grow test coverage for otherwise-untested code. Write a doctest only when it
  earns its place as a good example: if it would not help a reader, it does not
  belong in the docs even if it would happen to exercise the code.
- **You may omit the expected result line, and the code still runs** (the return
  value is just not asserted). Use this for helper functions that build large or
  deeply nested structs, where reproducing the full struct as the expected line
  is impractical. Write the `iex>` line(s) with no following result line.
- Use a non-doctest (illustrative) code block when the example is not runnable or
  deterministic (it needs a running server, network, or randomness), or when
  making it runnable would require fabricating setup the user never writes
  (constructing values the library hands them, receiving the framework's internal
  messages). In those cases an illustrative block in the real calling context, or
  no example at all, beats a contrived doctest.
- **Run `mix test` after writing doctests** (the suite is fast) to confirm they
  actually pass. This is ground truth: it catches a wrong expected line, a
  mistyped helper, or heredoc interpolation breakage. Beyond enabling doctests
  (see the rule below), do not edit tests to force them to pass, and never change
  `lib/`.

## Protocol context (2026-07-28 stateless core)

Keep these facts straight so docs are correct:

- The protocol version this library targets is **`2026-07-28`** (a draft or
  release candidate). The vocabulary modules live under `GenMCP.MCP.V2607`.
- The transport core is **stateless**: there is **no `initialize` handshake**.
  The protocol version is carried by the `MCP-Protocol-Version` HTTP header and
  per-request `_meta` (`io.modelcontextprotocol/protocolVersion`), and is
  advertised via `server/discover`.
- Servers run **per request**: `init/1` runs for each request, and per-request
  data arrives via the request and channel, not via long-lived session state.
- Anything tied to the legacy stateful session path may be deprecated or being
  removed. If the code marks something deprecated, reflect that with a
  `> #### Deprecated {: .warning}` admonition and say what replaces it.

## Suite callback argument order

When documenting `GenMCP.Suite` callbacks and related behaviours, the parameter
order convention is: **subject first**, `channel` second-to-last, `arg` last.
Describe parameters in that order and name them accordingly.

## Checklist before you finish a module

- [ ] The module's `@moduledoc` is written, plus a doc for every listed
      function/callback (or a confirmed `@doc false`, having asked the user
      before replacing an existing `@doc false`).
- [ ] Each doc was written from the current code, not from any prior doc text.
- [ ] Callbacks lead with a minimal example (introduced by a sentence first),
      document each option, and add variation/full examples where useful.
- [ ] Docs with interpolation in code use `~S"""` (or escape `\#{`).
- [ ] Examples use doctest syntax where runnable, and `mix test` is green.
- [ ] No code was changed, only doc attributes.
- [ ] Cross-references use backticks, and admonitions/Markdown render correctly.
