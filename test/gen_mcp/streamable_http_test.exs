# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMCP.StreamableHTTPTest do
  use ExUnit.Case, async: false

  import GenMCP.Test.Client
  import Mox

  alias GenMCP.Cluster.NodeSync
  alias GenMCP.MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.Support.ServerMock
  alias GenMCP.Support.SessionControllerMock
  alias GenMCP.Support.ToolMock

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

  defp init_session(opts) when is_list(opts) do
    url = Keyword.fetch!(opts, :url)
    init_state = Keyword.get(opts, :init_state, :some_state)

    ServerMock
    |> expect(:init, fn _, _ -> {:ok, init_state} end)
    |> expect(:handle_request, fn _req, _channel, state ->
      init_result =
        MCP.intialize_result(
          capabilities: MCP.capabilities(tools: true),
          server_info: MCP.server_info(name: "Mock Server", version: "foo", title: "stuff")
        )

      {:reply, {:result, init_result}, state}
    end)

    resp =
      client(url: url)
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

    expect(ServerMock, :handle_notification, fn _notif, state -> {:noreply, state} end)

    assert "" =
             client(session_id: session_id, url: url)
             |> post_message(%{
               jsonrpc: "2.0",
               method: "notifications/initialized",
               params: %{}
             })
             |> expect_status(202)
             |> body()

    Mox.verify!(ServerMock)

    stub(ServerMock, :handle_request, fn _, _, _ ->
      raise """
      no expectation defined for

          expect(ServerMock, :handle_request, fn req, channel, state ->

          end)

      """
    end)

    session_id
  end

  describe "session init" do
    @mcp_url "/mcp/mock"

    test "basic server does not support GET" do
      assert 405 = Req.get!(client(url: @mcp_url)).status
    end

    test "unknown RPC method" do
      resp =
        post_invalid_message(client(url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 123,
          method: "some_unknownw_method",
          params: %{
            foo: "bar"
          }
        })

      assert %{
               status: 400,
               body: %{
                 "error" => %{
                   "code" => -32_601,
                   "data" => %{"method" => "some_unknownw_method"},
                   "message" => "Unknown method some_unknownw_method"
                 },
                 "id" => 123,
                 "jsonrpc" => "2.0"
               }
             } = resp
    end

    test "we can run the initialization" do
      ServerMock
      |> expect(:init, fn _, _ -> {:ok, :some_session_state} end)
      |> expect(:handle_request, fn req, channel, :some_session_state ->
        assert %MCP.InitializeRequest{
                 id: 123,
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
               } = req

        # We are using a real HTTP client in test so the channel pid is not the
        # test pid.
        assert %Channel{client: pid, assigns: assigns} = channel
        assert is_pid(pid)
        assert %{gen_mcp_session_id: _} = assigns
        assert 1 = map_size(assigns)

        init_result =
          MCP.intialize_result(
            capabilities: MCP.capabilities(tools: true),
            server_info: MCP.server_info(name: "Mock Server", version: "foo", title: "stuff")
          )

        {:reply, {:result, init_result}, :some_session_state_1}
      end)

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

      expect(ServerMock, :handle_notification, fn notif, :some_session_state_1 ->
        assert %MCP.InitializedNotification{
                 method: "notifications/initialized",
                 params: %{}
               } = notif

        {:noreply, :some_session_state_2}
      end)

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
  end

  describe "bad requests" do
    @mcp_url "/mcp/mock"

    test "sending non json rpc" do
      assert %{
               "error" => %{"code" => -32_600, "message" => "Invalid RPC request"},
               "jsonrpc" => "2.0"
             } =
               client(url: @mcp_url)
               |> Req.post!(json: %{"hello" => "world"})
               |> expect_status(400)
               |> body()

      # same if we send non-json request (it's not parsed) (parse error should be
      # handled differently)

      assert %{
               "error" => %{"code" => -32_600, "message" => "Invalid RPC request"},
               "jsonrpc" => "2.0"
             } =
               client(url: @mcp_url)
               |> Req.post!(body: "hello")
               |> expect_status(400)
               |> body()
    end

    test "send invalid request" do
      assert %{
               # We still get the ID if provided
               "id" => 123,
               "jsonrpc" => "2.0",
               "error" => %{
                 "code" => -32_602,
                 "data" => %{"details" => _, "valid" => false},
                 "message" => "Invalid Parameters"
               }
             } =
               post_invalid_message(client(url: @mcp_url), %{
                 jsonrpc: "2.0",
                 id: 123,
                 method: "initialize",
                 params: %{
                   # missing capabilities in payload
                   clientInfo: %{name: "test client", version: "0.0.0"},
                   protocolVersion: "2025-06-18"
                 }
               }).body
    end
  end

  describe "tools" do
    @mcp_url "/mcp/mock"

    test "can list tools without initialization" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.ListToolsRequest{id: 123, params: %{}} =
                 req

        resp =
          MCP.list_tools_result([
            {ToolMock, :tool1},
            {ToolMock, :tool2}
          ])

        {:reply, {:result, resp}, state}
      end)

      ToolMock
      |> stub(:info, fn
        :name, :tool1 -> "Tool1"
        :title, :tool1 -> "Tool 1 title"
        :description, :tool1 -> "Tool 1 descr"
        :annotations, :tool1 -> %{title: "Tool 1 subtitle", destructiveHint: true}
        :_meta, :tool1 -> %{"some" => "meta"}
        :name, :tool2 -> "Tool2"
        :title, :tool2 -> nil
        :description, :tool2 -> nil
        :annotations, :tool2 -> nil
        :_meta, :tool2 -> nil
      end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)
      |> stub(:output_schema, fn
        :tool1 -> %{type: :object}
        :tool2 -> nil
      end)

      # For now we have one tool, we should be able to get it in the list
      assert %{
               "id" => 123,
               "jsonrpc" => "2.0",
               "result" => %{
                 "tools" => [
                   %{
                     "name" => "Tool1",
                     "annotations" => %{"title" => "Tool 1 subtitle", "destructiveHint" => true},
                     "title" => "Tool 1 title",
                     "description" => "Tool 1 descr",
                     "inputSchema" => %{"type" => "object"},
                     "outputSchema" => %{"type" => "object"},
                     "_meta" => %{"some" => "meta"}
                   },
                   %{
                     "name" => "Tool2",
                     "inputSchema" => %{"type" => "object"}
                   }
                 ]
               }
             } ==
               post_message(client(session_id: session_id, url: @mcp_url), %{
                 jsonrpc: "2.0",
                 id: 123,
                 method: "tools/list",
                 params: %{}
               }).body
    end

    test "calling a sync tool" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.CallToolRequest{
                 id: 456,
                 params: %MCP.CallToolRequestParams{
                   _meta: %{"progressToken" => "hello"},
                   arguments: %{"some" => "arg"},
                   name: "SomeTool"
                 }
               } = req

        result = MCP.call_tool_result(text: "hello")

        {:reply, {:result, result}, state}
      end)

      assert %{
               "id" => 456,
               "jsonrpc" => "2.0",
               "result" => %{"content" => [%{"text" => "hello", "type" => "text"}]}
             } =
               client(session_id: session_id, url: @mcp_url)
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
               |> body()
    end

    test "calling an unknown tool" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.CallToolRequest{
                 id: 456,
                 params: %MCP.CallToolRequestParams{
                   _meta: nil,
                   arguments: %{},
                   name: "SomeUnknownTool"
                 }
               } = req

        {:reply, {:error, {:unknown_tool, "swapped-tool-name"}}, state}
      end)

      assert %{
               "error" => %{
                 "code" => -32_602,
                 "message" => "Unknown tool swapped-tool-name",
                 "data" => %{"tool" => "swapped-tool-name"}
               },
               "id" => 456,
               "jsonrpc" => "2.0"
             } ==
               client(session_id: session_id, url: @mcp_url)
               |> post_message(%{
                 jsonrpc: "2.0",
                 id: 456,
                 method: "tools/call",
                 params: %{name: "SomeUnknownTool", arguments: %{}}
               })
               |> expect_status(400)
               |> body()
    end

    test "calling an async tool" do
      client = client(session_id: init_session(url: @mcp_url), url: @mcp_url)

      # The custom server wants to do async stuff, but we need to respond to the
      # incoming request, so the server can reply with {:stream, state}

      expect(ServerMock, :handle_request, fn req, channel, _state ->
        assert %MCP.CallToolRequest{
                 id: 456,
                 params: %MCP.CallToolRequestParams{
                   arguments: %{"arg" => 123},
                   name: "SomeAsyncTool"
                 }
               } = req

        # We will start a stream, but we will send a chunk to it before. It should
        # not cause any problem because the http handler will not listen for
        # messages until it starts streaming.

        Channel.send_result(channel, MCP.call_tool_result(audio: {"wav", "some-base-64"}))

        {:reply, :stream, :state_after_stream}
      end)

      resp =
        post_message(client, %{
          jsonrpc: "2.0",
          id: 456,
          method: "tools/call",
          params: %{
            name: "SomeAsyncTool",
            arguments: %{arg: 123}
          }
        })

      assert "data: " <> json = resp.body

      assert %{
               "id" => 456,
               "jsonrpc" => "2.0",
               "result" => %{
                 "content" => [
                   %{"type" => "audio", "data" => "some-base-64", "mimeType" => "wav"}
                 ]
               }
             } = JSV.Codec.decode!(json)
    end

    test "calling async tool with progressToken notifications" do
      session_id = init_session(url: @mcp_url)
      token = "some-progress-token"

      ServerMock
      |> expect(:handle_request, fn req, channel, _state ->
        assert %Channel{progress_token: ^token} = channel

        channel_as_state = channel

        # We will also test that handle_info is passed to the server
        # implementation by the session
        send(self(), :some_info1)

        {:reply, :stream, channel_as_state}
      end)
      |> expect(:handle_info, fn :some_info1, channel_as_state ->
        channel_as_state = Channel.send_progress(channel_as_state, 0, 3, "zero")
        send(self(), :some_info2)
        {:noreply, channel_as_state}
      end)
      |> expect(:handle_info, fn :some_info2, channel_as_state ->
        channel_as_state = Channel.send_progress(channel_as_state, 3, 3, "three")
        send(self(), :some_info3)
        {:noreply, channel_as_state}
      end)
      |> expect(:handle_info, fn :some_info3, channel_as_state ->
        channel_as_state =
          Channel.send_result(
            channel_as_state,
            MCP.call_tool_result(text: "hello")
          )

        {:noreply, channel_as_state}
      end)

      resp =
        post_message(
          client(session_id: session_id, url: @mcp_url),
          %{
            jsonrpc: "2.0",
            id: 456,
            method: "tools/call",
            params: %{
              name: "SomeAsyncTool",
              arguments: %{some: :arg},
              _meta: %{progressToken: token}
            }
          },
          into: :self
        )

      chunks =
        resp
        |> stream_chunks()
        |> Enum.map(fn "data: " <> json -> JSV.Codec.decode!(json) end)

      assert [
               %{
                 "method" => "notifications/progress",
                 "params" => %{
                   "message" => "zero",
                   "progressToken" => ^token,
                   "progress" => 0,
                   "total" => 3
                 }
               },
               %{
                 "method" => "notifications/progress",
                 "params" => %{
                   "message" => "three",
                   "progressToken" => ^token,
                   "progress" => 3,
                   "total" => 3
                 }
               },
               %{
                 "id" => 456,
                 "jsonrpc" => "2.0",
                 "result" => %{
                   "content" => [%{"text" => "hello", "type" => "text"}]
                 }
               }
             ] = chunks
    end

    test "calling async tool that returns error from continue callback" do
      session_id = init_session(url: @mcp_url)

      ServerMock
      |> expect(:handle_request, fn req, channel, _state ->
        assert %MCP.CallToolRequest{
                 id: 457,
                 params: %MCP.CallToolRequestParams{
                   arguments: %{"arg" => 123},
                   name: "AsyncToolWithError"
                 }
               } = req

        # Simulate async operation that will fail
        send(self(), :async_error)

        {:reply, :stream, channel}
      end)
      |> expect(:handle_info, fn :async_error, channel ->
        # Send an error through the channel
        channel = Channel.send_error(channel, "Something went wrong in async operation")

        {:noreply, channel}
      end)

      resp =
        post_message(
          client(session_id: session_id, url: @mcp_url),
          %{
            jsonrpc: "2.0",
            id: 457,
            method: "tools/call",
            params: %{name: "AsyncToolWithError", arguments: %{arg: 123}}
          },
          into: :self
        )

      chunks =
        resp
        |> stream_chunks()
        |> Enum.map(fn "data: " <> json -> JSV.Codec.decode!(json) end)

      # Should receive an error response that terminates the stream
      assert [
               %{
                 "error" => %{
                   "code" => -32_603,
                   "message" => "Something went wrong in async operation"
                 },
                 "id" => 457,
                 "jsonrpc" => "2.0"
               }
             ] = chunks
    end

    test "calling async tool with progress notifications then error" do
      session_id = init_session(url: @mcp_url)
      token = "error-progress-token"

      ServerMock
      |> expect(:handle_request, fn req, channel, _state ->
        assert %Channel{progress_token: ^token} = channel

        send(self(), :progress_step_1)

        {:reply, :stream, channel}
      end)
      |> expect(:handle_info, fn :progress_step_1, channel ->
        channel = Channel.send_progress(channel, 1, 3, "step 1")
        send(self(), :progress_step_2)
        {:noreply, channel}
      end)
      |> expect(:handle_info, fn :progress_step_2, channel ->
        channel = Channel.send_progress(channel, 2, 3, "step 2")
        send(self(), :error_step)
        {:noreply, channel}
      end)
      |> expect(:handle_info, fn :error_step, channel ->
        channel = Channel.send_error(channel, "Failed at step 3")
        {:noreply, channel}
      end)

      resp =
        post_message(
          client(session_id: session_id, url: @mcp_url),
          %{
            jsonrpc: "2.0",
            id: 458,
            method: "tools/call",
            params: %{name: "ProgressThenError", arguments: %{}, _meta: %{progressToken: token}}
          },
          into: :self
        )

      chunks =
        resp
        |> stream_chunks()
        |> Enum.map(fn "data: " <> json -> JSV.Codec.decode!(json) end)

      # Should receive progress notifications followed by an error
      assert [
               %{
                 "method" => "notifications/progress",
                 "params" => %{
                   "message" => "step 1",
                   "progressToken" => ^token,
                   "progress" => 1,
                   "total" => 3
                 }
               },
               %{
                 "method" => "notifications/progress",
                 "params" => %{
                   "message" => "step 2",
                   "progressToken" => ^token,
                   "progress" => 2,
                   "total" => 3
                 }
               },
               %{
                 "error" => %{
                   "code" => -32_603,
                   "message" => "Failed at step 3"
                 },
                 "id" => 458,
                 "jsonrpc" => "2.0"
               }
             ] = chunks
    end

    test "handles cancelled notification without error" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_notification, fn notif, state ->
        assert %MCP.CancelledNotification{
                 method: "notifications/cancelled",
                 params: %MCP.CancelledNotificationParams{
                   requestId: "request-to-cancel",
                   reason: "User cancelled"
                 }
               } = notif

        {:noreply, state}
      end)

      resp =
        client(session_id: session_id, url: @mcp_url)
        |> post_message(%{
          jsonrpc: "2.0",
          method: "notifications/cancelled",
          params: %{
            requestId: "request-to-cancel",
            reason: "User cancelled"
          }
        })
        |> expect_status(202)

      # Notification should return empty body
      assert "" = resp.body
    end
  end

  describe "ignored notification" do
    @mcp_url "/mcp/mock"

    test "handles roots list changed notification without error" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_notification, fn notif, state ->
        assert %MCP.RootsListChangedNotification{
                 method: "notifications/roots/list_changed",
                 params: %{"_meta" => %{}}
               } = notif

        {:noreply, state}
      end)

      resp =
        client(session_id: session_id, url: @mcp_url)
        |> post_message(%{
          jsonrpc: "2.0",
          method: "notifications/roots/list_changed",
          params: %{
            _meta: %{}
          }
        })
        |> expect_status(202)

      # Notification should return empty body
      assert "" = resp.body
    end
  end

  describe "resource operations" do
    @mcp_url "/mcp/mock"

    test "list resources with pagination" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.ListResourcesRequest{
                 id: 200,
                 params: %{}
               } = req

        result =
          MCP.list_resources_result(
            [
              %{uri: "file:///page1.txt", name: "Page 1", description: "First page"},
              %{uri: "file:///page2.txt", name: "Page 2"}
            ],
            "next-page-token"
          )

        {:reply, {:result, result}, state}
      end)

      # First page
      resp1 =
        post_message(client(session_id: session_id, url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 200,
          method: "resources/list",
          params: %{}
        })

      assert %{
               "id" => 200,
               "jsonrpc" => "2.0",
               "result" => %{
                 "resources" => [
                   %{
                     "uri" => "file:///page1.txt",
                     "name" => "Page 1",
                     "description" => "First page"
                   },
                   %{
                     "uri" => "file:///page2.txt",
                     "name" => "Page 2"
                   }
                 ],
                 "nextCursor" => cursor
               }
             } = resp1.body

      assert cursor == "next-page-token"

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.ListResourcesRequest{
                 id: 201,
                 params: %MCP.ListResourcesRequestParams{cursor: ^cursor}
               } = req

        result =
          MCP.list_resources_result(
            [
              %{uri: "file:///page3.txt", name: "Page 3"}
            ],
            nil
          )

        {:reply, {:result, result}, state}
      end)

      # Second page with cursor
      resp2 =
        post_message(client(session_id: session_id, url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 201,
          method: "resources/list",
          params: %{cursor: cursor}
        })

      assert %{
               "id" => 201,
               "jsonrpc" => "2.0",
               "result" => %{
                 "resources" => [
                   %{
                     "uri" => "file:///page3.txt",
                     "name" => "Page 3"
                   }
                 ]
               }
             } = resp2.body

      # Verify that nextCursor is nil (may or may not be in the response)
      assert nil == resp2.body["result"]["nextCursor"]
    end

    test "list resources error with invalid pagination cursor" do
      # not actually testing cursor decoding here

      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.ListResourcesRequest{
                 id: 202,
                 params: %MCP.ListResourcesRequestParams{
                   cursor: "some-cursor"
                 }
               } = req

        # The server implementation should return an error for invalid cursors
        {:reply, {:error, "Invalid pagination cursor"}, state}
      end)

      resp =
        client(session_id: session_id, url: @mcp_url)
        |> post_message(%{
          jsonrpc: "2.0",
          id: 202,
          method: "resources/list",
          params: %{cursor: "some-cursor"}
        })
        |> expect_status(500)

      assert %{
               "error" => %{
                 "code" => -32_603,
                 "message" => "Invalid pagination cursor"
               },
               "id" => 202,
               "jsonrpc" => "2.0"
             } = resp.body
    end

    test "read resource" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.ReadResourceRequest{
                 id: 204,
                 params: %MCP.ReadResourceRequestParams{
                   uri: "file:///readme.txt"
                 }
               } = req

        result =
          MCP.read_resource_result(
            uri: "file:///readme.txt",
            text: "# Welcome\n\nThis is the readme.",
            mime_type: "text/plain"
          )

        {:reply, {:result, result}, state}
      end)

      resp =
        post_message(client(session_id: session_id, url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 204,
          method: "resources/read",
          params: %{uri: "file:///readme.txt"}
        })

      assert %{
               "id" => 204,
               "jsonrpc" => "2.0",
               "result" => %{
                 "contents" => [
                   %{
                     "uri" => "file:///readme.txt",
                     "mimeType" => "text/plain",
                     "text" => "# Welcome\n\nThis is the readme."
                   }
                 ]
               }
             } = resp.body
    end

    test "read resource not found" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.ReadResourceRequest{
                 id: 205,
                 params: %MCP.ReadResourceRequestParams{
                   uri: "file:///missing.txt"
                 }
               } = req

        {:reply, {:error, {:resource_not_found, "file:///missing.txt"}}, state}
      end)

      resp =
        client(session_id: session_id, url: @mcp_url)
        |> post_message(%{
          jsonrpc: "2.0",
          id: 205,
          method: "resources/read",
          params: %{uri: "file:///missing.txt"}
        })
        |> expect_status(400)

      assert %{
               "error" => %{
                 "code" => -32_002,
                 "message" => message,
                 "data" => %{"uri" => "file:///missing.txt"}
               },
               "id" => 205,
               "jsonrpc" => "2.0"
             } = resp.body

      assert message =~ "Resource not found"
    end

    test "read resource URI template error" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.ReadResourceRequest{
                 id: 206,
                 params: %MCP.ReadResourceRequestParams{
                   uri: "file:///wrongprefix/data.txt"
                 }
               } = req

        {:reply,
         {:error,
          "expected uri matching template file://prefix/{path}, got file:///wrongprefix/data.txt"},
         state}
      end)

      resp =
        client(session_id: session_id, url: @mcp_url)
        |> post_message(%{
          jsonrpc: "2.0",
          id: 206,
          method: "resources/read",
          params: %{uri: "file:///wrongprefix/data.txt"}
        })
        |> expect_status(500)

      assert %{
               "error" => %{
                 "code" => -32_603,
                 "message" => message
               },
               "id" => 206,
               "jsonrpc" => "2.0"
             } = resp.body

      assert message =~ "expected uri matching template"
    end

    test "list resource templates" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.ListResourceTemplatesRequest{
                 id: 207,
                 params: %{}
               } = req

        result =
          MCP.list_resource_templates_result([
            %{
              uriTemplate: "file:///documents/{path}",
              name: "Documents",
              description: "Access documents by path",
              mimeType: "text/plain"
            },
            %{
              uriTemplate: "file:///images/{id}.png",
              name: "Images"
            }
          ])

        {:reply, {:result, result}, state}
      end)

      resp =
        post_message(client(session_id: session_id, url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 207,
          method: "resources/templates/list",
          params: %{}
        })

      assert %{
               "id" => 207,
               "jsonrpc" => "2.0",
               "result" => %{
                 "resourceTemplates" => [
                   %{
                     "uriTemplate" => "file:///documents/{path}",
                     "name" => "Documents",
                     "description" => "Access documents by path",
                     "mimeType" => "text/plain"
                   },
                   %{
                     "uriTemplate" => "file:///images/{id}.png",
                     "name" => "Images"
                   }
                 ]
               }
             } = resp.body
    end
  end

  describe "prompt operations" do
    @mcp_url "/mcp/mock"

    test "list prompts" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.ListPromptsRequest{
                 id: 300
               } = req

        result =
          MCP.list_prompts_result(
            [
              %{name: "greeting", description: "A friendly greeting"},
              %{
                name: "analysis",
                description: "Data analysis",
                arguments: [
                  %{name: "dataset", required: true, description: "Dataset to analyze"}
                ]
              }
            ],
            nil
          )

        {:reply, {:result, result}, state}
      end)

      resp =
        post_message(client(session_id: session_id, url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 300,
          method: "prompts/list",
          params: %{}
        })

      assert %{
               "id" => 300,
               "jsonrpc" => "2.0",
               "result" => %{
                 "prompts" => [
                   %{
                     "name" => "greeting",
                     "description" => "A friendly greeting"
                   },
                   %{
                     "name" => "analysis",
                     "description" => "Data analysis",
                     "arguments" => [
                       %{
                         "name" => "dataset",
                         "required" => true,
                         "description" => "Dataset to analyze"
                       }
                     ]
                   }
                 ]
               }
             } = resp.body
    end

    test "list prompts with pagination" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.ListPromptsRequest{
                 id: 301,
                 params: %{cursor: "page-2-token"}
               } = req

        result =
          MCP.list_prompts_result(
            [%{name: "prompt3"}],
            nil
          )

        {:reply, {:result, result}, state}
      end)

      resp =
        post_message(client(session_id: session_id, url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 301,
          method: "prompts/list",
          params: %{cursor: "page-2-token"}
        })

      assert %{
               "id" => 301,
               "jsonrpc" => "2.0",
               "result" => %{
                 "prompts" => [%{"name" => "prompt3"}]
               }
             } = resp.body
    end

    test "get prompt without arguments" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.GetPromptRequest{
                 id: 302,
                 params: %{name: "greeting"}
               } = req

        result = %MCP.GetPromptResult{
          description: "A friendly greeting",
          messages: [
            %MCP.PromptMessage{
              role: :user,
              content: %MCP.TextContent{text: "Hello! How can I help you today?"}
            }
          ]
        }

        {:reply, {:result, result}, state}
      end)

      resp =
        post_message(client(session_id: session_id, url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 302,
          method: "prompts/get",
          params: %{name: "greeting"}
        })

      assert %{
               "id" => 302,
               "jsonrpc" => "2.0",
               "result" => %{
                 "description" => "A friendly greeting",
                 "messages" => [
                   %{
                     "role" => "user",
                     "content" => %{
                       "type" => "text",
                       "text" => "Hello! How can I help you today?"
                     }
                   }
                 ]
               }
             } = resp.body
    end

    test "get prompt with arguments" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.GetPromptRequest{
                 id: 303,
                 params: %{
                   name: "analysis",
                   arguments: %{"dataset" => "sales.csv"}
                 }
               } = req

        result = %MCP.GetPromptResult{
          messages: [
            %MCP.PromptMessage{
              role: :user,
              content: %MCP.TextContent{text: "Analyze dataset: sales.csv"}
            }
          ]
        }

        {:reply, {:result, result}, state}
      end)

      resp =
        post_message(client(session_id: session_id, url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 303,
          method: "prompts/get",
          params: %{name: "analysis", arguments: %{dataset: "sales.csv"}}
        })

      assert %{
               "id" => 303,
               "jsonrpc" => "2.0",
               "result" => %{
                 "messages" => [
                   %{
                     "role" => "user",
                     "content" => %{
                       "type" => "text",
                       "text" => "Analyze dataset: sales.csv"
                     }
                   }
                 ]
               }
             } = resp.body
    end

    test "handles prompt not found error" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.GetPromptRequest{
                 id: 304,
                 params: %{name: "unknown"}
               } = req

        {:reply, {:error, {:prompt_not_found, "unknown"}}, state}
      end)

      resp =
        post_message(client(session_id: session_id, url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 304,
          method: "prompts/get",
          params: %{name: "unknown"}
        })

      assert %{
               "id" => 304,
               "jsonrpc" => "2.0",
               "error" => %{
                 "code" => -32_602,
                 "message" => "Prompt not found: unknown",
                 "data" => %{"name" => "unknown"}
               }
             } = resp.body
    end

    test "handles prompt validation error" do
      session_id = init_session(url: @mcp_url)

      expect(ServerMock, :handle_request, fn req, _channel, state ->
        assert %MCP.GetPromptRequest{
                 id: 305
               } = req

        {:reply, {:error, "Missing required argument: dataset"}, state}
      end)

      resp =
        post_message(client(session_id: session_id, url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 305,
          method: "prompts/get",
          params: %{name: "analysis"}
        })

      assert %{
               "id" => 305,
               "jsonrpc" => "2.0",
               "error" => %{
                 "code" => -32_603,
                 "message" => "Missing required argument: dataset"
               }
             } = resp.body
    end
  end

  describe "session location and termination without controller" do
    @mcp_url "/mcp/mock"

    test "request to unknown session id returns 404 with -32603 error" do
      unknown_session_id = "unknown-session-id-12345"

      resp =
        client(session_id: unknown_session_id, url: @mcp_url)
        |> post_message(%{
          jsonrpc: "2.0",
          id: 789,
          method: "tools/list",
          params: %{}
        })
        |> expect_status(404)

      assert %{
               "error" => %{
                 "code" => -32_603,
                 "message" => _message
               },
               "id" => 789,
               "jsonrpc" => "2.0"
             } = resp.body
    end

    test "delete session terminates the session" do
      session_id = init_session(url: @mcp_url)

      ref = Process.monitor(GenMCP.Mux.whereis(session_id))

      client(session_id: session_id, url: @mcp_url)
      |> Req.delete!()
      |> expect_status(204)

      assert_receive {:DOWN, ^ref, :process, _, {:shutdown, :mcp_stop}}
    end

    test "delete unknown session is 404" do
      session_id = "#{NodeSync.node_id()}-some-unknown-session"

      client(session_id: session_id, url: @mcp_url)
      |> Req.delete!()
      |> expect_status(404)
    end
  end

  describe "session handling" do
    @mcp_url "/mcp/controlled"

    test "initialize request does not call session controller" do
      ServerMock
      |> expect(:init, fn _, _ -> {:ok, :some_session_state} end)
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

    @tag :skip
    test "request without session calls fetch_session and returns 404 if not found" do
      expect(SessionControllerMock, :fetch_session, fn "some-session-id", _channel, :foo ->
        {:error, :not_found}
      end)

      client(session_id: "some-session-id", url: @mcp_url)
      |> post_message(%{
        jsonrpc: "2.0",
        id: 123,
        method: "tools/list",
        params: %{}
      })
      |> expect_status(404)
    end

    IO.warn(
      "session fetch_session should return the channel, because the server mock will want to use them as new default assigns"
    )

    @tag :skip
    test "request without session calls fetch_session and restores session if found" do
      expect(SessionControllerMock, :fetch_session, fn "some-session-id", _channel, :foo ->
        {:ok, :some_restored_data}
      end)

      ServerMock
      |> expect(:init, fn _, _ -> {:ok, :initial_state} end)
      |> expect(:session_restore, fn :some_restored_data, _channel, :initial_state ->
        {:ok, :restored_state}
      end)
      |> expect(:handle_request, fn req, _channel, :restored_state ->
        assert %MCP.ListToolsRequest{} = req
        {:reply, {:result, MCP.list_tools_result([])}, :restored_state}
      end)

      client(session_id: "some-session-id", url: @mcp_url)
      |> post_message(%{
        jsonrpc: "2.0",
        id: 123,
        method: "tools/list",
        params: %{}
      })
      |> expect_status(200)
    end

    @tag :skip
    test "delete request calls session_delete" do
      # First we need to establish a session or restore it. Let's restore it for simplicity.
      expect(SessionControllerMock, :fetch_session, fn "some-session-id", _channel, :foo ->
        {:ok, :some_restored_data}
      end)

      ServerMock
      |> expect(:init, fn _, _ -> {:ok, :initial_state} end)
      |> expect(:session_restore, fn :some_restored_data, _channel, :initial_state ->
        {:ok, :restored_state}
      end)
      |> expect(:session_delete, fn :restored_state -> :ok end)

      client(session_id: "some-session-id", url: @mcp_url)
      |> Req.delete!()
      |> expect_status(204)
    end

    @tag :skip
    test "initialize request with mcp-session-id header returns 400" do
      client(session_id: "some-session-id", url: @mcp_url)
      |> post_message(%MCP.InitializeRequest{
        id: 123,
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %MCP.Implementation{name: "test client", version: "0.0.0"},
          protocolVersion: "2025-06-18"
        }
      })
      |> expect_status(400)
      |> body()
      |> then(fn body ->
        assert %{
                 "error" => %{
                   "code" => -32_600,
                   "message" => _
                 }
               } = body
      end)
    end

    @tag :skip
    test "delete unknown session should attempt to fetch it and call the delete callback on the server mock"
  end
end
