defmodule GenMCP do
  @moduledoc """
  The main behaviour for MCP servers.

  Implement this behaviour to create a custom MCP server. If you are looking for a high-level framework to build tools and resources, see `GenMCP.Suite`.

  ## Example

      defmodule MyServer do
        @behaviour GenMCP

        alias GenMCP.MCP

        @impl true
        def init(_session_id, _opts) do
          {:ok, %{}}
        end

        @impl true
        def handle_request(%MCP.InitializeRequest{} = req, _channel, state) do
          # Protocol version check omitted for brevity
          result = MCP.intialize_result(
            capabilities: MCP.capabilities(tools: true),
            server_info: MCP.server_info(name: "My Server", version: "1.0.0")
          )
          {:reply, {:result, result}, state}
        end

        def handle_request(%MCP.ListToolsRequest{}, _channel, state) do
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
          {:reply, {:result, result}, state}
        end

        @impl true
        def handle_notification(%MCP.InitializedNotification{}, state) do
          {:noreply, state}
        end

        def handle_notification(_notif, state) do
          {:noreply, state}
        end

        @impl true
        def handle_info(_msg, state) do
          {:noreply, state}
        end
      end
  """

  alias GenMCP.MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.Suite.SessionController

  require(Elixir.GenMCP.MCP.ModMap).require_all()

  @doc """
  Returns the supported protocol versions.
  """
  def supported_protocol_versions do
    ["2025-06-18"]
  end

  @type state :: term
  @type session_id :: String.t()
  @type request ::
          MCP.InitializeRequest.t()
          | MCP.ListToolsRequest.t()
          | MCP.CallToolRequest.t()
          | MCP.ListResourcesRequest.t()
          | MCP.ReadResourceRequest.t()
          | MCP.ListResourceTemplatesRequest.t()
          | MCP.ListPromptsRequest.t()
          | MCP.GetPromptRequest.t()
          | MCP.PingRequest.t()

  @type result ::
          MCP.InitializeResult.t()
          | MCP.ListToolsResult.t()
          | MCP.CallToolResult.t()
          | MCP.ListResourcesResult.t()
          | MCP.ReadResourceResult.t()
          | MCP.ListResourceTemplatesResult.t()
          | MCP.ListPromptsResult.t()
          | MCP.GetPromptResult.t()

  @type notification ::
          MCP.InitializedNotification.t()
          | MCP.CancelledNotification.t()
          | MCP.RootsListChangedNotification.t()
          | MCP.ProgressNotification.t()

  @type server_reply :: {:result, result} | :stream | {:error, term}
  @type server_reply_nostream :: {:result, result} | :stream | {:error, term}

  @doc """
  Initializes the server state.

  Called when a new MCP session is established.
  """
  @callback init(session_id, init_arg :: term) :: {:ok, state} | {:stop, term}

  @doc """
  Handles an incoming MCP request and returns a result or stop the server.
  """
  @callback handle_request(request, Channel.t(), state) ::
              {:reply, server_reply, state}
              | {:stop, reason :: term, server_reply_nostream, state}

  @doc """
  Handles an incoming MCP notification.

  Notifications are one-way messages that do not expect a response.
  """
  @callback handle_notification(notification, state) :: {:noreply, state}

  @doc """
  Handles process messages.

  Invoked when the server process receives a message that is not an MCP request
  or notification.
  """
  @callback handle_info(term, state) :: {:noreply, state} | {:stop, reason :: term, state}

  @doc """
  This callback is called during session initialization when a
  non-initialization request (such as a call tool request) is received and there
  is no current OTP process tied to the session id.

  > #### This is a raw callback {: .warning}
  >
  > The call is made from the HTTP transport process, giving raw initialization
  > args for the server. It is called _before_ the `c:init/2` callback is called
  > and there is no possibility to return a new state or arg.
  >
  > The returned data will be passed to the `c:session_restore/3` callback after
  > server process initialization.
  """
  @callback session_fetch(session_id, channel :: Channel.t(), init_arg :: term) ::
              {:ok, SessionController.restore_data()} | {:error, :not_found}

  @doc """
  Called when a session is restored by the `GenMCP.Suite.SessionController`
  implementation.

  Your server `c:init/2` callback will have been called before, but there will
  be no call of `c:handle_request/3` with an initialization request.

  The next call will be either another request or a notification.
  """
  @callback session_restore(SessionController.restore_data(), channel :: Channel.t(), state) ::
              {:noreply, state} | {:stop, reason :: term, state}

  @doc """
  Called when a session is deleted by the client.

  Return value is not checked, and the server is shut down immediately.
  """
  @callback session_delete(state) :: term

  @doc """
  Called when a session times out.
  """
  @callback session_timeout(state) :: term

  @optional_callbacks session_restore: 3, session_delete: 1, session_timeout: 1

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
end
