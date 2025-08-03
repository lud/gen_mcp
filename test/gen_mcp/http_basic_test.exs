defmodule GenMcp.HttpBasicTest do
  use ExUnit.Case, async: true

  defp url(path) do
    GenMcp.TestWeb.Endpoint.url()
    |> URI.parse()
    |> URI.merge(path)
  end

  [
    # Requests
    GenMcp.Entities.InitializeRequest,
    GenMcp.Entities.PingRequest,
    GenMcp.Entities.ListResourcesRequest,
    GenMcp.Entities.ListResourceTemplatesRequest,
    GenMcp.Entities.ReadResourceRequest,
    GenMcp.Entities.SubscribeRequest,
    GenMcp.Entities.UnsubscribeRequest,
    GenMcp.Entities.ListPromptsRequest,
    GenMcp.Entities.GetPromptRequest,
    GenMcp.Entities.ListToolsRequest,
    GenMcp.Entities.CallToolRequest,
    GenMcp.Entities.SetLevelRequest,
    GenMcp.Entities.CompleteRequest,
    # Notifications
    GenMcp.Entities.CancelledNotification,
    GenMcp.Entities.InitializedNotification,
    GenMcp.Entities.ProgressNotification,
    GenMcp.Entities.RootsListChangedNotification
  ]
  |> Enum.map(fn mod ->
    method = mod.json_schema().properties.method.const
    {method, JSV.build!(mod)}
  end)
  |> Enum.each(fn {method, root} ->
    def jsv_root(unquote(method)) do
      unquote(Macro.escape(root))
    end
  end)

  @req_root JSV.build!(GenMcp.Entities.ClientRequest)
  defp validate_request(%{"method" => method} = data) do
    JSV.validate!(data, jsv_root(method))
    :ok
  end

  defp url do
    url("/mcp/basic")
  end

  defp post_message(data, req_opts \\ []) do
    data = JSV.Normalizer.normalize(data)
    :ok = validate_request(data)
    resp = Req.post!(url(), [json: data, receive_timeout: :timer.minutes(1)] ++ req_opts)
    assert resp.status in [200, 202]
    resp
  end

  defp post_invalid_message(data) do
    data = JSV.Normalizer.normalize(data)
    resp = Req.post!(url(), json: data)
    assert resp.status in [400]
    resp
  end

  defp read_chunk(resp) do
    Req.parse_message(
      resp,
      receive do
        msg -> msg
      end
    )
  end

  defp stream_chunks(resp) do
    Stream.unfold(resp, fn resp ->
      case read_chunk(resp) do
        {:ok, [:done]} -> nil
        {:ok, [data: data]} -> {data, resp}
      end
    end)
  end

  test "basic server does not support GET" do
    assert 405 = Req.get!(url()).status
  end

  test "can list tools without initialization" do
    # For now we have one tool, we should be able to get it in the list
    assert %{
             "id" => 123,
             "result" => %{
               "tools" => [
                 %{
                   "annotations" => %{"title" => "Basic Calculator"},
                   "title" => "Basic Calculator",
                   "description" => _,
                   "inputSchema" => %{},
                   "name" => "Calculator",
                   "outputSchema" => %{}
                 }
                 | _
               ]
             }
           } = post_message(%{jsonrpc: "2.0", id: 123, method: "tools/list", params: %{}}).body
  end

  test "we can run the initialization" do
    assert %{
             "id" => 123,
             "jsonrpc" => "2.0",
             "result" => %{
               "capabilities" => %{"tools" => %{}},
               "protocolVersion" => "2025-06-18",
               "serverInfo" => %{
                 "name" => _,
                 "title" => _,
                 "version" => _
               }
             }
           } =
             post_message(%{
               jsonrpc: "2.0",
               id: 123,
               method: "initialize",
               params: %{
                 capabilities: %{},
                 clientInfo: %{name: "test client", version: "0.0.0"},
                 protocolVersion: "2025-06-18"
               }
             }).body

    assert "" =
             post_message(%{
               jsonrpc: "2.0",
               method: "notifications/initialized",
               params: %{}
             }).body
  end

  test "sending non json rpc" do
    assert %{
             status: 400,
             body: %{
               "error" => %{"code" => 1, "data" => nil, "message" => "invalid JSON-RPC payload"},
               "jsonrpc" => "2.0"
             }
           } = Req.post!(url(), json: %{"hello" => "world"})

    # same if we send non-json request (it's not parsed) (parse error should be handled differently)

    assert %{
             status: 400,
             body: %{
               "error" => %{"code" => 1, "data" => nil, "message" => "invalid JSON-RPC payload"},
               "jsonrpc" => "2.0"
             }
           } = Req.post!(url(), body: "hello")
  end

  test "send invalid request" do
    assert %{
             # We still get the ID if provided
             "id" => 123,
             "jsonrpc" => "2.0",
             "error" => %{
               "code" => 2,
               "data" => %{"details" => _, "valid" => false},
               "message" => "request validation failed"
             }
           } =
             post_invalid_message(%{
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

  test "calling a sync tool" do
    assert %{
             "id" => 456,
             "jsonrpc" => "2.0",
             "result" => %{
               "content" => [
                 %{"text" => "{\"result\":15}", "type" => "text"}
               ],
               "structuredContent" => %{"result" => 15}
             }
           } =
             post_message(%{
               jsonrpc: "2.0",
               id: 456,
               method: "tools/call",
               params: %{
                 _meta: %{progressToken: "hello"},
                 name: "Calculator",
                 arguments: %{operator: "+", operands: [7, 8]}
               }
             }).body
  end

  test "calling an async tool" do
    resp =
      post_message(%{
        jsonrpc: "2.0",
        id: 456,
        method: "tools/call",
        params: %{
          name: "AsyncCounter",
          arguments: %{upto: 3}
        }
      })

    assert "data: " <> json = resp.body

    assert %{
             "id" => 456,
             "jsonrpc" => "2.0",
             "result" => %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => "I counted up to 3"
                 }
               ]
             }
           } = JSV.Codec.decode!(json)
  end

  test "calling async tool with progressToken notifications" do
    resp =
      post_message(
        %{
          jsonrpc: "2.0",
          id: 456,
          method: "tools/call",
          params: %{
            name: "AsyncCounter",
            arguments: %{upto: 3, sleep: 1},
            _meta: %{progressToken: "myToken"}
          }
        },
        into: :self
      )

    chunks =
      resp
      |> stream_chunks()
      |> Enum.map(fn "data: " <> json -> JSV.Codec.decode!(json) end)
      |> dbg()

    assert [
             %{
               "method" => "notifications/progress",
               "params" => %{
                 "message" => nil,
                 "progressToken" => "myToken",
                 "progress" => 0,
                 "total" => 3
               }
             },
             %{
               "method" => "notifications/progress",
               "params" => %{
                 "message" => nil,
                 "progressToken" => "myToken",
                 "progress" => 1,
                 "total" => 3
               }
             },
             %{
               "method" => "notifications/progress",
               "params" => %{
                 "message" => nil,
                 "progressToken" => "myToken",
                 "progress" => 2,
                 "total" => 3
               }
             },
             %{
               "id" => 456,
               "jsonrpc" => "2.0",
               "result" => %{
                 "content" => [%{"type" => "text", "text" => "I counted up to 3"}]
               }
             }
           ] == chunks
  end

  # TODO this test should be directly made on the default server impl, no need to go
  # through http
  test "calling an unknown tool" do
    assert %{
             "error" => %{"code" => 3, "message" => "unknown tool SomeUnknownTool"},
             "id" => 456,
             "jsonrpc" => "2.0"
           } ==
             post_invalid_message(%{
               jsonrpc: "2.0",
               id: 456,
               method: "tools/call",
               params: %{
                 name: "SomeUnknownTool",
                 arguments: %{}
               }
             }).body
  end

  @tag :slow
  test "calling async tool with keepalive SSE comments" do
    resp =
      post_message(
        %{
          jsonrpc: "2.0",
          id: 456,
          method: "tools/call",
          params: %{
            name: "Sleeper",
            arguments: %{seconds: 30}
          }
        },
        into: :self
      )

    # keepalive is set to 25 seconds so we should get one

    assert {:ok, [data: ":keepalive\n"]} = read_chunk(resp)
    assert {:ok, [data: chunk]} = read_chunk(resp)

    assert "data: " <> json = chunk

    assert %{
             "id" => 456,
             "jsonrpc" => "2.0",
             "result" => %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => "I slept for 30 seconds"
                 }
               ]
             }
           } = JSV.Codec.decode!(json)
  end
end
