defmodule GenMCP.Validator do
  @moduledoc """
  Validates and casts decoded JSON-RPC messages into the `GenMCP.MCP.V2607`
  struct vocabulary.

  The transport decodes an incoming HTTP body into a plain map, then hands that
  map to `validate_request/1` before any dispatch happens. The validator checks
  the message against the JSON Schema of the method it names, and on success
  returns the matching protocol struct (for example a
  `GenMCP.MCP.V2607.CallToolRequest`) together with whether the message is a
  request or a notification. A message whose method is not recognized, or whose
  body does not conform to the schema, is rejected before it reaches a handler.

  The set of recognized methods is the request and notification surface of the
  `2026-07-28` protocol that the library currently serves. The full JSON Schema
  root is assembled once at compile time, so validation at runtime is a lookup
  by method followed by a single `JSV.validate/3` call.

  This module is used internally by `GenMCP.Transport.StreamableHTTP`. The single
  public entry point is `validate_request/1`.
  """

  alias JSV.Ref

  require GenMCP.MCP.V2607.ModMap, as: ModMap

  ModMap.require_all()

  defmodule Formats do
    @moduledoc false
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
      GenMCP.MCP.V2607.ListResourcesRequest,
      GenMCP.MCP.V2607.ListResourceTemplatesRequest,
      GenMCP.MCP.V2607.ReadResourceRequest,
      GenMCP.MCP.V2607.SubscriptionsListenRequest,
      GenMCP.MCP.V2607.ListPromptsRequest,
      GenMCP.MCP.V2607.GetPromptRequest,
      GenMCP.MCP.V2607.ListToolsRequest,
      GenMCP.MCP.V2607.DiscoverRequest,
      GenMCP.MCP.V2607.CallToolRequest
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
  Validates a decoded JSON-RPC message and casts it to its protocol struct.

  The argument is the full message map as decoded from the request body, carrying
  at least a `"method"` key, and usually `"jsonrpc"`, `"id"`, and `"params"`. The
  method selects the schema to validate against, and the rest of the map is the
  body that gets validated and cast.

  On success the call returns `{:ok, kind, cast}`:

  * `kind` is `:request` or `:notification`, telling the caller how to treat the
    message.
  * `cast` is the validated `GenMCP.MCP.V2607` struct, with its fields already
    coerced (atom keys, decoded `byte` formats, nested structs).

  Two errors are possible:

  * `{:error, {:unknown_method, method}}` when no schema is registered for the
    method. This is checked before the body, so a map carrying only a `"method"`
    is enough to trigger it.
  * `{:error, {:invalid_body, jsv_error}}` when the method is known but the body
    fails schema validation. The `jsv_error` is a `JSV.ValidationError` whose
    message explains which property did not conform.

  ### Examples

  A `tools/list` request validates and casts to a
  `GenMCP.MCP.V2607.ListToolsRequest`. The body is what a client sends, with the
  protocol version and client info travelling in `_meta` as the protocol
  requires (the cast struct is omitted here because it is deeply nested):

      iex> GenMCP.Validator.validate_request(%{
      ...>   "jsonrpc" => "2.0",
      ...>   "id" => 1,
      ...>   "method" => "tools/list",
      ...>   "params" => %{
      ...>     "_meta" => %{
      ...>       "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
      ...>       "io.modelcontextprotocol/clientCapabilities" => %{},
      ...>       "io.modelcontextprotocol/clientInfo" => %{
      ...>         "name" => "my-client",
      ...>         "version" => "1.0.0"
      ...>       }
      ...>     }
      ...>   }
      ...> })
      {:ok, :request,
      %GenMCP.MCP.V2607.ListToolsRequest{
        id: 1,
        params: %GenMCP.MCP.V2607.PaginatedRequestParams{
          _meta: %GenMCP.MCP.V2607.RequestMetaObject{
            "io.modelcontextprotocol/clientCapabilities": %GenMCP.MCP.V2607.ClientCapabilities{
              elicitation: nil,
              experimental: nil,
              extensions: nil,
              roots: nil,
              sampling: nil
            },
            "io.modelcontextprotocol/clientInfo": %GenMCP.MCP.V2607.Implementation{
              description: nil,
              icons: nil,
              name: "my-client",
              title: nil,
              version: "1.0.0",
              websiteUrl: nil
            },
            "io.modelcontextprotocol/logLevel": nil,
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            progressToken: nil
          },
          cursor: nil
        }
      }}

  An unrecognized method is rejected before its body is even looked at:

      iex> GenMCP.Validator.validate_request(%{"method" => "bogus/method"})
      {:error, {:unknown_method, "bogus/method"}}
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
