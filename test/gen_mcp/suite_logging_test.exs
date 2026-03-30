# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMCP.SuiteLoggingTest do
  use ExUnit.Case, async: true

  import GenMCP.Test.Helpers
  import Mox

  alias GenMCP.MCP
  alias GenMCP.Suite
  alias GenMCP.Support.ToolMock

  @moduletag :capture_log

  setup :verify_on_exit!

  @server_info [
    server_name: "Test Server",
    server_version: "0"
  ]

  defp init_session(server_opts \\ []) do
    assert {:ok, state} = Suite.init("some-session-id", Keyword.merge(@server_info, server_opts))

    init_req = %MCP.InitializeRequest{
      id: "setup-init-1",
      params: %MCP.InitializeRequestParams{
        capabilities: %MCP.ClientCapabilities{},
        clientInfo: %{name: "test", version: "1.0.0"},
        protocolVersion: "2025-06-18"
      }
    }

    assert {:reply, {:result, _result}, state} =
             Suite.handle_request(init_req, build_channel(), state)

    client_init_notif = %MCP.InitializedNotification{
      params: %{}
    }

    assert {:noreply, state} = Suite.handle_notification(client_init_notif, state)

    state
  end

  defp set_level_request(level) do
    %MCP.SetLevelRequest{
      id: System.unique_integer([:positive]),
      params: %MCP.SetLevelRequestParams{level: level}
    }
  end

  describe "logging capability" do
    test "logging capability is always declared" do
      {:ok, state} = Suite.init("some-session-id", @server_info)

      init_req = %MCP.InitializeRequest{
        id: 1,
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, result}, _state} =
               Suite.handle_request(init_req, build_channel(), state)

      assert %MCP.InitializeResult{
               capabilities: %MCP.ServerCapabilities{logging: %{}}
             } = result
    end
  end

  describe "set level request" do
    test "returns empty result" do
      state = init_session()

      assert {:reply, {:result, %MCP.Result{}}, _state} =
               Suite.handle_request(set_level_request(:warning), build_channel(), state)
    end

    test "updates the log level in state" do
      state = init_session()
      assert state.log_level == GenMCP.default_channel_log_level()

      assert {:reply, {:result, _}, state} =
               Suite.handle_request(set_level_request(:error), build_channel(), state)

      assert state.log_level == :error
    end
  end

  describe "channel log level stamping" do
    test "tool receives channel with current log level" do
      ToolMock
      |> stub(:info, fn :name, :log_tool -> "LogTool" end)
      |> expect(:call, fn _req, channel, _arg ->
        # The channel should have the current log level
        assert channel.log_level == GenMCP.default_channel_log_level()
        {:result, MCP.call_tool_result(text: "ok"), channel}
      end)

      state = init_session(tools: [{ToolMock, :log_tool}])

      tool_call_req = %MCP.CallToolRequest{
        id: 1001,
        params: %MCP.CallToolRequestParams{
          name: "LogTool",
          arguments: %{}
        }
      }

      assert {:reply, {:result, _}, _state} =
               Suite.handle_request(tool_call_req, build_channel(), state)
    end

    test "tool receives channel with updated log level after set level" do
      ToolMock
      |> stub(:info, fn :name, :log_tool -> "LogTool" end)
      |> expect(:call, fn _req, channel, _arg ->
        assert channel.log_level == :error
        {:result, MCP.call_tool_result(text: "ok"), channel}
      end)

      state = init_session(tools: [{ToolMock, :log_tool}])

      # Change log level
      assert {:reply, {:result, _}, state} =
               Suite.handle_request(set_level_request(:error), build_channel(), state)

      tool_call_req = %MCP.CallToolRequest{
        id: 1001,
        params: %MCP.CallToolRequestParams{
          name: "LogTool",
          arguments: %{}
        }
      }

      assert {:reply, {:result, _}, _state} =
               Suite.handle_request(tool_call_req, build_channel(), state)
    end
  end

  describe "async tool log level updates" do
    test "changing log level updates tracker channels for continue callback" do
      # 1. Call an async tool, it starts a task and returns {:async, ...}
      # 2. In the task, send a message to the test and wait for a reply
      # 3. In the test, change the log level and await success
      # 4. Reply to the task
      # 5. On continue, the channel should have the updated log level

      test_pid = self()

      ToolMock
      |> stub(:info, fn :name, :async_log_tool -> "AsyncLogTool" end)
      |> expect(:call, fn _req, channel, _arg ->
        task =
          Task.async(fn ->
            send(test_pid, {:task_ready, self()})

            receive do
              :continue -> :task_done
            end
          end)

        {:async, {:log_tag, task}, channel}
      end)
      |> expect(:continue, fn {:log_tag, {:ok, :task_done}}, channel, _arg ->
        # The channel should have the updated log level from set_level
        send(test_pid, {:continue_log_level, channel.log_level})
        {:result, MCP.call_tool_result(text: "done"), channel}
      end)

      state = init_session(tools: [{ToolMock, :async_log_tool}])

      tool_call_req = %MCP.CallToolRequest{
        id: 1001,
        params: %MCP.CallToolRequestParams{
          name: "AsyncLogTool",
          arguments: %{}
        }
      }

      # Start the async tool
      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, build_channel(), state)

      # Wait for task to be ready
      assert_receive {:task_ready, task_pid}

      # Change the log level while the task is in flight
      assert {:reply, {:result, _}, state} =
               Suite.handle_request(set_level_request(:error), build_channel(), state)

      # Now let the task complete
      send(task_pid, :continue)

      # Receive the task result and deliver it to the suite
      assert_receive {ref, :task_done} when is_reference(ref)
      assert {:noreply, _state} = Suite.handle_info({ref, :task_done}, state)

      # Verify the continue callback received the updated log level
      assert_receive {:continue_log_level, :error}

      # Result should be delivered
      assert_receive {:"$gen_mcp", :result, _result}
    end

    test "sc_channel is updated when log level changes" do
      state = init_session()

      assert {:reply, {:result, _}, state} =
               Suite.handle_request(set_level_request(:warning), build_channel(), state)

      assert state.sc_channel.log_level == :warning
    end

    test "chained async gets updated log level on each continue" do
      # First async step uses initial level, then level changes, second
      # continue should see the new level.

      ref1 = make_ref()
      ref2 = make_ref()
      test_pid = self()

      ToolMock
      |> stub(:info, fn :name, :chain_log_tool -> "ChainLogTool" end)
      |> expect(:call, fn _req, channel, _arg ->
        send(test_pid, {:call_log_level, channel.log_level})
        {:async, {:step1, ref1}, channel}
      end)
      |> expect(:continue, fn {:step1, {:ok, :step1_done}}, channel, _arg ->
        send(test_pid, {:continue1_log_level, channel.log_level})
        {:async, {:step2, ref2}, channel}
      end)
      |> expect(:continue, fn {:step2, {:ok, :step2_done}}, channel, _arg ->
        send(test_pid, {:continue2_log_level, channel.log_level})
        {:result, MCP.call_tool_result(text: "done"), channel}
      end)

      state = init_session(tools: [{ToolMock, :chain_log_tool}])

      tool_call_req = %MCP.CallToolRequest{
        id: 1001,
        params: %MCP.CallToolRequestParams{
          name: "ChainLogTool",
          arguments: %{}
        }
      }

      # Start with default log level
      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, build_channel(), state)

      assert_receive {:call_log_level, default_level}
      assert default_level == GenMCP.default_channel_log_level()

      # Complete step 1
      assert {:noreply, state} = Suite.handle_info({ref1, :step1_done}, state)
      assert_receive {:continue1_log_level, ^default_level}

      # Change log level between step 1 and step 2
      assert {:reply, {:result, _}, state} =
               Suite.handle_request(set_level_request(:error), build_channel(), state)

      # Complete step 2 — should see updated level
      assert {:noreply, _state} = Suite.handle_info({ref2, :step2_done}, state)
      assert_receive {:continue2_log_level, :error}

      assert_receive {:"$gen_mcp", :result, _result}
    end
  end
end
