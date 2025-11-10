defmodule GenMcp.Plug.StreamableHttp do
  alias GenMcp.Mcp.Entities.InitializeRequest
  alias GenMcp.Mcp.Entities.InitializeResult
  alias GenMcp.Mcp.Entities.JSONRPCResponse
  alias GenMcp.Mux
  alias GenMcp.RpcError
  alias GenMcp.Validator
  alias JSV.Codec
  alias JSV.Helpers.MapExt
  import Plug.Conn
  require Logger
  use Plug.Router, copy_opts_to_assign: :gen_mcp_streamable_http_opts

  # -- Plug API ---------------------------------------------------------------

  plug :match
  plug :dispatch

  get "/" do
    http_get(conn, conn.assigns.gen_mcp_streamable_http_opts)
  end

  post "/" do
    http_post(conn, conn.assigns.gen_mcp_streamable_http_opts)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  # -- Plug Duplication -------------------------------------------------------

  defmacro defplug(module) do
    module = Macro.expand_literals(module, __CALLER__)

    {:module, mod, _, _} =
      defmodule module do
        defdelegate init(opts), to: GenMcp.Plug.StreamableHttp
        defdelegate call(conn, opts), to: GenMcp.Plug.StreamableHttp
      end

    mod
  end

  # -- Internal ---------------------------------------------------------------

  @stream_keepalive_timeout :timer.seconds(25)

  def http_get(conn, _opts) do
    send_resp(conn, 405, "Method Not Allowed")
  end

  def http_post(%{body_params: %{"jsonrpc" => "2.0"} = body_params} = conn, opts) do
    case Validator.validate_request(body_params) do
      {:error, jsv_err} ->
        send_error(conn, jsv_err, msg_id: msg_id_from_req(body_params))

      {:ok, :request, %{id: msg_id} = req} ->
        dispatch_req(conn, msg_id, req, opts)

      {:ok, :notification, req} ->
        dispatch_notif(conn, req, opts)
    end
  rescue
    e ->
      Logger.error(Exception.format(:error, e, __STACKTRACE__))
      reraise e, __STACKTRACE__
  end

  def http_post(%{body_params: %{"jsonrpc" => _}} = conn, _opts) do
    send_error(conn, :bad_rpc_version)
  end

  def http_post(conn, _opts) do
    send_error(conn, :bad_rpc)
  end

  defp msg_id_from_req(body) do
    case body do
      %{"id" => id} -> id
      _ -> nil
    end
  end

  IO.warn("""
  @todo we should pass the initialize request in the start_session arguments,
  so if the protocol version is not supported or another incompatibility error,
  we can just return an error from Session.init or even start_link and not
  bother starting the server at all.

  The supervisor will restart the session with the request. For now session is
  :temporary so we do not care because DynamicSupervisor.mfa_for_restart (defp)
  discards the start_link arguments when it registers the child.

  # TODO add a test to validate that this is always true.
  """)

  defp dispatch_req(conn, msg_id, %InitializeRequest{} = req, opts) do
    with {:ok, session_id} <- Mux.start_session(opts),
         {:result, %InitializeResult{} = result} <-
           Mux.request(session_id, req, channel_info(conn, req)) do
      conn
      |> with_session_id(session_id)
      |> send_result_response(200, msg_id, result)
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  defp dispatch_req(conn, msg_id, req, _opts) do
    case fetch_session_id(conn) do
      {:ok, session_id} -> do_dispatch_req(conn, session_id, msg_id, req)
      {:error, reason} -> send_error(conn, reason)
    end
  end

  defp do_dispatch_req(conn, session_id, msg_id, req) do
    case Mux.request(session_id, req, channel_info(conn, req)) do
      {:result, result} -> send_result_response(conn, 200, msg_id, result)
      {:error, reason} -> send_error(conn, reason, msg_id: msg_id)
      :stream -> stream_start(conn, 200, msg_id)
    end
  end

  defp dispatch_notif(conn, notif, _opts) do
    with {:ok, session_id} <- fetch_session_id(conn),
         :ack <- Mux.notify(session_id, notif) do
      send_accepted(conn)
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  @session_id_header "mcp-session-id"

  defp with_session_id(conn, session_id) do
    Plug.Conn.put_resp_header(conn, @session_id_header, session_id)
  end

  defp fetch_session_id(conn) do
    case List.keyfind(conn.req_headers, @session_id_header, 0) do
      nil -> {:error, :missing_session_id}
      {@session_id_header, session_id} -> {:ok, session_id}
    end
  end

  defp channel_info(_conn, _req) do
    {:channel, __MODULE__, self()}
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
    Logger.debug(["RESPONSE\n", body], ansi_color: :light_yellow)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  defp send_error(conn, reason, opts \\ []) do
    case RpcError.cast_error(reason) do
      {status, payload} ->
        payload = %GenMcp.Mcp.Entities.JSONRPCError{
          error: payload,
          id: opts[:msg_id],
          jsonrpc: "2.0"
        }

        send_json(conn, status, payload)
    end
  end

  defp stream_start(conn, 200, msg_id) do
    conn = put_resp_header(conn, "content-type", "text/event-stream")
    conn = send_chunked(conn, 200)
    stream_loop(conn, msg_id, start_keepalive())
  end

  defp start_keepalive do
    :erlang.start_timer(@stream_keepalive_timeout, self(), {__MODULE__, :keepalive})
  end

  defp reset_keepalive(old_ref) do
    :ok = :erlang.cancel_timer(old_ref, async: true, info: false)
    _new_ref = start_keepalive()
  end

  defp stream_loop(conn, msg_id, keepalive_ref) do
    receive do
      {:timeout, ^keepalive_ref, {__MODULE__, :keepalive}} ->
        IO.puts("keepalive")
        {:ok, conn} = chunk(conn, ":keepalive\n")
        stream_loop(conn, msg_id, start_keepalive())

      {:timeout, _stale_ref, {__MODULE__, :keepalive}} ->
        IO.puts("stale keepalive")
        stream_loop(conn, msg_id, keepalive_ref)

      # On result we will stop the stream
      {:"$gen_mcp", :result, result} ->
        {:ok, conn} = send_result_response_chunk(conn, msg_id, result)
        stream_end(conn)

      {:"$gen_mcp", :notification, notification} ->
        {:ok, conn} = send_notification_chunk(conn, notification)

        stream_loop(conn, msg_id, reset_keepalive(keepalive_ref))

      other
      when other != {:plug_conn, :sent} and not (is_tuple(other) and elem(other, 0) == :bandit) ->
        Logger.warning("Received unexpected message: #{inspect(other)}")
        stream_loop(conn, msg_id, keepalive_ref)
    end
  end

  defp stream_end(conn) do
    #  TODO remove this function if nothing more to do
    conn
  end

  defp send_result_response_chunk(conn, msg_id, result) do
    payload = %JSONRPCResponse{
      id: msg_id,
      jsonrpc: "2.0",
      result: result
    }

    {:ok, _conn} = send_stream_data(conn, payload)
  end

  defp send_notification_chunk(conn, notification) do
    {:ok, _conn} = send_stream_data(conn, notification)
  end

  defp send_stream_data(conn, payload) do
    json = json_encode(payload)
    event = "data: #{json}\n\n"
    {:ok, _conn} = chunk(conn, event)
  end

  defp json_encode(payload, pretty? \\ false) do
    normal =
      JSV.Helpers.Traverse.prewalk(payload, fn
        {:struct, v} -> MapExt.from_struct_no_nils(v)
        other -> elem(other, 1)
      end)

    if pretty? do
      Codec.format_to_iodata!(normal)
    else
      Codec.encode_to_iodata!(normal)
    end
  end
end
