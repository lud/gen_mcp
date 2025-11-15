defmodule GenMCP.Mux.SessionTest do
  alias GenMCP.MCP
  alias GenMCP.Mux
  alias GenMCP.Server
  alias GenMCP.Support.ServerMock
  import Mox
  import GenMCP.Test.Helpers
  use ExUnit.Case

  setup [:set_mox_global, :verify_on_exit!]

  defp init_req do
    %MCP.InitializeRequest{
      id: "test-ini-req",
      method: "initialize",
      params: %MCP.InitializeRequestParams{
        _meta: nil,
        capabilities: %MCP.ClientCapabilities{
          elicitation: nil,
          experimental: nil,
          roots: nil,
          sampling: nil
        },
        clientInfo: %MCP.Implementation{
          name: "test client",
          title: nil,
          version: "0.0.0"
        },
        protocolVersion: "2025-06-18"
      }
    }
  end

  defp init_notif do
    %MCP.InitializedNotification{
      method: "notifications/initialized",
      params: %{}
    }
  end

  defp list_tools_req do
    %MCP.ListToolsRequest{id: :erlang.unique_integer(), method: "tools/list", params: %{}}
  end

  test "session can timeout" do
    ServerMock
    |> expect(:init, fn _, _ -> {:ok, :some_session_state} end)
    |> expect(:handle_request, fn %MCP.InitializeRequest{}, _, state ->
      {:reply, {:result, "foo"}, state}
    end)
    |> expect(:handle_notification, fn %MCP.InitializedNotification{}, state ->
      {:noreply, state}
    end)
    |> stub(:handle_request, fn %MCP.ListToolsRequest{}, _, state ->
      {:reply, {:result, MCP.list_tools_result([])}, state}
    end)

    # session timeout is refreshed whenever a request or notification hits the
    # server

    session_timeout = 500

    assert {:ok, session_id} =
             Mux.start_session(
               session_id: "some_session_id",
               server: ServerMock,
               session_timeout: session_timeout
             )

    assert {:result, "foo"} = Mux.request(session_id, init_req(), chan_info())

    # We can sleep for a bit, as long as we send requests, the session stays alive

    Process.sleep(100)

    assert :ack = Mux.notify(session_id, init_notif())

    Process.sleep(100)

    assert {:result, _} = Mux.request(session_id, list_tools_req(), chan_info())

    # If it waits too much, the sesssion will be down

    Process.sleep(700)

    assert nil == Mux.whereis(session_id)
  end
end
