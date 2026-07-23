defmodule GenMCP.Suite do
  @moduledoc ~S"""
  Ready-made `GenMCP` server that serves tools, resources, and prompts from a set
  of configured providers.

  `GenMCP.Suite` is the default `:server` for `GenMCP.Transport.StreamableHTTP`.
  Instead of implementing the `GenMCP` behaviour yourself, you configure a Suite
  with lists of provider modules and it answers every Model Context Protocol
  request by dispatching to them: `server/discover`, `tools/list`, `tools/call`,
  the `resources/*` and `prompts/*` requests, and subscription requests. The
  `server/discover` capability snapshot is self-describing, computed from the
  providers you configured, so you never hand-declare capabilities. A request for
  a method the Suite does not implement is answered with a JSON-RPC "method not
  found" error.

  Like any `GenMCP` implementation, a Suite runs **per request** on the stateless
  `2026-07-28` transport: `init/1` builds the state from your configuration on
  every request, and per-request client context arrives through the
  `t:GenMCP.Mux.Channel.t/0`, not through long-lived session state. Pagination
  cursors and the multi round-trip `requestState` are encrypted and carried by the
  client between requests, so the Suite holds no state of its own between them.

  ## Minimal usage

  Configure a Suite with a single `add` tool. The tool implements
  `GenMCP.Suite.Tool` and delegates the arithmetic to a plain `Calculator` module,
  so the tool stays a thin adapter with no logic of its own:

      defmodule MyApp.Calculator do
        def add(a, b) do
          a + b
        end
      end

      defmodule MyApp.AddTool do
        use GenMCP.Suite.Tool,
          name: "add",
          description: "Adds two numbers and returns the sum.",
          input_schema: %{
            "type" => "object",
            "properties" => %{
              "a" => %{"type" => "number"},
              "b" => %{"type" => "number"}
            },
            "required" => ["a", "b"]
          }

        alias GenMCP.MCP.V2607, as: MCP

        @impl true
        def call(request, _channel, _arg) do
          %{"a" => a, "b" => b} = request.params.arguments
          {:result, MCP.call_tool_result(text: "#{MyApp.Calculator.add(a, b)}")}
        end
      end

  Because the Suite is the default server, its options are passed straight to the
  transport plug in your router. The tool list, server name, and server version
  are all the Suite needs:

      # In your router
      forward "/mcp", GenMCP.Transport.StreamableHTTP,
        server_name: "My App",
        server_version: "1.0.0",
        tools: [MyApp.AddTool]

  ## Configuration

  The Suite accepts these options:

  * `:server_name` - required string, the server's name reported in
    `server/discover`.
  * `:server_version` - required string, the server's version.
  * `:server_title` - optional human-readable title, defaults to `nil`.
  * `:tools` - the list of `GenMCP.Suite.Tool` implementations exposed by the
    server. Defaults to `[]`.
  * `:resources` - the list of `GenMCP.Suite.ResourceRepo` implementations to
    serve resources from. Defaults to `[]`.
  * `:prompts` - the list of `GenMCP.Suite.PromptRepo` implementations to generate
    prompts with. Defaults to `[]`.
  * `:extensions` - the list of `GenMCP.Suite.Extension` implementations that
    contribute further tools, resource repositories, and prompt repositories,
    typically computed from the request's `t:GenMCP.Mux.Channel.t/0`. Defaults to
    `[]`.
  * `:subscription_handler` - a single `GenMCP.Suite.SubscriptionHandler`
    implementation that answers subscription requests. Defaults to `nil` (no
    subscriptions).
  * `:send_server_info` - whether to include the server's
    `io.modelcontextprotocol/serverInfo` metadata (built from `:server_name`,
    `:server_version`, and `:server_title`) in the `_meta` of every result, as
    the spec recommends. Defaults to `true`.

  ## Providers and their arguments

  Every provider entry (in `:tools`, `:resources`, `:prompts`, `:extensions`, and
  `:subscription_handler`) is given in one of three forms: a bare `module`, a
  `{module, arg}` tuple, or a ready-built descriptor map. The provider behaviours
  (`GenMCP.Suite.Tool`, `GenMCP.Suite.ResourceRepo`, `GenMCP.Suite.PromptRepo`,
  `GenMCP.Suite.SubscriptionHandler`, and `GenMCP.Suite.Extension`) share two
  arguments that recur across their callbacks:

  * `arg` is the trailing argument of every provider callback. It is the value you
    attach next to the module as `{module, arg}` (a bare `module` is treated as
    `{module, []}`). It lets one generic, config-driven provider module be
    configured differently in different Suites, for example
    `{MyApp.FileResource, root: "/srv/docs"}`.
  * `channel` is the request-scoped `t:GenMCP.Mux.Channel.t/0`, threaded as the
    second-to-last argument of the callbacks that need request context. It carries
    read-only client `meta` and authorization assigns, so a provider can vary what
    it exposes per request (for instance hiding a tool from an unauthorized
    caller). It is passed only to the callbacks that act on a request, not to
    every callback.

  See each provider behaviour's own documentation for the callbacks it defines and
  how it carries state across a streaming request.

  ## Custom server

  A Suite covers the common case. When you need full control over request
  handling, implement the `GenMCP` behaviour directly and hand your module to the
  transport as the `:server` option instead. See `GenMCP` for that contract.
  """

  @behaviour GenMCP

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.Suite.Extension
  alias GenMCP.Suite.PromptRepo
  alias GenMCP.Suite.ResourceRepo
  alias GenMCP.Suite.SubscriptionHandler
  alias GenMCP.Suite.Tool
  alias GenMCP.Utils.OptsValidator
  require Record

  provider_list = fn doc ->
    [
      default: [],
      type: {:list, {:or, [:atom, :mod_arg, :map]}},
      doc:
        doc <>
          " List items can be either module names, `{module, arg}` tuples or descriptor maps."
    ]
  end

  provider_single = fn doc ->
    [
      default: nil,
      type: {:or, [:atom, :mod_arg, :map]},
      doc:
        doc <>
          " Either a module name, a `{module, arg}` tuple or a descriptor map."
    ]
  end

  init_opts_schema =
    NimbleOptions.new!(
      server_name: [required: true, type: :string],
      server_version: [required: true, type: :string],
      server_title: [type: {:or, [:string, nil]}, default: nil],
      tools:
        provider_list.(
          "The list of `GenMCP.Suite.Tool` implementations" <>
            " that will be available in the server."
        ),
      resources:
        provider_list.(
          "The list of `GenMCP.Suite.ResourceRepo` implementations" <>
            " to serve resources from."
        ),
      prompts:
        provider_list.(
          "A list of `GenMCP.Suite.PromptRepo` implementations" <>
            " to generate prompts with."
        ),
      extensions:
        provider_list.(
          "A list `Extension` implementations" <>
            " to add more tools, resource repositories and prompt repositories."
        ),
      subscription_handler: provider_single.("A handler for subscription requests."),
      send_server_info: [
        type: :boolean,
        default: true,
        doc:
          "Includes the server's `io.modelcontextprotocol/serverInfo` metadata" <>
            " (built from `:server_name`, `:server_version`, and `:server_title`)" <>
            " in the `_meta` of every result, as the spec recommends."
      ]
    )

  defmodule State do
    @moduledoc false

    @enforce_keys [
      :server_name,
      :server_version,
      :server_title,
      :send_server_info,
      :subscription_handler,
      :tools,
      :resources,
      :prompts,
      :extensions,
      :on_message
    ]

    defstruct @enforce_keys
  end

  Record.defrecordp(:tracker, id: nil, data: nil, channel: nil, mref: nil)

  @init_opts_schema init_opts_schema
  @doc false
  def init_opts_schema do
    @init_opts_schema
  end

  @impl GenMCP

  def init(opts) do
    case OptsValidator.validate_take_opts(opts, @init_opts_schema) do
      {:ok, valid_opts, _} -> {:ok, init_state(valid_opts)}
      {:error, reason} -> {:stop, reason}
    end
  end

  defp init_state(opts) do
    struct!(State, Keyword.put(opts, :on_message, nil))
  end

  @impl GenMCP

  def handle_request(req, channel, state) do
    req
    |> dispatch_request(channel, state)
    |> merge_server_info(state)
  end

  defp dispatch_request(%MCP.DiscoverRequest{}, channel, state) do
    {:result, discover_result(state, channel)}
  end

  defp dispatch_request(%MCP.ListToolsRequest{}, channel, state) do
    {:result, list_tools(state, channel)}
  end

  defp dispatch_request(%MCP.CallToolRequest{} = req, channel, state) do
    handle_tool_call(state, req, channel)
  end

  defp dispatch_request(%MCP.ReadResourceRequest{} = req, channel, state) do
    handle_read_resource(state, req, channel)
  end

  defp dispatch_request(%MCP.ListResourcesRequest{} = req, channel, state) do
    handle_list_resources(state, req, channel)
  end

  defp dispatch_request(%MCP.GetPromptRequest{} = req, channel, state) do
    handle_get_prompt(state, req, channel)
  end

  defp dispatch_request(%MCP.ListPromptsRequest{} = req, channel, state) do
    handle_list_prompts(state, req, channel)
  end

  defp dispatch_request(%MCP.ListResourceTemplatesRequest{} = req, channel, state) do
    handle_list_templates(state, req, channel)
  end

  defp dispatch_request(%MCP.SubscriptionsListenRequest{} = req, channel, state) do
    handle_subscription(state, req, channel)
  end

  # Catch-all: a request that validated as legal MCP but that this server does
  # not implement. Returns a JSON-RPC "method not found" (-32601) rather than
  # crashing with a FunctionClauseError. Every validable request has a clause
  # above today, so this only fires if the transport validator gains a method
  # before the Suite handles it.
  defp dispatch_request(req, _channel, _state) do
    {:error, {:unsupported_method, request_method(req)}}
  end

  # The method string of a validated request struct, read from its schema — the
  # same source the transport validator dispatches on.
  defp request_method(req) do
    req.__struct__.method()
  end

  @impl GenMCP

  # Accept-and-ignore. Under the stateless HTTP core no client->server
  # notification carries an action the Suite can take:
  # - `notifications/cancelled` is the stdio cancellation mechanism, HTTP
  #   cancels by closing the stream
  # - `progress` targets server-initiated requests, removed from stateless
  # - `roots/list_changed` is not used by a stateless model either
  # - `initialized` is ignored at the transport level
  def handle_notification(_notif, _channel, _state) do
    :ok
  end

  @impl GenMCP

  def handle_message(message, channel, state) do
    reply =
      case state.on_message do
        {:tool, req, tool, tool_state} ->
          handle_tool_message(state, req, tool, message, tool_state, channel)

        {:sub, req, handler, handler_state} ->
          handle_sub_message(state, req, handler, message, handler_state, channel)

        _ ->
          {:stop, {:unexpected_message, message}}
      end

    merge_server_info(reply, state)
  end

  @impl GenMCP

  # Mirrors handle_message/3: forwards a client-close to the active streaming
  # tool's optional `handle_close/3` so it can run cleanup. Return ignored.
  def handle_close(channel, state) do
    case state.on_message do
      {:tool, _req, tool, tool_state} ->
        Tool.handle_close(tool, channel, tool_state)

      {:sub, _req, handler, handler_state} ->
        SubscriptionHandler.handle_close(handler, channel, handler_state)

      _ ->
        :ok
    end
  end

  # -- Extension discovery ----------------------------------------------------

  defp discover_result(state, channel) do
    MCP.discover_result(
      name: state.server_name,
      version: state.server_version,
      title: state.server_title,
      capabilities: capabilities(state, channel)
    )
  end

  # Builds all extensions at once
  defp build_extensions(state) do
    self_extension = self_extension(state)

    extensions = state.extensions
    extensions = [self_extension | extensions]
    _extensions = Enum.map(extensions, &Extension.expand/1)
  end

  defp stream_extensions(state) do
    Stream.concat([self_extension(state)], Stream.map(state.extensions, &Extension.expand/1))
  end

  defp self_extension(state) do
    %State{tools: tools, resources: resources, prompts: prompts} = state
    __MODULE__.SelfExtension.new(tools, resources, prompts)
  end

  defp capabilities(state, channel) do
    extensions = build_extensions(state)

    subscription_flags =
      case expand_subscription_handler(state) do
        nil -> %{}
        handler -> SubscriptionHandler.subscription_capabilities(handler, channel)
      end

    accin = %{tools: false, prompts: false, resources: false, logging: true}

    impl_capabilities =
      Enum.reduce_while(extensions, accin, fn
        _, %{tools: true, prompts: true, resources: true} = acc ->
          {:halt, acc}

        ext, acc ->
          tools = acc.tools || [] != Extension.tools(ext, channel)
          prompts = acc.prompts || [] != Extension.prompts(ext, channel)
          resources = acc.resources || [] != Extension.resources(ext, channel)

          {:cont, %{acc | tools: tools, prompts: prompts, resources: resources, logging: true}}
      end)

    Enum.reduce(subscription_flags, impl_capabilities, fn
      {:tools_list_changed, true}, acc ->
        add_capability_flag(acc, :tools, :listChanged, true)

      {:prompts_list_changed, true}, acc ->
        add_capability_flag(acc, :prompts, :listChanged, true)

      {:resources_list_changed, true}, acc ->
        add_capability_flag(acc, :resources, :listChanged, true)

      {:resources_updated, true}, acc ->
        add_capability_flag(acc, :resources, :subscribe, true)
    end)
  end

  @spec add_capability_flag(
          map,
          :tools | :resources | :prompts,
          :listChanged | :subscribe,
          boolean
        ) :: map
  defp add_capability_flag(map, scope, capability, bool) do
    case map do
      %{^scope => atom} when atom in [nil, true, false] ->
        Map.put(map, scope, %{capability => bool})

      %{} ->
        put_in(map[scope][capability], bool)
    end
  end

  defp stream_resource_repos(state, channel, mode \\ :expand) do
    stream =
      state
      |> stream_extensions()
      |> Stream.flat_map(fn ext -> Extension.resources(ext, channel) end)

    case mode do
      :expand -> Stream.map(stream, &ResourceRepo.expand/1)
      :bare -> stream
    end
  end

  defp stream_prompt_repos(state, channel, mode \\ :expand) do
    stream =
      state
      |> stream_extensions()
      |> Stream.flat_map(fn ext -> Extension.prompts(ext, channel) end)

    case mode do
      :expand -> Stream.map(stream, &PromptRepo.expand/1)
      :bare -> stream
    end
  end

  # -- Tools ------------------------------------------------------------------

  defp list_tools(state, channel) do
    # tools/list is a single aggregated result, so the cache hint is combined
    # across every listed tool (public iff all public, minimum ttl).
    tools =
      state
      |> build_extensions()
      |> Enum.flat_map(&Extension.tools(&1, channel))
      |> Enum.map(&Tool.expand/1)
      |> Enum.uniq_by(& &1.name)

    cache_control =
      Enum.reduce(tools, {nil, nil}, fn tool, acc ->
        merge_cache(acc, Tool.cache_control(tool))
      end)

    tools
    |> Enum.map(&Tool.describe/1)
    |> MCP.list_tools_result(cache_opts(cache_control))
  end

  defp handle_tool_call(state, %MCP.CallToolRequest{} = req, channel) do
    case resolve_tool(state, req, channel) do
      {:ok, tool} -> call_tool(state, req, tool, channel)
      {:error, _} = err -> err
    end
  end

  defp resolve_tool(state, %MCP.CallToolRequest{} = req, channel) do
    tool_name = req.params.name

    state
    |> stream_extensions()
    |> Stream.flat_map(&Extension.tools(&1, channel))
    |> Stream.map(&Tool.expand/1)
    |> Enum.find(fn %{name: name} -> name == tool_name end)
    |> case do
      nil -> {:error, {:unknown_tool, tool_name}}
      tool -> {:ok, tool}
    end
  end

  defp call_tool(state, req, tool, channel) do
    case decode_tool_call_request_state(req, tool, channel) do
      {:ok, req} ->
        result = Tool.call(tool, req, channel)
        to_tool_result(state, req, tool, result, channel)

      {:error, _} = err ->
        err
    end
  end

  defp decode_tool_call_request_state(req, tool, channel) do
    case req do
      %MCP.CallToolRequest{params: %MCP.CallToolRequestParams{requestState: nil}} ->
        {:ok, req}

      %MCP.CallToolRequest{params: %MCP.CallToolRequestParams{requestState: request_state} = ps} =
          ctr
      when is_binary(request_state) ->
        case decode_request_state(request_state, tool, req, channel) do
          {:ok, data} -> {:ok, %{ctr | params: %{ps | requestState: data}}}
          {:error, :expired} -> {:error, :expired_request_state}
          {:error, :invalid} -> {:error, :invalid_request_state}
        end
    end
  end

  defp handle_tool_message(state, req, tool, message, tool_state, channel) do
    result = Tool.handle_message(tool, message, channel, tool_state)
    to_tool_result(state, req, tool, result, channel)
  end

  defp to_tool_result(state, req, tool, result, channel) do
    case result do
      {:result, result} ->
        {:result, result}

      {:error, error} ->
        {:error, error}

      {:stream, tool_state} ->
        {:stream, %{state | on_message: {:tool, req, tool, tool_state}}}

      {:input_required, input_requests, request_state} ->
        to_input_required_tool_result(req, tool, input_requests, request_state, channel)
    end
  end

  defp to_input_required_tool_result(req, tool, input_requests, request_state, channel) do
    {:result,
     %MCP.InputRequiredResult{
       inputRequests: input_requests,
       requestState: encode_request_state(request_state, tool, req, channel),
       resultType: "input-required"
     }}
  end

  defp encode_request_state(request_state, tool, req, channel) do
    hashdata = tool_request_state_unicity_data(tool, req)
    GenMCP.Token.encrypt(channel, {:reqstate, hashdata}, request_state)
  end

  defp decode_request_state(request_state, tool, req, channel) do
    hashdata = tool_request_state_unicity_data(tool, req)
    GenMCP.Token.decrypt(channel, {:reqstate, hashdata}, request_state)
  end

  @doc false
  def tool_request_state_unicity_data(tool, req) do
    # Unicity of tokens is based on the tool and request params. Request ID
    # change over multiple repeats. For now we include all the tool, meaning the
    # `arg` too, which should invalidate the request if the arg changes (for
    # instance if an extension sees different meta on the channel, based on
    # authentication)
    #
    # Note that all this data is hashed as an unicity token, it is not packed in
    # the state.
    %{tool: tool, params: req.params.arguments}
  end

  # -- Subscriptions ----------------------------------------------------------

  defp handle_subscription(state, req, channel) do
    case expand_subscription_handler(state) do
      nil ->
        {:error, {:unsupported_method, request_method(req)}}

      handler ->
        result = SubscriptionHandler.subscribe(handler, req, channel)

        case result do
          {:stream, honored_filter, handler_state} ->
            ack = notif_ack_from_req(req, honored_filter)
            _ = Channel.send_notification(channel, ack)
            {:stream, %{state | on_message: {:sub, req, handler, handler_state}}}

          {:stop, reason} ->
            {:error, reason}
        end
    end
  end

  defp expand_subscription_handler(state) do
    case state.subscription_handler do
      nil -> nil
      handler -> SubscriptionHandler.expand(handler)
    end
  end

  defp notif_ack_from_req(req, new_filter) do
    %MCP.SubscriptionsAcknowledgedNotification{
      params: %MCP.SubscriptionsAcknowledgedNotificationParams{
        _meta: %MCP.NotificationMetaObject{
          "io.modelcontextprotocol/subscriptionId": req.id
        },
        notifications: new_filter
      }
    }
  end

  defp handle_sub_message(state, req, handler, message, handler_state, channel) do
    result = SubscriptionHandler.handle_message(handler, message, channel, handler_state)

    case result do
      {:stream, handler_state} ->
        {:stream, %{state | on_message: {:sub, req, handler, handler_state}}}

      {:stop, reason} ->
        result =
          %MCP.SubscriptionsListenResult{
            resultType: "complete",
            _meta: %MCP.SubscriptionsListenResultMeta{
              "io.modelcontextprotocol/subscriptionId": req.id
            }
          }

        {:result, result, reason}
    end
  end

  # -- Resources --------------------------------------------------------------

  defp handle_list_resources(state, req, channel) do
    method = "resources/list"

    cursor =
      case req do
        %{params: %{cursor: global_cursor}} when is_binary(global_cursor) -> global_cursor
        _ -> nil
      end

    case decode_pagination(cursor, method, channel) do
      {:ok, pagination} ->
        {resources, next_pagination, cache_control} = list_resources(state, pagination, channel)

        result =
          MCP.list_resources_result(
            resources,
            encode_pagination(next_pagination, method, channel),
            cache_opts(cache_control)
          )

        {:result, result}

      {:error, _} = err ->
        err
    end
  end

  defp list_resources(state, pagination, channel) do
    repos = state |> stream_resource_repos(channel, :bare) |> Enum.to_list()

    paginate_repos(repos, pagination, fn repo, repo_cursor ->
      repo = ResourceRepo.expand(repo)
      {list, cursor} = ResourceRepo.list_resources(repo, repo_cursor, channel)
      cache_control = ResourceRepo.cache_control(repo)
      {list, cursor, cache_control}
    end)
  end

  # req is not used because templates are not paginated
  defp handle_list_templates(state, _req, channel) do
    {templates, cache_control} =
      state
      |> stream_resource_repos(channel)
      |> Enum.uniq_by(& &1.prefix)
      |> Enum.flat_map_reduce({nil, nil}, fn
        %{template: nil}, acc ->
          {[], acc}

        %{template: %{uriTemplate: %Texture.UriTemplate{raw: raw}} = template} = repo, acc ->
          cache_control = ResourceRepo.cache_control(repo)

          # Build the ResourceTemplate struct using the raw template string
          {[
             struct!(
               MCP.ResourceTemplate,
               template
               |> Map.put(:uriTemplate, raw)
               |> Map.delete(:__struct__)
             )
           ], merge_cache(acc, cache_control)}
      end)

    result = MCP.list_resource_templates_result(templates, cache_opts(cache_control))
    {:result, result}
  end

  defp handle_read_resource(state, req, channel) do
    uri = req.params.uri

    case find_resource_repo_for_uri(state, uri, channel) do
      {:ok, repo} ->
        case ResourceRepo.read_resource(repo, uri, channel) do
          {:ok, result} -> {:result, result}
          {:error, reason} -> {:error, reason}
        end

      {:error, :no_matching_repo} ->
        {:error, {:resource_not_found, uri}}
    end
  end

  defp find_resource_repo_for_uri(state, uri, channel) do
    find_repo(uri, stream_resource_repos(state, channel))
  end

  # -- Prompts ----------------------------------------------------------------

  defp handle_list_prompts(state, req, channel) do
    method = "prompts/list"

    cursor =
      case req do
        %{params: %{cursor: global_cursor}} when is_binary(global_cursor) -> global_cursor
        _ -> nil
      end

    case decode_pagination(cursor, method, channel) do
      {:ok, pagination} ->
        {prompts, next_pagination, cache_control} = list_prompts(state, pagination, channel)

        result =
          MCP.list_prompts_result(
            prompts,
            encode_pagination(next_pagination, method, channel),
            cache_opts(cache_control)
          )

        {:result, result}

      {:error, _} = err ->
        err
    end
  end

  defp list_prompts(state, pagination, channel) do
    repos = state |> stream_prompt_repos(channel, :bare) |> Enum.to_list()

    paginate_repos(repos, pagination, fn repo, repo_cursor ->
      repo = PromptRepo.expand(repo)
      {list, cursor} = PromptRepo.list_prompts(repo, repo_cursor, channel)
      cache_control = PromptRepo.cache_control(repo)
      {list, cursor, cache_control}
    end)
  end

  defp handle_get_prompt(state, req, channel) do
    {name, arguments} =
      case req do
        %{params: %{name: name, arguments: arguments}} when is_map(arguments) -> {name, arguments}
        %{params: %{name: name}} -> {name, %{}}
      end

    case find_prompt_repo_for_name(state, name, channel) do
      {:ok, repo} ->
        case PromptRepo.get_prompt(repo, name, arguments, channel) do
          {:ok, result} -> {:result, result}
          {:error, reason} -> {:error, reason}
        end

      {:error, :no_matching_repo} ->
        {:error, {:prompt_not_found, name}}
    end
  end

  defp find_prompt_repo_for_name(state, uri, channel) do
    find_repo(uri, stream_prompt_repos(state, channel))
  end

  # -- Helpers ----------------------------------------------------------------

  # Stamps the server info (spec: servers SHOULD identify themselves on every
  # response) into the `_meta` of any result reply, keeping a serverInfo the
  # handler set itself. The Implementation struct is built only when a result
  # is actually returned.

  defp merge_server_info(reply, %{send_server_info: false}) do
    reply
  end

  defp merge_server_info({:result, result}, state) do
    {:result, put_server_info(result, server_info(state))}
  end

  defp merge_server_info({:result, result, reason}, state) do
    {:result, put_server_info(result, server_info(state)), reason}
  end

  defp merge_server_info(reply, _state) do
    reply
  end

  defp put_server_info(%{_meta: nil} = result, server_info) do
    %{
      result
      | _meta: %MCP.ResultMetaObject{"io.modelcontextprotocol/serverInfo": server_info}
    }
  end

  defp put_server_info(
         %{_meta: %_{"io.modelcontextprotocol/serverInfo": nil} = meta} = result,
         server_info
       ) do
    %{result | _meta: %{meta | "io.modelcontextprotocol/serverInfo": server_info}}
  end

  # Struct response without the key, or with the key but not nil, skip
  defp put_server_info(%{_meta: %_{}} = result, _server_info) do
    result
  end

  defp put_server_info(%{_meta: %{} = meta} = result, server_info) do
    case meta do
      %{"io.modelcontextprotocol/serverInfo": _} ->
        result

      %{"io.modelcontextprotocol/serverInfo" => _} ->
        result

      _ ->
        %{result | _meta: Map.put(meta, :"io.modelcontextprotocol/serverInfo", server_info)}
    end
  end

  defp server_info(state) do
    %{server_name: name, server_version: version, server_title: title} = state
    MCP.server_info(name: name, version: version, title: title)
  end

  defp find_repo(identifier, repos) do
    found_result = Enum.find(repos, fn repo -> String.starts_with?(identifier, repo.prefix) end)

    case found_result do
      nil -> {:error, :no_matching_repo}
      repo -> {:ok, repo}
    end
  end

  defp paginate_repos(repos, {repo_index, repo_cursor}, list_fun) do
    paginate_repos(repos, 0, repo_index, repo_cursor, list_fun)
  end

  defp paginate_repos([_ | repos], index, repo_index, repo_cursor, list_fun)
       when index < repo_index do
    paginate_repos(repos, index + 1, repo_index, repo_cursor, list_fun)
  end

  defp paginate_repos([repo | repos], repo_index, repo_index, repo_cursor, list_fun) do
    case list_fun.(repo, repo_cursor) do
      # no more items, bump repo index and immediately try next repo
      {[], _, _} ->
        paginate_repos(repos, repo_index + 1, repo_index + 1, _repo_cursor = nil, list_fun)

      # some result but no more pages, bump repo index for next request.
      # some edge case, we do not want to return a pagination cursor if this
      # is the last repository
      {list, nil, cache_control} when repos == [] ->
        {list, nil, cache_control}

      {list, nil, cache_control} ->
        {list, {repo_index + 1, _repo_cursor = nil}, cache_control}

      # some results with a cursor so no bump
      {list, repo_cursor, cache_control} ->
        {list, {repo_index, repo_cursor}, cache_control}
    end
  end

  defp paginate_repos([], _index, _repo_index, _repo_cursor, _list_fun) do
    {[], nil, {MCP.default_cache_scope(), MCP.default_ttl_ms()}}
  end

  defp encode_pagination(nil, _method, _channel) do
    nil
  end

  defp encode_pagination(pagination, method, channel) do
    GenMCP.Token.encrypt(channel, {:cursor, method}, pagination)
  end

  defp decode_pagination(nil, _method, _channel) do
    {:ok, {_repository_index = 0, _repository_cursor = nil}}
  end

  defp decode_pagination(token, method, channel) do
    case GenMCP.Token.decrypt(channel, {:cursor, method}, token) do
      {:ok, data} -> {:ok, data}
      {:error, :expired} -> {:error, :expired_cursor}
      {:error, :invalid} -> {:error, :invalid_cursor}
    end
  end

  @spec merge_cache(maybe_cache_control, maybe_cache_control) :: cache_control
        when cache_control: {:public | :private, non_neg_integer},
             maybe_cache_control: cache_control | {nil, nil}
  defp merge_cache({scope_a, ttl_a}, {scope_b, ttl_b}) do
    {merge_cache_scope(scope_a, scope_b), merge_ttl(ttl_a, ttl_b)}
  end

  defp merge_cache_scope(a, b) do
    case {a, b} do
      {nil, b} when b in [:public, :private] -> b
      {:private, _} -> :private
      {_, :private} -> :private
      {:public, :public} -> :public
    end
  end

  defp merge_ttl(a, b) do
    case {a, b} do
      {nil, b} -> b
      _ -> min(a, b)
    end
  end

  defp cache_opts({nil, ttl_ms}) do
    cache_opts({:private, ttl_ms})
  end

  defp cache_opts({cache_scope, nil}) do
    cache_opts({cache_scope, 0})
  end

  defp cache_opts({cache_scope, ttl_ms}) do
    [cache_scope: cache_scope, ttl_ms: ttl_ms]
  end
end
