defmodule GenMCP.Validator do
  @moduledoc false

  alias JSV.Ref

  require GenMCP.MCP.V2607.ModMap, as: ModMap

  ModMap.require_all()

  defmodule Formats do
    @behaviour JSV.FormatValidator

    def supported_formats do
      ["byte"]
    end

    def applies_to_type?("byte", data) when is_binary(data) do
      true
    end

    def applies_to_type?(_, _) do
      false
    end

    def validate_cast("byte", data) do
      case Base.decode64(data) do
        {:ok, v} -> {:ok, v}
        :error -> {:error, "invalid base64 encoded string"}
      end
    end
  end

  validable = [
    request: [
      # GenMCP.MCP.V2607.PingRequest,
      GenMCP.MCP.V2607.ListResourcesRequest,
      GenMCP.MCP.V2607.ListResourceTemplatesRequest,
      GenMCP.MCP.V2607.ReadResourceRequest,
      # GenMCP.MCP.V2607.SubscribeRequest,
      # GenMCP.MCP.V2607.UnsubscribeRequest,
      GenMCP.MCP.V2607.ListPromptsRequest,
      GenMCP.MCP.V2607.GetPromptRequest,
      GenMCP.MCP.V2607.ListToolsRequest,
      GenMCP.MCP.V2607.DiscoverRequest,
      GenMCP.MCP.V2607.CallToolRequest
      # GenMCP.MCP.V2607.SetLevelRequest
      # GenMCP.MCP.V2607.CompleteRequest
    ],
    notification: [
      GenMCP.MCP.V2607.CancelledNotification
      # GenMCP.MCP.V2607.InitializedNotification,
      # GenMCP.MCP.V2607.ProgressNotification,
      # GenMCP.MCP.V2607.RootsListChangedNotification
    ]
  ]

  ctx = JSV.build_init!(formats: [Formats | JSV.default_format_validator_modules()], atoms: true)
  {:root, _, ctx} = JSV.build_add!(ctx, ModMap)

  {ctx, items} =
    for {kind, mods} <- validable, mod <- mods, reduce: {ctx, []} do
      {ctx, items} ->
        js = mod.json_schema()
        method = js.properties.method.const
        "MCP:" <> shortname = js.title

        {jsv_key, ctx} = JSV.build_key!(ctx, Ref.pointer!(["definitions", shortname], :root))
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
         {:ok, cast} <- validate_body(request, jsv_key) do
      {:ok, kind, cast}
    end
  end

  defp validate_body(request, jsv_key) do
    case JSV.validate(request, jsv_root(), key: jsv_key) do
      {:ok, cast} -> {:ok, cast}
      {:error, jsv_err} -> {:error, {:invalid_body, jsv_err}}
    end
  end
end
