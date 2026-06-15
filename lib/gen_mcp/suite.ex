defmodule GenMCP.Suite do
  @moduledoc """
  A `GenMCP` implementation providing tools, resources, and prompts through a
  composable extension system.

  This module does not directly export functions or callbacks. Please refer to
  the [GenMCP Suite guide](guides/002.using-mcp-suite.md) to use the suite.
  """

  # TODO(spec 004): re-implement the stateless `GenMCP` behaviour. The module
  # still has the pre-fork callback shape, so the `@behaviour` declaration and
  # `@impl` annotations are dropped until the rewrite (they only produced
  # stale-callback warnings).

  @behaviour GenMCP

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Suite.Extension
  alias GenMCP.Suite.PromptRepo
  alias GenMCP.Suite.ResourceRepo
  alias GenMCP.Suite.Tool
  alias GenMCP.Utils.OptsValidator

  require Record

  provider_list = fn doc ->
    [
      default: [],
      type: {:list, {:or, [:atom, :mod_arg, :map]}},
      doc:
        doc <>
          " List items can be either module names, `{module, arg}` tuples or a descriptor map."
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
        )
    )

  defmodule State do
    @moduledoc false

    @enforce_keys [
      :server_name,
      :server_version,
      :server_title,
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
    struct!(State, [{:on_message, nil} | opts])
  end

  @impl GenMCP

  def handle_request(%MCP.DiscoverRequest{}, channel, state) do
    {:result, discover_result(state, channel)}
  end

  def handle_request(%MCP.ListToolsRequest{}, channel, state) do
    {:result, list_tools(state, channel)}
  end

  def handle_request(%MCP.CallToolRequest{} = req, channel, state) do
    handle_tool_call(req, channel, state)
  end

  def handle_request(%MCP.ReadResourceRequest{} = req, channel, state) do
    handle_read_resource(req, channel, state)
  end

  def handle_request(%MCP.ListResourcesRequest{} = req, channel, state) do
    handle_list_resources(req, channel, state)
  end

  def handle_request(%MCP.GetPromptRequest{} = req, channel, state) do
    handle_get_prompt(req, channel, state)
  end

  def handle_request(%MCP.ListPromptsRequest{} = req, channel, state) do
    handle_list_prompts(req, channel, state)
  end

  def handle_request(%MCP.ListResourceTemplatesRequest{} = req, channel, state) do
    handle_list_templates(req, channel, state)
  end

  # Catch-all: a request that validated as legal MCP but that this server does
  # not implement. Returns a JSON-RPC "method not found" (-32601) rather than
  # crashing with a FunctionClauseError. Every validable request has a clause
  # above today, so this only fires if the transport validator gains a method
  # before the Suite handles it.
  def handle_request(req, _channel, _state) do
    {:error, {:unsupported_method, request_method(req)}}
  end

  # The method string of a validated request struct, read from its schema — the
  # same source the transport validator dispatches on.
  defp request_method(req) do
    req.__struct__.json_schema().properties.method.const
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
    case state.on_message do
      {:tool, tool, tool_state} -> continue_tool(state, tool, message, channel, tool_state)
      _ -> {:stop, {:unexpected_message, message}}
    end
  end

  # -- Extension discovery ----------------------------------------------------

  defp discover_result(state, channel) do
    extensions = build_extensions(state)

    MCP.discover_result(
      name: state.server_name,
      version: state.server_version,
      title: state.server_title,
      capabilities: capabilities(extensions, channel)
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

  defp capabilities(extensions, channel) do
    accin = %{tools: false, prompts: false, resources: false, logging: true}

    Enum.reduce_while(extensions, accin, fn
      _, %{tools: true, prompts: true, resources: true} = acc ->
        {:halt, acc}

      ext, acc ->
        tools = acc.tools || [] != Extension.tools(ext, channel)
        prompts = acc.prompts || [] != Extension.prompts(ext, channel)
        resources = acc.resources || [] != Extension.resources(ext, channel)

        {:cont, %{acc | tools: tools, prompts: prompts, resources: resources, logging: true}}
    end)
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
    state
    |> build_extensions()
    |> Enum.flat_map(fn ext ->
      ext
      |> Extension.tools(channel)
      |> Enum.map(&Tool.describe/1)
    end)
    |> Enum.uniq_by(& &1.name)
    |> MCP.list_tools_result()
  end

  defp handle_tool_call(%MCP.CallToolRequest{} = req, channel, state) do
    case resolve_tool(state, req, channel) do
      {:ok, tool} -> call_tool(state, req, channel, tool)
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

  defp call_tool(state, req, channel, tool) do
    result = Tool.call(tool, req, channel)
    to_tool_result(state, tool, result)
  end

  defp continue_tool(state, tool, message, channel, tool_state) do
    result = Tool.continue(tool, message, channel, tool_state)
    to_tool_result(state, tool, result)
  end

  defp to_tool_result(state, tool, result) do
    case result do
      {:result, result} -> {:result, result}
      {:error, error} -> {:error, error}
      {:stream, tool_state} -> {:stream, %{state | on_message: {:tool, tool, tool_state}}}
    end
  end

  # -- Resources --------------------------------------------------------------

  defp handle_list_resources(req, channel, state) do
    method = "list/resources"

    cursor =
      case req do
        %{params: %{cursor: global_cursor}} when is_binary(global_cursor) -> global_cursor
        _ -> nil
      end

    case decode_pagination(cursor, method, channel) do
      {:ok, pagination} ->
        {resources, next_pagination} = list_resources(pagination, channel, state)

        result =
          MCP.list_resources_result(
            resources,
            encode_pagination(next_pagination, method, channel)
          )

        {:result, result}

      {:error, _} = err ->
        err
    end
  end

  defp list_resources(pagination, channel, state) do
    repos = state |> stream_resource_repos(channel, :bare) |> Enum.to_list()

    paginate_repos(repos, pagination, fn repo, repo_cursor ->
      ResourceRepo.list_resources(ResourceRepo.expand(repo), repo_cursor, channel)
    end)
  end

  # req is not used because templates are not paginated
  defp handle_list_templates(_req, channel, state) do
    templates =
      state
      |> stream_resource_repos(channel)
      |> Enum.uniq_by(& &1.prefix)
      |> Enum.flat_map(fn
        %{template: nil} ->
          []

        %{template: %{uriTemplate: %Texture.UriTemplate{raw: raw}} = template} ->
          # Build the ResourceTemplate struct using the raw template string
          [
            struct!(
              MCP.ResourceTemplate,
              template
              |> Map.put(:uriTemplate, raw)
              |> Map.delete(:__struct__)
            )
          ]
      end)

    result = MCP.list_resource_templates_result(templates)
    {:result, result}
  end

  defp handle_read_resource(req, channel, state) do
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

  defp handle_list_prompts(req, channel, state) do
    method = "list/prompts"

    cursor =
      case req do
        %{params: %{cursor: global_cursor}} when is_binary(global_cursor) -> global_cursor
        _ -> nil
      end

    case decode_pagination(cursor, method, channel) do
      {:ok, pagination} ->
        {prompts, next_pagination} = list_prompts(pagination, channel, state)

        result =
          MCP.list_prompts_result(
            prompts,
            encode_pagination(next_pagination, method, channel)
          )

        {:result, result}

      {:error, _} = err ->
        err
    end
  end

  defp list_prompts(pagination, channel, state) do
    repos = state |> stream_prompt_repos(channel, :bare) |> Enum.to_list()

    paginate_repos(repos, pagination, fn repo, repo_cursor ->
      PromptRepo.list_prompts(PromptRepo.expand(repo), repo_cursor, channel)
    end)
  end

  defp handle_get_prompt(req, channel, state) do
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
      {[], _} ->
        paginate_repos(repos, repo_index + 1, repo_index + 1, _repo_cursor = nil, list_fun)

      # some result but no more pages, bump repo index for next request.
      # some edge case, we do not want to return a pagination cursor if this
      # is the last repository
      {list, nil} when repos == [] ->
        {list, nil}

      {list, nil} ->
        {list, {repo_index + 1, _repo_cursor = nil}}

      # some results with a cursor so no bump
      {list, repo_cursor} ->
        {list, {repo_index, repo_cursor}}
    end
  end

  defp paginate_repos([], _index, _repo_index, _repo_cursor, _list_fun) do
    {[], nil}
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
end
