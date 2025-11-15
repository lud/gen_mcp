defmodule GenMCP.Validator do
  alias JSV.Ref
  require GenMCP.MCP.ModMap, as: ModMap
  ModMap.require_all()

  IO.warn("todo support cancellation (cancelled notification)")

  validable = [
    request: [
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
      GenMCP.MCP.CallToolRequest
      # GenMCP.MCP.SetLevelRequest,
      # GenMCP.MCP.CompleteRequest
    ],
    notification: [
      # GenMCP.MCP.CancelledNotification,
      GenMCP.MCP.InitializedNotification,
      GenMCP.MCP.ProgressNotification
      # GenMCP.MCP.RootsListChangedNotification
    ]
  ]

  ctx = JSV.build_init!(formats: true)
  {:root, _, ctx} = JSV.build_add!(ctx, ModMap)

  {ctx, items} =
    for {kind, mods} <- validable, mod <- mods, reduce: {ctx, []} do
      {ctx, items} ->
        js = mod.json_schema()
        method = js.properties.method.const
        title = js.title
        {method, kind, title}
        {jsv_key, ctx} = JSV.build_key!(ctx, Ref.pointer!(["definitions", title], :root))
        item = {method, kind, jsv_key}
        {ctx, [item | items]}
    end

  @root JSV.to_root!(ctx, :root)
  defp jsv_root do
    @root
  end

  Enum.each(items, fn {method, kind, jsv_key} ->
    defp jsv_key(unquote(method)) do
      {:ok, unquote(kind), unquote(Macro.escape(jsv_key))}
    end
  end)

  defp jsv_key(method) do
    {:error, {:unknown_method, method}}
  end

  @doc """
  Validates request but also notifications, and returns the kind
  (:request/:notification) with the cast message.
  """
  def validate_request(%{"method" => method} = request) do
    with {:ok, kind, jsv_key} <- jsv_key(method),
         {:ok, cast} <- JSV.validate(request, jsv_root(), key: jsv_key) do
      {:ok, kind, cast}
    end
  end
end
