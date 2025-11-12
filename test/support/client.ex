defmodule GenMCP.Test.Client do
  import ExUnit.Assertions
  require(GenMCP.Entities.ModMap).require_all()

  [
    # Requests
    GenMCP.Entities.InitializeRequest,
    GenMCP.Entities.PingRequest,
    GenMCP.Entities.ListResourcesRequest,
    GenMCP.Entities.ListResourceTemplatesRequest,
    GenMCP.Entities.ReadResourceRequest,
    GenMCP.Entities.SubscribeRequest,
    GenMCP.Entities.UnsubscribeRequest,
    GenMCP.Entities.ListPromptsRequest,
    GenMCP.Entities.GetPromptRequest,
    GenMCP.Entities.ListToolsRequest,
    GenMCP.Entities.CallToolRequest,
    GenMCP.Entities.SetLevelRequest,
    GenMCP.Entities.CompleteRequest,

    # Notifications
    GenMCP.Entities.CancelledNotification,
    GenMCP.Entities.InitializedNotification,
    GenMCP.Entities.ProgressNotification,
    GenMCP.Entities.RootsListChangedNotification
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
