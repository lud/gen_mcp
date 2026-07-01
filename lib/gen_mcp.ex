defmodule GenMCP do
  @moduledoc ~S"""
  Behaviour for an MCP server that handles JSON-RPC requests over the stateless
  `2026-07-28` transport.

  A module implementing `GenMCP` answers Model Context Protocol requests: listing
  and calling tools, listing and reading resources, listing and getting prompts,
  and the `server/discover` capability snapshot. The library runs the
  implementation **per request**. For every incoming message the transport starts
  a fresh worker process that calls `c:init/1` to build the state, then the
  matching handler. The per-request client context (client info, capabilities,
  negotiated protocol version, authorization assigns) is read from the
  `t:GenMCP.Mux.Channel.t/0` passed to every callback, not from `c:init/1`.

  ## Choosing between `GenMCP.Suite` and a custom implementation

  For most servers, reach for `GenMCP.Suite` instead of implementing this
  behaviour yourself. `GenMCP.Suite` is a ready-made `GenMCP` implementation, and
  the default server, that serves tools, resources, and prompts from a composable
  set of providers: you describe *what* to expose and it handles the protocol
  wiring. It fits the general, high-level case, and it is where to start.

  Implement `GenMCP` directly when you need tight control over request handling,
  for a specific need the provider model does not cover: routing raw requests
  yourself, driving the SSE stream by hand, or shaping responses that the
  providers do not express. The rest of this document is for that case.

  ## One process per request

  Each request gets its **own dedicated process**, and every callback for that
  request runs **in that same process**, one after another: `c:init/1`, then the
  handler, then any `c:handle_message/3` calls, then `c:handle_close/2`. So a
  handler can keep transient data in `state`, read its process mailbox, and block
  safely without affecting anyone else. Separate requests run in **separate
  processes** and share none of that state.

  ## Minimal implementation

  A server that exposes a single `add` tool. It advertises the tool on
  `tools/list` and runs it on `tools/call`, delegating the real work to a plain
  `Calculator` module so the server stays a thin protocol adapter:

      defmodule MyServer do
        @behaviour GenMCP

        alias GenMCP.MCP.V2607, as: MCP

        @impl true
        def init(_arg) do
          {:ok, %{}}
        end

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
        def handle_notification(_notification, _channel, _state) do
          :ok
        end

        @impl true
        def handle_message(_message, _channel, _state) do
          {:stop, :normal}
        end
      end

  The `Calculator` module owns the tool's schema and its logic, with no MCP
  concern of its own:

      defmodule Calculator do
        alias GenMCP.MCP.V2607, as: MCP

        def tool do
          %MCP.Tool{
            name: "add",
            description: "Adds two numbers and returns the sum.",
            inputSchema: %{
              "type" => "object",
              "properties" => %{
                "a" => %{"type" => "number"},
                "b" => %{"type" => "number"}
              },
              "required" => ["a", "b"]
            }
          }
        end

        def add(a, b) do
          a + b
        end
      end

  `c:handle_close/2` is optional, so `MyServer` does not define it.

  ## Wiring a server into the transport

  An implementation is handed to `GenMCP.Transport.StreamableHTTP` (the HTTP plug)
  through its `:server` option, usually from a router. The default `:server` is
  `GenMCP.Suite`, so you set the option only for a custom implementation:

      forward "/mcp", GenMCP.Transport.StreamableHTTP, server: MyServer

  When `:server` is a bare module, `c:init/1` receives the leftover transport
  options as a keyword list. Pass `{MyServer, arg}` to hand `c:init/1` an explicit
  `arg` instead:

      forward "/mcp", GenMCP.Transport.StreamableHTTP, server: {MyServer, mode: :read_only}

  ## Terminate or keep streaming

  Every request follows one of two paths. A handler either **terminates** the
  request with a single response, or **keeps it streaming**:

  - `c:handle_request/3` returns `{:result, result}` or `{:error, reason}` to
    answer immediately, or `{:stream, state}` to hold the response open as a
    Server-Sent Events stream.
  - While streaming, the worker forwards every Erlang message it receives to
    `c:handle_message/3` with the carried `state`. The stream stays open as long
    as `c:handle_message/3` returns `{:stream, state}`, and ends when it returns
    `{:result, result}`, `{:error, reason}`, or `{:stop, reason}`.

  State is carried **only** by the `{:stream, state}` return, because that is the
  only return with a successor callback. Terminal returns end the worker, so they
  carry no state.

  Because the worker is the request's own process, a handler that just needs to
  compute or wait does **not** need to stream: it may block in `c:handle_request/3`
  (including awaiting a `Task`) and return `{:result, result}` when done. Streaming
  earns its place when the result is produced **elsewhere** and arrives as a
  message. The server below hands the work to a job queue, keeps the stream open,
  and finishes the request when the queue messages the worker back:

      def handle_request(%MCP.CallToolRequest{} = request, _channel, _state) do
        {:ok, job_id} = MyApp.JobQueue.enqueue(self(), request.params.arguments)
        {:stream, %{job_id: job_id}}
      end

      def handle_message({:job_finished, job_id, output}, _channel, %{job_id: job_id}) do
        {:result, MCP.call_tool_result(text: output)}
      end

  A streaming handler can also report progress and logs to the client through the
  channel, with `GenMCP.Mux.Channel.send_progress/4` and
  `GenMCP.Mux.Channel.send_log/4`.
  """

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.MCP.V2607.ModMap
  alias GenMCP.Mux.Channel

  require ModMap

  ModMap.require_all()

  @type state :: term

  # TODO(005) exhaustive list of requests/results/notifications types

  @type request ::
          MCP.ListToolsRequest.t()
          | MCP.CallToolRequest.t()
          | MCP.ListResourcesRequest.t()
          | MCP.ReadResourceRequest.t()
          | MCP.ListResourceTemplatesRequest.t()
          | MCP.ListPromptsRequest.t()
          | MCP.GetPromptRequest.t()

  @type result ::
          MCP.ListToolsResult.t()
          | MCP.CallToolResult.t()
          | MCP.ListResourcesResult.t()
          | MCP.ReadResourceResult.t()
          | MCP.ListResourceTemplatesResult.t()
          | MCP.ListPromptsResult.t()
          | MCP.GetPromptResult.t()
          # The multi round-trip ask (MRTR, spec 007). Just another result: a
          # handler that needs more input from the client returns it via the
          # normal `{:result, result}` path. `GenMCP.Suite` builds it from a
          # tool's `{:input_required, …}` return (encrypting the continuation
          # into `requestState`); a custom server may build it directly.
          | MCP.InputRequiredResult.t()
          # Graceful teardown of a `subscriptions/listen` stream: `GenMCP.Suite`
          # returns this when the subscription handler stops an established
          # stream, carried back to the client over the normal `{:result, _}`
          # path (`resultType: "complete"`). See
          # `c:GenMCP.Suite.SubscriptionHandler.handle_message/4`.
          | MCP.SubscriptionsListenResult.t()

  @type notification ::
          MCP.CancelledNotification.t()
          | MCP.ProgressNotification.t()

  @doc """
  Builds the per-request state before any handler runs.

  `init/1` is called once for every incoming request or notification, on a fresh
  worker, before the matching handler. Keep it cheap: the stateless core runs it
  on the hot path of each message, not once per session.

  The argument is the server configuration. When the server is wired as a bare
  module (`server: MyServer`), `init/1` receives the leftover transport options as
  a keyword list. When wired as `{MyServer, arg}`, it receives `arg` unchanged.

  Return `{:ok, state}` to proceed, where `state` is threaded into the handler, or
  `{:stop, reason}` to abort the request before it is handled.
  """
  @callback init(init_arg :: term) :: {:ok, state} | {:stop, term}

  @doc """
  Handles one MCP request and either answers it or upgrades it to a stream.

  This is the primary callback. It receives the decoded request struct, the
  request's `t:GenMCP.Mux.Channel.t/0`, and the `state` from `c:init/1`. Match on
  the request struct to route the call. The request types are listed in
  `t:request/0`: `tools/list`, `tools/call`, the `resources/*` and `prompts/*`
  requests, and the `server/discover` capability snapshot.

  Return one of:

  - `{:result, result}` answers the request and ends it. Build `result` with the
    helpers in `GenMCP.MCP.V2607`, for example `GenMCP.MCP.V2607.list_tools_result/2`
    or `GenMCP.MCP.V2607.call_tool_result/1`.
  - `{:result, result, stop_reason}` answers the request with `result`, then stops
    the worker process with `stop_reason` instead of the default `{:shutdown,
    :reply}`. The client sees the same response; `stop_reason` only sets the
    worker's exit reason, observable to whatever monitors or supervises it (and in
    telemetry). Use `:normal`, `:shutdown`, or `{:shutdown, term}` for a clean exit.
  - `{:error, reason}` ends the request with a JSON-RPC error.
  - `{:stream, state}` holds the response open as an SSE stream and routes every
    later message to `c:handle_message/3` with the returned `state`.

  ### Examples

  Answer `tools/call` for one known tool and reject the rest:

      @impl true
      def handle_request(%MCP.CallToolRequest{params: %{name: "ping"}}, _channel, _state) do
        {:result, MCP.call_tool_result(text: "pong")}
      end

      def handle_request(%MCP.CallToolRequest{}, _channel, _state) do
        {:error, :method_not_found}
      end
  """
  @callback handle_request(request, Channel.t(), state) ::
              {:result, result}
              | {:result, result, stop_reason :: term}
              | {:error, reason :: term}
              | {:stream, state}

  @doc """
  Observes a client notification. Returns `:ok`.

  Each client notification arrives as its own HTTP POST that is answered with
  `202 Accepted` and never streams, so there is nothing to return beyond `:ok`,
  and no state is carried forward. The notification struct, its own
  `t:GenMCP.Mux.Channel.t/0`, and the `state` from `c:init/1` are passed in. The
  notification types are listed in `t:notification/0`.

  The channel is the notification's **own** per-request context, a sibling of any
  in-flight request rather than a handle to it. Read `channel.meta` (client info,
  capabilities, authorization assigns) to decide whether to trust the sender. A
  notification cannot reach or cancel another request: on this transport,
  cancellation is signalled by the client closing the connection, which the
  framework already turns into `c:handle_close/2`.

  The default behaviour, and a fine implementation when there is nothing to
  observe, is to accept and ignore:

      @impl true
      def handle_notification(_notification, _channel, _state) do
        :ok
      end
  """
  @callback handle_notification(notification, Channel.t(), state) :: :ok

  @doc """
  Handles a process message while a request is streaming.

  This callback runs only after `c:handle_request/3` returned `{:stream, state}`.
  Once a request is streaming, the worker forwards **every** Erlang message it
  receives to this callback, so a handler that spawns tasks, subscribes to a
  `Phoenix.PubSub` topic, or monitors another process receives those messages
  here. It is passed the raw message, the request's `t:GenMCP.Mux.Channel.t/0`,
  and the current `state`.

  Return one of:

  - `{:stream, state}` keeps the stream open and waits for the next message,
    carrying the updated `state`.
  - `{:result, result}` ends the stream with the request's final result.
  - `{:result, result, stop_reason}` ends the stream with `result`, then stops the
    worker process with `stop_reason` instead of the default `{:shutdown, :reply}`.
    The client sees the same final result; `stop_reason` only sets the worker's
    exit reason. Use `:normal`, `:shutdown`, or `{:shutdown, term}` for a clean exit.
  - `{:error, reason}` ends the stream with a JSON-RPC error.
  - `{:stop, reason}` ends the stream with no further result, for example when a
    process the handler was listening to exits normally. Use `:normal`,
    `:shutdown`, or `{:shutdown, term}` for a clean exit.

  Send intermediate progress and log notifications through the channel with
  `GenMCP.Mux.Channel.send_progress/4` and `GenMCP.Mux.Channel.send_log/4` before
  returning.

  ### Examples

  A handler waiting on a background job. The job sends its own status messages to
  the worker process; an update keeps the stream open and reports progress to the
  client, and the completion message ends the request:

      @impl true
      def handle_message({:job_update, job_id, done, total}, channel, %{job_id: job_id} = state) do
        GenMCP.Mux.Channel.send_progress(channel, done, total)
        {:stream, state}
      end

      def handle_message({:job_finished, job_id, output}, _channel, %{job_id: job_id}) do
        {:result, MCP.call_tool_result(text: output)}
      end
  """
  @callback handle_message(message :: term, Channel.t(), state) ::
              {:stream, state}
              | {:result, result}
              | {:result, result, stop_reason :: term}
              | {:stop, reason :: term}
              | {:error, reason :: term}

  @doc """
  Cleans up when a streaming request is closed from the connection side. Optional.

  This callback fires only when a streaming request is torn down by something
  other than the handler's own return value — practically, when the client
  disconnects or the network fails (the transport-level cancellation signal on
  this binding). It is **not** called when the handler ends the request itself by
  returning `{:result, …}`, `{:stop, …}`, or `{:error, …}` from
  `c:handle_request/3` or `c:handle_message/3`; those finish the request directly,
  with no cleanup hook. (A handler that closes its own stream with
  `GenMCP.Mux.Channel.close/1` is the one server-side exception that still runs
  this callback.)

  It receives the request's `t:GenMCP.Mux.Channel.t/0`, now marked closed, and the
  last `state`. It is the place to release resources the handler acquired while
  streaming, such as unsubscribing from a `Phoenix.PubSub` topic. The return value
  is ignored.

  The callback is optional. Define it only when a streaming handler holds
  resources that must be released on disconnect:

      @impl true
      def handle_close(_channel, state) do
        Phoenix.PubSub.unsubscribe(MyApp.PubSub, state.topic)
      end
  """
  @callback handle_close(Channel.t(), state) :: term

  @optional_callbacks handle_close: 2

  @doc """
  Returns the list of MCP protocol versions this library supports (currently
  `["2026-07-28"]`).

  This is the allowlist the transport checks an incoming `MCP-Protocol-Version`
  against. A request carrying a version not in this list is rejected with an
  `UnsupportedProtocolVersionError` (`-32004`) whose `data.supported` is this
  list.
  """
  def supported_protocol_versions do
    ["2026-07-28"]
  end

  @doc """
  Returns the MCP protocol version this library targets (currently `"2026-07-28"`).
  """
  def protocol_version do
    "2026-07-28"
  end

  @doc """
  Attaches the default `:telemetry` logger for `:gen_mcp` events.

  Convenience wrapper that delegates to `GenMCP.TelemetryLogger.attach/1`. Call
  it once at startup to get `Logger` output for the library's lifecycle and
  transport events. See `GenMCP.TelemetryLogger` for the events and their log
  levels, and `GenMCP.TelemetryLogger.attach/1` for the available `filters`.

      :ok = GenMCP.attach_default_logger()
  """
  def attach_default_logger(filters \\ []) do
    GenMCP.TelemetryLogger.attach(filters)
  end

  @doc """
  Returns the historical default channel log level (`:notice`).

  > #### Deprecated {: .warning}
  >
  > The stateless core no longer applies a library-wide default log level. A
  > channel's level is read per request from the `io.modelcontextprotocol/logLevel`
  > `_meta` field, and its absence means logging is **disabled**, not `:notice`.
  > See `GenMCP.Mux.Channel.send_log/4`.
  """
  @default_channel_log_level :notice
  def default_channel_log_level do
    @default_channel_log_level
  end
end
