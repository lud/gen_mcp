# quokka:skip-module-reordering

defmodule GenMCP.Transport.StreamableHTTP do
  plug_opts_schema =
    NimbleOptions.new!(
      assigns: [
        type: :map,
        default: %{},
        doc:
          "A map of assigns to define to the channel passed to" <>
            " tools, resources, etc."
      ],
      copy_assigns: [
        type: {:list, :atom},
        default: [],
        doc:
          "A list of assigns keys that will be copied from the conn to the channel." <>
            " Those will overwrite the assigns from the `:assigns` option above."
      ]
    )

  @moduledoc """
  Handles incoming MCP requests over HTTP with SSE support.

  This module is a Plug that can be mounted in your router. It handles the MCP
  protocol handshake, session management, and request routing.

  It supports Server-Sent Events (SSE) for streaming responses, such as
  notifications and asynchronous tool results.

  ## Configuration

  ### Options for the HTTP connection

  #{NimbleOptions.docs(plug_opts_schema)}

  ### Options for the MCP OTP session wrapper

  Note that the `:session_controller` is managed directly by the `GenMCP`
  behaviour implementation.

  #{GenMCP.Mux.Session.init_opts_schema().schema |> Keyword.delete(:session_id) |> NimbleOptions.docs()}

  ### Options for the GenMCP behaviour implmentation

  All other options given to `#{inspect(__MODULE__)}` will be forwarded to the
  server implementation.

  The default server, `GenMCP.Suite`, will accept the following options:

  #{GenMCP.Suite.init_opts_schema().schema |> Keyword.delete(:session_controller) |> NimbleOptions.docs()}



  ## Example

      # In your router
      forward "/mcp", GenMCP.Transport.StreamableHTTP,
        server_name: "My App",
        server_version: "1.0.0",
        tools: [MyTool]
  """

  use Plug.Router, copy_opts_to_assign: :gen_mcp_streamable_http_opts

  import Plug.Conn

  alias GenMCP.MCP.InitializeRequest
  alias GenMCP.MCP.InitializeResult
  alias GenMCP.MCP.JSONRPCError
  alias GenMCP.MCP.JSONRPCResponse
  alias GenMCP.Mux
  alias GenMCP.Mux.Channel
  alias GenMCP.RpcError
  alias GenMCP.Transport.StreamableHTTP.Impl
  alias GenMCP.Utils.OptsValidator
  alias GenMCP.Validator
  alias JSV.Codec

  require Logger

  @plug_opts_schema plug_opts_schema

  # -- Plug API ---------------------------------------------------------------
  def init(opts) do
    {self_opts, session_opts} = OptsValidator.validate_take_opts!(opts, @plug_opts_schema)
    _conf = Map.put(Map.new(self_opts), :session_opts, session_opts)
  end

  plug :match
  plug :dispatch

  get "/" do
    Impl.http_get(conn, conn.assigns.gen_mcp_streamable_http_opts)
  end

  post "/" do
    Impl.http_post(conn, conn.assigns.gen_mcp_streamable_http_opts)
  end

  delete "/" do
    Impl.http_delete(conn, conn.assigns.gen_mcp_streamable_http_opts)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  # -- Plug Duplication -------------------------------------------------------

  @doc """
  Defines a module that delegates to `GenMCP.Transport.StreamableHTTP`.

  This is useful if you want to define a named Plug for your MCP server.

  ## Example

      defmodule MyMCPPlug do
        require GenMCP.Transport.StreamableHTTP
        GenMCP.Transport.StreamableHTTP.defplug(MyMCPPlug)
      end
  """
  defmacro defplug(module) do
    module = Macro.expand_literals(module, __CALLER__)

    {:module, mod, _, _} =
      defmodule module do
        alias GenMCP.Transport.StreamableHTTP

        defdelegate init(opts), to: StreamableHTTP
        defdelegate call(conn, opts), to: StreamableHTTP
      end

    mod
  end
end

# Separate modules so we do not get bad stacktraces because of Plug

defmodule GenMCP.Transport.StreamableHTTP.Impl do
  @moduledoc false

  import Plug.Conn

  alias GenMCP.MCP.InitializeRequest
  alias GenMCP.MCP.InitializeResult
  alias GenMCP.MCP.JSONRPCError
  alias GenMCP.MCP.JSONRPCResponse
  alias GenMCP.Mux
  alias GenMCP.Mux.Channel
  alias GenMCP.RpcError
  alias GenMCP.Utils.OptsValidator
  alias GenMCP.Validator
  alias JSV.Codec

  @stream_keepalive_timeout to_timeout(second: 25)
  @session_id_assign_key :gen_mcp_session_id
  @session_id_header "mcp-session-id"

  # TODO(doc) the :assigns option has less precedence than :copy_assigns.
  # Assigns copied from the conn will overwrite static assigns.

  def http_get(conn, conf) do
    dispatch_listener(conn, conf)
  end

  def http_post(%{body_params: %{"jsonrpc" => "2.0"} = body_params} = conn, conf) do
    case Validator.validate_request(body_params) do
      {:error, jsv_err} ->
        send_error(conn, jsv_err, msg_id_from_req(body_params))

      {:ok, :request, %{id: msg_id} = req} ->
        dispatch_req(conn, msg_id, req, conf)

      {:ok, :notification, req} ->
        dispatch_notif(conn, req, conf)
    end
  end

  def http_post(%{body_params: %{"jsonrpc" => _}} = conn, _conf) do
    send_error(conn, :bad_rpc_version, _msg_id = nil)
  end

  def http_post(conn, _conf) do
    send_error(conn, :bad_rpc, _msg_id = nil)
  end

  def http_delete(conn, conf) do
    terminate_session(conn, conf)
  end

  defp msg_id_from_req(body) do
    case body do
      %{"id" => id} -> id
      _ -> nil
    end
  end

  defp dispatch_listener(conn, conf) do
    req = %GenMCP.MCP.ListenerRequest{}
    msg_id = nil

    with {:ok, session_id} <- lookup_session_id(conn),
         channel = make_channel(conn, req, session_id, conf),
         {:ok, session_pid} <- ensure_started_session(session_id, channel, conf) do
      case Mux.request(session_pid, req, channel) do
        {:result, result} -> send_result_response(conn, 200, msg_id, result)
        {:error, reason} -> send_error(conn, reason, _msg_id = nil)
        :stream -> stream_start(conn, 200, msg_id)
      end
    else
      {:error, reason} -> send_error(conn, reason, _msg_id = nil)
    end
  end

  defp dispatch_req(conn, msg_id, %InitializeRequest{} = req, conf) do
    with :ok <- reject_session_id(conn),
         {:ok, session_id} <- Mux.start_session(conf.session_opts),
         channel = make_channel(conn, req, session_id, conf),
         {:result, %InitializeResult{} = result} <- Mux.request(session_id, req, channel) do
      conn
      |> put_resp_session_id(session_id)
      |> send_result_response(200, msg_id, result)
    else
      {:error, reason} -> send_error(conn, reason, msg_id)
    end
  end

  defp dispatch_req(conn, msg_id, req, conf) do
    with {:ok, session_id} <- lookup_session_id(conn),
         channel = make_channel(conn, req, session_id, conf),
         {:ok, session_pid} <- ensure_started_session(session_id, channel, conf) do
      do_dispatch_req(conn, session_pid, msg_id, req, channel)
    else
      {:error, reason} -> send_error(conn, reason, msg_id)
    end
  end

  defp do_dispatch_req(conn, session_pid, msg_id, req, channel) do
    case Mux.request(session_pid, req, channel) do
      {:result, result} -> send_result_response(conn, 200, msg_id, result)
      {:error, reason} -> send_error(conn, reason, msg_id)
      :stream -> stream_start(conn, 200, msg_id)
    end
  end

  defp dispatch_notif(conn, notif, conf) do
    with {:ok, session_id} <- lookup_session_id(conn),
         channel = make_channel(conn, notif, session_id, conf),
         {:ok, session_pid} <- ensure_started_session(session_id, channel, conf),
         :ack <- Mux.notify(session_pid, notif) do
      send_accepted(conn)
    else
      {:error, reason} -> send_error(conn, reason, _msg_id = nil)
    end
  end

  defp ensure_started_session(session_id, channel, conf) do
    case Mux.ensure_started(session_id, channel, conf.session_opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, _reason} = err -> err
    end
  end

  defp lookup_session_id(conn) do
    case List.keyfind(conn.req_headers, @session_id_header, 0) do
      nil -> {:error, :missing_session_id}
      {@session_id_header, session_id} -> {:ok, session_id}
    end
  end

  defp reject_session_id(conn) do
    case List.keyfind(conn.req_headers, @session_id_header, 0) do
      nil -> :ok
      {@session_id_header, _} -> {:error, :unexpected_session_id}
    end
  end

  defp terminate_session(conn, conf) do
    with {:ok, session_id} <- lookup_session_id(conn),
         channel = make_channel(conn, nil, session_id, conf),
         {:ok, session_pid} <- ensure_started_session(session_id, channel, conf),
         :ok <- Mux.delete_session(session_pid) do
      send_resp(conn, 204, "")
    else
      {:error, reason} -> send_error(conn, reason, _msg_id = nil)
    end
  end

  defp put_resp_session_id(conn, session_id) do
    Plug.Conn.put_resp_header(conn, @session_id_header, session_id)
  end

  defp make_channel(conn, req, session_id, conf) do
    %{assigns: conn_assigns} = conn

    static_assigns = Map.put(conf.assigns, @session_id_assign_key, session_id)
    copied_assign_keys = conf.copy_assigns

    assigns =
      Enum.reduce(copied_assign_keys, static_assigns, fn key, acc ->
        case Map.fetch(conn_assigns, key) do
          {:ok, value} -> Map.put(acc, key, value)
          :error -> acc
        end
      end)

    Channel.from_request(req, assigns)
  end

  defp send_accepted(conn) do
    send_resp(conn, 202, "")
  end

  defp send_result_response(conn, status, msg_id, result) do
    payload = %JSONRPCResponse{
      id: msg_id,
      jsonrpc: "2.0",
      result: result
    }

    send_json(conn, status, payload)
  end

  defp send_json(conn, status, payload) do
    body = json_encode(payload, true)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  defp send_error(conn, reason, msg_id) do
    case RpcError.cast_error(reason) do
      {status, payload} ->
        payload = %JSONRPCError{
          error: payload,
          id: msg_id,
          jsonrpc: "2.0"
        }

        send_json(conn, status, payload)
    end
  end

  defp stream_start(conn, 200, msg_id) do
    conn = put_resp_header(conn, "content-type", "text/event-stream")
    conn = send_chunked(conn, 200)

    conn =
      conn
      |> Plug.Conn.put_private(:gen_mcp_client_request_id, msg_id)
      |> start_keepalive()

    stream_loop(conn)
  end

  defp start_keepalive(conn) do
    tref = :erlang.start_timer(@stream_keepalive_timeout, self(), {__MODULE__, :keepalive})
    Plug.Conn.put_private(conn, :gen_mcp_keepalive, tref)
  end

  defp reset_keepalive(conn) do
    :ok = :erlang.cancel_timer(conn.private.gen_mcp_keepalive, async: true, info: false)
    _conn = start_keepalive(conn)
  end

  defp stream_loop(conn) do
    receive do
      message when elem(message, 0) == :"$gen_mcp" ->
        handle_message(conn, message)

      {:timeout, tref, {__MODULE__, :keepalive}} ->
        case conn.private.gen_mcp_keepalive do
          ^tref ->
            case chunk(conn, ":keepalive\n") do
              {:ok, conn} -> conn |> start_keepalive() |> stream_loop()
              {:error, :closed} -> stream_closed(conn)
            end

          _ ->
            stream_loop(conn)
        end

      other
      when other != {:plug_conn, :sent} and not (is_tuple(other) and elem(other, 0) == :bandit) ->
        unexpected_message(other)
        stream_loop(conn)
    end
  end

  # On result we will stop the stream
  defp handle_message(conn, {:"$gen_mcp", :result, result}) do
    case send_result_response_chunk(conn, result) do
      {:ok, conn} -> stream_end(conn)
      {:error, :closed} -> stream_closed(conn)
    end
  end

  # On error we will stop the stream
  defp handle_message(conn, {:"$gen_mcp", :error, reason}) do
    case send_error_response_chunk(conn, reason) do
      {:ok, conn} -> stream_end(conn)
      {:error, :closed} -> stream_closed(conn)
    end
  end

  defp handle_message(conn, {:"$gen_mcp", :notification, notification}) do
    case send_notification_chunk(conn, notification) do
      {:ok, conn} -> conn |> reset_keepalive() |> stream_loop()
      {:error, :closed} -> stream_closed(conn)
    end
  end

  defp handle_message(conn, {:"$gen_mcp", :raw_message, data}) do
    case send_stream_message(conn, data) do
      {:ok, conn} -> conn |> reset_keepalive() |> stream_loop()
      {:error, :closed} -> stream_closed(conn)
    end
  end

  defp handle_message(conn, {:"$gen_mcp", :close}) do
    stream_end(conn)
  end

  if Mix.env() == :test do
    @spec unexpected_message(term) :: no_return
    defp unexpected_message(msg) do
      raise "unexpected message in #{inspect(__MODULE__)}: #{inspect(msg)}"
    end
  else
    defp unexpected_message(_msg) do
      :ok
    end
  end

  defp stream_end(conn) do
    # Nothing to do on stream end for now. TODO remove this function if unused
    conn
  end

  defp stream_closed(conn) do
    # Stream was closed by remote, there is nothing much to do either
    conn
  end

  defp send_result_response_chunk(conn, result) do
    msg_id = conn.private.gen_mcp_client_request_id

    payload = %JSONRPCResponse{
      id: msg_id,
      jsonrpc: "2.0",
      result: result
    }

    send_stream_message(conn, json_encode(payload))
  end

  defp send_error_response_chunk(conn, reason) do
    msg_id = conn.private.gen_mcp_client_request_id
    {_status, error_payload} = RpcError.cast_error(reason)

    payload = %JSONRPCError{
      error: error_payload,
      id: msg_id,
      jsonrpc: "2.0"
    }

    send_stream_message(conn, json_encode(payload))
  end

  defp send_notification_chunk(conn, notification) do
    send_stream_message(conn, json_encode(notification))
  end

  defp send_stream_message(conn, data) do
    event = "event: message\ndata: #{data}\n\n"
    chunk(conn, event)
  end

  defp json_encode(payload, pretty? \\ false) do
    if pretty? do
      Codec.format_to_iodata!(payload)
    else
      Codec.encode_to_iodata!(payload)
    end
  end
end
