defmodule GenMCP.Test.Client do
  import ExUnit.Assertions

  require(GenMCP.MCP.ModMap).require_all()

  [
    # Requests

    GenMCP.MCP.InitializeRequest,
    # GenMCP.MCP.PingRequest,
    GenMCP.MCP.ListResourcesRequest,
    GenMCP.MCP.ListResourceTemplatesRequest,
    GenMCP.MCP.ReadResourceRequest,
    # GenMCP.MCP.SubscribeRequest,
    # GenMCP.MCP.UnsubscribeRequest,
    GenMCP.MCP.ListPromptsRequest,
    GenMCP.MCP.GetPromptRequest,
    GenMCP.MCP.ListToolsRequest,
    GenMCP.MCP.CallToolRequest,
    # GenMCP.MCP.SetLevelRequest,
    # GenMCP.MCP.CompleteRequest,

    # Notifications

    GenMCP.MCP.CancelledNotification,
    GenMCP.MCP.InitializedNotification,
    GenMCP.MCP.ProgressNotification,
    GenMCP.MCP.RootsListChangedNotification
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

  defp validate_request(%{"method" => method} = data) do
    JSV.validate!(data, jsv_root(method))
    :ok
  end

  def new(opts \\ []) do
    opts = Keyword.put_new_lazy(opts, :base_url, &GenMCP.TestWeb.Endpoint.url/0)

    Req.new(opts)
  end

  def post_message(client, data, req_opts \\ []) do
    post(client, data, req_opts, _validate_req? = true)
  end

  def post_invalid_message(client, data, req_opts \\ []) do
    post(client, data, req_opts, _validate_req? = false)
  end

  defp post(client, data, req_opts, validate_req?) do
    data = JSV.Normalizer.normalize(data)

    if validate_req? do
      assert :ok = validate_request(data)
    end

    Req.post!(client, [json: data, receive_timeout: to_timeout(minute: 1)] ++ req_opts)
  end

  def expect_status(resp, status) when is_integer(status) do
    if status != resp.status do
      flunk("""
      Expected status #{status} but got #{resp.status}

      Response body:
      #{inspect(resp.body, pretty: true, limit: :infinity)}
      """)
    end

    resp
  end

  def expect_session_header(resp) do
    _ = assert {:ok, [session_id]} = Map.fetch(resp.headers, "mcp-session-id")
    assert is_binary(session_id)
    session_id
  end

  def body(%{body: body}) do
    body
  end

  def read_chunk(resp) do
    Req.parse_message(
      resp,
      receive do
        msg -> msg
      end
    )
  end

  def stream_chunks(resp) do
    Stream.unfold(resp, fn resp ->
      case read_chunk(resp) do
        {:ok, [:done]} -> nil
        {:ok, [data: data]} -> {data, resp}
      end
    end)
  end
end
