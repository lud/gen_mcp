defmodule GenMcp.Server.BasicTest do
  alias GenMcp.Mcp.Entities
  alias GenMcp.Server.Basic
  alias GenMcp.Server
  alias GenMcp.Support.ToolMock
  import Mox
  use ExUnit.Case, async: true

  setup :verify_on_exit!

  @server_info [
    server_name: "Test Server",
    server_version: "0"
  ]

  defp chan_info do
    {:channel, __MODULE__, self()}
  end

  defp check_error({:error, reason}) do
    check_error(reason)
  end

  defp check_error(reason) do
    GenMcp.RpcError.cast_error(reason)
  end

  defp init_session(server_opts \\ []) do
    assert {:ok, state} = Basic.init(Keyword.merge(@server_info, server_opts))

    init_req = %Entities.InitializeRequest{
      id: "setup-init-1",
      method: "initialize",
      params: %Entities.InitializeRequestParams{
        capabilities: %{},
        clientInfo: %{name: "test", version: "1.0.0"},
        protocolVersion: "2025-06-18"
      }
    }

    assert {:reply, {:result, result}, %{status: :server_initialized} = state} =
             Basic.handle_request(init_req, chan_info(), state)

    client_init_notif = %Entities.InitializedNotification{
      method: "notifications/initialized",
      params: %{}
    }

    assert {:noreply, %{status: :client_initialized} = state} =
             Basic.handle_notification(client_init_notif, state)

    state
  end

  describe "handles initialization requests" do
    test "handles InitializeRequest" do
      {:ok, state} = Basic.init(@server_info)

      init_eq = %Entities.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %Entities.InitializeRequestParams{
          capabilities: %{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, result}, %{status: :server_initialized}} =
               Basic.handle_request(init_eq, chan_info(), state)

      assert %Entities.InitializeResult{
               capabilities: %Entities.ServerCapabilities{},
               protocolVersion: "2025-06-18"
             } = result
    end

    test "handles initialize request and reject tool call request without initialization" do
      {:ok, state} = Basic.init(@server_info)

      req = %Entities.CallToolRequest{
        id: 2,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "SomeTool",
          arguments: %{}
        }
      }

      assert {:error, :not_initialized, %{status: :starting}} =
               Basic.handle_request(req, chan_info(), state)

      check_error(:not_initialized)
    end

    test "handles initialize request and reject tool call request without initialization notification" do
      {:ok, state} = Basic.init(@server_info)

      init_req = %Entities.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %Entities.InitializeRequestParams{
          capabilities: %{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, result}, %{status: :server_initialized} = state} =
               Basic.handle_request(init_req, chan_info(), state)

      tool_call_req = %Entities.CallToolRequest{
        id: 2,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "SomeTool",
          arguments: %{}
        }
      }

      assert {:error, :not_initialized, %{status: :server_initialized}} =
               Basic.handle_request(tool_call_req, chan_info(), state)

      check_error(:not_initialized)
    end

    test "rejects initialization request when already initialized" do
      state = init_session()

      # Attempt to initialize again while already initialized
      init_req = %Entities.InitializeRequest{
        id: "setup-init-2",
        method: "initialize",
        params: %Entities.InitializeRequestParams{
          capabilities: %{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      # Should return an error with :stop tuple since we're already initialized
      assert {:stop, :already_initialized, {:error, :already_initialized} = err, _} =
               Basic.handle_request(init_req, chan_info(), state)

      check_error(err)
    end

    test "rejects initialization with invalid protocol version" do
      {:ok, state} = Basic.init(@server_info)

      init_req = %Entities.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %Entities.InitializeRequestParams{
          capabilities: %{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2024-01-01"
        }
      }

      # Should return an error with :stop tuple for invalid protocol version
      assert {:stop, reason, {:error, {:unsupported_protocol, "2024-01-01"} = reason}, _} =
               Basic.handle_request(init_req, chan_info(), state)

      check_error(reason)
    end
  end

  describe "listing tools" do
    test "example test" do
      ToolMock
      |> stub(:info, fn
        :name, :tool1 -> "Tool1"
        :title, :tool1 -> "Tool 1 title"
        :description, :tool1 -> "Tool 1 descr"
        :annotations, :tool1 -> %{title: "Tool 1 subtitle", destructiveHint: true}
        :name, :tool2 -> "Tool2"
        :title, :tool2 -> nil
        :description, :tool2 -> nil
        :annotations, :tool2 -> nil
      end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)
      |> stub(:output_schema, fn
        :tool1 -> %{type: :object}
        :tool2 -> nil
      end)

      state = init_session(tools: [{ToolMock, :tool1}, {ToolMock, :tool2}])

      assert {:reply,
              {:result,
               %GenMcp.Mcp.Entities.ListToolsResult{_meta: nil, nextCursor: nil, tools: tools}},
              _} =
               Basic.handle_request(%Entities.ListToolsRequest{}, chan_info(), state)

      assert [
               %GenMcp.Mcp.Entities.Tool{
                 name: "Tool1",
                 title: "Tool 1 title",
                 description: "Tool 1 descr",
                 annotations: %{destructiveHint: true, title: "Tool 1 subtitle"},
                 inputSchema: %{"type" => "object"},
                 outputSchema: %{"type" => "object"}
               },
               %GenMcp.Mcp.Entities.Tool{
                 inputSchema: %{"type" => "object"},
                 name: "Tool2"
               }
             ] = tools
    end
  end

  describe "calling tools" do
    test "unknown tool" do
      state = init_session()

      tool_call_req = %Entities.CallToolRequest{
        id: 2,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "SomeTool",
          arguments: %{}
        }
      }

      assert {:reply, {:error, {:unknown_tool, "SomeTool"}}, _} =
               Basic.handle_request(tool_call_req, chan_info(), state)
    end

    test "sync tool" do
      ToolMock
      |> stub(:info, fn :name, :some_tool_arg -> "ExistingTool" end)
      |> expect(:call, fn req, chan, arg ->
        # The whole request is given

        assert %GenMcp.Mcp.Entities.CallToolRequest{
                 id: 2,
                 method: "tools/call",
                 params: %GenMcp.Mcp.Entities.CallToolRequestParams{
                   _meta: nil,
                   arguments: %{"some" => "arg"},
                   name: "ExistingTool"
                 }
               } = req

        # We also receive a channel struct istead of the chan info
        assert %GenMcp.Mux.Channel{} = chan
        assert :some_tool_arg = arg
        # we can return a cast value
        {:result, Server.call_tool_result(text: "hello"), chan}
      end)

      state = init_session(tools: [{ToolMock, :some_tool_arg}])

      tool_call_req = %Entities.CallToolRequest{
        id: 2,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "ExistingTool",
          arguments: %{"some" => "arg"}
        }
      }

      assert {:reply, {:result, result}, _} =
               Basic.handle_request(tool_call_req, chan_info(), state)

      assert %GenMcp.Mcp.Entities.CallToolResult{
               _meta: nil,
               content: [%{type: :text, text: "hello"}],
               isError: nil,
               structuredContent: nil
             } = result
    end

    test "tool call argument validation returns error with rpc code" do
      ToolMock
      |> stub(:info, fn :name, :validated_tool -> "ValidatedTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        {:error, JSV.ValidationError.of([]), chan}
      end)

      state = init_session(tools: [{ToolMock, :validated_tool}])

      tool_call_req = %Entities.CallToolRequest{
        id: 4,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "ValidatedTool",
          arguments: %{"invalid" => "args"}
        }
      }

      assert {:reply, {:error, %JSV.ValidationError{}} = err, _} =
               Basic.handle_request(tool_call_req, chan_info(), state)

      check_error(err)
    end
  end
end
