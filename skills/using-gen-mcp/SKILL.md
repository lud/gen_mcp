---
name: using-gen-mcp
description: >-
  Build an MCP (Model Context Protocol) server in Elixir with the gen_mcp
  library — defining tools, resources, prompts, subscriptions, and the HTTP
  transport. Use this whenever the user is writing or wiring an MCP server in an
  Elixir/Phoenix app, mentions gen_mcp, GenMCP, GenMCP.Suite, MCP tools/resources/prompts,
  or the StreamableHTTP transport — even if they don't name the library. Covers
  exposing functions to LLM clients as tools, serving data as resources, and
  returning results with the GenMCP.MCP.V2607 helpers.
---

# Using gen_mcp

`gen_mcp` is an Elixir library for building **MCP servers** (the server side of
the Model Context Protocol). You define tools, resources and prompts as plain
modules and mount one HTTP plug. This skill gives the patterns; the library's own
moduledocs are the source of truth for full option lists.

## Mental model — read this first

- **Stateless, per request.** For each JSON-RPC request the library spawns a
  *fresh worker process* (distinct from the HTTP connection process): `init`
  builds state, the handler answers, then the worker dies. Nothing is shared
  between requests. Per-request client context (client info, auth, meta) arrives
  through the **channel**, never through long-lived session state.
- **Protocol version is `2026-07-28`.** Clients must send it.
- **Two ways to build a server:**
  - **`GenMCP.Suite`** (default, high-level) — list provider modules (tools,
    resources, prompts), it advertises and routes them. Use this almost always.
  - **`GenMCP` behaviour** (low-level) — implement request handling yourself.
    Only when you need full control. See `references/custom-server.md`.
- **Build every result with `GenMCP.MCP.V2607` helpers**, aliased `as: MCP`.
  Never hand-build result structs.
- **Keep providers thin.** A tool/repo should validate input and shape output;
  push real logic into a plain module with no MCP concern.

## Decision tree

- Client calls an operation (function with args) → **Tool** (`GenMCP.Suite.Tool`).
- Client reads addressable content (file, record, document) → **Resource repo**
  (`GenMCP.Suite.ResourceRepo`). See `references/providers.md`.
- Client fetches a reusable message template → **Prompt repo**
  (`GenMCP.Suite.PromptRepo`). See `references/providers.md`.
- What's exposed varies per request (auth, tenant) → **Extension**
  (`GenMCP.Suite.Extension`). See `references/providers.md`.
- Client wants a live notification stream → **Subscription handler**
  (`GenMCP.Suite.SubscriptionHandler`). See `references/providers.md`.
- You need to own the whole request lifecycle → raw **`GenMCP` behaviour**. See
  `references/custom-server.md`.

## Install

```elixir
def deps do
  [{:gen_mcp, "~> 0.10"}]
end
```

## Minimal server

A tool plus the router mount. This is the whole getting-started path.

Define a tool:

```elixir
defmodule MyApp.AddTool do
  use GenMCP.Suite.Tool,
    name: "add",
    description: "Adds two numbers and returns the sum.",
    input_schema: %{
      type: :object,
      properties: %{a: %{type: :number}, b: %{type: :number}},
      required: [:a, :b]
    }

  alias GenMCP.MCP.V2607, as: MCP

  @impl true
  def call(request, _channel, _arg) do
    %{"a" => a, "b" => b} = request.params.arguments
    {:result, MCP.call_tool_result(text: "#{a + b}")}
  end
end
```

Mount it (Phoenix router). The transport plug serves a `GenMCP.Suite` out of the
box, so you pass the Suite's options — name, version, providers — straight to it:

```elixir
scope "/mcp" do
  forward "/", GenMCP.Transport.StreamableHTTP,
    server_name: "My App",
    server_version: "1.0.0",
    tools: [MyApp.AddTool]
end
```

`:server_name` and `:server_version` are **required**. Add `resources:`,
`prompts:`, `extensions:`, `subscription_handler:` as needed.

Smoke-test with curl (note the headers carry the method and protocol version):

```bash
curl http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: tools/call" -H "Mcp-Name: add" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
       "params":{"name":"add","arguments":{"a":2,"b":3},
       "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28",
                "io.modelcontextprotocol/clientInfo":{"name":"curl","version":"1.0"},
                "io.modelcontextprotocol/clientCapabilities":{}}}}'
```

## Tools

`use GenMCP.Suite.Tool` generates metadata + argument validation from options,
leaving you to implement `call/3`. Callback signature is always
`(request, channel, arg)` — subject first, `arg` last.

**Arguments arrive as a string-keyed map** (from `:input_schema`). Destructure
`request.params.arguments` with string keys: `%{"a" => a}`.

**To cast arguments into a struct**, point `:input_schema` at a `JSV` schema
module built with `defschema`; `call/3` then receives the struct:

```elixir
defmodule MyApp.AddTool do
  use GenMCP.Suite.Tool, name: "add", input_schema: Add
  use JSV.Schema
  alias GenMCP.MCP.V2607, as: MCP

  defschema Add, a: number(), b: number()

  @impl true
  def call(%{params: %{arguments: %Add{a: a, b: b}}}, _channel, _arg) do
    {:result, MCP.call_tool_result(text: "#{a + b}")}
  end
end
```

**To validate by other means** (e.g. Ecto), implement `validate_request/2`
yourself — `use` then skips generating one, and `:input_schema` is used only to
describe the tool. Return `{:ok, request}` or `{:error, reason}`.

**To return a tool-level error the model can read** (vs a protocol error), pass
`error:` to the result helper:

```elixir
{:result, MCP.call_tool_result(error: "Upstream service unavailable")}
```

Use `{:error, "message"}` from `call/3` only for a true *protocol* error.

### Streaming tools

When the result is produced *elsewhere* and arrives as a process message, return
`{:stream, state}` from `call/3`. Subscribe to your event source first, then
handle each message in `handle_message/4`:

```elixir
@impl true
def call(_request, _channel, _arg) do
  MyApp.ReportBuilder.start(self())   # your worker; sends messages to this process
  {:stream, %{lines: []}}
end

@impl true
def handle_message({:report_line, line}, channel, %{lines: lines} = state, _arg) do
  GenMCP.Mux.Channel.send_progress(channel, length(lines) + 1, nil, "building report")
  {:stream, %{state | lines: [line | lines]}}
end

def handle_message(:report_finished, _channel, %{lines: lines}, _arg) do
  {:result, MCP.call_tool_result(text: Enum.join(Enum.reverse(lines), "\n"))}
end
```

`handle_message/4` returns the same shapes as `call/3`: `{:stream, state}` to
keep waiting, `{:result, result}` / `{:error, reason}` to finish. Implement the
optional `handle_close/3` to clean up if the client disconnects mid-stream.

`call/3` runs in the request's dedicated worker process, so run blocking work
right there — make the HTTP call, query the database, then return `{:result, _}`.
No need to spawn a `Task` to await it; the worker is already yours to block.
Reach for `{:stream, _}` only when the result is produced elsewhere and arrives
as a message.

## Building results — V2607 cheat-sheet

Alias `GenMCP.MCP.V2607, as: MCP`. Common helpers:

- `MCP.call_tool_result(text: "...")` — text result.
- `MCP.call_tool_result(data: map)` — structured result + JSON text mirror.
  `_data:` sets structured content without the text mirror.
- `MCP.call_tool_result(error: "msg")` — tool-level error (sets `isError`).
- `MCP.call_tool_result([{:text, "a"}, {:image, {"image/png", b64}}])` — list of
  content blocks (`:text`, `:image`, `:audio`, `:resource`, `:link`).
- `MCP.read_resource_result(uri: uri, text: body, mime_type: "text/markdown")`.
- `MCP.get_prompt_result(description: "...", text: "...")`.

## Passing per-request data (auth, tenant) to providers

The channel carries `meta` (read-only client meta + your assigns). Two transport
options feed it:

- `assigns: %{...}` — static map merged into the channel for every request.
- `copy_assigns: [:current_user]` — keys copied from the `conn` assigns (set by
  your upstream plugs/auth) into the channel.

Providers read them via `channel.meta`:

```elixir
forward "/mcp", GenMCP.Transport.StreamableHTTP,
  server_name: "My App", server_version: "1.0.0",
  tools: [MyApp.SearchTool],
  copy_assigns: [:current_user]
```

```elixir
def call(request, channel, _arg) do
  %{current_user: user} = channel.meta
  ...
end
```

To vary *which* providers are exposed per request, use an Extension
(`references/providers.md`).

## Provider arguments (`arg`)

Every provider entry is a bare `module` (treated as `{module, []}`) or
`{module, arg}`. `arg` is handed to every callback as its **last** argument — use
it to configure one generic module differently per Suite:

```elixir
resources: [{MyApp.FileResource, root: "/srv/docs"}]
```

## Gotchas

- **Args are string-keyed maps**, not atoms, unless you cast with a `defschema`
  module. `%{"a" => a}`, not `%{a: a}`.
- **Never build result structs by hand** — use `MCP.*` helpers.
- **`error:` in `call_tool_result` ≠ `{:error, _}` from `call/3`.** The first is
  a tool error the model reads; the second is a protocol error.
- **Stateless**: don't stash anything in module/ETS state expecting it to survive
  to the next request. Carry continuation data via the channel/return values.
- **Callback arg order**: subject first, `channel` second-to-last, `arg` last.
- **Each request gets its own dedicated worker process** (not the HTTP
  connection process) — blocking in `call/3` is safe and normal.
- **Allowed origins**: browsers are checked against `:allowed_origins` (DNS-
  rebinding protection). Set it (or `allowed_origins: :any` behind a gateway) for
  browser clients.
- **Same plug module forwarded twice** (Phoenix < 1.8, or for URL generation):
  use `StreamableHTTP.defplug/1` to make a distinct module per mount.

## Reference files

- `references/providers.md` — resource repos (static, templated, pagination),
  prompt repos, subscription handlers, extensions.
- `references/custom-server.md` — implementing the raw `GenMCP` behaviour.

## Source of truth

For full option lists and edge cases, read the moduledocs. URLs are the module
name under `https://gen-mcp.hexdocs.pm/`, ending in `.md` (the plain-text form —
cheaper to load than the HTML page):

- [`GenMCP.Suite`](https://gen-mcp.hexdocs.pm/GenMCP.Suite.md) — Suite options and provider conventions
- [`GenMCP.Suite.Tool`](https://gen-mcp.hexdocs.pm/GenMCP.Suite.Tool.md)
- [`GenMCP.Suite.ResourceRepo`](https://gen-mcp.hexdocs.pm/GenMCP.Suite.ResourceRepo.md)
- [`GenMCP.Suite.PromptRepo`](https://gen-mcp.hexdocs.pm/GenMCP.Suite.PromptRepo.md)
- [`GenMCP.Suite.Extension`](https://gen-mcp.hexdocs.pm/GenMCP.Suite.Extension.md)
- [`GenMCP.Suite.SubscriptionHandler`](https://gen-mcp.hexdocs.pm/GenMCP.Suite.SubscriptionHandler.md)
- [`GenMCP.Transport.StreamableHTTP`](https://gen-mcp.hexdocs.pm/GenMCP.Transport.StreamableHTTP.md)
- [`GenMCP.MCP.V2607`](https://gen-mcp.hexdocs.pm/GenMCP.MCP.V2607.md) — the result helpers
- [`GenMCP.Mux.Channel`](https://gen-mcp.hexdocs.pm/GenMCP.Mux.Channel.md)
- [`GenMCP`](https://gen-mcp.hexdocs.pm/GenMCP.md) — the low-level behaviour

Machine-readable index of all modules: https://gen-mcp.hexdocs.pm/llms.txt
