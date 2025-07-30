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

  defp post_message(data) do
    data = JSV.Normalizer.normalize(data)
    :ok = validate_request(data)
    %{status: status, body: body} = Req.post!(url(), json: data)
    assert status in [200, 202]
    body
  end

  test "basic server does not support GET" do
    assert 405 = Req.get!(url()).status
  end

  test "requires RPC protocol" do
    assert %{
             "error" => %{"code" => 1, "data" => nil, "message" => "unknown protocol"},
             "jsonrpc" => "2.0"
           } = Req.post!(url(), json: %{}).body
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
               ]
             }
           } = post_message(%{jsonrpc: "2.0", id: 123, method: "tools/list", params: %{}})
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
             })

    assert "" =
             post_message(%{
               jsonrpc: "2.0",
               method: "notifications/initialized",
               params: %{}
             })
  end
end
