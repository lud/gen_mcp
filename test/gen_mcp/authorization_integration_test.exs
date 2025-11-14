defmodule GenMCP.AuthorizationIntegrationTest do
  alias GenMCP.Server
  alias GenMCP.Support.ServerMock
  import GenMCP.Test.Client
  import Mox
  use ExUnit.Case, async: false

  # DISCLAIMER
  #
  # This tests seem to test Plug itself. Indeed we need to ensure that
  # authentication can be left to be implemented by users, relying on phoenix
  # router pipelines (or other plug systems).
  #
  # The real test is the assigns management.

  setup [:set_mox_global, :verify_on_exit!]

  def client(opts \\ []) do
    opts = Keyword.put_new(opts, :url, "/mcp/mock-auth")
    new(opts)
  end

  def client_with_session(session_id, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:url, "/mcp/mock-auth")
      |> Keyword.put(:headers, %{"mcp-session-id" => session_id})

    new(opts)
  end

  describe "when auth plug halts the connection" do
    setup do
      GenMCP.Support.AuthorizationMock
      |> expect(:init, fn opts -> opts end)
      |> expect(:call, fn conn, _opts ->
        conn
        |> Plug.Conn.put_resp_header("www-authenticate", "PlugWasCalled")
        |> Plug.Conn.send_resp(401, "Unauthorized")
        |> Plug.Conn.halt()
      end)

      :ok
    end

    test "initialize request returns 401 without invoking server handler" do
      resp =
        client()
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
        |> expect_status(401)

      assert ["PlugWasCalled"] == resp.headers["www-authenticate"]

      # Server was not called
      Mox.verify!(ServerMock)
    end

    test "notification request returns 401 without invoking server handler" do
      resp =
        client()
        |> post_message(%{
          jsonrpc: "2.0",
          method: "notifications/initialized",
          params: %{}
        })
        |> expect_status(401)

      assert ["PlugWasCalled"] == resp.headers["www-authenticate"]

      # Server was not called
      Mox.verify!(ServerMock)
    end

    test "tool call request returns 401 without invoking server handler" do
      resp =
        client()
        |> post_message(%{
          jsonrpc: "2.0",
          id: 123,
          method: "tools/call",
          params: %{
            name: "test_tool",
            arguments: %{}
          }
        })
        |> expect_status(401)

      assert ["PlugWasCalled"] == resp.headers["www-authenticate"]

      # Server was not called
      Mox.verify!(ServerMock)
    end
  end

  describe "when auth plug passes the connection through" do
    setup do
      GenMCP.Support.AuthorizationMock
      |> stub(:init, fn opts -> opts end)
      |> stub(:call, fn conn, _opts ->
        conn
        |> Plug.Conn.assign(:assign_from_auth, "value_from_auth")
        |> Plug.Conn.assign(:shared_assign, "value_from_auth")
      end)

      :ok
    end

    test "initialize request reaches server handler with merged assigns" do
      ServerMock
      |> expect(:init, fn sid, _ -> {:ok, {:sid, sid}} end)
      |> expect(:handle_request, fn _req, chan_info, {:sid, sid} ->
        assert {:channel, GenMCP.Transport.StreamableHttp, _pid, assigns} = chan_info

        # sessionid is set in the assigns by the client
        assert ^sid = assigns.gen_mcp_session_id

        # static assigns from router are present
        assert "hello" == assigns.assign_from_forward

        # assigns from auth plug are present
        assert "value_from_auth" == assigns.assign_from_auth

        # auth value takes precedence over static value
        assert "value_from_auth" == assigns.shared_assign

        # unexisting copy_assigns key is not set
        assert not Map.has_key?(assigns, :unexisting_assign)

        init_result =
          Server.intialize_result(
            capabilities: Server.capabilities(tools: true),
            server_info: Server.server_info(name: "Mock Server", version: "0.0.1")
          )

        {:reply, {:result, init_result}, :session_state}
      end)

      resp =
        client()
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

      _session_id = expect_session_header(resp)
    end

    test "tool call request reaches server handler with merged assigns" do
      ServerMock
      |> expect(:init, fn sid, _ -> {:ok, {:sid, sid}} end)
      |> expect(:handle_request, fn _req, chan_info, {:sid, sid} ->
        assert {:channel, GenMCP.Transport.StreamableHttp, _pid, assigns} = chan_info

        assert ^sid = assigns.gen_mcp_session_id
        assert assigns[:assign_from_forward] == "hello"
        assert assigns[:assign_from_auth] == "value_from_auth"
        assert assigns[:shared_assign] == "value_from_auth"

        init_result =
          Server.intialize_result(
            capabilities: Server.capabilities(tools: true),
            server_info: Server.server_info(name: "Mock Server", version: "0.0.1")
          )

        {:reply, {:result, init_result}, :session_state_1}
      end)
      |> expect(:handle_request, fn _req, chan_info, :session_state_1 ->
        assert {:channel, GenMCP.Transport.StreamableHttp, _pid, assigns} = chan_info

        # assigns are properly merged for tool call
        assert assigns[:assign_from_forward] == "hello"
        assert assigns[:assign_from_auth] == "value_from_auth"
        assert assigns[:shared_assign] == "value_from_auth"

        call_tool_result = Server.call_tool_result(text: "hello")

        {:reply, {:result, call_tool_result}, :session_state_2}
      end)

      resp =
        client()
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

      session_id = expect_session_header(resp)

      _resp =
        client_with_session(session_id)
        |> post_message(%{
          jsonrpc: "2.0",
          id: 456,
          method: "tools/call",
          params: %{
            name: "test_tool",
            arguments: %{}
          }
        })
        |> expect_status(200)
    end
  end
end
