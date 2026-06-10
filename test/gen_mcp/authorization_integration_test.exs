defmodule GenMCP.AuthorizationIntegrationTest do
  use ExUnit.Case, async: false

  import GenMCP.Test.Client
  import Mox

  alias GenMCP.MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.Support.AuthorizationMock
  alias GenMCP.Support.ServerMock

  # DISCLAIMER
  #
  # This tests seem to test Plug itself. Indeed we need to ensure that
  # authentication can be left to be implemented by users, relying on phoenix
  # router pipelines (or other plug systems).
  #
  # The real test is the assigns management: router static assigns + auth-plug
  # assigns + `copy_assigns` must reach the channel. This is a per-request
  # transport concern under the stateless protocol — there is no session.

  @protocol_version GenMCP.protocol_version()

  setup [:set_mox_global, :verify_on_exit!]

  def client(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:url, "/mcp/mock-auth")
      |> Keyword.put_new(:headers, %{"mcp-protocol-version" => @protocol_version})

    new(opts)
  end

  describe "when auth plug halts the connection" do
    setup do
      AuthorizationMock
      |> expect(:init, fn opts -> opts end)
      |> expect(:call, fn conn, _opts ->
        conn
        |> Plug.Conn.put_resp_header("www-authenticate", "PlugWasCalled")
        |> Plug.Conn.send_resp(401, "Unauthorized")
        |> Plug.Conn.halt()
      end)

      :ok
    end

    test "request returns 401 without invoking the server handler" do
      resp =
        client()
        |> post_message(%{
          jsonrpc: "2.0",
          id: 123,
          method: "tools/list",
          params: %{}
        })
        |> expect_status(401)

      assert ["PlugWasCalled"] == resp.headers["www-authenticate"]

      # Server was not called
      Mox.verify!(ServerMock)
    end

    test "notification returns 401 without invoking the server handler" do
      resp =
        client()
        |> post_message(%{
          jsonrpc: "2.0",
          method: "notifications/cancelled",
          params: %{requestId: "x", reason: "y"}
        })
        |> expect_status(401)

      assert ["PlugWasCalled"] == resp.headers["www-authenticate"]

      # Server was not called
      Mox.verify!(ServerMock)
    end

    test "tool call returns 401 without invoking the server handler" do
      resp =
        client()
        |> post_message(%{
          jsonrpc: "2.0",
          id: 123,
          method: "tools/call",
          params: %{name: "test_tool", arguments: %{}}
        })
        |> expect_status(401)

      assert ["PlugWasCalled"] == resp.headers["www-authenticate"]

      # Server was not called
      Mox.verify!(ServerMock)
    end
  end

  describe "when auth plug passes the connection through" do
    setup do
      AuthorizationMock
      |> stub(:init, fn opts -> opts end)
      |> stub(:call, fn conn, _opts ->
        conn
        |> Plug.Conn.assign(:assign_from_auth, "value_from_auth")
        |> Plug.Conn.assign(:shared_assign, "value_from_auth")
      end)

      :ok
    end

    test "request reaches the server handler with merged assigns" do
      ServerMock
      |> expect(:init, fn _opts -> {:ok, :server_state} end)
      |> expect(:handle_request, fn _req, channel, :server_state ->
        assert %Channel{assigns: assigns} = channel

        # static assigns from the router forward are present
        assert "hello" == assigns.assign_from_forward

        # assigns from the auth plug are present
        assert "value_from_auth" == assigns.assign_from_auth

        # auth value takes precedence over the static value
        assert "value_from_auth" == assigns.shared_assign

        # unexisting copy_assigns key is not set
        assert not Map.has_key?(assigns, :unexisting_assign)

        # the stateless transport mints no session id assign
        assert not Map.has_key?(assigns, :gen_mcp_session_id)

        {:result, MCP.list_tools_result([])}
      end)

      client()
      |> post_message(%{jsonrpc: "2.0", id: 123, method: "tools/list", params: %{}})
      |> expect_status(200)
      |> refute_session_header()
    end

    test "two independent requests each reach the handler with merged assigns" do
      # Statelessly each request stands alone: it is authenticated, builds fresh
      # state via init/2, and carries the same merged assigns.
      for id <- [123, 456] do
        ServerMock
        |> expect(:init, fn _opts -> {:ok, :server_state} end)
        |> expect(:handle_request, fn _req, channel, :server_state ->
          assert %Channel{assigns: assigns} = channel
          assert assigns[:assign_from_forward] == "hello"
          assert assigns[:assign_from_auth] == "value_from_auth"
          assert assigns[:shared_assign] == "value_from_auth"

          {:result, MCP.list_tools_result([])}
        end)

        client()
        |> post_message(%{jsonrpc: "2.0", id: id, method: "tools/list", params: %{}})
        |> expect_status(200)
        |> refute_session_header()
      end
    end
  end
end
