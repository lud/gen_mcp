defmodule GenMcp.Plug.StreamableHttp do
  alias GenMcp.Plug.StreamableHttp.Impl
  use Plug.Router, copy_opts_to_assign: :server_opts
  plug :match
  plug :dispatch

  get "/" do
    Impl.http_get(conn, conn.assigns.server_opts)
  end

  post "/" do
    Impl.http_post(conn, conn.assigns.server_opts)
  end

  match _ do
    require(Logger).debug("RESPONSE\404", ansi_color: :light_yellow)
    send_resp(conn, 404, "Not found")
  end

  defmacro delegate(module) do
    module = Macro.expand_literals(module, __CALLER__)
    IO.puts("-----------------------\n#{inspect(module)}\n-----------------------\n")

    {:module, mod, _, _} =
      defmodule module do
        defdelegate init(opts), to: GenMcp.Plug.StreamableHttp
        defdelegate call(conn, opts), to: GenMcp.Plug.StreamableHttp
      end

    mod
  end
end

defmodule GenMcp.Plug.StreamableHttp.Impl do
  alias GenMcp.Entities.InitializeRequest
  alias GenMcp.Entities.InitializeResult
  alias GenMcp.Entities.JSONRPCResponse
  alias GenMcp.Validator
  alias JSV.Codec
  alias JSV.Helpers.MapExt
  import Plug.Conn
  require Logger

  def http_get(conn, _opts) do
    Logger.debug("RESPONSE\nMethod Not Allowed", ansi_color: :light_yellow)
    send_resp(conn, 405, "Method Not Allowed")
  end

  def http_post(%{body_params: %{"jsonrpc" => "2.0"} = body_params} = conn, opts) do
    case Validator.validate_request(body_params) do
      {:error, jsv_err} -> send_error_sessionless(conn, msgid_from_req(body_params), jsv_err)
      {:ok, :request, %{id: msgid} = req} -> dispatch_req(conn, msgid, req, opts)
      {:ok, :notification, req} -> dispatch_notif(conn, req, opts)
    end
  end

  def http_post(conn, opts) do
    send_error_sessionless(conn, nil, :bad_rpc)
  end

  defp msgid_from_req(body) do
    case body do
      %{"id" => id} -> id
      _ -> nil
    end
  end

  defp send_error_sessionless(conn, msgid, %JSV.ValidationError{} = jsv_err) do
    Logger.error("invalid request sent to #{inspect(__MODULE__)}")

    do_send_error(conn, 400, msgid, GenMcp.Error.json_schema_validation(jsv_err))
  end

  defp send_error_sessionless(conn, msgid, :bad_rpc) do
    Logger.error("invalid request sent to #{inspect(__MODULE__)}")

    do_send_error(conn, 400, msgid, GenMcp.Error.bad_rpc())
  end

  defp send_error(conn, _channel, msgid, err) do
    do_send_error(conn, 400, msgid, err)
  end

  defp do_send_error(conn, status, msgid, err_payload) do
    payload = %GenMcp.Entities.JSONRPCError{
      error: err_payload,
      # no session, we do not know what client that is,
      id: msgid,
      jsonrpc: "2.0"
    }

    send_json(conn, status, payload)
  end

  # TODO use for server-initiated requests
  # defp impersistent_msgid do
  #   # TODO we should use our own counter that we can rewrap to zero, otherwise
  #   # we may put the whole system to use heap allocated integers if we have a
  #   # very long uptime.
  #   #
  #   # Or we can use system_time microseconds since it's very unlikely that a
  #   # single client will hit that speed during interactions, and we do not care
  #   # about duplicate IDs on different clients.
  #   #
  #   # This is only for non persistent
  #   "#{NodeSync.node_id()}-#{:erlang.unique_integer([:positive, :monotonic])}"
  # end

  # For now we will only support sessionless, so we will not boot a server but
  # directly run it in this process.
  defp dispatch_req(conn, msgid, %InitializeRequest{} = req, opts) do
    server = Keyword.get(opts, :server, GenMcp.DefaultServer)
    {:ok, state} = server.init(opts)

    {:reply, result, state} = server.client_init(req, state)

    result = %InitializeResult{
      capabilities: Map.get(result, :capabilities, %{}),
      serverInfo: Map.fetch!(result, :serverInfo),
      protocolVersion: "2025-06-18"
    }

    rpc_reply(conn, 200, msgid, result)
  end

  defp dispatch_req(conn, msgid, req, opts) do
    server = Keyword.get(opts, :server, GenMcp.DefaultServer)
    {:ok, state} = server.init(opts)
    channel = build_channel(conn, req, opts)

    # TODO here if we have a persistent server we must send a message instead of
    # directly calling the module. The channel could have infos for both
    # directions: how to call the server implementation from the transport, and
    # how to send to the transport from the server.
    case server.handle_request(req, channel, state) do
      {:reply, resp, _state} -> rpc_reply(conn, 200, msgid, resp)
      {:stream, state} -> rpc_stream(conn, 200, msgid, server, state)
      {:error, %{code: _} = err, _state} -> send_error(conn, channel, msgid, err)
    end
  end

  IO.warn("@todo build channel according to session/persistent (persistent implies session)")

  defp build_channel(conn, req, _opts) do
    progress_token =
      case req do
        %{params: %{_meta: %{"progressToken" => pt}}} -> pt
        _ -> nil
      end

    %GenMcp.Channel{
      kind: :local,
      client: [:alias | :erlang.alias()],
      session: nil,
      progress_token: progress_token
    }
  end

  defp dispatch_notif(conn, notif, opts) do
    server = Keyword.get(opts, :server, GenMcp.DefaultServer)
    {:ok, state} = server.init(opts)
    {:noreply, _state} = server.handle_notification(notif, state)
    send_accepted(conn)
  end

  defp rpc_reply(conn, status, msgid, result) do
    payload = %JSONRPCResponse{
      id: msgid,
      jsonrpc: "2.0",
      result: result
    }

    send_json(conn, status, payload)
  end

  @stream_keepalive_timeout :timer.seconds(25)

  defp rpc_stream(conn, 200, msgid, server, state) do
    conn = put_resp_header(conn, "content-type", "text/event-stream")
    conn = send_chunked(conn, 200)

    rpc_stream_loop(conn, msgid, server, state, start_keepalive())
  end

  defp start_keepalive do
    :erlang.start_timer(@stream_keepalive_timeout, self(), {__MODULE__, :keepalive})
  end

  defp reset_keepalive(old_ref) do
    IO.puts("reset keepalive")
    :ok = :erlang.cancel_timer(old_ref, async: true, info: false)
    start_keepalive()
  end

  defp rpc_stream_loop(conn, msgid, server, state, keepalive_ref) do
    # Here too server should be the bi-directional channel if we need to call a
    # process

    receive do
      # This chunk handler can only be part of the actual plug code
      {:timeout, ^keepalive_ref, {__MODULE__, :keepalive}} ->
        IO.puts("deliver keepalive")
        {:ok, conn} = chunk(conn, ":keepalive\n")
        rpc_stream_loop(conn, msgid, server, state, start_keepalive())

      # stale timers could be delivered before cancellation, so we must handle
      # them. Since we handle them we can cancel them asynchronously.
      {:timeout, _stale_ref, {__MODULE__, :keepalive}} ->
        rpc_stream_loop(conn, msgid, server, state, keepalive_ref)

      {:"$gen_mcp", :progress, payload} ->
        {:ok, conn} = send_data_event(conn, payload)
        rpc_stream_loop(conn, msgid, server, state, reset_keepalive(keepalive_ref))

      other
      when other != {:plug_conn, :sent} and not (is_tuple(other) and elem(other, 0) == :bandit) ->
        case server.handle_info(other, state) do
          {:reply, result, state} ->
            payload = %JSONRPCResponse{
              id: msgid,
              jsonrpc: "2.0",
              result: result
            }

            # On reply we can stop streaming
            {:ok, conn} = send_data_event(conn, payload)
            conn
        end
    end
  end

  defp send_json(conn, status, payload) do
    body = json_encode(payload, true)

    Logger.debug(["RESPONSE\n", body], ansi_color: :light_yellow)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  defp send_data_event(conn, payload) do
    json = json_encode(payload)
    event = "data: #{json}\n\n"
    chunk(conn, event)
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

  defp send_accepted(conn) do
    Logger.debug("RESPONSE\n--empty (202)--", ansi_color: :light_yellow)
    send_resp(conn, 202, "")
  end
end
