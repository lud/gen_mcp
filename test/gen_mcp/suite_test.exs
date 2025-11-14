# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMCP.SuiteTest do
  alias GenMCP.Entities
  alias GenMCP.Server
  alias GenMCP.Suite
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

  IO.warn("""
  @todo we should test that capabilities for tools/resources/prompts are only
  defined when there is at least one tool/repo
  """)

  defp init_session(server_opts \\ [], init_assigns \\ %{}) do
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

  describe "handles initialization requests" do
    test "handles InitializeRequest" do
      {:ok, state} = Suite.init("some-session-id", @server_info)

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
               Suite.handle_request(init_eq, chan_info(), state)

      assert %Entities.InitializeResult{
               capabilities: %Entities.ServerCapabilities{},
               protocolVersion: "2025-06-18"
             } = result
    end

    test "handles initialize request and reject tool call request without initialization" do
      {:ok, state} = Suite.init("some-session-id", @server_info)

      req = %Entities.CallToolRequest{
        id: 2,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "SomeTool",
          arguments: %{}
        }
      }

      assert {:error, :not_initialized, %{status: :starting}} =
               Suite.handle_request(req, chan_info(), state)

      assert {400, %{code: -32603, message: "Server not initialized"}} =
               check_error(:not_initialized)
    end

    test "handles initialize request and reject tool call request without initialization notification" do
      {:ok, state} = Suite.init("some-session-id", @server_info)

      init_req = %Entities.InitializeRequest{
        id: 1,
        method: "initialize",
        params: %Entities.InitializeRequestParams{
          capabilities: %{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:reply, {:result, _result}, %{status: :server_initialized} = state} =
               Suite.handle_request(init_req, chan_info(), state)

      tool_call_req = %Entities.CallToolRequest{
        id: 2,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
          name: "SomeTool",
          arguments: %{}
        }
      }

      assert {:error, :not_initialized, %{status: :server_initialized}} =
               Suite.handle_request(tool_call_req, chan_info(), state)

      assert {400, %{code: -32603, message: "Server not initialized"}} =
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
               Suite.handle_request(init_req, chan_info(), state)

      assert {400, %{code: -32602, message: "Session is already initialized"}} = check_error(err)
    end

    test "rejects initialization with invalid protocol version" do
      {:ok, state} = Suite.init("some-session-id", @server_info)

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
              {:result,
               %GenMCP.Entities.ListToolsResult{_meta: nil, nextCursor: nil, tools: tools}}, _} =
               Suite.handle_request(%Entities.ListToolsRequest{}, chan_info(), state)

      assert [
               %GenMCP.Entities.Tool{
                 name: "Tool1",
                 title: "Tool 1 title",
                 description: "Tool 1 descr",
                 annotations: %{destructiveHint: true, title: "Tool 1 subtitle"},
                 inputSchema: %{"type" => "object"},
                 outputSchema: %{"type" => "object"}
               },
               %GenMCP.Entities.Tool{
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

        assert %GenMCP.Entities.CallToolRequest{
                 id: 2,
                 method: "tools/call",
                 params: %GenMCP.Entities.CallToolRequestParams{
                   _meta: nil,
                   arguments: %{"some" => "arg"},
                   name: "ExistingTool"
                 }
               } = req

        # We also receive a channel struct istead of the chan info
        assert %GenMCP.Mux.Channel{} = chan
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
               Suite.handle_request(tool_call_req, chan_info(), state)

      assert %GenMCP.Entities.CallToolResult{
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

      tool_call_req = %Entities.CallToolRequest{
        id: 5,
        method: "tools/call",
        params: %Entities.CallToolRequestParams{
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
               Suite.handle_request(%Entities.ListResourcesRequest{}, chan_info(), state)

      assert %Entities.ListResourcesResult{resources: resources, nextCursor: _} = result
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
               Suite.handle_request(%Entities.ListResourcesRequest{}, chan_info(), state)

      assert %Entities.ListResourcesResult{
               resources: [%{name: "Page 1"}],
               nextCursor: pagination
             } = result1

      # Second page
      assert {:reply, {:result, result2}, _} =
               Suite.handle_request(
                 %Entities.ListResourcesRequest{
                   params: %Entities.ListResourcesRequestParams{cursor: pagination}
                 },
                 chan_info(),
                 state
               )

      assert %Entities.ListResourcesResult{
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
               Suite.handle_request(%Entities.ListResourcesRequest{}, chan_info(), state)

      assert %Entities.ListResourcesResult{resources: [], nextCursor: nil} = result
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
               Suite.handle_request(%Entities.ListResourcesRequest{}, chan_info(), state)

      assert %Entities.ListResourcesResult{resources: resources1, nextCursor: cursor} = result1
      assert length(resources1) == 2
      assert Enum.any?(resources1, &(&1.name == "Local README"))
      assert Enum.any?(resources1, &(&1.name == "Local license"))
      assert cursor != nil

      # Second request with cursor returns repo2's resources
      assert {:reply, {:result, result2}, _} =
               Suite.handle_request(
                 %Entities.ListResourcesRequest{
                   params: %Entities.ListResourcesRequestParams{cursor: cursor}
                 },
                 chan_info(),
                 state
               )

      assert %Entities.ListResourcesResult{resources: resources2, nextCursor: nil} = result2
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
               Suite.handle_request(%Entities.ListResourcesRequest{}, chan_info(), state)

      assert %Entities.ListResourcesResult{resources: resources, nextCursor: nil} = result
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
               Suite.handle_request(%Entities.ListResourcesRequest{}, chan_info(), state)

      assert %Entities.ListResourcesResult{
               resources: [%{name: "API"}],
               nextCursor: cursor
             } = result1

      assert cursor != nil

      # Second call should use repo2's cursor, get empty result, skip to repo3
      assert {:reply, {:result, result2}, _} =
               Suite.handle_request(
                 %Entities.ListResourcesRequest{
                   params: %Entities.ListResourcesRequestParams{cursor: cursor}
                 },
                 chan_info(),
                 state
               )

      assert %Entities.ListResourcesResult{
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
               Suite.handle_request(%Entities.ListResourcesRequest{}, chan_info(), state)

      assert %Entities.ListResourcesResult{
               resources: [%{name: "Page 1"}],
               nextCursor: cursor
             } = result1

      assert cursor != nil

      # Client sends an invalid/tampered pagination token
      invalid_request = %Entities.ListResourcesRequest{
        params: %Entities.ListResourcesRequestParams{cursor: "invalid-token-from-client"}
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
         Server.read_resource_result(
           uri: "file:///readme.txt",
           text: "# Welcome\n\nThis is the readme."
         )}
      end)

      state = init_session(resources: [{ResourceRepoMock, :repo1}])

      request = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{
          uri: "file:///readme.txt"
        }
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(request, chan_info(), state)

      assert %Entities.ReadResourceResult{contents: contents} = result
      assert [%Entities.TextResourceContents{uri: "file:///readme.txt", text: text}] = contents
      assert text == "# Welcome\n\nThis is the readme."
    end

    test "reads a text resource with custom MIME type" do
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:read, fn "file:///index.html", _channel, :repo1 ->
        {:ok,
         Server.read_resource_result(
           uri: "file:///index.html",
           text: "<p>Hello</p>",
           mime_type: "text/html"
         )}
      end)

      state = init_session(resources: [{ResourceRepoMock, :repo1}])

      request = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{uri: "file:///index.html"}
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(request, chan_info(), state)

      assert %Entities.ReadResourceResult{contents: [content]} = result
      assert %Entities.TextResourceContents{mimeType: "text/html", text: "<p>Hello</p>"} = content
    end

    test "reads a blob resource" do
      blob_data = Base.encode64(<<1, 2, 3, 4, 5>>)

      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:read, fn "file:///data.bin", _channel, :repo1 ->
        {:ok,
         Server.read_resource_result(
           uri: "file:///data.bin",
           blob: blob_data,
           mime_type: "application/octet-stream"
         )}
      end)

      state = init_session(resources: [{ResourceRepoMock, :repo1}])

      request = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{uri: "file:///data.bin"}
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(request, chan_info(), state)

      assert %Entities.ReadResourceResult{contents: [content]} = result

      assert %Entities.BlobResourceContents{
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

      request = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{uri: "file:///missing.txt"}
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

      request = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{uri: "file:///invalid.txt"}
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
         Server.read_resource_result(
           uri: "http://example.com/resource",
           text: "Remote resource"
         )}
      end)

      state =
        init_session(resources: [{ResourceRepoMock, :repo1}, {ResourceRepoMock, :repo2}])

      request = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{uri: "http://example.com/resource"}
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(request, chan_info(), state)

      assert %Entities.ReadResourceResult{contents: [content]} = result
      assert %Entities.TextResourceContents{text: "Remote resource"} = content
    end

    test "returns error when no repository matches URI prefix" do
      stub(ResourceRepoMock, :prefix, fn :repo1 -> "file:///" end)

      state = init_session(resources: [{ResourceRepoMock, :repo1}])

      request = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{uri: "ftp://example.com/file"}
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
        {:ok, Server.read_resource_result(uri: "file:///readme.txt", text: "Hello")}
      end)

      # Pass module directly (will be expanded to {Module, []})
      state = init_session(resources: [ResourceRepoMock])

      request = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{uri: "file:///readme.txt"}
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(request, chan_info(), state)

      assert %Entities.ReadResourceResult{
               contents: [%Entities.TextResourceContents{text: "Hello"}]
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
        {:ok, Server.read_resource_result(uri: "file:///private/secret.txt", text: "Secret")}
      end)
      # General path (without private) should route to second repo
      |> expect(:read, fn "file:///readme.txt", _channel, :general_repo ->
        {:ok, Server.read_resource_result(uri: "file:///readme.txt", text: "General")}
      end)
      # Trash path should ALSO route to second repo (not third) because it matches first
      |> expect(:read, fn "file:///trash/deleted.txt", _channel, :general_repo ->
        {:ok, Server.read_resource_result(uri: "file:///trash/deleted.txt", text: "Deleted")}
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
      request1 = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{uri: "file:///private/secret.txt"}
      }

      assert {:reply, {:result, result1}, _} =
               Suite.handle_request(request1, chan_info(), state)

      assert %Entities.ReadResourceResult{
               contents: [%Entities.TextResourceContents{text: "Secret"}]
             } = result1

      # Request 2: General path routes to general repo
      request2 = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{uri: "file:///readme.txt"}
      }

      assert {:reply, {:result, result2}, _} =
               Suite.handle_request(request2, chan_info(), state)

      assert %Entities.ReadResourceResult{
               contents: [%Entities.TextResourceContents{text: "General"}]
             } = result2

      # Request 3: Trash path ALSO routes to general repo (first match wins)
      request3 = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{uri: "file:///trash/deleted.txt"}
      }

      assert {:reply, {:result, result3}, _} =
               Suite.handle_request(request3, chan_info(), state)

      assert %Entities.ReadResourceResult{
               contents: [%Entities.TextResourceContents{text: "Deleted"}]
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
         Server.read_resource_result(
           uri: "file:///config/app.json",
           text: ~s({"port": 3000}),
           mime_type: "application/json"
         )}
      end)

      state = init_session(resources: [{ResourceRepoMockTpl, :repo1}])

      request = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{uri: "file:///config/app.json"}
      }

      assert {:reply, {:result, result}, _} =
               Suite.handle_request(request, chan_info(), state)

      assert %Entities.ReadResourceResult{contents: [content]} = result

      assert %Entities.TextResourceContents{
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

      request = %Entities.ReadResourceRequest{
        params: %Entities.ReadResourceRequestParams{uri: "file:///otherprefix"}
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
                 %Entities.ListResourceTemplatesRequest{},
                 chan_info(),
                 state
               )

      assert %Entities.ListResourceTemplatesResult{resourceTemplates: templates} = result

      assert [
               %Entities.ResourceTemplate{
                 uriTemplate: "file:///{path}",
                 name: "FileTemplate",
                 description: "A file resource",
                 mimeType: "text/plain"
               },
               %Entities.ResourceTemplate{
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
                 %Entities.ListResourceTemplatesRequest{},
                 chan_info(),
                 state
               )

      assert %Entities.ListResourceTemplatesResult{resourceTemplates: templates} = result

      assert [
               %Entities.ResourceTemplate{
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
                 %Entities.ListResourceTemplatesRequest{},
                 chan_info(),
                 state
               )

      assert %Entities.ListResourceTemplatesResult{resourceTemplates: []} = result
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
                 %Entities.ListPromptsRequest{},
                 chan_info(),
                 state
               )

      assert %Entities.ListPromptsResult{
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
                 %Entities.ListPromptsRequest{},
                 chan_info(),
                 state
               )

      assert %Entities.ListPromptsResult{
               prompts: ^page1,
               nextCursor: cursor1
             } = result1

      assert is_binary(cursor1)

      # Second page
      assert {:reply, {:result, result2}, _} =
               Suite.handle_request(
                 %Entities.ListPromptsRequest{params: %{cursor: cursor1}},
                 chan_info(),
                 state
               )

      assert %Entities.ListPromptsResult{
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
                 %Entities.ListPromptsRequest{},
                 chan_info(),
                 state
               )

      assert %Entities.ListPromptsResult{
               prompts: [%{name: "prompt1"}],
               nextCursor: cursor1
             } = result1

      # Second request
      assert {:reply, {:result, result2}, _} =
               Suite.handle_request(
                 %Entities.ListPromptsRequest{params: %{cursor: cursor1}},
                 chan_info(),
                 state
               )

      assert %Entities.ListPromptsResult{
               prompts: [%{name: "prompt2"}],
               nextCursor: cursor2
             } = result2

      # Third request
      assert {:reply, {:result, result3}, _} =
               Suite.handle_request(
                 %Entities.ListPromptsRequest{params: %{cursor: cursor2}},
                 chan_info(),
                 state
               )

      assert %Entities.ListPromptsResult{
               prompts: [%{name: "prompt3"}],
               nextCursor: nil
             } = result3
    end

    test "handles invalid pagination token" do
      expect(PromptRepoMock, :prefix, fn :repo1 -> "some_prefix" end)

      state = init_session(prompts: [{PromptRepoMock, :repo1}])

      assert {:reply, {:error, :invalid_cursor}, _} =
               Suite.handle_request(
                 %Entities.ListPromptsRequest{params: %{cursor: "invalid_token"}},
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
                 %Entities.ListPromptsRequest{},
                 chan_info(),
                 state
               )

      assert %Entities.ListPromptsResult{
               prompts: [],
               nextCursor: nil
             } = result
    end
  end

  describe "getting prompts" do
    test "gets prompt without arguments" do
      result = %Entities.GetPromptResult{
        description: "A greeting",
        messages: [
          %Entities.PromptMessage{
            role: :user,
            content: %Entities.TextContent{type: :text, text: "Hello!"}
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
                 %Entities.GetPromptRequest{
                   params: %{name: "greeting"}
                 },
                 chan_info(),
                 state
               )
    end

    test "gets prompt with valid arguments" do
      result = %Entities.GetPromptResult{
        messages: [
          %Entities.PromptMessage{
            role: :user,
            content: %Entities.TextContent{type: :text, text: "Analyze: test.csv"}
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
                 %Entities.GetPromptRequest{
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
                 %Entities.GetPromptRequest{
                   params: %{name: "unknown"}
                 },
                 chan_info(),
                 state
               )

      assert {400,
              %{code: -32602, data: %{name: "unknown"}, message: "Prompt not found: unknown"}} =
               check_error({:prompt_not_found, "unknown"})
    end

    IO.warn("@todo implement required params error and expect HTTP error 400")

    IO.warn(
      "@todo test we can return invalid params from the call as well, to skip validate_request"
    )

    test "returns error for validation failure" do
      PromptRepoMock
      |> expect(:prefix, fn :repo1 -> "analysis" end)
      |> expect(:get, fn "analysis", _, _channel, :repo1 ->
        {:error, "Missing required argument: dataset"}
      end)

      state = init_session(prompts: [{PromptRepoMock, :repo1}])

      assert {:reply, {:error, "Missing required argument: dataset"}, _} =
               Suite.handle_request(
                 %Entities.GetPromptRequest{
                   params: %{name: "analysis"}
                 },
                 chan_info(),
                 state
               )

      assert {500, %{code: -32603}} = check_error("Missing required argument: dataset")
    end

    test "searches across multiple repos" do
      result = %Entities.GetPromptResult{
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
                 %Entities.GetPromptRequest{
                   params: %{name: "prompt2"}
                 },
                 chan_info(),
                 state
               )
    end
  end
end

IO.warn("""
Todo test that channel info + assigns is given to repo,prompts and tool callbacks
""")
