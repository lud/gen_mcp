defmodule GenMCP do
  @moduledoc """
  The main behaviour for MCP servers.

  Implement this behaviour to create a custom MCP server. If you are looking for a high-level framework to build tools and resources, see `GenMCP.Suite`.

  ## Example

      defmodule MyServer do
        @behaviour GenMCP

        alias GenMCP.MCP
        alias GenMCP.Mux.Channel

        # Runs per request (the transport is stateless). Receives the validated
        # server opts; per-request data arrives via the request and channel.
        @impl true
        def init(_opts) do
          {:ok, %{}}
        end

        # Terminal blocking path: compute and return the result directly.
        @impl true
        def handle_request(%MCP.ListToolsRequest{}, _channel, _state) do
          result = MCP.list_tools_result([
            %MCP.Tool{
              name: "hello",
              description: "Say hello",
              inputSchema: %{
                type: "object",
                properties: %{
                  name: %{type: "string"}
                }
              }
            }
          ])
          {:result, result}
        end

        # Continue as a stream: opt into the wrapper receive loop, carrying state.
        # Subsequent messages are delivered to `handle_message/3`, which may emit
        # progress and ultimately return the result.
        def handle_request(%MCP.CallToolRequest{}, _channel, state) do
          send(self(), :do_work)
          {:stream, state}
        end

        @impl true
        def handle_notification(_notif, _channel, _state) do
          :ok
        end

        @impl true
        def handle_message(:do_work, channel, _state) do
          Channel.send_progress(channel, 1, 1, "done")
          {:result, MCP.call_tool_result(text: "hello")}
        end
      end
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

  @type notification ::
          MCP.CancelledNotification.t()
          | MCP.ProgressNotification.t()

  @doc """
  Initializes the server state.

  The transport is stateless: this runs **per request**, receiving the validated
  server opts. Per-request data (the request, client info/capabilities from
  `_meta`) arrives via `c:handle_request/3` and the channel, not here.
  """
  @callback init(init_arg :: term) :: {:ok, state} | {:stop, term}

  @doc """
  Handles an incoming MCP request.

  Every return either **terminates** the request or **continues** it as a stream.
  State rides only on the continue return — terminal returns end the worker, so
  their state would be discarded and is therefore not carried.

  * `{:result, result}` / `{:error, reason}` — **terminal, blocking path**:
    compute (optionally emitting `GenMCP.Mux.Channel.send_progress/4` or
    `send_log/4`) and return the outcome directly. The worker owns its process,
    so it may block as long as needed while the relay pumps the socket.
  * `{:stream, state}` — **continue, streaming path**: hand control back to the
    wrapper receive loop, carrying `state`. Subsequent process messages are
    delivered to `c:handle_message/3`. This is the path for handlers driven by
    external events (e.g. subscribing to a producer); it also commits the
    response to `text/event-stream` immediately, even before the first
    notification.

  The channel is passed **in** (for `send_progress`/`send_log`) but never
  returned — it is immutable per-request framework context, not handler state.

  Never hand-roll a `receive` block here — it would miss the relay's `:DOWN`
  (client disconnect) and system messages. Return `{:stream, state}` instead.
  """
  @callback handle_request(request, Channel.t(), state) ::
              {:result, result}
              | {:error, reason :: term}
              | {:stream, state}

  @doc """
  Handles an incoming MCP notification.
  """
  @callback handle_notification(notification, Channel.t(), state) :: :ok

  @doc """
  Handles a process message during a streaming request.

  Invoked only after `c:handle_request/3` returned `{:stream, state}`, for each
  non-system message the worker receives. Shares `c:handle_request/3`'s return
  vocabulary — every callback either terminates or continues the stream:

  * `{:stream, state}` — keep streaming, carrying `state`.
  * `{:result, result}` — emit the final result and end the request.
  * `{:stop, reason}` — end the stream with no final result (e.g. a long-lived
    listener's normal exit).
  * `{:error, reason}` — emit an error and terminate the stream.
  """
  @callback handle_message(message :: term, Channel.t(), state) ::
              {:stream, state}
              | {:result, result}
              | {:stop, reason :: term}
              | {:error, reason :: term}

  @doc """
  Returns the supported protocol versions.
  """
  def supported_protocol_versions do
    ["2025-11-25", "2025-06-18"]
  end

  @doc """
  Returns the protocol version this library targets.

  The `2026-07-28` release candidate currently lives in the `schema/draft`
  directory of the MCP repository and is the version named by the
  `GenMCP.MCP.V2607` vocabulary. There is no `initialize` handshake under this
  protocol; the version is carried by the `MCP-Protocol-Version` HTTP header and
  the per-request `_meta` (`io.modelcontextprotocol/protocolVersion`), and is
  advertised via `server/discover`.
  """
  def protocol_version do
    "2026-07-28"
  end

  @doc """
  The gen_mcp application uses telemetry events to publish various application
  lifecycle events. This can be used to log only what is important to you.

  The telemetry logger will log all telemetry events by default, at various log
  levels (debug, info, warning, error , _etc._).

  Two filters are supported:

  * `:min_log_level` - For instance if `:error` is given, the default logger
    will not log events for which it uses the lower levels. This allows you to
    still have logs for errors, without cluttering info and debug logs.
  * `:prefixes` - A list of event prefixes (which are a list too) to match. The
    logger will only log events whose prefixes match one of the the given
    prefixes. For instance, `[[:gen_mcp, :cluster], [:gen_mcp, :session]]` will
    only log events related to the cluster and sessions.

  Both filters are compatible.

  See `GenMCP.TelemetryLogger` for a list of all emitted events.
  """
  def attach_default_logger(filters \\ []) do
    GenMCP.TelemetryLogger.attach(filters)
  end

  @default_channel_log_level :notice
  @doc """
  Returns the default logging level used by the MCP logging features on session
  initialization.

  > #### Deprecated {: .warning}
  >
  > Under the 2026-07-28 stateless core there is **no default log level**: the
  > level is read per-request from `_meta` `io.modelcontextprotocol/logLevel`, and
  > a request that omits it has logging **disabled** (the server MUST NOT emit
  > `notifications/message`). This function only feeds the legacy session path and
  > is removed with it (spec 011).
  """
  def default_channel_log_level do
    @default_channel_log_level
  end
end
