defmodule GenMcp.Test.Client do
  import ExUnit.Assertions
  require(GenMcp.Entities.ModMap).require_all()

  def url(path) do
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

  defp validate_request(%{"method" => method} = data) do
    JSV.validate!(data, jsv_root(method))
    :ok
  end

  def post_message(path, data, req_opts \\ []) do
    data = JSV.Normalizer.normalize(data)
    :ok = validate_request(data)
    resp = Req.post!(url(path), [json: data, receive_timeout: :timer.minutes(1)] ++ req_opts)
    assert resp.status in [200, 202]
    resp
  end

  def post_invalid_message(path, data) do
    data = JSV.Normalizer.normalize(data)
    resp = Req.post!(url(path), json: data)
    assert resp.status in [400]
    resp
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
