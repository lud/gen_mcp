# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMcp.StreamableHttpTest do
  alias GenMcp.ConnCase
  alias GenMcp.Mux.Channel
  alias GenMcp.Server
  alias GenMcp.Support.ServerMock
  alias GenMcp.Support.ToolMock
  import ConnCase
  import GenMcp.Test.Client
  import Mox
  use ExUnit.Case, async: false

  setup [:set_mox_global, :verify_on_exit!]

  def client(session_id \\ nil) do
    opts =
      case session_id do
        nil -> []
        sid when is_binary(sid) -> [headers: %{"mcp-session-id" => sid}]
      end

    opts = Keyword.put_new(opts, :url, "/mcp/mock")

    new(opts)
  end

  test "basic server does not support GET" do
    assert 405 = Req.get!(client()).status
  end

  test "we can run the initialization" do
    ServerMock
    |> expect(:init, fn _ -> {:ok, :some_session_state} end)
    |> expect(:handle_request, fn req, chan_info, :some_session_state ->
      assert %GenMcp.Mcp.Entities.InitializeRequest{
               id: 123,
               method: "initialize",
               params: %GenMcp.Mcp.Entities.InitializeRequestParams{
                 _meta: nil,
                 capabilities: %GenMcp.Mcp.Entities.ClientCapabilities{
                   elicitation: nil,
                   experimental: nil,
                   roots: nil,
                   sampling: nil
                 },
                 clientInfo: %GenMcp.Mcp.Entities.Implementation{
                   name: "test client",
                   title: nil,
                   version: "0.0.0"
                 },
                 protocolVersion: "2025-06-18"
               }
             } = req

      # We are using a real HTTP client in test so the chan_info pid is not the
      # test pid.
      assert {:channel, GenMcp.Plug.StreamableHttp, pid} = chan_info
      assert is_pid(pid)

      init_result =
        Server.intialize_result(
          capabilities: Server.capabilities(tools: true),
          server_info: Server.server_info(name: "Mock Server", version: "foo", title: "stuff")
        )

      {:reply, {:result, init_result}, :some_session_state_1}
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

    expect(ServerMock, :handle_notification, fn notif, :some_session_state_1 ->
      assert %GenMcp.Mcp.Entities.InitializedNotification{
               method: "notifications/initialized",
               params: %{}
             } = notif

      {:noreply, :some_session_state_2}
    end)

    assert "" =
             session_id
             |> client()
             |> post_message(%{
               jsonrpc: "2.0",
               method: "notifications/initialized",
               params: %{}
             })
             |> expect_status(202)
             |> body()
  end

  defp init_session(init_state \\ :some_state) do
    ServerMock
    |> expect(:init, fn _ -> {:ok, init_state} end)
    |> expect(:handle_request, fn req, chan_info, state ->
      init_result =
        Server.intialize_result(
          capabilities: Server.capabilities(tools: true),
          server_info: Server.server_info(name: "Mock Server", version: "foo", title: "stuff")
        )

      {:reply, {:result, init_result}, state}
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

    expect(ServerMock, :handle_notification, fn notif, state -> {:noreply, state} end)

    assert "" =
             session_id
             |> client()
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

          expect(ServerMock, :handle_request, fn req, chan_info, state ->

          end)

      """
    end)

    session_id
  end

  test "sending non json rpc" do
    assert %{
             "error" => %{"code" => -32600, "message" => "Invalid RPC request"},
             "jsonrpc" => "2.0"
           } =
             client()
             |> Req.post!(json: %{"hello" => "world"})
             |> expect_status(400)
             |> body()

    # same if we send non-json request (it's not parsed) (parse error should be handled differently)

    assert %{
             "error" => %{"code" => -32600, "message" => "Invalid RPC request"},
             "jsonrpc" => "2.0"
           } =
             client()
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
               "code" => -32602,
               "data" => %{"details" => _, "valid" => false},
               "message" => "Invalid Parameters"
             }
           } =
             post_invalid_message(client(), %{
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

  test "can list tools without initialization" do
    session_id = init_session()

    expect(ServerMock, :handle_request, fn req, _chan_info, state ->
      assert %GenMcp.Mcp.Entities.ListToolsRequest{id: 123, method: "tools/list", params: %{}} =
               req

      resp =
        Server.list_tools_result([
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
                   "outputSchema" => %{"type" => "object"}
                 },
                 %{
                   "name" => "Tool2",
                   "inputSchema" => %{"type" => "object"}
                 }
               ]
             }
           } ==
             post_message(client(session_id), %{
               jsonrpc: "2.0",
               id: 123,
               method: "tools/list",
               params: %{}
             }).body
  end

  test "calling a sync tool" do
    session_id = init_session()

    expect(ServerMock, :handle_request, fn req, _chan_info, state ->
      assert %GenMcp.Mcp.Entities.CallToolRequest{
               id: 456,
               method: "tools/call",
               params: %GenMcp.Mcp.Entities.CallToolRequestParams{
                 _meta: %{"progressToken" => "hello"},
                 arguments: %{"some" => "arg"},
                 name: "SomeTool"
               }
             } = req

      result = Server.call_tool_result(text: "hello")

      {:reply, {:result, result}, state}
    end)

    assert %{
             "id" => 456,
             "jsonrpc" => "2.0",
             "result" => %{"content" => [%{"text" => "hello", "type" => "text"}]}
           } =
             session_id
             |> client()
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
    session_id = init_session()

    expect(ServerMock, :handle_request, fn req, _chan_info, state ->
      assert %GenMcp.Mcp.Entities.CallToolRequest{
               id: 456,
               method: "tools/call",
               params: %GenMcp.Mcp.Entities.CallToolRequestParams{
                 _meta: nil,
                 arguments: %{},
                 name: "SomeUnknownTool"
               }
             } = req

      result = Server.call_tool_result(text: "text")

      {:reply, {:error, {:unknown_tool, "swapped-tool-name"}}, state}
    end)

    assert %{
             "error" => %{
               "code" => -32602,
               "message" => "Unknown tool swapped-tool-name",
               "data" => %{"tool" => "swapped-tool-name"}
             },
             "id" => 456,
             "jsonrpc" => "2.0"
           } ==
             session_id
             |> client()
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
    client = client(init_session())

    # The custom server wants to do async stuff, but we need to respond to the
    # incoming request, so the server can reply with {:stream, state}
    #
    # The session should reply to the http handler to start a chunked response.
    # But then how do the session/server know which chan_info send updates to?

    expect(ServerMock, :handle_request, fn req, chan_info, state ->
      assert %GenMcp.Mcp.Entities.CallToolRequest{
               id: 456,
               method: "tools/call",
               params: %GenMcp.Mcp.Entities.CallToolRequestParams{
                 arguments: %{"arg" => 123},
                 name: "SomeAsyncTool"
               }
             } = req

      # We will start a stream, but we will send a chunk to it before. It should
      # not cause any problem because the http handler will not listen for
      # messages until it starts streaming.

      chan_info
      |> Channel.from_client(req)
      |> Channel.send_result(Server.call_tool_result(text: "hello"))

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
               "content" => [%{"text" => "hello", "type" => "text"}]
             }
           } = JSV.Codec.decode!(json)
  end

  test "calling async tool with progressToken notifications" do
    session_id = init_session()
    token = "some-progress-token"

    ServerMock
    |> expect(:handle_request, fn req, chan_info, _state ->
      assert %Channel{progress_token: ^token} =
               channel = Channel.from_client(chan_info, req)

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
          Server.call_tool_result(text: "hello")
        )

      {:noreply, channel_as_state}
    end)

    resp =
      session_id
      |> client()
      |> post_message(
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

  IO.warn("@todo add a test to verify that tool call isError result is properly encoded")

  IO.warn(
    "@todo add a test to verify that tool call structuredContent result is properly encoded"
  )
end
