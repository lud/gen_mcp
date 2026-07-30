# Custom server — the raw `GenMCP` behaviour

Reach for this only when a Suite can't express what you need (full control over
request handling). Otherwise use `GenMCP.Suite` + providers.

## How it runs

Per request, the transport starts a fresh process and calls, in order, `init/1`
→ the handler → any `handle_message/3` (while streaming) → `handle_close/2`.
Every callback for a request runs in that **same process**, so a handler may keep
transient data in `state`, read its mailbox, and block safely. Separate requests
share nothing. Per-request client context comes from the `channel`, not `init/1`.

Requests are typed structs from `GenMCP.MCP.V2607` (`ListToolsRequest`,
`CallToolRequest`, `ListResourcesRequest`, `ReadResourceRequest`, prompt
requests, `server/discover`, etc.). Match on them in `handle_request/3`.

## Minimal implementation

```elixir
defmodule MyServer do
  @behaviour GenMCP
  alias GenMCP.MCP.V2607, as: MCP

  @impl true
  def init(_arg), do: {:ok, %{}}

  @impl true
  def handle_request(%MCP.ListToolsRequest{}, _channel, _state) do
    {:result, MCP.list_tools_result([Calculator.tool()])}
  end

  def handle_request(%MCP.CallToolRequest{params: %{name: "add"}} = request, _channel, _state) do
    %{"a" => a, "b" => b} = request.params.arguments
    {:result, MCP.call_tool_result(text: "#{Calculator.add(a, b)}")}
  end

  def handle_request(_request, _channel, _state) do
    {:error, :method_not_found}
  end

  @impl true
  def handle_notification(_notification, _channel, _state), do: :ok

  @impl true
  def handle_message(_message, _channel, _state), do: {:stop, :normal}
end
```

`handle_close/2` is optional. The `Calculator` here is a plain module owning the
tool's schema and logic, keeping the server a thin protocol adapter.

## Wiring

Hand it to the transport via `:server` (the default is `GenMCP.Suite`, so set
this only for a custom server):

```elixir
forward "/mcp", GenMCP.Transport.StreamableHTTP, server: MyServer
```

A bare module gives `init/1` the leftover transport options as a keyword list.
Pass `{MyServer, arg}` to hand `init/1` an explicit `arg`:

```elixir
forward "/mcp", GenMCP.Transport.StreamableHTTP, server: {MyServer, mode: :read_only}
```

## Terminate or keep streaming

Each request either terminates with one response or holds open as SSE:

- `handle_request/3` returns `{:result, result}` or `{:error, reason}` to answer
  immediately, or `{:stream, state}` to keep streaming.
- While streaming, every Erlang message the worker receives goes to
  `handle_message/3` with the carried `state`. Keep open with `{:stream, state}`;
  end with `{:result, result}`, `{:error, reason}`, or `{:stop, reason}`.

State is carried **only** by `{:stream, state}` (the one return with a successor
callback). Terminal returns end the worker and carry no state.

Because the worker is a process dedicated to this request, computing or waiting
needs no streaming — run the work directly in `handle_request/3` and return
`{:result, result}`. Stream when the result is produced elsewhere and arrives as
a message:

```elixir
def handle_request(%MCP.CallToolRequest{} = request, _channel, _state) do
  {:ok, job_id} = MyApp.JobQueue.enqueue(self(), request.params.arguments)
  {:stream, %{job_id: job_id}}
end
```

See the `GenMCP` moduledoc for the complete callback contract.
