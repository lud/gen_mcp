defmodule GenMcp.Test.Client do
  import ExUnit.Assertions
  require(GenMcp.Mcp.Entities.ModMap).require_all()

  [
    # Requests
    GenMcp.Mcp.Entities.InitializeRequest,
    GenMcp.Mcp.Entities.PingRequest,
    GenMcp.Mcp.Entities.ListResourcesRequest,
    GenMcp.Mcp.Entities.ListResourceTemplatesRequest,
    GenMcp.Mcp.Entities.ReadResourceRequest,
    GenMcp.Mcp.Entities.SubscribeRequest,
    GenMcp.Mcp.Entities.UnsubscribeRequest,
    GenMcp.Mcp.Entities.ListPromptsRequest,
    GenMcp.Mcp.Entities.GetPromptRequest,
    GenMcp.Mcp.Entities.ListToolsRequest,
    GenMcp.Mcp.Entities.CallToolRequest,
    GenMcp.Mcp.Entities.SetLevelRequest,
    GenMcp.Mcp.Entities.CompleteRequest,

    # Notifications
    GenMcp.Mcp.Entities.CancelledNotification,
    GenMcp.Mcp.Entities.InitializedNotification,
    GenMcp.Mcp.Entities.ProgressNotification,
    GenMcp.Mcp.Entities.RootsListChangedNotification
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
    opts = Keyword.put_new_lazy(opts, :base_url, &GenMcp.TestWeb.Endpoint.url/0)

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

    Req.post!(client, [json: data, receive_timeout: :timer.minutes(1)] ++ req_opts)
  end

  def expect_status(resp, status) when is_integer(status) do
    assert status == resp.status
    resp
  end

  def expect_session_header(resp) do
    assert {:ok, [session_id]} = Map.fetch(resp.headers, "mcp-session-id")
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
