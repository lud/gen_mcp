# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMCP.SuiteAsyncTest do
  alias GenMCP.Entities
  alias GenMCP.Mux.Channel
  alias GenMCP.Server
  alias GenMCP.Suite
  alias GenMCP.Support.ToolMock
  import Mox
  use ExUnit.Case, async: true

  @moduletag :capture_log

  setup :verify_on_exit!

  @server_info [
    server_name: "Test Server",
    server_version: "0"
  ]

  defp chan_info(assigns \\ %{}) do
    {:channel, __MODULE__, self(), assigns}
  end

  defp task_sup do
    start_supervised!(Task.Supervisor)
  end

  defp check_error({:error, reason}) do
    check_error(reason)
  end

  defp check_error(reason) do
    GenMCP.RpcError.cast_error(reason)
  end

  defp init_session(server_opts, init_assigns \\ %{}) do
    assert {:ok, state} = Suite.init("some-session-id", Keyword.merge(@server_info, server_opts))

    init_req = %Entities.InitializeRequest{
      id: "setup-init-1",
      method: "initialize",
      params: %Entities.InitializeRequestParams{
        capabilities: %{},
        clientInfo: %{name: "test", version: "1.0.0"},
        protocolVersion: "2025-06-18"
      }
    }

    assert {:reply, {:result, _result}, %{status: :server_initialized} = state} =
             Suite.handle_request(init_req, chan_info(init_assigns), state)

    client_init_notif = %Entities.InitializedNotification{
      method: "notifications/initialized",
      params: %{}
    }

    assert {:noreply, %{status: :client_initialized} = state} =
             Suite.handle_notification(client_init_notif, state)

    state
  end

  describe "basic async execution" do
    test "tool returns async with bare reference" do
      # This test validates that a tool can spawn a task using make_ref()
      # and return {:async, {tag, ref}, channel}. The server should track
      # the ref, wait for {ref, result} message, and call continue/3.

      ref = make_ref()

      ToolMock
      |> stub(:info, fn :name, :async_tool -> "AsyncTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        {:async, {:my_tag, ref}, chan}
      end)
      |> expect(:continue, fn {:my_tag, {:ok, {:success, 42}}}, chan, _arg ->
        {:result, Server.call_tool_result(text: "Result: 42"), chan}
      end)

      state = init_session(tools: [{ToolMock, :async_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "AsyncTool",
          arguments: %{}
        }
      }

      # Call the tool - should return :stream since tool is async
      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      # Deliver some response with the ref
      assert {:noreply, _state} = Suite.handle_info({ref, {:success, 42}}, state)

      # The continue callback should have been called with wrapped result
      # and the result should be delivered to the client process
      assert_receive {:"$gen_mcp", :result, result}

      assert %Entities.CallToolResult{content: [%{type: :text, text: "Result: 42"}]} = result
    end

    test "tool returns async with Task struct instead of ref" do
      # This test validates that a tool can use Task.async/1 which returns
      # a %Task{} struct. The server should extract Task.ref for tracking.

      test_pid = self()

      ToolMock
      |> stub(:info, fn :name, :async_task_tool -> "AsyncTaskTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        task =
          Task.async(fn ->
            send(test_pid, :task_started)
            {:computed, 100}
          end)

        {:async, {:calculation_tag, task}, chan}
      end)
      |> expect(:continue, fn {:calculation_tag, {:ok, {:computed, 100}}}, chan, _arg ->
        {:result, Server.call_tool_result(text: "Computed: 100"), chan}
      end)

      state = init_session(tools: [{ToolMock, :async_task_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "AsyncTaskTool",
          arguments: %{}
        }
      }

      # Call the tool - should return :stream since tool is async
      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      # Wait for task to start and complete
      assert_receive :task_started
      assert_receive {ref, {:computed, 100}} when is_reference(ref)

      # Deliver message to server
      assert {:noreply, _state} = Suite.handle_info({ref, {:computed, 100}}, state)

      # Assert result is delivered to client
      assert_receive {:"$gen_mcp", :result, result}

      # The server demonitored the task
      assert false == Process.demonitor(ref, [:info])

      assert %Entities.CallToolResult{content: [%Entities.TextContent{text: "Computed: 100"}]} =
               result
    end
  end

  describe "Task.Supervisor integration" do
    test "successful Task.Supervisor.async execution" do
      task_sup = task_sup()

      # This test validates that tools can use Task.Supervisor.async/2
      # for supervised async execution.

      test_pid = self()

      ToolMock
      |> stub(:info, fn :name, :supervised_tool -> "SupervisedTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        task =
          Task.Supervisor.async(task_sup, fn ->
            send(test_pid, :supervised_task_started)
            {:supervised_result, 200}
          end)

        {:async, {:supervised_tag, task}, chan}
      end)
      |> expect(:continue, fn {:supervised_tag, {:ok, {:supervised_result, 200}}}, chan, _arg ->
        {:result, Server.call_tool_result(text: "Supervised: 200"), chan}
      end)

      state = init_session(tools: [{ToolMock, :supervised_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "SupervisedTool",
          arguments: %{}
        }
      }

      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      assert_receive :supervised_task_started
      assert_receive {ref, {:supervised_result, 200}} when is_reference(ref)

      assert {:noreply, _state} = Suite.handle_info({ref, {:supervised_result, 200}}, state)

      # Assert result is delivered to client
      assert_receive {:"$gen_mcp", :result, result}

      assert %Entities.CallToolResult{
               content: [%Entities.TextContent{text: "Supervised: 200"}]
             } = result
    end

    test "down message for monitored process after successful completion" do
      # This test validates that when a task completes normally, the server
      # receives both {ref, result} and {:DOWN, ref, :process, pid, :normal}.
      # The server should process the result and ignore the subsequent DOWN.

      test_pid = self()

      ToolMock
      |> stub(:info, fn :name, :down_test_tool -> "DownTestTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        task =
          Task.async(fn ->
            send(test_pid, :task_running)
            :completed
          end)

        {:async, {:down_tag, task}, chan}
      end)
      |> expect(:continue, fn {:down_tag, {:ok, :completed}}, chan, _arg ->
        {:result, Server.call_tool_result(text: "Completed"), chan}
      end)

      state = init_session(tools: [{ToolMock, :down_test_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "DownTestTool",
          arguments: %{}
        }
      }

      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      assert_receive :task_running
      assert_receive {ref, :completed} when is_reference(ref)

      # Process the successful result first
      assert {:noreply, state} = Suite.handle_info({ref, :completed}, state)

      # The server demonitored the task
      assert false == Process.demonitor(ref, [:info])

      # Server should ignore this DOWN message since task already completed
      # This should NOT call continue/3 again
      assert {:noreply, _state} =
               Suite.handle_info({:DOWN, ref, :process, self(), :normal}, state)

      # Assert result is delivered to client
      assert_receive {:"$gen_mcp", :result, result}

      assert %Entities.CallToolResult{content: [%Entities.TextContent{text: "Completed"}]} =
               result
    end
  end

  describe "error handling" do
    test "task.Supervisor.async_nolink with failing task" do
      task_sup = task_sup()

      # This test validates that when a task crashes (exit/1), the server
      # receives {:DOWN, ref, :process, pid, reason} and calls continue/3
      # with {:error, {:exit, reason}}.

      test_pid = self()

      ToolMock
      |> stub(:info, fn :name, :failing_tool -> "FailingTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        task =
          Task.Supervisor.async_nolink(task_sup, fn ->
            send(test_pid, :about_to_fail)
            exit(:intentional_failure)
          end)

        {:async, {:failing_tag, task}, chan}
      end)
      |> expect(:continue, fn {:failing_tag, {:error, :intentional_failure}}, chan, _arg ->
        {:result, Server.call_tool_result(text: "Handled failure", is_error: true), chan}
      end)

      state = init_session(tools: [{ToolMock, :failing_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "FailingTool",
          arguments: %{}
        }
      }

      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      assert_receive :about_to_fail
      downmsg = assert_receive {:DOWN, _ref, :process, _pid, :intentional_failure}

      # Server should call continue with error tuple
      assert {:noreply, _state} = Suite.handle_info(downmsg, state)

      # Assert result is delivered to client
      assert_receive {:"$gen_mcp", :result, result}

      assert %Entities.CallToolResult{
               content: [%Entities.TextContent{text: "Handled failure"}],
               isError: true
             } = result
    end

    test "task with runtime error" do
      # The server process does not trap exits. If Task.async crashes, so does
      # the server.

      {_, spawn_ref} =
        spawn_monitor(fn ->
          ToolMock
          |> stub(:info, fn :name, :error_tool -> "ErrorTool" end)
          |> expect(:call, fn _req, chan, _arg ->
            task = Task.async(fn -> raise RuntimeError, "Something went wrong" end)

            {:async, {:error_tag, task}, chan}
          end)
          |> expect(:continue, fn {:error_tag,
                                   {:error, {:exception, %RuntimeError{}, _stacktrace}}},
                                  chan,
                                  _arg ->
            {:result, Server.call_tool_result(text: "Caught exception"), chan}
          end)

          state = init_session(tools: [{ToolMock, :error_tool}])

          tool_call_req = %Entities.CallToolRequest{
            id: 1001,
            method: "tools/call",
            params: %Entities.CallToolRequestParams{
              name: "ErrorTool",
              arguments: %{}
            }
          }

          Suite.handle_request(tool_call_req, chan_info(), state)
          Process.sleep(:infinity)
        end)

      # The server process should have crashed
      assert_receive {:DOWN, ^spawn_ref, :process, _pid,
                      {%RuntimeError{message: "Something went wrong"}, _}}
    end

    test "tool returns error string from continue callback" do
      ref = make_ref()

      ToolMock
      |> stub(:info, fn :name, :error_continue_tool -> "ErrorContinueTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        {:async, {:error_continue_tag, ref}, chan}
      end)
      |> expect(:continue, fn {:error_continue_tag, {:ok, :some_result}}, chan, _arg ->
        {:error, "Error from continue callback", chan}
      end)

      state = init_session(tools: [{ToolMock, :error_continue_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "ErrorContinueTool",
          arguments: %{}
        }
      }

      # Initial call succeeds
      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      # Delivering a reply: should return an error
      assert {:noreply, _state} = Suite.handle_info({ref, :some_result}, state)

      # The error should be delivered to the client
      assert_receive {:"$gen_mcp", :error, error}

      # Should return HTTP 500 and RPC code -32603 (internal error)
      assert {500, %{code: -32603, message: "Error from continue callback"}} =
               check_error(error)
    end

    test "stale task reference" do
      # This test validates that if the server receives a message for a ref
      # that is no longer being tracked (already processed), it should log
      # a warning and ignore the message without calling continue/3.

      ref = make_ref()

      ToolMock
      |> stub(:info, fn :name, :stale_tool -> "StaleTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        {:async, {:stale_tag, ref}, chan}
      end)
      |> expect(:continue, 1, fn {:stale_tag, {:ok, :first_result}}, chan, _arg ->
        {:result, Server.call_tool_result(text: "First result"), chan}
      end)

      state = init_session(tools: [{ToolMock, :stale_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "StaleTool",
          arguments: %{}
        }
      }

      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      assert {:noreply, state} = Suite.handle_info({ref, :first_result}, state)

      # Assert result is delivered to client
      assert_receive {:"$gen_mcp", :result, result}

      assert %Entities.CallToolResult{content: [%Entities.TextContent{text: "First result"}]} =
               result

      # Now send a stale message with the same ref Server should ignore it and
      # NOT call continue/3 again (Mox expect count of 1 ensures continue is
      # only called once)
      #
      # This can happen if users send {ref, data} from other process instead of
      # using Tasks.
      assert {:noreply, _state} = Suite.handle_info({ref, :stale_result}, state)

      # This should log an error but we do not care in this test
    end
  end

  describe "chained async operations" do
    test "continue returns another async operation" do
      # This test validates that a tool's continue/3 can return another
      # {:async, ...} tuple, creating a chain of async operations.

      ref1 = make_ref()
      ref2 = make_ref()

      ToolMock
      |> stub(:info, fn :name, :chain_tool -> "ChainTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        {:async, {:chain_step1, ref1}, chan}
      end)
      |> expect(:continue, fn {:chain_step1, {:ok, :step1_complete}}, chan, _arg ->
        {:async, {:chain_step2, ref2}, chan}
      end)
      |> expect(:continue, fn {:chain_step2, {:ok, :step2_complete}}, chan, _arg ->
        {:result, Server.call_tool_result(text: "Chain complete"), chan}
      end)

      state = init_session(tools: [{ToolMock, :chain_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "ChainTool",
          arguments: %{}
        }
      }

      # Initial call
      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      # Some first result
      assert {:noreply, state} = Suite.handle_info({ref1, :step1_complete}, state)

      # Some some second result
      assert {:noreply, _state} = Suite.handle_info({ref2, :step2_complete}, state)

      # Assert final result is delivered to client
      assert_receive {:"$gen_mcp", :result, result}

      assert %Entities.CallToolResult{
               content: [%Entities.TextContent{text: "Chain complete"}]
             } = result
    end

    test "multiple chained async with error in chain" do
      task_sup = task_sup()

      # This test validates that when a chained async operation fails,
      # the error is properly propagated to continue/3 and the tool
      # can choose to handle it or return an error.

      ref1 = make_ref()
      test_pid = self()

      ToolMock
      |> stub(:info, fn :name, :chain_error_tool -> "ChainErrorTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        {:async, {:chain_err_step1, ref1}, chan}
      end)
      |> expect(:continue, fn {:chain_err_step1, {:ok, :step1_ok}}, chan, _arg ->
        # Second step will fail - use supervised task to prevent crashing test process
        task =
          Task.Supervisor.async_nolink(task_sup, fn ->
            send(test_pid, :step2_about_to_fail)
            exit(:step2_failure)
          end)

        {:async, {:chain_err_step2, task}, chan}
      end)
      |> expect(:continue, fn {:chain_err_step2, {:error, :step2_failure}}, chan, _arg ->
        # Tool handles the error and returns a result
        {:result, Server.call_tool_result(text: "Recovered from step2 failure"), chan}
      end)

      state = init_session(tools: [{ToolMock, :chain_error_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "ChainErrorTool",
          arguments: %{}
        }
      }

      # Initial call
      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      # Process first async result (success)
      assert {:noreply, state} = Suite.handle_info({ref1, :step1_ok}, state)

      # Second step fails
      assert_receive :step2_about_to_fail
      downmsg = assert_receive {:DOWN, _ref2, :process, _pid, :step2_failure}

      # Process error
      assert {:noreply, _state} = Suite.handle_info(downmsg, state)

      # Assert result is delivered to client (tool recovered from error)
      assert_receive {:"$gen_mcp", :result, result}

      assert %Entities.CallToolResult{
               content: [%Entities.TextContent{text: "Recovered from step2 failure"}]
             } = result
    end

    test "rapid task completion" do
      # This test validates that even if a task completes very quickly
      # (before the server finishes processing the initial call), the
      # server still handles the message correctly.

      ref = make_ref()

      ToolMock
      |> stub(:info, fn :name, :rapid_tool -> "RapidTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        # Task completes immediately
        send(self(), {ref, :instant_result})

        # And for some reason, updating the Basic state takes some time.
        Process.sleep(200)

        {:async, {:rapid_tag, ref}, chan}
      end)
      |> expect(:continue, fn {:rapid_tag, {:ok, :instant_result}}, chan, _arg ->
        {:result, Server.call_tool_result(text: "Rapid result"), chan}
      end)

      state = init_session(tools: [{ToolMock, :rapid_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "RapidTool",
          arguments: %{}
        }
      }

      # The message might already be in the mailbox before handle_request returns
      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      # Message should be available (might have been sent before handle_request returned)
      msg = assert_receive {^ref, :instant_result}, 500
      assert {:noreply, _state} = Suite.handle_info(msg, state)

      # Assert result is delivered to client
      assert_receive {:"$gen_mcp", :result, result}

      assert %Entities.CallToolResult{content: [%Entities.TextContent{text: "Rapid result"}]} =
               result
    end
  end

  describe "concurrent async operations" do
    test "multiple concurrent async operations from different tools" do
      # This test validates that the server can track multiple async
      # operations from different tools simultaneously, and route results
      # to the correct tool instance.

      ref_a = make_ref()
      ref_b = make_ref()

      ToolMock
      |> stub(:info, fn
        :name, :tool_a -> "ToolA"
        :name, :tool_b -> "ToolB"
      end)
      |> expect(:call, 2, fn
        _req, chan, :tool_a -> {:async, {:tag_a, ref_a}, chan}
        _req, chan, :tool_b -> {:async, {:tag_b, ref_b}, chan}
      end)
      |> expect(:continue, 2, fn
        {:tag_a, {:ok, :result_a}}, chan, :tool_a ->
          {:result, Server.call_tool_result(text: "Result from A"), chan}

        {:tag_b, {:ok, :result_b}}, chan, :tool_b ->
          {:result, Server.call_tool_result(text: "Result from B"), chan}
      end)

      state = init_session(tools: [{ToolMock, :tool_a}, {ToolMock, :tool_b}])

      # To validate that the correct response is sent to the correct client
      # process, each client is simulated by a process.

      test_pid = self()

      fake_client = fn ->
        send(test_pid, {self(), :cinf, chan_info()})
        assert_receive {:"$gen_mcp", :result, result}
        send(test_pid, {self(), :result, result})
      end

      client_pid_a = spawn_link(fake_client)
      {^client_pid_a, :cinf, chan_info_a} = assert_receive {_, :cinf, _}

      client_pid_b = spawn_link(fake_client)
      {^client_pid_b, :cinf, chan_info_b} = assert_receive {_, :cinf, _}

      # Delivering both requests using those channel info

      req_a = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "ToolA",
          arguments: %{}
        }
      }

      assert {:reply, :stream, state} = Suite.handle_request(req_a, chan_info_a, state)

      req_b = %Entities.CallToolRequest{
        id: 1002,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "ToolB",
          arguments: %{}
        }
      }

      assert {:reply, :stream, state} = Suite.handle_request(req_b, chan_info_b, state)

      # We should be able to handle the results in any order, so let's do B
      # before A.
      assert {:noreply, state} = Suite.handle_info({ref_b, :result_b}, state)
      assert {:noreply, _state} = Suite.handle_info({ref_a, :result_a}, state)

      # Our fake clients should relay the results and have been received the right ones

      assert_receive {^client_pid_b, :result, %{content: [%{text: "Result from B"}]}}
      assert_receive {^client_pid_a, :result, %{content: [%{text: "Result from A"}]}}
    end

    test "multiple concurrent async operations with the same tool" do
      # This test validates that the server can track multiple async operations
      # using the same tool. There should be no shared state between multiple
      # calls to the same tool.

      ToolMock
      |> stub(:info, fn :name, _ -> "SomeTool" end)
      |> expect(:call, 2, fn
        %{params: %{arguments: %{"callname" => callname}}}, chan, _ ->
          {:async, {:some_tag, Task.async(fn -> {:callname, callname} end)}, chan}
      end)
      |> expect(:continue, 2, fn
        {:some_tag, {:ok, {:callname, callname}}}, chan, _ ->
          {:result, Server.call_tool_result(text: "Result from #{callname}"), chan}
      end)

      state = init_session(tools: [{ToolMock, :tool_a}, {ToolMock, :tool_b}])

      # Call tool A
      req_a = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "SomeTool",
          arguments: %{"callname" => "A"}
        }
      }

      assert {:reply, :stream, state} =
               Suite.handle_request(req_a, chan_info(), state)

      # Call tool B
      req_b = %Entities.CallToolRequest{
        id: 1002,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "SomeTool",
          arguments: %{"callname" => "B"}
        }
      }

      assert {:reply, :stream, state} = Suite.handle_request(req_b, chan_info(), state)

      # We should be able to handle the results in any order, so let's do B
      # before A.

      msg_b = assert_receive {_, {:callname, "B"}}
      assert {:noreply, state} = Suite.handle_info(msg_b, state)

      msg_a = assert_receive {_, {:callname, "A"}}
      assert {:noreply, _state} = Suite.handle_info(msg_a, state)

      # Assert both results are delivered to client
      assert_receive {:"$gen_mcp", :result, result_b}

      assert %Entities.CallToolResult{
               content: [%Entities.TextContent{text: "Result from B"}]
             } = result_b

      assert_receive {:"$gen_mcp", :result, result_a}

      assert %Entities.CallToolResult{
               content: [%Entities.TextContent{text: "Result from A"}]
             } = result_a
    end

    @tag :skip
    # TODO we must implement monitoring http clients (via the channel?) from the
    # Basic server.
    #
    # But otherwise there is nothing much to do, the tool lifecycle should
    # continue because at some point we want to implement resumable streams, so
    # the session would store the tool result expecting a GET request (or
    # deliver it immediately if a get request is already active)
    #
    # But it's more complicated because we should tag the responses with the
    # request IDS so the client can call a GET request to resume streaming from
    # a specific message id.
    test "client disconnects during async operation" do
      # This test validates that if a client disconnects while an async
      # operation is pending, the server handles it gracefully.
      #
      # Note: The exact behavior (cancel task vs let it complete) is a
      # design decision. This test just ensures no crashes occur.

      ref = make_ref()

      ToolMock
      |> stub(:info, fn :name, :disconnect_tool -> "DisconnectTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        {:async, {:disconnect_tag, ref}, chan}
      end)

      # Don't expect continue to be called if task is cancelled
      # OR expect it to be called if task completes anyway
      # This is a design decision for the implementation

      state = init_session(tools: [{ToolMock, :disconnect_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "DisconnectTool",
          arguments: %{}
        }
      }

      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      # Simulate client disconnect (implementation-specific)
      # For now, just ensure the server doesn't crash if result arrives
      # after the client is gone

      flunk("todo implement monitor")

      # This should not crash even if client is disconnected
      assert {:noreply, _state} = Suite.handle_info({ref, :some_message}, state)

      # Note: If continue is called, result would be sent to the (possibly disconnected) client
      # The test verifies no crash occurs regardless
    end

    test "two concurrent tools return duplicate reference" do
      # This test validates that when two concurrent tool calls return the same
      # reference, the server raises an error with "duplicate" in the message.
      #
      # This prevents bugs where tools accidentally reuse a reference,
      # which would cause message routing confusion.

      ref = make_ref()

      ToolMock
      |> stub(:info, fn :name, _ -> "SomeTool" end)
      |> expect(:call, 2, fn _req, chan, _ -> {:async, {:some_tag, ref}, chan} end)

      state = init_session(tools: [{ToolMock, :tool_one}, {ToolMock, :tool_two}])

      # Call tool one
      req_one = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "SomeTool",
          arguments: %{}
        }
      }

      assert {:reply, :stream, state} =
               Suite.handle_request(req_one, chan_info(), state)

      # Call tool two - should raise error about duplicate reference
      req_two = %Entities.CallToolRequest{
        id: 1002,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "SomeTool",
          arguments: %{}
        }
      }

      # The second tool call should raise an error about duplicate reference
      assert_raise RuntimeError, ~r/duplicate/i, fn ->
        Suite.handle_request(req_two, chan_info(), state)
      end
    end
  end

  describe "assigns transmission" do
    test "assigns from initialize, tool call, and tool modifications flow through async callbacks" do
      stub(ToolMock, :info, fn
        :name, _ -> "AssignsTool"
        _, _ -> nil
      end)

      # session init

      init_assigns = %{from_initialize: true, shared_assign: "from_init"}

      state = init_session([tools: [ToolMock]], init_assigns)

      # 1st tool call

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "AssignsTool",
          arguments: {}
        }
      }

      # Call request assigns override initialize assigns
      call_assigns = %{from_call: true, shared_assign: "from_call"}

      ref1 = make_ref()
      ref2 = make_ref()

      ToolMock
      |> expect(:call, fn _req, chan, _arg ->
        assert %{
                 from_initialize: true,
                 from_call: true,
                 shared_assign: "from_call"
               } = chan.assigns

        # Tool adds its own assigns and overrides one
        chan = Channel.assign(chan, :from_call_step1, true)
        chan = Channel.assign(chan, :shared_assign, "from_tool_step1")

        {:async, {:step1, ref1}, chan}
      end)
      |> expect(:continue, 2, fn
        {:step1, {:ok, :step1_complete}}, chan, _arg ->
          # Verify all assigns from first call
          assert %{
                   from_initialize: true,
                   from_call: true,
                   from_call_step1: true,
                   shared_assign: "from_tool_step1"
                 } = chan.assigns

          # Tool adds more assigns for next step
          chan = Channel.assign(chan, :from_continue_step1, true)
          chan = Channel.assign(chan, :shared_assign, "from_continue_step1")

          {:async, {:step2, ref2}, chan}

        {:step2, {:ok, :step2_complete}}, chan, _arg ->
          # Verify all assigns including the new ones from continue
          assert %{
                   from_initialize: true,
                   from_call: true,
                   from_call_step1: true,
                   from_continue_step1: true,
                   shared_assign: "from_continue_step1"
                 } = chan.assigns

          {:result, Server.call_tool_result(text: "Assigns verified"), chan}
      end)

      # Initial call
      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(call_assigns), state)

      # Process first async result
      assert {:noreply, state} = Suite.handle_info({ref1, :step1_complete}, state)

      # Process second async result
      assert {:noreply, _state} = Suite.handle_info({ref2, :step2_complete}, state)

      # Assert final result is delivered to client
      assert_receive {:"$gen_mcp", :result,
                      %Entities.CallToolResult{
                        content: [%Entities.TextContent{text: "Assigns verified"}]
                      }}
    end
  end

  describe "behaviour contract violations" do
    test "tool returns invalid value from call/3" do
      # This test validates that when a tool violates the behaviour contract
      # by returning an invalid value from call/3, the server exits with
      # a {:bad_return_value, value} reason.

      ToolMock
      |> stub(:info, fn :name, :bad_tool -> "BadTool" end)
      |> expect(:call, fn _req, _chan, _arg ->
        # Return completely invalid value
        :invalid_return_value
      end)

      state = init_session(tools: [{ToolMock, :bad_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "BadTool",
          arguments: %{}
        }
      }

      # The tool call should exit the process with bad_return_value
      assert catch_exit(Suite.handle_request(tool_call_req, chan_info(), state)) ==
               {:bad_return_value, :invalid_return_value}
    end

    test "tool returns invalid value from continue/3" do
      # This test validates that when a tool returns a valid async tuple
      # from call/3 but then violates the contract in continue/3, the
      # server exits with a {:bad_return_value, value} reason.

      ref = make_ref()

      ToolMock
      |> stub(:info, fn :name, :bad_continue_tool -> "BadContinueTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        {:async, {:bad_continue_tag, ref}, chan}
      end)
      |> expect(:continue, fn {:bad_continue_tag, {:ok, :some_result}}, _chan, _arg ->
        # Return invalid value from continue
        {:bad_tuple, "oops"}
      end)

      state = init_session(tools: [{ToolMock, :bad_continue_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "BadContinueTool",
          arguments: %{}
        }
      }

      # Initial call succeeds
      assert {:reply, :stream, state} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      assert catch_exit(Suite.handle_info({ref, :some_result}, state)) ==
               {:bad_return_value, {:bad_tuple, "oops"}}
    end
  end
end
