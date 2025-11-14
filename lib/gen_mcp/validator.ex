defmodule GenMCP.Validator do
  alias JSV.Ref
  require GenMCP.Entities.ModMap, as: ModMap
  ModMap.require_all()

  validable = [
    request: [
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
      GenMCP.Entities.CompleteRequest
    ],
    notification: [
      GenMCP.Entities.CancelledNotification,
      GenMCP.Entities.InitializedNotification,
      GenMCP.Entities.ProgressNotification,
      GenMCP.Entities.RootsListChangedNotification
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
