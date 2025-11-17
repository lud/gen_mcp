# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMCP.SuiteTest do
  alias GenMCP.MCP
  alias GenMCP.Suite
  alias GenMCP.Support.ExtensionMock
  alias GenMCP.Support.PromptRepoMock
  alias GenMCP.Support.ResourceRepoMock
  alias GenMCP.Support.ResourceRepoMockTpl
  alias GenMCP.Support.ToolMock
  import Mox
  import GenMCP.Test.Helpers
  use ExUnit.Case, async: true

  setup :verify_on_exit!

  @server_info [
    server_name: "Test Server",
    server_version: "0"
  ]

  defp init_session(server_opts \\ [], init_assigns \\ %{}) do
    assert {:ok, state} = Suite.init("some-session-id", Keyword.merge(@server_info, server_opts))

    init_req = %MCP.InitializeRequest{
      id: "setup-init-1",
      method: "initialize",
      params: %MCP.InitializeRequestParams{
        capabilities: %MCP.ClientCapabilities{elicitation: %{"foo" => "bar"}},
        clientInfo: %{name: "test", version: "1.0.0"},
        protocolVersion: "2025-06-18"
      }
    }

    assert {:reply, {:result, _result},
            %{
              client_capabilities: %{
                __init: %MCP.ClientCapabilities{elicitation: %{"foo" => "bar"}}
              }
            } = state} = Suite.handle_request(init_req, chan_info(init_assigns), state)

    client_init_notif = %MCP.InitializedNotification{
      method: "notifications/initialized",
      params: %{}
    }

    assert {:noreply,
            %{client_capabilities: %MCP.ClientCapabilities{elicitation: %{"foo" => "bar"}}} =
              state} =
             Suite.handle_notification(client_init_notif, state)

    state
  end

  describe "server capabilities based on enabled components" do
    test "declares no capabilities when no tools, resources, or prompts configured" do
      {:ok, state} = Suite.init("some-session-id", @server_info)

      init_req = %MCP.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, result}, _state} =
               Suite.handle_request(init_req, chan_info(), state)

      assert %MCP.InitializeResult{
               capabilities: %MCP.ServerCapabilities{
                 tools: nil,
                 resources: nil,
                 prompts: nil
               }
             } = result
    end

    test "declares tools capability when at least one tool in :tools option" do
      ToolMock
      |> stub(:info, fn :name, :test_tool -> "TestTool" end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)

      {:ok, state} =
        Suite.init(
          "some-session-id",
          Keyword.merge(@server_info, tools: [{ToolMock, :test_tool}])
        )

      init_req = %MCP.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, result}, _state} =
               Suite.handle_request(init_req, chan_info(), state)

      assert %MCP.InitializeResult{
               capabilities: %MCP.ServerCapabilities{
                 tools: %{},
                 resources: nil,
                 prompts: nil
               }
             } = result
    end

    test "declares tools capability when at least one tool provided by extension" do
      ToolMock
      |> stub(:info, fn :name, :ext_tool -> "ExtTool" end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)

      ExtensionMock
      |> stub(:tools, fn _channel, :test_ext -> [{ToolMock, :ext_tool}] end)
      |> stub(:resources, fn _channel, :test_ext -> [] end)
      |> stub(:prompts, fn _channel, :test_ext -> [] end)

      {:ok, state} =
        Suite.init(
          "some-session-id",
          Keyword.merge(@server_info, extensions: [{ExtensionMock, :test_ext}])
        )

      init_req = %MCP.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, result}, _state} =
               Suite.handle_request(init_req, chan_info(), state)

      assert %MCP.InitializeResult{
               capabilities: %MCP.ServerCapabilities{
                 tools: %{},
                 resources: nil,
                 prompts: nil
               }
             } = result
    end

    test "declares resources capability when at least one resource repo in :resources option" do
      ResourceRepoMock
      |> stub(:prefix, fn :test_repo -> "file:///" end)

      {:ok, state} =
        Suite.init(
          "some-session-id",
          Keyword.merge(@server_info, resources: [{ResourceRepoMock, :test_repo}])
        )

      init_req = %MCP.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, result}, _state} =
               Suite.handle_request(init_req, chan_info(), state)

      assert %MCP.InitializeResult{
               capabilities: %MCP.ServerCapabilities{
                 tools: nil,
                 resources: %{},
                 prompts: nil
               }
             } = result
    end

    test "declares resources capability when at least one resource repo provided by extension" do
      ResourceRepoMock
      |> stub(:prefix, fn :ext_repo -> "file:///" end)

      ExtensionMock
      |> stub(:tools, fn _channel, :test_ext -> [] end)
      |> stub(:resources, fn _channel, :test_ext -> [{ResourceRepoMock, :ext_repo}] end)
      |> stub(:prompts, fn _channel, :test_ext -> [] end)

      {:ok, state} =
        Suite.init(
          "some-session-id",
          Keyword.merge(@server_info, extensions: [{ExtensionMock, :test_ext}])
        )

      init_req = %MCP.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, result}, _state} =
               Suite.handle_request(init_req, chan_info(), state)

      assert %MCP.InitializeResult{
               capabilities: %MCP.ServerCapabilities{
                 tools: nil,
                 resources: %{},
                 prompts: nil
               }
             } = result
    end

    test "declares prompts capability when at least one prompt repo in :prompts option" do
      PromptRepoMock
      |> stub(:prefix, fn :test_repo -> "test_" end)

      {:ok, state} =
        Suite.init(
          "some-session-id",
          Keyword.merge(@server_info, prompts: [{PromptRepoMock, :test_repo}])
        )

      init_req = %MCP.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, result}, _state} =
               Suite.handle_request(init_req, chan_info(), state)

      assert %MCP.InitializeResult{
               capabilities: %MCP.ServerCapabilities{
                 tools: nil,
                 resources: nil,
                 prompts: %{}
               }
             } = result
    end

    test "declares prompts capability when at least one prompt repo provided by extension" do
      PromptRepoMock
      |> stub(:prefix, fn :ext_repo -> "ext_" end)

      ExtensionMock
      |> stub(:tools, fn _channel, :test_ext -> [] end)
      |> stub(:resources, fn _channel, :test_ext -> [] end)
      |> stub(:prompts, fn _channel, :test_ext -> [{PromptRepoMock, :ext_repo}] end)

      {:ok, state} =
        Suite.init(
          "some-session-id",
          Keyword.merge(@server_info, extensions: [{ExtensionMock, :test_ext}])
        )

      init_req = %MCP.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, result}, _state} =
               Suite.handle_request(init_req, chan_info(), state)

      assert %MCP.InitializeResult{
               capabilities: %MCP.ServerCapabilities{
                 tools: nil,
                 resources: nil,
                 prompts: %{}
               }
             } = result
    end

    test "declares all capabilities when tools, resources, and prompts all configured" do
      ToolMock
      |> stub(:info, fn :name, :test_tool -> "TestTool" end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)

      ResourceRepoMock
      |> stub(:prefix, fn :test_repo -> "file:///" end)

      PromptRepoMock
      |> stub(:prefix, fn :test_prompt -> "test_" end)

      {:ok, state} =
        Suite.init(
          "some-session-id",
          Keyword.merge(@server_info,
            tools: [{ToolMock, :test_tool}],
            resources: [{ResourceRepoMock, :test_repo}],
            prompts: [{PromptRepoMock, :test_prompt}]
          )
        )

      init_req = %MCP.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, result}, _state} =
               Suite.handle_request(init_req, chan_info(), state)

      assert %MCP.InitializeResult{
               capabilities: %MCP.ServerCapabilities{
                 tools: %{},
                 resources: %{},
                 prompts: %{}
               }
             } = result
    end
  end

  describe "handles initialization requests" do
    test "handles InitializeRequest" do
      {:ok, state} = Suite.init("some-session-id", @server_info)

      init_eq = %MCP.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, result}, _state} =
               Suite.handle_request(init_eq, chan_info(), state)

      assert %MCP.InitializeResult{
               capabilities: %MCP.ServerCapabilities{},
               protocolVersion: "2025-06-18"
             } = result
    end

    test "stops the session if initialization request somehow is invalid" do
      assert {:error, _} = Suite.init("some-session-id", [])
    end

    test "handles initialize request and reject tool call request without initialization" do
      {:ok, state} = Suite.init("some-session-id", @server_info)

      req = %MCP.CallToolRequest{
        id: 2,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "SomeTool",
          arguments: %{}
        }
      }

      assert {:error, :not_initialized, _} =
               Suite.handle_request(req, chan_info(), state)

      assert {400, %{code: -32603, message: "Server not initialized"}} =
               check_error(:not_initialized)
    end

    test "handles initialize request and accepts tool call request without initialization notification" do
      # We do not require client to be ready as we do not support elicitation or
      # sampling yet

      {:ok, state} = Suite.init("some-session-id", @server_info)

      init_req = %MCP.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, _result}, state} =
               Suite.handle_request(init_req, chan_info(), state)

      tool_call_req = %MCP.CallToolRequest{
        id: 2,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "SomeTool",
          arguments: %{}
        }
      }

      assert {:reply, {:error, {:unknown_tool, "SomeTool"}}, _state} =
               Suite.handle_request(tool_call_req, chan_info(), state)
    end

    test "rejects initialization request when already initialized" do
      state = init_session()

      # Attempt to initialize again while already initialized
      init_req = %MCP.InitializeRequest{
        id: "setup-init-2",
        method: "initialize",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      # Should return an error with :stop tuple since we're already initialized
      assert {:stop, {:shutdown, {:init_failure, :already_initialized}},
              {:error, :already_initialized} = err, _} =
               Suite.handle_request(init_req, chan_info(), state)

      assert {400, %{code: -32602, message: "Session is already initialized"}} = check_error(err)
    end

    test "rejects initialization with invalid protocol version" do
      {:ok, state} = Suite.init("some-session-id", @server_info)

      init_req = %MCP.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2024-01-01"
        }
      }

      # Should return an error with :stop tuple for invalid protocol version
      assert {:stop, {:shutdown, {:init_failure, reason}},
              {:error, {:unsupported_protocol, "2024-01-01"} = reason}, _} =
               Suite.handle_request(init_req, chan_info(), state)

      assert {400,
              %{
                code: -32600,
                data: %{version: "2024-01-01", supported: ["2025-06-18"]},
                message: "Unsupported protocol version"
              }} = check_error(reason)
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
              {:result, %GenMCP.MCP.ListToolsResult{_meta: nil, nextCursor: nil, tools: tools}},
              _} =
               Suite.handle_request(%MCP.ListToolsRequest{}, chan_info(), state)

      assert [
               %GenMCP.MCP.Tool{
                 name: "Tool1",
                 title: "Tool 1 title",
                 description: "Tool 1 descr",
                 annotations: %{destructiveHint: true, title: "Tool 1 subtitle"},
                 inputSchema: %{"type" => "object"},
                 outputSchema: %{"type" => "object"}
               },
               %GenMCP.MCP.Tool{
                 inputSchema: %{"type" => "object"},
                 name: "Tool2"
               }
             ] = tools
    end
  end

  describe "calling tools" do
    test "unknown tool" do
      state = init_session()

      tool_call_req = %MCP.CallToolRequest{
        id: 2,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "SomeTool",
          arguments: %{}
        }
      }

      assert {:reply, {:error, {:unknown_tool, "SomeTool"}} = err, _} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      assert {400, %{code: -32602, data: %{tool: "SomeTool"}, message: "Unknown tool SomeTool"}} =
               check_error(err)
    end

    test "sync tool" do
      ToolMock
      |> stub(:info, fn :name, :some_tool_arg -> "ExistingTool" end)
      |> expect(:call, fn req, chan, arg ->
        # The whole request is given

        assert %GenMCP.MCP.CallToolRequest{
                 id: 2,
                 method: "tools/call",
                 params: %GenMCP.MCP.CallToolRequestParams{
                   _meta: nil,
                   arguments: %{"some" => "arg"},
                   name: "ExistingTool"
                 }
               } = req

        # We also receive a channel struct istead of the chan info
        assert %GenMCP.Mux.Channel{} = chan
        assert :some_tool_arg = arg
        # we can return a cast value
        {:result, MCP.call_tool_result(text: "hello"), chan}
      end)

      state = init_session(tools: [{ToolMock, :some_tool_arg}])

      tool_call_req = %MCP.CallToolRequest{
        id: 2,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "ExistingTool",
          arguments: %{"some" => "arg"}
        }
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      assert %GenMCP.MCP.CallToolResult{
               _meta: nil,
               content: [%MCP.TextContent{type: "text", text: "hello"}],
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

      tool_call_req = %MCP.CallToolRequest{
        id: 4,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "ValidatedTool",
          arguments: %{"invalid" => "args"}
        }
      }

      assert {:reply, {:error, %JSV.ValidationError{}} = err, _} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      assert {400,
              %{code: -32602, data: %{valid: false, details: []}, message: "Invalid Parameters"}} =
               check_error(err)
    end

    test "tool returns error string from call callback" do
      ToolMock
      |> stub(:info, fn :name, :error_tool -> "ErrorTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        {:error, "Something went wrong in the tool", chan}
      end)

      state = init_session(tools: [{ToolMock, :error_tool}])

      tool_call_req = %MCP.CallToolRequest{
        id: 5,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "ErrorTool",
          arguments: %{}
        }
      }

      assert {:reply, {:error, "Something went wrong in the tool"} = err, _} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      # Should return HTTP 500 and RPC code -32603 (internal error)
      assert {500, %{code: -32603, message: "Something went wrong in the tool"}} =
               check_error(err)
    end

    test "tool returns {:invalid_params, _} string from call callback" do
      ToolMock
      |> stub(:info, fn :name, :error_tool -> "ErrorTool" end)
      |> expect(:call, fn _req, chan, _arg ->
        {:error, {:invalid_params, :foo}, chan}
      end)

      state = init_session(tools: [{ToolMock, :error_tool}])

      tool_call_req = %MCP.CallToolRequest{
        id: 5,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "ErrorTool",
          arguments: %{}
        }
      }

      assert {:reply, {:error, {:invalid_params, :foo}} = err, _} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      assert {400, %{code: -32602, message: "Invalid Parameters"}} =
               check_error(err)
    end
  end

  describe "listing resources" do
    test "lists resources from a direct resource repository" do
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:list, fn nil, channel, :repo1 ->
        %{some_assign: "some_assign"} = channel.assigns

        {[
           %{uri: "file:///readme.txt", name: "README", description: "Project readme"},
           %{uri: "file:///config.json", name: "Config"}
         ], nil}
      end)

      init_assigns = %{some_assign: "some_assign"}
      state = init_session([resources: [{ResourceRepoMock, :repo1}]], init_assigns)

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(%MCP.ListResourcesRequest{}, chan_info(), state)

      assert %MCP.ListResourcesResult{resources: resources, nextCursor: _} = result
      assert length(resources) == 2

      assert [
               %{
                 uri: "file:///readme.txt",
                 name: "README",
                 description: "Project readme"
               },
               %{
                 uri: "file:///config.json",
                 name: "Config"
               }
             ] = resources
    end

    test "lists resources with pagination" do
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:list, fn nil, channel, :repo1 ->
        assert %{some_assign: "some_assign"} = channel.assigns

        {[%{uri: "file:///page1.txt", name: "Page 1"}], "next-token"}
      end)
      |> expect(:list, fn "next-token", channel, :repo1 ->
        assert %{some_assign: "some_assign"} = channel.assigns

        {[%{uri: "file:///page2.txt", name: "Page 2"}], nil}
      end)

      init_assigns = %{some_assign: "some_assign"}
      state = init_session([resources: [{ResourceRepoMock, :repo1}]], init_assigns)

      # First page
      assert {:reply, {:result, result1}, _} =
               Suite.handle_request(%MCP.ListResourcesRequest{}, chan_info(), state)

      assert %MCP.ListResourcesResult{
               resources: [%{name: "Page 1"}],
               nextCursor: pagination
             } = result1

      # Second page
      assert {:reply, {:result, result2}, _} =
               Suite.handle_request(
                 %MCP.ListResourcesRequest{
                   params: %MCP.ListResourcesRequestParams{cursor: pagination}
                 },
                 chan_info(),
                 state
               )

      assert %MCP.ListResourcesResult{
               resources: [%{name: "Page 2"}],
               nextCursor: nil
             } = result2
    end

    test "returns empty list when no resources available" do
      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:list, 3, fn nil, _channel, _ -> {[], nil} end)

      state =
        init_session(
          resources: [
            {ResourceRepoMock, :repo1},
            {ResourceRepoMock, :repo2},
            {ResourceRepoMock, :repo3}
          ]
        )

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(%MCP.ListResourcesRequest{}, chan_info(), state)

      assert %MCP.ListResourcesResult{resources: [], nextCursor: nil} = result
    end

    test "lists resources from multiple repositories" do
      # Global pagination over multiple repos is done on a per-repo basis,
      # so with two repos we need to make two requests to get all resources

      ResourceRepoMock
      |> stub(:prefix, fn
        :repo1 -> "file:///"
        :repo2 -> "http://localhost/"
      end)
      |> expect(:list, fn nil, _channel, :repo1 ->
        {[
           %{uri: "file:///readme.txt", name: "Local README"},
           %{uri: "file:///license.txt", name: "Local license"}
         ], nil}
      end)
      |> expect(:list, fn nil, _channel, :repo2 ->
        {[%{uri: "http://localhost/api", name: "API"}], nil}
      end)

      state =
        init_session(resources: [{ResourceRepoMock, :repo1}, {ResourceRepoMock, :repo2}])

      # First request returns repo1's resources with a cursor to continue to repo2
      assert {:reply, {:result, result1}, _} =
               Suite.handle_request(%MCP.ListResourcesRequest{}, chan_info(), state)

      assert %MCP.ListResourcesResult{resources: resources1, nextCursor: cursor} = result1
      assert length(resources1) == 2
      assert Enum.any?(resources1, &(&1.name == "Local README"))
      assert Enum.any?(resources1, &(&1.name == "Local license"))
      assert cursor != nil

      # Second request with cursor returns repo2's resources
      assert {:reply, {:result, result2}, _} =
               Suite.handle_request(
                 %MCP.ListResourcesRequest{
                   params: %MCP.ListResourcesRequestParams{cursor: cursor}
                 },
                 chan_info(),
                 state
               )

      assert %MCP.ListResourcesResult{resources: resources2, nextCursor: nil} = result2
      assert length(resources2) == 1
      assert Enum.any?(resources2, &(&1.name == "API"))
    end

    test "skips empty repositories and returns resources from first non-empty repo" do
      ResourceRepoMock
      |> stub(:prefix, fn
        :repo1 -> "file:///"
        :repo2 -> "http://localhost/"
        :repo3 -> "s3://bucket/"
      end)
      |> expect(:list, fn nil, _channel, :repo1 -> {[], nil} end)
      |> expect(:list, fn nil, _channel, :repo2 -> {[], nil} end)
      |> expect(:list, fn nil, _channel, :repo3 ->
        {[
           %{uri: "s3://bucket/file1.txt", name: "File 1"},
           %{uri: "s3://bucket/file2.txt", name: "File 2"}
         ], nil}
      end)

      state =
        init_session(
          resources: [
            {ResourceRepoMock, :repo1},
            {ResourceRepoMock, :repo2},
            {ResourceRepoMock, :repo3}
          ]
        )

      # First call should skip the empty repos and return resources from repo3
      assert {:reply, {:result, result}, _} =
               Suite.handle_request(%MCP.ListResourcesRequest{}, chan_info(), state)

      assert %MCP.ListResourcesResult{resources: resources, nextCursor: nil} = result
      assert length(resources) == 2
      assert Enum.any?(resources, &(&1.name == "File 1"))
      assert Enum.any?(resources, &(&1.name == "File 2"))
    end

    test "skips empty paginated results and continues to next repository" do
      # In this test the second repo returns a cursor, but returns empty results
      # given that cursor. The server should immediately move on to the next
      # repository on the second request.

      ResourceRepoMock
      |> stub(:prefix, fn
        :repo1 -> "file:///"
        :repo2 -> "http://localhost/"
        :repo3 -> "s3://bucket/"
      end)
      |> expect(:list, fn nil, _channel, :repo1 -> {[], nil} end)
      |> expect(:list, fn nil, _channel, :repo2 ->
        {[%{uri: "http://localhost/api", name: "API"}], "repo2-cursor"}
      end)
      |> expect(:list, fn "repo2-cursor", _channel, :repo2 -> {[], nil} end)
      |> expect(:list, fn nil, _channel, :repo3 ->
        {[%{uri: "s3://bucket/data.txt", name: "Data"}], nil}
      end)

      state =
        init_session(
          resources: [
            {ResourceRepoMock, :repo1},
            {ResourceRepoMock, :repo2},
            {ResourceRepoMock, :repo3}
          ]
        )

      # First call should skip repo1 and return repo2's resource with cursor
      assert {:reply, {:result, result1}, _} =
               Suite.handle_request(%MCP.ListResourcesRequest{}, chan_info(), state)

      assert %MCP.ListResourcesResult{
               resources: [%{name: "API"}],
               nextCursor: cursor
             } = result1

      assert cursor != nil

      # Second call should use repo2's cursor, get empty result, skip to repo3
      assert {:reply, {:result, result2}, _} =
               Suite.handle_request(
                 %MCP.ListResourcesRequest{
                   params: %MCP.ListResourcesRequestParams{cursor: cursor}
                 },
                 chan_info(),
                 state
               )

      assert %MCP.ListResourcesResult{
               resources: [%{name: "Data"}],
               nextCursor: nil
             } = result2
    end

    test "returns error when client provides invalid pagination token" do
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:list, fn nil, _channel, :repo1 ->
        {[%{uri: "file:///page1.txt", name: "Page 1"}], "valid-token"}
      end)

      state = init_session(resources: [{ResourceRepoMock, :repo1}])

      # First request succeeds and returns a valid cursor
      assert {:reply, {:result, result1}, _} =
               Suite.handle_request(%MCP.ListResourcesRequest{}, chan_info(), state)

      assert %MCP.ListResourcesResult{
               resources: [%{name: "Page 1"}],
               nextCursor: cursor
             } = result1

      assert cursor != nil

      # Client sends an invalid/tampered pagination token
      invalid_request = %MCP.ListResourcesRequest{
        params: %MCP.ListResourcesRequestParams{cursor: "invalid-token-from-client"}
      }

      assert {:reply, {:error, error}, _} =
               Suite.handle_request(invalid_request, chan_info(), state)

      # Verify it returns a proper error that can be cast to RPC error
      assert {400, %{code: -32602, message: "Invalid pagination cursor"}} = check_error(error)
    end
  end

  describe "reading resources" do
    test "reads a direct text resource" do
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:read, fn "file:///readme.txt", _channel, :repo1 ->
        {:ok,
         MCP.read_resource_result(
           uri: "file:///readme.txt",
           text: "# Welcome\n\nThis is the readme."
         )}
      end)

      state = init_session(resources: [{ResourceRepoMock, :repo1}])

      request = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{
          uri: "file:///readme.txt"
        }
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(request, chan_info(), state)

      assert %MCP.ReadResourceResult{contents: contents} = result
      assert [%MCP.TextResourceContents{uri: "file:///readme.txt", text: text}] = contents
      assert text == "# Welcome\n\nThis is the readme."
    end

    test "reads a text resource with custom MIME type" do
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:read, fn "file:///index.html", _channel, :repo1 ->
        {:ok,
         MCP.read_resource_result(
           uri: "file:///index.html",
           text: "<p>Hello</p>",
           mime_type: "text/html"
         )}
      end)

      state = init_session(resources: [{ResourceRepoMock, :repo1}])

      request = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{uri: "file:///index.html"}
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(request, chan_info(), state)

      assert %MCP.ReadResourceResult{contents: [content]} = result
      assert %MCP.TextResourceContents{mimeType: "text/html", text: "<p>Hello</p>"} = content
    end

    test "reads a blob resource" do
      blob_data = Base.encode64(<<1, 2, 3, 4, 5>>)

      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:read, fn "file:///data.bin", _channel, :repo1 ->
        {:ok,
         MCP.read_resource_result(
           uri: "file:///data.bin",
           blob: blob_data,
           mime_type: "application/octet-stream"
         )}
      end)

      state = init_session(resources: [{ResourceRepoMock, :repo1}])

      request = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{uri: "file:///data.bin"}
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(request, chan_info(), state)

      assert %MCP.ReadResourceResult{contents: [content]} = result

      assert %MCP.BlobResourceContents{
               blob: ^blob_data,
               mimeType: "application/octet-stream"
             } = content
    end

    test "returns not found error for missing resource" do
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:read, fn "file:///missing.txt", _channel, :repo1 ->
        {:error, :not_found}
      end)

      state = init_session(resources: [{ResourceRepoMock, :repo1}])

      request = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{uri: "file:///missing.txt"}
      }

      assert {:reply, {:error, {:resource_not_found, "file:///missing.txt"}} = err, _} =
               Suite.handle_request(request, chan_info(), state)

      # Check that it returns proper RPC error code -32002
      assert {400, %{code: -32002}} = check_error(err)
    end

    test "returns custom error message from repository" do
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:read, fn "file:///invalid.txt", _channel, :repo1 ->
        {:error, "Invalid file format"}
      end)

      state = init_session(resources: [{ResourceRepoMock, :repo1}])

      request = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{uri: "file:///invalid.txt"}
      }

      assert {:reply, {:error, "Invalid file format"} = err, _} =
               Suite.handle_request(request, chan_info(), state)

      assert {500, %{code: -32603, message: "Invalid file format"}} = check_error(err)
    end

    test "routes to correct repository based on URI prefix" do
      ResourceRepoMock
      |> stub(:prefix, fn
        :repo1 -> "file:///"
        :repo2 -> "http://example.com/"
      end)
      |> expect(:read, fn "http://example.com/resource", _channel, :repo2 ->
        {:ok,
         MCP.read_resource_result(
           uri: "http://example.com/resource",
           text: "Remote resource"
         )}
      end)

      state =
        init_session(resources: [{ResourceRepoMock, :repo1}, {ResourceRepoMock, :repo2}])

      request = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{uri: "http://example.com/resource"}
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(request, chan_info(), state)

      assert %MCP.ReadResourceResult{contents: [content]} = result
      assert %MCP.TextResourceContents{text: "Remote resource"} = content
    end

    test "returns error when no repository matches URI prefix" do
      stub(ResourceRepoMock, :prefix, fn :repo1 -> "file:///" end)

      state = init_session(resources: [{ResourceRepoMock, :repo1}])

      request = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{uri: "ftp://example.com/file"}
      }

      assert {:reply, {:error, {:resource_not_found, "ftp://example.com/file"}} = err, _} =
               Suite.handle_request(request, chan_info(), state)

      # Check that it returns proper RPC error code -32002
      assert {400, %{code: -32002}} = check_error(err)
    end

    test "reads resource with repository using module shorthand" do
      ResourceRepoMock
      |> stub(:prefix, fn [] -> "file:///" end)
      |> expect(:read, fn "file:///readme.txt", _channel, [] ->
        {:ok, MCP.read_resource_result(uri: "file:///readme.txt", text: "Hello")}
      end)

      # Pass module directly (will be expanded to {Module, []})
      state = init_session(resources: [ResourceRepoMock])

      request = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{uri: "file:///readme.txt"}
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(request, chan_info(), state)

      assert %MCP.ReadResourceResult{
               contents: [%MCP.TextResourceContents{text: "Hello"}]
             } =
               result
    end

    test "matches repository prefixes in declaration order, not by longest match" do
      # The repositories are declared in order: private, general, trash Routing
      # should use the first matching prefix, not the longest one.
      #
      # * An URI starting with "file:///private/..." should be matched by the
      #   repo with "file:///private/" prefix.
      # * An URI starting with "file:///trash/..." should be matched by the repo
      #   with "file:///" repo, not the trash repo.

      ResourceRepoMock
      |> stub(:prefix, fn
        :private_repo -> "file:///private/"
        :general_repo -> "file:///"
        :trash_repo -> "file:///trash/"
      end)
      # Private path should route to first repo
      |> expect(:read, fn "file:///private/secret.txt", _channel, :private_repo ->
        {:ok, MCP.read_resource_result(uri: "file:///private/secret.txt", text: "Secret")}
      end)
      # General path (without private) should route to second repo
      |> expect(:read, fn "file:///readme.txt", _channel, :general_repo ->
        {:ok, MCP.read_resource_result(uri: "file:///readme.txt", text: "General")}
      end)
      # Trash path should ALSO route to second repo (not third) because it matches first
      |> expect(:read, fn "file:///trash/deleted.txt", _channel, :general_repo ->
        {:ok, MCP.read_resource_result(uri: "file:///trash/deleted.txt", text: "Deleted")}
      end)

      state =
        init_session(
          resources: [
            {ResourceRepoMock, :private_repo},
            {ResourceRepoMock, :general_repo},
            {ResourceRepoMock, :trash_repo}
          ]
        )

      # Request 1: Private path routes to private repo
      request1 = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{uri: "file:///private/secret.txt"}
      }

      assert {:reply, {:result, result1}, _} =
               Suite.handle_request(request1, chan_info(), state)

      assert %MCP.ReadResourceResult{
               contents: [%MCP.TextResourceContents{text: "Secret"}]
             } = result1

      # Request 2: General path routes to general repo
      request2 = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{uri: "file:///readme.txt"}
      }

      assert {:reply, {:result, result2}, _} =
               Suite.handle_request(request2, chan_info(), state)

      assert %MCP.ReadResourceResult{
               contents: [%MCP.TextResourceContents{text: "General"}]
             } = result2

      # Request 3: Trash path ALSO routes to general repo (first match wins)
      request3 = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{uri: "file:///trash/deleted.txt"}
      }

      assert {:reply, {:result, result3}, _} =
               Suite.handle_request(request3, chan_info(), state)

      assert %MCP.ReadResourceResult{
               contents: [%MCP.TextResourceContents{text: "Deleted"}]
             } = result3
    end
  end

  describe "reading template-based resources" do
    test "reads template-based resource" do
      # Using a mock that skips the parse_uri callback.
      #
      # Still expecting URI template parameters as arguments to read since the
      # library must do it on its own
      ResourceRepoMockTpl
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> stub(:template, fn :repo1 ->
        %{uriTemplate: "file://{/path*}", name: "FileTemplate"}
      end)
      |> expect(:read, fn %{"path" => ["config", "app.json"]}, _channel, :repo1 ->
        {:ok,
         MCP.read_resource_result(
           uri: "file:///config/app.json",
           text: ~s({"port": 3000}),
           mime_type: "application/json"
         )}
      end)

      state = init_session(resources: [{ResourceRepoMockTpl, :repo1}])

      request = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{uri: "file:///config/app.json"}
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(request, chan_info(), state)

      assert %MCP.ReadResourceResult{contents: [content]} = result

      assert %MCP.TextResourceContents{
               text: ~s({"port": 3000}),
               mimeType: "application/json"
             } = content
    end

    test "returns error when URI does not match template pattern" do
      # Repo is badly configured, it declares a short prefix but the template
      # expects a longer prefix. The client sends an incompatible prefix.
      #
      # We do not get a resource not found error in that case.

      ResourceRepoMockTpl
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> stub(:template, fn :repo1 ->
        %{uriTemplate: "file://someprefix{/path*}", name: "FileTemplate"}
      end)

      state = init_session(resources: [{ResourceRepoMockTpl, :repo1}])

      request = %MCP.ReadResourceRequest{
        params: %MCP.ReadResourceRequestParams{uri: "file:///otherprefix"}
      }

      assert {:reply, {:error, "expected uri matching" <> _} = err, _} =
               Suite.handle_request(request, chan_info(), state)

      assert {500, %{code: -32603}} = check_error(err)
    end
  end

  describe "listing resource templates" do
    test "lists templates from repositories with templates" do
      ResourceRepoMockTpl
      |> stub(:prefix, fn
        :repo1 -> "file:///"
        :repo2 -> "http://localhost/"
      end)
      |> stub(:template, fn
        :repo1 ->
          %{
            uriTemplate: "file:///{path}",
            name: "FileTemplate",
            description: "A file resource",
            mimeType: "text/plain"
          }

        :repo2 ->
          %{
            uriTemplate: "http://localhost/api/{endpoint}",
            name: "APITemplate",
            title: "API Endpoint"
          }
      end)

      state =
        init_session(resources: [{ResourceRepoMockTpl, :repo1}, {ResourceRepoMockTpl, :repo2}])

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(
                 %MCP.ListResourceTemplatesRequest{},
                 chan_info(),
                 state
               )

      assert %MCP.ListResourceTemplatesResult{resourceTemplates: templates} = result

      assert [
               %MCP.ResourceTemplate{
                 uriTemplate: "file:///{path}",
                 name: "FileTemplate",
                 description: "A file resource",
                 mimeType: "text/plain"
               },
               %MCP.ResourceTemplate{
                 uriTemplate: "http://localhost/api/{endpoint}",
                 name: "APITemplate",
                 title: "API Endpoint"
               }
             ] = templates
    end

    test "skips repositories without templates" do
      ResourceRepoMockTpl
      |> stub(:prefix, fn :repo2 -> "http://localhost/" end)
      |> stub(:template, fn :repo2 ->
        %{uriTemplate: "http://localhost/{path}", name: "HTTPTemplate"}
      end)

      stub(ResourceRepoMock, :prefix, fn
        :repo1 -> "file:///"
        :repo3 -> "s3://bucket/"
      end)

      state =
        init_session(
          resources: [
            {ResourceRepoMock, :repo1},
            {ResourceRepoMockTpl, :repo2},
            {ResourceRepoMock, :repo3}
          ]
        )

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(
                 %MCP.ListResourceTemplatesRequest{},
                 chan_info(),
                 state
               )

      assert %MCP.ListResourceTemplatesResult{resourceTemplates: templates} = result

      assert [
               %MCP.ResourceTemplate{
                 uriTemplate: "http://localhost/{path}",
                 name: "HTTPTemplate"
               }
             ] = templates
    end

    test "returns empty list when no templates available" do
      stub(ResourceRepoMock, :prefix, fn _ -> "file:///" end)

      state =
        init_session(
          resources: [
            {ResourceRepoMock, :repo1},
            {ResourceRepoMock, :repo2}
          ]
        )

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(
                 %MCP.ListResourceTemplatesRequest{},
                 chan_info(),
                 state
               )

      assert %MCP.ListResourceTemplatesResult{resourceTemplates: []} = result
    end
  end

  describe "listing prompts" do
    test "lists prompts from single repository" do
      prompts = [
        %{name: "greeting", description: "Say hello"},
        %{
          name: "analysis",
          description: "Analyze data",
          arguments: [
            %{name: "dataset", required: true}
          ]
        }
      ]

      PromptRepoMock
      |> expect(:prefix, fn :arg -> "some_prefix" end)
      |> expect(:list, fn nil, channel, :arg ->
        %{some_assign: "some_assign"} = channel.assigns

        {prompts, nil}
      end)

      init_assigns = %{some_assign: "some_assign"}
      state = init_session([prompts: [{PromptRepoMock, :arg}]], init_assigns)

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(
                 %MCP.ListPromptsRequest{},
                 chan_info(),
                 state
               )

      assert %MCP.ListPromptsResult{
               prompts: ^prompts,
               nextCursor: nil
             } = result
    end

    test "lists prompts with pagination from single repository" do
      page1 = [%{name: "prompt1"}, %{name: "prompt2"}]
      page2 = [%{name: "prompt3"}]

      PromptRepoMock
      |> expect(:prefix, fn :repo1 -> "some_prefix" end)
      |> expect(:list, fn nil, channel, :repo1 ->
        %{some_assign: "some_assign"} = channel.assigns

        {page1, "repo_cursor_2"}
      end)
      |> expect(:list, fn "repo_cursor_2", channel, :repo1 ->
        %{some_assign: "some_assign"} = channel.assigns

        {page2, nil}
      end)

      init_assigns = %{some_assign: "some_assign"}
      state = init_session([prompts: [{PromptRepoMock, :repo1}]], init_assigns)

      # First page
      assert {:reply, {:result, result1}, _} =
               Suite.handle_request(
                 %MCP.ListPromptsRequest{},
                 chan_info(),
                 state
               )

      assert %MCP.ListPromptsResult{
               prompts: ^page1,
               nextCursor: cursor1
             } = result1

      assert is_binary(cursor1)

      # Second page
      assert {:reply, {:result, result2}, _} =
               Suite.handle_request(
                 %MCP.ListPromptsRequest{params: %{cursor: cursor1}},
                 chan_info(),
                 state
               )

      assert %MCP.ListPromptsResult{
               prompts: ^page2,
               nextCursor: nil
             } = result2
    end

    test "lists prompts across multiple repositories" do
      PromptRepoMock
      |> expect(:prefix, 3, fn
        :repo1 -> "prompt1"
        :repo2 -> "prompt2"
        :repo3 -> "prompt3"
      end)
      |> expect(:list, fn nil, _channel, :repo1 -> {[%{name: "prompt1"}], nil} end)
      |> expect(:list, fn nil, _channel, :repo2 -> {[%{name: "prompt2"}], nil} end)
      |> expect(:list, fn nil, _channel, :repo3 -> {[%{name: "prompt3"}], nil} end)

      state =
        init_session(
          prompts: [
            {PromptRepoMock, :repo1},
            {PromptRepoMock, :repo2},
            {PromptRepoMock, :repo3}
          ]
        )

      # First request
      assert {:reply, {:result, result1}, _} =
               Suite.handle_request(
                 %MCP.ListPromptsRequest{},
                 chan_info(),
                 state
               )

      assert %MCP.ListPromptsResult{
               prompts: [%{name: "prompt1"}],
               nextCursor: cursor1
             } = result1

      # Second request
      assert {:reply, {:result, result2}, _} =
               Suite.handle_request(
                 %MCP.ListPromptsRequest{params: %{cursor: cursor1}},
                 chan_info(),
                 state
               )

      assert %MCP.ListPromptsResult{
               prompts: [%{name: "prompt2"}],
               nextCursor: cursor2
             } = result2

      # Third request
      assert {:reply, {:result, result3}, _} =
               Suite.handle_request(
                 %MCP.ListPromptsRequest{params: %{cursor: cursor2}},
                 chan_info(),
                 state
               )

      assert %MCP.ListPromptsResult{
               prompts: [%{name: "prompt3"}],
               nextCursor: nil
             } = result3
    end

    test "handles invalid pagination token" do
      expect(PromptRepoMock, :prefix, fn :repo1 -> "some_prefix" end)

      state = init_session(prompts: [{PromptRepoMock, :repo1}])

      assert {:reply, {:error, :invalid_cursor}, _} =
               Suite.handle_request(
                 %MCP.ListPromptsRequest{params: %{cursor: "invalid_token"}},
                 chan_info(),
                 state
               )

      assert {400, %{code: -32602, message: "Invalid pagination cursor"}} =
               check_error(:invalid_cursor)
    end

    test "returns empty list when no prompts configured" do
      state = init_session(prompts: [])

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(
                 %MCP.ListPromptsRequest{},
                 chan_info(),
                 state
               )

      assert %MCP.ListPromptsResult{
               prompts: [],
               nextCursor: nil
             } = result
    end
  end

  describe "getting prompts" do
    test "gets prompt without arguments" do
      result = %MCP.GetPromptResult{
        description: "A greeting",
        messages: [
          %MCP.PromptMessage{
            role: :user,
            content: %MCP.TextContent{type: :text, text: "Hello!"}
          }
        ]
      }

      PromptRepoMock
      |> expect(:prefix, fn :repo1 -> "gre" end)
      |> expect(:get, fn "greeting", args, _channel, :repo1 ->
        assert(args == %{})
        {:ok, result}
      end)

      state = init_session(prompts: [{PromptRepoMock, :repo1}])

      assert {:reply, {:result, ^result}, _} =
               Suite.handle_request(
                 %MCP.GetPromptRequest{
                   params: %{name: "greeting"}
                 },
                 chan_info(),
                 state
               )
    end

    test "gets prompt with valid arguments" do
      result = %MCP.GetPromptResult{
        messages: [
          %MCP.PromptMessage{
            role: :user,
            content: %MCP.TextContent{type: :text, text: "Analyze: test.csv"}
          }
        ]
      }

      PromptRepoMock
      |> expect(:prefix, fn :repo1 -> "an" end)
      |> expect(:get, fn "analysis", args, _channel, :repo1 ->
        assert(args == %{"dataset" => "test.csv"})
        {:ok, result}
      end)

      state = init_session(prompts: [{PromptRepoMock, :repo1}])

      assert {:reply, {:result, ^result}, _} =
               Suite.handle_request(
                 %MCP.GetPromptRequest{
                   params: %{
                     name: "analysis",
                     arguments: %{"dataset" => "test.csv"}
                   }
                 },
                 chan_info(),
                 state
               )
    end

    test "returns error for non-existent prompt" do
      PromptRepoMock
      |> expect(:prefix, fn :repo1 -> "unknown" end)
      |> expect(:get, fn "unknown", _, _channel, :repo1 -> {:error, :not_found} end)

      state = init_session(prompts: [{PromptRepoMock, :repo1}])

      assert {:reply, {:error, {:prompt_not_found, "unknown"}}, _} =
               Suite.handle_request(
                 %MCP.GetPromptRequest{
                   params: %{name: "unknown"}
                 },
                 chan_info(),
                 state
               )

      assert {400,
              %{code: -32602, data: %{name: "unknown"}, message: "Prompt not found: unknown"}} =
               check_error({:prompt_not_found, "unknown"})
    end

    test "returns error for validation failure" do
      PromptRepoMock
      |> expect(:prefix, fn :repo1 -> "analysis" end)
      |> expect(:get, fn "analysis", _, _channel, :repo1 ->
        {:error, "Missing required argument: dataset"}
      end)

      state = init_session(prompts: [{PromptRepoMock, :repo1}])

      assert {:reply, {:error, "Missing required argument: dataset"}, _} =
               Suite.handle_request(
                 %MCP.GetPromptRequest{
                   params: %{name: "analysis"}
                 },
                 chan_info(),
                 state
               )

      assert {500, %{code: -32603}} = check_error("Missing required argument: dataset")
    end

    test "returns :invalid_params from call" do
      PromptRepoMock
      |> expect(:prefix, fn :repo1 -> "analysis" end)
      |> expect(:get, fn "analysis", _, _channel, :repo1 ->
        {:error, {:invalid_params, :foo}}
      end)

      state = init_session(prompts: [{PromptRepoMock, :repo1}])

      assert {:reply, {:error, {:invalid_params, :foo}}, _} =
               Suite.handle_request(
                 %MCP.GetPromptRequest{
                   params: %{name: "analysis"}
                 },
                 chan_info(),
                 state
               )

      assert {500, %{code: -32603}} = check_error("Missing required argument: dataset")
    end

    test "searches across multiple repos" do
      result = %MCP.GetPromptResult{
        messages: []
      }

      PromptRepoMock
      |> expect(:prefix, 2, fn
        :repo1 -> "prompt1"
        :repo2 -> "prompt2"
      end)
      |> expect(:get, fn "prompt2", _, _channel, :repo2 -> {:ok, result} end)

      state =
        init_session(
          prompts: [
            {PromptRepoMock, :repo1},
            {PromptRepoMock, :repo2}
          ]
        )

      assert {:reply, {:result, ^result}, _} =
               Suite.handle_request(
                 %MCP.GetPromptRequest{
                   params: %{name: "prompt2"}
                 },
                 chan_info(),
                 state
               )
    end
  end

  describe "cancelled notification handling" do
    # For now it is ignored, but can be delivered without crashing the repo
    test "handles cancelled notification without error" do
      state = init_session()

      cancelled_notif = %MCP.CancelledNotification{
        method: "notifications/cancelled",
        params: %MCP.CancelledNotificationParams{
          requestId: "some-request-id",
          reason: "User cancelled the operation"
        }
      }

      # Should return :noreply and not raise an error
      assert {:noreply, ^state} = Suite.handle_notification(cancelled_notif, state)
    end

    test "handles roots list changed notification without error" do
      state = init_session()

      roots_changed_notif = %MCP.RootsListChangedNotification{
        method: "notifications/roots/list_changed",
        params: %{_meta: %{}}
      }

      # Should return :noreply and not raise an error
      assert {:noreply, ^state} = Suite.handle_notification(roots_changed_notif, state)
    end
  end

  describe "extension ordering" do
    test "lists tools with direct tool first, then extension tools in order" do
      ToolMock
      |> stub(:info, fn
        #
        :name, :direct_tool -> "DirectTool"
        :description, :direct_tool -> "A direct tool"
        :title, :direct_tool -> nil
        :annotations, :direct_tool -> nil
        #
        :name, :ext1_tool -> "Ext1Tool"
        :description, :ext1_tool -> "Tool from extension 1"
        :title, :ext1_tool -> nil
        :annotations, :ext1_tool -> nil
        #
        :name, :ext2_tool -> "Ext2Tool"
        :description, :ext2_tool -> "Tool from extension 2"
        :title, :ext2_tool -> nil
        :annotations, :ext2_tool -> nil
      end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)
      |> stub(:output_schema, fn _ -> nil end)

      ExtensionMock
      |> stub(:tools, fn
        _channel, :ext1 -> [{ToolMock, :ext1_tool}]
        _channel, :ext2 -> [{ToolMock, :ext2_tool}]
      end)
      |> stub(:resources, fn _channel, _ -> [] end)
      |> stub(:prompts, fn _channel, _ -> [] end)

      state =
        init_session(
          tools: [{ToolMock, :direct_tool}],
          extensions: [{ExtensionMock, :ext1}, {ExtensionMock, :ext2}]
        )

      assert {:reply, {:result, %MCP.ListToolsResult{tools: tools}}, _} =
               Suite.handle_request(
                 %MCP.ListToolsRequest{},
                 chan_info(),
                 state
               )

      # Tool order is respected, self extension is first

      assert [
               %{name: "DirectTool"},
               %{name: "Ext1Tool"},
               %{name: "Ext2Tool"}
             ] = tools
    end

    test "lists resources with direct repo first, then extension repos in order with pagination" do
      ResourceRepoMock
      |> stub(:prefix, fn
        :direct_repo -> "file:///"
        :ext1_repo1 -> "http://ext1-1/"
        :ext1_repo2 -> "http://ext1-2/"
        :ext2_repo -> "http://ext2/"
      end)
      |> expect(:list, fn nil, _channel, :direct_repo ->
        {[%{uri: "file:///direct.txt", name: "Direct Resource"}], nil}
      end)
      |> expect(:list, fn nil, _channel, :ext1_repo1 ->
        {[%{uri: "http://ext1-1/resource1.txt", name: "Ext1 Repo1 Resource 1"}], :go_page_2}
      end)
      |> expect(:list, fn :go_page_2, _channel, :ext1_repo1 ->
        {[
           %{uri: "http://ext1-1/resource2.txt", name: "Ext1 Repo1 Resource 2"},
           %{uri: "http://ext1-1/resource3.txt", name: "Ext1 Repo1 Resource 3"}
         ], nil}
      end)
      |> expect(:list, fn nil, _channel, :ext1_repo2 ->
        {[%{uri: "http://ext1-2/resource.txt", name: "Ext1 Repo2 Resource"}], nil}
      end)
      |> expect(:list, fn nil, _channel, :ext2_repo ->
        {[%{uri: "http://ext2/resource.txt", name: "Ext2 Resource"}], nil}
      end)

      ExtensionMock
      |> stub(:tools, fn _channel, _ -> [] end)
      |> stub(:resources, fn
        _channel, :ext1 -> [{ResourceRepoMock, :ext1_repo1}, {ResourceRepoMock, :ext1_repo2}]
        _channel, :ext2 -> [{ResourceRepoMock, :ext2_repo}]
      end)
      |> stub(:prompts, fn _channel, _ -> [] end)

      state =
        init_session(
          resources: [{ResourceRepoMock, :direct_repo}],
          extensions: [{ExtensionMock, :ext1}, {ExtensionMock, :ext2}]
        )

      # fetch all pages
      req = fn cursor ->
        %MCP.ListResourcesRequest{params: %MCP.ListResourcesRequestParams{cursor: cursor}}
      end

      assert {:reply, {:result, %{resources: page1, nextCursor: cursor}}, state} =
               Suite.handle_request(req.(nil), chan_info(), state)

      assert {:reply, {:result, %{resources: page2, nextCursor: cursor}}, state} =
               Suite.handle_request(req.(cursor), chan_info(), state)

      assert {:reply, {:result, %{resources: page3, nextCursor: cursor}}, state} =
               Suite.handle_request(req.(cursor), chan_info(), state)

      assert {:reply, {:result, %{resources: page4, nextCursor: cursor}}, state} =
               Suite.handle_request(req.(cursor), chan_info(), state)

      assert {:reply, {:result, %{resources: page5, nextCursor: _cursor}}, _state} =
               Suite.handle_request(req.(cursor), chan_info(), state)

      # should be in order. Actually we already know it because mocks
      # expectations are ordered.

      assert [%{name: "Direct Resource", uri: "file:///direct.txt"}] = page1
      assert [%{name: "Ext1 Repo1 Resource 1", uri: "http://ext1-1/resource1.txt"}] = page2

      assert [
               %{name: "Ext1 Repo1 Resource 2", uri: "http://ext1-1/resource2.txt"},
               %{name: "Ext1 Repo1 Resource 3", uri: "http://ext1-1/resource3.txt"}
             ] = page3

      assert [%{name: "Ext1 Repo2 Resource", uri: "http://ext1-2/resource.txt"}] = page4
      assert [%{name: "Ext2 Resource", uri: "http://ext2/resource.txt"}] = page5
    end

    test "lists prompts with direct repo first, then extension repos in order with pagination" do
      PromptRepoMock
      |> stub(:prefix, fn
        :direct_repo -> "direct_"
        :ext1_repo1 -> "ext1_1_"
        :ext1_repo2 -> "ext1_2_"
        :ext2_repo -> "ext2_"
      end)
      |> expect(:list, fn nil, _channel, :direct_repo ->
        {[%{name: "direct_prompt", description: "Direct Prompt"}], nil}
      end)
      |> expect(:list, fn nil, _channel, :ext1_repo1 ->
        {[%{name: "ext1_1_prompt_1", description: "Ext1 Repo1 Prompt 1"}], :go_page_2}
      end)
      |> expect(:list, fn :go_page_2, _channel, :ext1_repo1 ->
        {[
           %{name: "ext1_1_prompt_2", description: "Ext1 Repo1 Prompt 2"},
           %{name: "ext1_1_prompt_3", description: "Ext1 Repo1 Prompt 3"}
         ], nil}
      end)
      |> expect(:list, fn nil, _channel, :ext1_repo2 ->
        {[%{name: "ext1_2_prompt", description: "Ext1 Repo2 Prompt"}], nil}
      end)
      |> expect(:list, fn nil, _channel, :ext2_repo ->
        {[%{name: "ext2_prompt", description: "Ext2 Prompt"}], nil}
      end)

      ExtensionMock
      |> stub(:tools, fn _channel, _ -> [] end)
      |> stub(:resources, fn _channel, _ -> [] end)
      |> stub(:prompts, fn
        _channel, :ext1 -> [{PromptRepoMock, :ext1_repo1}, {PromptRepoMock, :ext1_repo2}]
        _channel, :ext2 -> [{PromptRepoMock, :ext2_repo}]
      end)

      state =
        init_session(
          prompts: [{PromptRepoMock, :direct_repo}],
          extensions: [{ExtensionMock, :ext1}, {ExtensionMock, :ext2}]
        )

      # fetch all pages
      req = fn cursor ->
        %MCP.ListPromptsRequest{params: %MCP.ListPromptsRequestParams{cursor: cursor}}
      end

      assert {:reply, {:result, %{prompts: page1, nextCursor: cursor}}, state} =
               Suite.handle_request(req.(nil), chan_info(), state)

      assert {:reply, {:result, %{prompts: page2, nextCursor: cursor}}, state} =
               Suite.handle_request(req.(cursor), chan_info(), state)

      assert {:reply, {:result, %{prompts: page3, nextCursor: cursor}}, state} =
               Suite.handle_request(req.(cursor), chan_info(), state)

      assert {:reply, {:result, %{prompts: page4, nextCursor: cursor}}, state} =
               Suite.handle_request(req.(cursor), chan_info(), state)

      assert {:reply, {:result, %{prompts: page5, nextCursor: _cursor}}, _state} =
               Suite.handle_request(req.(cursor), chan_info(), state)

      # should be in order. Actually we already know it because mocks
      # expectations are ordered.

      assert [%{name: "direct_prompt", description: "Direct Prompt"}] = page1
      assert [%{name: "ext1_1_prompt_1", description: "Ext1 Repo1 Prompt 1"}] = page2

      assert [
               %{name: "ext1_1_prompt_2", description: "Ext1 Repo1 Prompt 2"},
               %{name: "ext1_1_prompt_3", description: "Ext1 Repo1 Prompt 3"}
             ] = page3

      assert [%{name: "ext1_2_prompt", description: "Ext1 Repo2 Prompt"}] = page4
      assert [%{name: "ext2_prompt", description: "Ext2 Prompt"}] = page5
    end
  end
end
