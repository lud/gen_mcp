defmodule GenMCP.Mux.SessionTest do
  alias GenMCP.MCP
  alias GenMCP.Mux
  alias GenMCP.Mux.SessionSupervisor
  alias GenMCP.Support.ServerMock
  import GenMCP.Test.Helpers
  import Mox
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

  test "dynamic supervisor does not keep initialization args in memory" do
    # OK so now we are just testing dynamic supervisor itself, and not really
    # our library. But if the DynamicSupervisor implementation changes, we will
    # change our own implementation to avoid keeping the full session and plug
    # in memory for no reason.

    expect(ServerMock, :init, fn _, _ -> {:ok, :some_session_state} end)

    assert {:ok, session_id} = Mux.start_session(server: ServerMock)
    pid = Mux.whereis(session_id)
    assert is_pid(pid)
    session_sup = GenServer.whereis(SessionSupervisor.name())
    assert is_pid(session_sup)

    # Supervisor should have mfa = {GenMCP.Mux.Session, :start_link, :undefined}
    # where :undefined replaces the init args

    assert %{
             children: %{
               ^pid => {{GenMCP.Mux.Session, :start_link, :undefined}, :temporary, _, _, _}
             }
           } = :sys.get_state(session_sup)
  end

  @tag :capture_log
  test "stops if server returns error tuple in init" do
    expect(ServerMock, :init, fn _, _ -> {:stop, :some_error} end)

    assert {:error, {:mcp_server_init_failure, :some_error}} =
             Mux.start_session(server: ServerMock)
  end

  @tag :capture_log
  test "stops handle_request returns stop" do
    ServerMock
    |> expect(:init, fn _, _ -> {:ok, :some_session_state} end)
    |> expect(:handle_request, fn %{params: %{protocolVersion: "bad_version"}}, _, _ ->
      {:stop, :exit_reason, :reply_reason, :some_session_state}
    end)

    assert {:ok, session_id} = Mux.start_session(server: ServerMock)
    pid = Mux.whereis(session_id)
    ref = Process.monitor(pid)

    bad_request = %MCP.InitializeRequest{
      id: 1,
      method: "initialize",
      params: %MCP.InitializeRequestParams{
        capabilities: %{},
        clientInfo: %{name: "test", version: "1.0.0"},
        protocolVersion: "bad_version"
      }
    }

    assert :reply_reason = Mux.request(session_id, bad_request, chan_info())
    assert_receive {:DOWN, ^ref, :process, ^pid, :exit_reason}
  end
end
