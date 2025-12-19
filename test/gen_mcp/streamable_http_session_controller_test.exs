# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMCP.StreamableHTTPSessionControllerTest do
  use ExUnit.Case, async: false

  import GenMCP.Test.Client
  import GenMCP.Test.Helpers
  import Mox

  alias GenMCP.MCP
  alias GenMCP.Support.ServerMock
  alias GenMCP.Support.SessionControllerMock

  @mcp_url "/mcp/controlled"
  setup [:set_mox_global, :verify_on_exit!]

  def client(opts) when is_list(opts) do
    headers =
      case Keyword.get(opts, :session_id, nil) do
        nil -> %{}
        sid when is_binary(sid) -> %{"mcp-session-id" => sid}
      end

    url = Keyword.fetch!(opts, :url)

    new(headers: headers, url: url)
  end

  describe "session handling" do
    test "initialize relays the session_controller option to the server" do
      ServerMock
      |> expect(:init, fn _sesion_id, opts ->
        assert {:ok, {SessionControllerMock, _}} = Keyword.fetch(opts, :session_controller)
        {:ok, :some_server_state}
      end)
      |> expect(:handle_request, fn %MCP.InitializeRequest{}, _channel, state ->
        init_result =
          MCP.intialize_result(
            capabilities: MCP.capabilities(tools: true),
            server_info: MCP.server_info(name: "Mock Server", version: "foo", title: "stuff")
          )

        {:reply, {:result, init_result}, state}
      end)

      client(url: @mcp_url)
      |> post_message(%MCP.InitializeRequest{
        id: 123,
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %MCP.Implementation{name: "test client", version: "0.0.0"},
          protocolVersion: "2025-06-18"
        }
      })
      |> expect_status(200)
    end

    test "initialize request does not call session controller" do
      ServerMock
      |> expect(:init, fn _, _ -> {:ok, :some_server_state} end)
      |> expect(:handle_request, fn _req, _channel, state ->
        init_result =
          MCP.intialize_result(
            capabilities: MCP.capabilities(tools: true),
            server_info: MCP.server_info(name: "Mock Server", version: "foo", title: "stuff")
          )

        {:reply, {:result, init_result}, state}
      end)
      |> expect(:handle_notification, fn _notif, state -> {:noreply, state} end)

      # We should NOT expect any call to SessionControllerMock

      resp =
        client(url: @mcp_url)
        |> post_message(%MCP.InitializeRequest{
          id: 123,
          params: %MCP.InitializeRequestParams{
            capabilities: %MCP.ClientCapabilities{},
            clientInfo: %MCP.Implementation{name: "test client", version: "0.0.0"},
            protocolVersion: "2025-06-18"
          }
        })
        |> expect_status(200)

      session_id = expect_session_header(resp)

      assert "" =
               client(session_id: session_id, url: @mcp_url)
               |> post_message(%{
                 jsonrpc: "2.0",
                 method: "notifications/initialized",
                 params: %{}
               })
               |> expect_status(202)
               |> body()
    end

    test "request without session calls fetch and returns 404 if not found" do
      sid = random_session_id()

      expect(ServerMock, :session_fetch, fn ^sid, _channel, _ ->
        {:error, :not_found}
      end)

      client(session_id: sid, url: @mcp_url)
      |> post_message(%{
        jsonrpc: "2.0",
        id: 123,
        method: "tools/list",
        params: %{}
      })
      |> expect_status(404)
    end

    test "request without session calls fetch and restores session if found" do
      sid = random_session_id()

      ServerMock
      |> expect(:session_fetch, fn ^sid, _channel, _ ->
        {:ok, :some_restored_session_data}
      end)
      |> expect(:init, fn _, _ -> {:ok, :initial_server_state} end)
      |> expect(:session_restore, fn :some_restored_session_data,
                                     _channel,
                                     :initial_server_state ->
        {:noreply, :restored_server_state}
      end)
      |> expect(:handle_request, fn req, _channel, :restored_server_state ->
        assert %MCP.ListToolsRequest{} = req
        {:reply, {:result, MCP.list_tools_result([])}, :restored_server_state}
      end)

      client(session_id: sid, url: @mcp_url)
      |> post_message(%{
        jsonrpc: "2.0",
        id: 123,
        method: "tools/list",
        params: %{}
      })
      |> expect_status(200)
    end

    test "notification without session calls fetch and returns 404 if not found" do
      sid = random_session_id()

      expect(ServerMock, :session_fetch, fn ^sid, _channel, _ ->
        {:error, :not_found}
      end)

      assert %{
               "error" => %{
                 "code" => -32_603,
                 "message" => "Session not found"
               },
               "jsonrpc" => "2.0"
             } =
               client(session_id: sid, url: @mcp_url)
               |> post_message(%{
                 jsonrpc: "2.0",
                 method: "notifications/initialized",
                 params: %{}
               })
               |> expect_status(404)
               |> body()
    end

    test "notification without session calls fetch and restores session if found" do
      sid = random_session_id()

      ServerMock
      |> expect(:session_fetch, fn ^sid, _channel, _ ->
        {:ok, :some_restored_session_data}
      end)
      |> expect(:init, fn _, _ -> {:ok, :initial_server_state} end)
      |> expect(:session_restore, fn :some_restored_session_data,
                                     _channel,
                                     :initial_server_state ->
        {:noreply, :restored_server_state}
      end)
      |> expect(:handle_notification, fn _notif, state -> {:noreply, state} end)

      assert "" =
               client(session_id: sid, url: @mcp_url)
               |> post_message(%{
                 jsonrpc: "2.0",
                 method: "notifications/initialized",
                 params: %{}
               })
               |> expect_status(202)
               |> body()
    end

    test "delete request calls session_delete" do
      sid = random_session_id()
      # First we need to establish a session or restore it. Let's restore it for simplicity.

      ServerMock
      |> expect(:session_fetch, fn ^sid, _channel, _ -> {:ok, :some_restored_session_data} end)
      |> expect(:init, fn _, _ -> {:ok, :initial_server_state} end)
      |> expect(:session_restore, fn :some_restored_session_data,
                                     _channel,
                                     :initial_server_state ->
        {:noreply, :restored_server_state}
      end)
      |> expect(:session_delete, fn :restored_server_state -> :ok end)

      client(session_id: sid, url: @mcp_url)
      |> Req.delete!()
      |> expect_status(204)
    end

    test "delete unknown session calls the server raw callback" do
      sid = random_session_id()

      expect(ServerMock, :session_fetch, fn ^sid, _channel, _ ->
        {:error, :not_found}
      end)

      client(session_id: sid, url: @mcp_url)
      |> Req.delete!()
      |> expect_status(404)
    end

    @tag :capture_log
    test "restore failure" do
      sid = random_session_id()

      ServerMock
      |> expect(:session_fetch, fn ^sid, _channel, _ ->
        {:ok, :some_sesssion_data}
      end)
      |> expect(:init, fn _, _ -> {:ok, :some_server_state} end)
      |> expect(:session_restore, fn _, _, state ->
        {:stop, :goodbye, state}
      end)

      assert %{
               "error" => %{"code" => -32_603, "message" => "Session Lost"},
               "id" => 456,
               "jsonrpc" => "2.0"
             } =
               client(session_id: sid, url: @mcp_url)
               |> post_message(%{
                 jsonrpc: "2.0",
                 id: 456,
                 method: "tools/call",
                 params: %{
                   _meta: %{progressToken: "hello"},
                   name: "SomeTool",
                   arguments: %{some: "arg"}
                 }
               })
               |> expect_status(404)
               |> body()
    end

    @tag :capture_log
    test "stopping from handle info" do
      parent = self()

      ServerMock
      |> expect(:init, fn _, _ ->
        send(parent, {:session_pid, self()})
        {:ok, :some_server_state}
      end)
      |> expect(:handle_request, fn %MCP.InitializeRequest{}, _channel, state ->
        init_result =
          MCP.intialize_result(
            capabilities: MCP.capabilities(tools: true),
            server_info: MCP.server_info(name: "Mock Server", version: "foo", title: "stuff")
          )

        {:reply, {:result, init_result}, state}
      end)

      # Init is ok

      assert %{
               "id" => 123,
               "jsonrpc" => "2.0",
               "result" => %{}
             } =
               client(url: @mcp_url)
               |> post_message(%{
                 jsonrpc: "2.0",
                 id: 123,
                 method: "initialize",
                 params: %{
                   capabilities: %{},
                   clientInfo: %{name: "test client", version: "0.0.0"},
                   protocolVersion: "2025-06-18"
                 }
               })
               |> expect_status(200)
               |> body()

      # And we get the pid

      assert_receive {:session_pid, session_pid}

      ref = Process.monitor(session_pid)

      expect(ServerMock, :handle_info, fn :please_stop, state ->
        {:stop, :okay_i_stop, state}
      end)

      send(session_pid, :please_stop)

      assert_receive {:DOWN, ^ref, :process, ^session_pid, reason}

      assert :okay_i_stop = reason
    end
  end
end
