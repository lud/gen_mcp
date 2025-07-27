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

  def http_post(%{body_params: %{"jsonrpc" => "2.0", "id" => msgid} = body_params} = conn, opts) do
    case Validator.validate_request(body_params) do
      {:ok, req} -> dispatch_req(conn, msgid, req, opts)
      {:error, e} -> send_error_sessionless(conn, msgid, e)
    end
  end

  def http_post(%{body_params: %{"jsonrpc" => "2.0"} = body_params} = conn, opts) do
    case Validator.validate_notification(body_params) do
      {:ok, notif} -> dispatch_notif(conn, notif, opts)
      {:error, e} -> send_error_sessionless(conn, nil, e)
    end
  end

  defp send_error_sessionless(conn, msgid, %JSV.ValidationError{} = jsv_err) do
    Logger.error("invalid request sent to #{inspect(__MODULE__)}")

    payload = %GenMcp.Entities.JSONRPCError{
      error: %{
        code: 1,
        data: JSV.normalize_error(jsv_err),
        message: "request validation failed"
      },
      # no session, we do not know what client that is,
      id: msgid,
      jsonrpc: "2.0"
    }

    send_json(conn, 400, payload)
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
    {:reply, resp, _state} = server.handle_request(req, state)
    rpc_reply(conn, 200, msgid, resp)
  end

  defp dispatch_notif(conn, notif, opts) do
    server = Keyword.get(opts, :server, GenMcp.DefaultServer)
    {:ok, state} = server.init(opts)
    {:noreply, _state} = server.handle_notification(notif, state)
    send_accepted(conn)
  end

  defp rpc_reply(conn, status, id, result) do
    payload = %JSONRPCResponse{
      id: id,
      jsonrpc: "2.0",
      result: result
    }

    send_json(conn, status, payload)
  end

  defp send_json(conn, status, payload) do
    body =
      payload
      |> JSV.Helpers.Traverse.prewalk(fn
        {:struct, v} -> MapExt.from_struct_no_nils(v)
        other -> elem(other, 1)
      end)
      |> Codec.format_to_iodata!()

    Logger.debug(["RESPONSE\n", body], ansi_color: :light_yellow)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  defp send_accepted(conn) do
    Logger.debug("RESPONSE\n--empty (202)--", ansi_color: :light_yellow)
    send_resp(conn, 202, "")
  end
end
