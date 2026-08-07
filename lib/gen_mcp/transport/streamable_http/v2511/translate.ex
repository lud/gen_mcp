defmodule GenMCP.Transport.StreamableHTTP.V2511.Translate do
  @moduledoc false

  # The whole 2025 <-> 2026 conversion, kept in one place.
  #
  # Incoming: a decoded 2025 JSON-RPC body becomes a `V2607` request struct, so
  # the worker, the Suite and the providers only ever see 2026 vocabulary.
  # Outgoing: a `V2607` result becomes a plain map holding only the fields a
  # 2025 client understands.
  #
  # Results are downgraded into plain maps rather than reused as structs
  # because the 2026 structs force their 2026-only fields onto the wire — a
  # `CallToolResult` always encodes `resultType`, for instance. Building the
  # 2025 shape explicitly is also what keeps this file the single readable
  # answer to "what does a 2025 client actually get".

  alias GenMCP.MCP.V2607, as: MCP

  # The 2026 spec reserves this prefix for its own `_meta` keys. A 2025 client
  # knows none of them, so none of them belong in a downgraded payload.
  @reserved_meta_prefix "io.modelcontextprotocol/"

  @sid_atom_key :"io.modelcontextprotocol/subscriptionId"
  @sid_bin_key "io.modelcontextprotocol/subscriptionId"

  # The minimum severity a 2025 client receives, since it has no way to ask for
  # one. See `request_meta/2`.
  @default_log_level :info

  # -- Requests ---------------------------------------------------------------
  #
  # Every function here takes the normalized message the transport built
  # (`%{id:, params:, meta:}`), so `id` is already known to be a scalar and
  # `params` and `meta` to be maps. What is left to check is per-method: the
  # fields this shim actually reads.

  def discover_request(msg, session) do
    %MCP.DiscoverRequest{
      id: msg.id,
      params: %MCP.RequestParams{_meta: request_meta(msg, session)}
    }
  end

  def list_tools_request(msg, session) do
    paginated_request(MCP.ListToolsRequest, msg, session)
  end

  def list_resources_request(msg, session) do
    paginated_request(MCP.ListResourcesRequest, msg, session)
  end

  def list_resource_templates_request(msg, session) do
    paginated_request(MCP.ListResourceTemplatesRequest, msg, session)
  end

  # The three list methods differ only in which request struct they build: 2025
  # and 2026 agree on the method names and on `params.cursor` being the only
  # field a client sends.
  defp paginated_request(module, msg, session) do
    case Map.get(msg.params, "cursor") do
      cursor when is_binary(cursor) or is_nil(cursor) ->
        {:ok,
         struct!(module,
           id: msg.id,
           params: %MCP.PaginatedRequestParams{
             cursor: cursor,
             _meta: request_meta(msg, session)
           }
         )}

      _ ->
        {:error, invalid_params("params.cursor must be a string")}
    end
  end

  def read_resource_request(msg, session) do
    case Map.get(msg.params, "uri") do
      uri when is_binary(uri) ->
        {:ok,
         %MCP.ReadResourceRequest{
           id: msg.id,
           params: %MCP.ReadResourceRequestParams{
             uri: uri,
             _meta: request_meta(msg, session)
           }
         }}

      _ ->
        {:error, invalid_params("params.uri is required and must be a string")}
    end
  end

  def call_tool_request(msg, session) do
    with {:ok, name} <- tool_name(msg.params),
         {:ok, arguments} <- tool_arguments(msg.params) do
      {:ok,
       %MCP.CallToolRequest{
         id: msg.id,
         params: %MCP.CallToolRequestParams{
           name: name,
           arguments: arguments,
           # The argument *values* are not checked here: `GenMCP.Suite`
           # validates them against the tool's own input schema, which knows
           # nothing about protocol versions.
           _meta: request_meta(msg, session)
         }
       }}
    end
  end

  defp tool_name(%{"name" => name}) when is_binary(name) do
    {:ok, name}
  end

  defp tool_name(_params) do
    {:error, invalid_params("params.name is required and must be a string")}
  end

  defp tool_arguments(%{"arguments" => arguments}) when is_map(arguments) do
    {:ok, arguments}
  end

  defp tool_arguments(%{"arguments" => arguments}) when not is_nil(arguments) do
    {:error, invalid_params("params.arguments must be an object")}
  end

  defp tool_arguments(_params) do
    {:ok, nil}
  end

  # These rejections stand in for the schema validation the 2026 transport gets
  # from `GenMCP.Validator`, so they answer like it does: a pre-dispatch 400,
  # not the 200 that `{:invalid_params, _}` carries for an application-level
  # failure raised after a request was accepted.
  @rpc_invalid_params -32_602

  @doc false
  def invalid_params(message) do
    {:mcp_error, @rpc_invalid_params, 400, "Invalid Parameters: " <> message}
  end

  # The GET stream asks for every notification type. The handler narrows it to
  # what it actually serves via its honored filter, so requesting everything
  # here is a "give me what you have", not an over-claim. There is no request
  # id: a GET stream answers no JSON-RPC request, and a nil id also stops
  # `GenMCP.Mux.Channel` from stamping subscription ids onto the notifications.
  def subscriptions_listen_request(session) do
    {:ok,
     %MCP.SubscriptionsListenRequest{
       id: nil,
       params: %MCP.SubscriptionsListenRequestParams{
         notifications: %MCP.SubscriptionFilter{
           toolsListChanged: true,
           promptsListChanged: true,
           resourcesListChanged: true
         },
         _meta: request_meta(%{id: nil, params: %{}, meta: %{}}, session)
       }
     }}
  end

  # A 2025 request carries no protocol context of its own — that was settled
  # once at `initialize`. Rebuilding it here from the session is what lets
  # `GenMCP.Mux.Channel.from_request/3` populate `channel.meta` for a 2025
  # request exactly as it does for a 2026 one, so handlers reading client info
  # need no special case. The protocol version is the negotiated 2025 one, not
  # 2026-07-28: a handler that inspects it should see what the client speaks.
  #
  # `progressToken` lives at `params._meta.progressToken` in both versions, so
  # it carries straight over.
  #
  # The log level is the one field with no 2025 counterpart to read: 2026 has
  # the client name a minimum level per request, while 2025 sets one per
  # session with `logging/setLevel`, which this slice does not serve. Left
  # unset, `Channel.send_log/4` drops every record silently and the `logging`
  # capability advertised at `initialize` would be a promise the server never
  # keeps — while feature 017 puts log notifications on the POST stream in
  # scope. So a default stands in for the level the client never got to choose.
  defp request_meta(msg, session) do
    %MCP.RequestMetaObject{
      "io.modelcontextprotocol/protocolVersion": session.protocol_version,
      "io.modelcontextprotocol/clientInfo": client_info(session),
      "io.modelcontextprotocol/clientCapabilities": %MCP.ClientCapabilities{},
      "io.modelcontextprotocol/logLevel": @default_log_level,
      progressToken: progress_token(msg.meta)
    }
  end

  # A progress token is a string or a number in both versions. Anything else is
  # dropped rather than rejected: the client just does not get progress.
  defp progress_token(%{"progressToken" => token}) when is_binary(token) when is_number(token) do
    token
  end

  defp progress_token(_meta) do
    nil
  end

  defp client_info(%{client_name: nil}) do
    nil
  end

  defp client_info(session) do
    %MCP.Implementation{name: session.client_name, version: session.client_version}
  end

  # -- Results ----------------------------------------------------------------

  @doc """
  Strips a `V2607` result down to the fields a 2025 client understands.
  """
  def downgrade_result(%MCP.ListToolsResult{} = result) do
    # 2026-only on this result: resultType, cacheScope, ttlMs. The Tool objects
    # themselves are a 2025-compatible subset already.
    %{"tools" => result.tools}
    |> put_present("nextCursor", result.nextCursor)
    |> put_present("_meta", downgrade_meta(result._meta))
  end

  def downgrade_result(%MCP.ListResourcesResult{} = result) do
    # 2026-only on this result: resultType, cacheScope, ttlMs. The Resource
    # objects are a 2025-compatible subset already, same as Tool above.
    %{"resources" => result.resources}
    |> put_present("nextCursor", result.nextCursor)
    |> put_present("_meta", downgrade_meta(result._meta))
  end

  def downgrade_result(%MCP.ListResourceTemplatesResult{} = result) do
    %{"resourceTemplates" => result.resourceTemplates}
    |> put_present("nextCursor", result.nextCursor)
    |> put_present("_meta", downgrade_meta(result._meta))
  end

  def downgrade_result(%MCP.ReadResourceResult{} = result) do
    # `contents` is always present, even empty, because 2025 requires it.
    put_present(%{"contents" => result.contents || []}, "_meta", downgrade_meta(result._meta))
  end

  def downgrade_result(%MCP.CallToolResult{} = result) do
    # 2026-only on this result: resultType. `content` is always present, even
    # empty, because 2025 requires it.
    %{"content" => result.content || []}
    |> put_present("isError", result.isError)
    |> put_present("structuredContent", result.structuredContent)
    |> put_present("_meta", downgrade_meta(result._meta))
  end

  def downgrade_result(other) do
    other
  end

  # A result `_meta` carries the 2026 reserved keys the Suite adds — the
  # `io.modelcontextprotocol/serverInfo` block, for one. Those are stripped and
  # anything the application put there is kept, since `_meta` is exactly the
  # free-form channel both versions offer for it. An emptied `_meta` is dropped
  # rather than sent as `{}`.
  defp downgrade_meta(nil) do
    nil
  end

  defp downgrade_meta(meta) do
    kept =
      meta
      |> Map.delete(:__struct__)
      |> Enum.reject(fn {key, value} -> is_nil(value) or reserved_meta_key?(key) end)
      |> Map.new()

    if map_size(kept) != 0 do
      kept
    end
  end

  defp reserved_meta_key?(key) when is_atom(key) do
    reserved_meta_key?(Atom.to_string(key))
  end

  defp reserved_meta_key?(key) when is_binary(key) do
    String.starts_with?(key, @reserved_meta_prefix)
  end

  @doc """
  Builds the 2025 `initialize` result from a `server/discover` result.
  """
  def initialize_result(%MCP.DiscoverResult{} = discover, protocol_version) do
    put_present(
      %{
        "protocolVersion" => protocol_version,
        "capabilities" => downgrade_capabilities(discover.capabilities),
        "serverInfo" => server_info(discover)
      },
      "instructions",
      discover.instructions
    )
  end

  # 2026 moved server info into the result `_meta`; 2025 wants it as a
  # top-level `serverInfo`.
  defp server_info(%MCP.DiscoverResult{_meta: %{"io.modelcontextprotocol/serverInfo": info}})
       when not is_nil(info) do
    put_present(%{"name" => info.name, "version" => info.version}, "title", info.title)
  end

  defp server_info(_discover) do
    %{"name" => "gen_mcp", "version" => "0.0.0"}
  end

  # 2025 capability values are objects, never booleans, and only the four
  # capabilities this shim serves are advertised. `logging` is always on: the
  # Suite emits log notifications on the request stream.
  defp downgrade_capabilities(nil) do
    %{"logging" => %{}}
  end

  defp downgrade_capabilities(%MCP.ServerCapabilities{} = caps) do
    %{"logging" => %{}}
    |> put_capability("tools", caps.tools)
    |> put_capability("prompts", caps.prompts)
    |> put_capability("resources", resources_capability(caps.resources))
  end

  # A subscription handler with `resources_updated: true` puts `subscribe` on
  # the 2026 capability, where it promises `subscriptions/listen`. In 2025 the
  # same flag promises `resources/subscribe`, which this shim does not serve —
  # its update notifications ride the GET stream without a per-resource
  # subscription. `listChanged` survives: those notifications ride the GET
  # stream too, which is exactly what the flag promises a 2025 client.
  defp resources_capability(%{subscribe: _} = sub) do
    Map.delete(sub, :subscribe)
  end

  defp resources_capability(other) do
    other
  end

  defp put_capability(acc, _key, nil) do
    acc
  end

  defp put_capability(acc, _key, false) do
    acc
  end

  defp put_capability(acc, key, true) do
    Map.put(acc, key, %{})
  end

  defp put_capability(acc, key, %{} = sub) do
    Map.put(acc, key, sub)
  end

  # -- Notifications ----------------------------------------------------------

  @doc """
  Removes the 2026 subscription id a notification may carry.

  `notifications/progress`, `notifications/message` and the `list_changed`
  family have the same method names and param shapes in both versions, so the
  only thing to take off is the `io.modelcontextprotocol/subscriptionId` that
  `GenMCP.Mux.Channel` stamps into `params._meta` — a 2025 client has no
  subscription to route it to.
  """
  def strip_subscription_id(notif) when is_map(notif) do
    with {:ok, params_key, params} when is_map(params) <- lax_fetch(notif, :params),
         {:ok, meta_key, meta} when is_map(meta) <- lax_fetch(params, :_meta) do
      Map.put(notif, params_key, put_meta(params, meta_key, clean_meta(meta)))
    else
      _ -> notif
    end
  end

  def strip_subscription_id(notif) do
    notif
  end

  # `GenMCP.Mux.Channel` stamps the id under an atom or a string key depending
  # on the notification's own shape, and a handler may hand it either a struct
  # or a plain map, so both forms have to be looked for.
  defp lax_fetch(map, atom_key) do
    bin_key = Atom.to_string(atom_key)

    case map do
      %{^atom_key => value} when not is_nil(value) -> {:ok, atom_key, value}
      %{^bin_key => value} when not is_nil(value) -> {:ok, bin_key, value}
      _ -> :error
    end
  end

  # `io.modelcontextprotocol/subscriptionId` is a declared field of
  # `NotificationMetaObject`, so on a struct it must be set to nil, never
  # deleted: deleting it would strip a field off the struct and leave a
  # `__struct__`-only value behind. A nil field is dropped at encoding time.
  defp clean_meta(%_struct{} = meta) do
    meta = Map.put(meta, @sid_atom_key, nil)

    if !(meta |> Map.delete(:__struct__) |> Enum.all?(&nil_value?/1)) do
      meta
    end
  end

  defp clean_meta(meta) do
    meta = Map.drop(meta, [@sid_atom_key, @sid_bin_key])

    if !Enum.all?(meta, &nil_value?/1) do
      meta
    end
  end

  defp nil_value?({_key, value}) do
    is_nil(value)
  end

  # An emptied `_meta` is removed outright from a plain map, but only nilled on
  # a struct, where the field cannot be taken away. Both disappear at encoding.
  defp put_meta(params, meta_key, nil) when is_struct(params) do
    Map.put(params, meta_key, nil)
  end

  defp put_meta(params, meta_key, nil) do
    Map.delete(params, meta_key)
  end

  defp put_meta(params, meta_key, meta) do
    Map.put(params, meta_key, meta)
  end

  defp put_present(map, _key, nil) do
    map
  end

  defp put_present(map, key, value) do
    Map.put(map, key, value)
  end
end
