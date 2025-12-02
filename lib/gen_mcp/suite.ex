# quokka:skip-module-reordering
defmodule GenMCP.Suite do
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
      server_title: [type: :string],
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
          "A list `GenMCP.Suite.Extension` implementations" <>
            " to add more tools, resource repositories and prompt repositories."
        )
    )

  @moduledoc """
  A `GenMCP` implementation providing tools, resources, and prompts through a
  composable extension system.

  This module does not directly export functions or callbacks. Please refer to
  the [GenMCP Suite guide](guides/002.using-mcp-suite.md) to use the suite.
  """

  @behaviour GenMCP

  alias GenMCP.MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.Suite.Extension
  alias GenMCP.Suite.PromptRepo
  alias GenMCP.Suite.ResourceRepo
  alias GenMCP.Suite.Tool
  alias GenMCP.Utils.OptsValidator

  require Logger
  require Record

  @supported_protocol_versions GenMCP.supported_protocol_versions()

  defmodule State do
    @moduledoc false

    @enforce_keys [
      :client_capabilities,
      :default_assigns,
      :extensions,
      :prompt_prefixes,
      :prompt_repos,
      :resource_prefixes,
      :resource_repos,
      :server_info,
      :session_id,
      :token_key,
      :tool_names,
      :tools_map,
      :trackers
    ]
    defstruct @enforce_keys
  end

  Record.defrecordp(:tracker, id: nil, tool_name: nil, channel: nil, tag: nil)

  # TODO we need a new behaviour to handle listChanged notifications.
  #
  # * behaviour Suite.SessionController
  # * when the client listens from a GET request, we start a stream and keep the
  #   channel
  # * unknown messages from handle_info are given to the session controller with
  #   that channel.
  # * handle_info messages should be delivered even if there is no GET stream,
  #   but the channel would be a special channel struct that just ignores
  #   notifications given to it.
  # * the session controller callback should return a {:noreply, channel},
  #   {:noreply, channel, actions} or {:stop, reason, channel} tuple. Actions
  #   are for refreshing tools/repos.
  # * assigns from that returned channel would replace the default_assigns
  #   (which are still overriden by copied conn assigns). Currently the the
  #   default_assigns are taken from the initialize request. We should call a
  #   on_initialize callback on the session controller instead.
  # * to not have those assigns overriden by the :assigns option of the
  #   transport plug, that option must not be used by the plug anymore, and just
  #   forwared to the server implementation. The server would initialize with
  #   that as the default assigns (+ gen_mcp_session_id)
  # * the session controller SHOULD NOT send notifications to the channel for
  #   list changedlike list changed (for tools, resources, etc), but rather
  #   return actions such as [:refresh_tools, :refresh_all]. This would make the
  #   Suite server recompute extensions to get new tools/repos lists and send
  #   the notification itself.
  # * the session controller should send the resources updated notifications
  #   itself.

  @init_opts_schema init_opts_schema
  @doc false
  def init_opts_schema do
    @init_opts_schema
  end

  @impl true
  def init(session_id, opts) do
    case OptsValidator.validate_take_opts(opts, @init_opts_schema) do
      {:ok, valid_opts, _} -> {:ok, {:__init__, session_id, valid_opts}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_request(
        %MCP.InitializeRequest{} = req,
        channel,
        {:__init__, session_id, opts} = init_state
      ) do
    with :ok <- check_protocol_version(req),
         {:ok, state} <- initialize(req, channel, session_id, opts) do
      init_result =
        MCP.intialize_result(
          capabilities: MCP.capabilities(capabilities(state)),
          server_info: state.server_info
        )

      {:reply, {:result, init_result}, state}
    else
      {:error, reason} = err ->
        {:stop, {:shutdown, {:init_failure, reason}}, err, init_state}
    end
  end

  def handle_request(%MCP.InitializeRequest{} = _req, _channel, state) do
    reason = :already_initialized
    {:stop, {:shutdown, {:init_failure, reason}}, {:error, reason}, state}
  end

  # Handling requests requires having handled the first initialization request.
  # Once this is done, we accept other requests even before receiving the client
  # initialized notification.
  #
  # According to the docs:
  #
  # > The server SHOULD NOT send requests other than pings and logging before
  # > receiving the initialized notification.
  #
  # Our interpretation is that this notification tells that the client is ready
  # to handle server requests, not that it will not send client requests.
  #
  # Also, this is much more simple as we do not have to deal with http requests
  # delays changing order of delivery and do not have to buffer requests until
  # the client notification is received.
  def handle_request(_req, _, {:__init__, _, _} = state) do
    {:error, :not_initialized, state}
  end

  # TODO handle cursor?
  def handle_request(%MCP.ListToolsRequest{}, _, state) do
    %{tool_names: tool_names, tools_map: tools_map} = state

    tools =
      Enum.map(tool_names, fn
        name -> tools_map |> Map.fetch!(name) |> Tool.describe()
      end)

    {:reply, {:result, MCP.list_tools_result(tools)}, state}
  end

  def handle_request(%MCP.CallToolRequest{} = req, channel, state) do
    tool_name = req.params.name

    case state.tools_map do
      %{^tool_name => tool} ->
        channel = channel_defaults(channel, state)

        case call_tool(req, tool, channel, state) do
          {:result, result, _chan} ->
            {:reply, {:result, result}, state}

          {:error, reason, _chan} ->
            {:reply, {:error, reason}, state}

          {:async, {tag, req}, chan} ->
            # TODO send progress when starting async with a task without any
            # server request.

            # the tracking process will set the ID of the request
            {_req, state} = track_request(state, tool, tag, req, chan)
            {:reply, :stream, state}
        end

      _ ->
        {:reply, {:error, {:unknown_tool, tool_name}}, state}
    end
  end

  def handle_request(%MCP.ListResourcesRequest{} = req, channel, state) do
    cursor =
      case req do
        %{params: %{cursor: global_cursor}} when is_binary(global_cursor) -> global_cursor
        _ -> nil
      end

    case decode_pagination(cursor, state) do
      {:ok, pagination} ->
        channel = channel_defaults(channel, state)
        {resources, next_pagination} = list_resources(pagination, channel, state)

        result =
          MCP.list_resources_result(
            resources,
            encode_pagination(next_pagination, state)
          )

        {:reply, {:result, result}, state}

      {:error, _} = err ->
        reply_pagination_error(err, state)
    end
  end

  def handle_request(%MCP.ReadResourceRequest{} = req, channel, state) do
    uri = req.params.uri

    case find_resource_repo_for_uri(state, uri) do
      {:ok, repo} ->
        channel = channel_defaults(channel, state)

        case ResourceRepo.read_resource(repo, uri, channel) do
          {:ok, result} -> {:reply, {:result, result}, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, :no_matching_repo} ->
        {:reply, {:error, {:resource_not_found, uri}}, state}
    end
  end

  def handle_request(%MCP.ListResourceTemplatesRequest{}, _channel, state) do
    templates =
      Enum.flat_map(state.resource_prefixes, fn prefix ->
        case Map.fetch!(state.resource_repos, prefix).template do
          nil ->
            []

          %{uriTemplate: parsed_template} = tpl_desc ->
            # Build the ResourceTemplate struct using the raw template string
            [
              struct!(
                MCP.ResourceTemplate,
                tpl_desc
                |> Map.put(:uriTemplate, parsed_template.raw)
                |> Map.delete(:__struct__)
              )
            ]
        end
      end)

    result = MCP.list_resource_templates_result(templates)
    {:reply, {:result, result}, state}
  end

  def handle_request(%MCP.ListPromptsRequest{} = req, channel, state) do
    cursor =
      case req do
        %{params: %{cursor: global_cursor}} when is_binary(global_cursor) -> global_cursor
        _ -> nil
      end

    case decode_pagination(cursor, state) do
      {:ok, pagination} ->
        channel = channel_defaults(channel, state)
        {prompts, next_pagination} = list_prompts(pagination, channel, state)

        result =
          MCP.list_prompts_result(
            prompts,
            encode_pagination(next_pagination, state)
          )

        {:reply, {:result, result}, state}

      {:error, _} = err ->
        reply_pagination_error(err, state)
    end
  end

  def handle_request(%MCP.GetPromptRequest{} = req, channel, state) do
    {name, arguments} =
      case req do
        %{params: %{name: name, arguments: arguments}} when is_map(arguments) -> {name, arguments}
        %{params: %{name: name}} -> {name, %{}}
      end

    case find_prompt_repo_for_name(state, name) do
      {:ok, repo} ->
        channel = channel_defaults(channel, state)

        case PromptRepo.get_prompt(repo, name, arguments, channel) do
          {:ok, result} -> {:reply, {:result, result}, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, :no_matching_repo} ->
        {:reply, {:error, {:prompt_not_found, name}}, state}
    end
  end

  def handle_request(req, _, state) do
    :telemetry.execute([:gen_mcp, :suite, :error, :unknown_request], %{}, %{
      session_id: state.session_id,
      request: req
    })

    {:reply, {:error, :unsupported_request, req}, state}
  end

  @impl true
  def handle_notification(%MCP.InitializedNotification{}, state) do
    capabilities =
      case state.client_capabilities do
        %{__init: real_capas} -> real_capas
        already_swapped -> already_swapped
      end

    {:noreply, %{state | client_capabilities: capabilities}}
  end

  def handle_notification(%MCP.CancelledNotification{}, state) do
    # Cancelled notifications are currently ignored
    {:noreply, state}
  end

  def handle_notification(%MCP.RootsListChangedNotification{}, state) do
    # Roots list changed notifications are currently ignored
    {:noreply, state}
  end

  @impl true
  def handle_info({task_ref, _} = msg, state) when is_reference(task_ref) do
    state =
      case handle_task_info(msg, state) do
        :error ->
          log_unhandled_info(msg)
          state

        {:ok, state} ->
          state
      end

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason} = msg, state) do
    state =
      case handle_task_info(msg, state) do
        :error ->
          # No error log on stale down messages
          # TODO monitor channels and look for channel disconnection

          state

        {:ok, state} ->
          state
      end

    {:noreply, state}
  end

  def handle_info(msg, state) do
    log_unhandled_info(msg)
    {:noreply, state}
  end

  defp log_unhandled_info(msg) do
    # This should be handled by the session controller, no need for
    # telemetry logging here
    Logger.error("unhandled info message in #{inspect(__MODULE__)}: #{inspect(msg)}")
  end

  defp handle_task_info(task_msg, state) do
    {task_ref, task_result, demonitor?} =
      case task_msg do
        {ref, value} -> {ref, {:ok, value}, true}
        {:DOWN, ref, :process, _pid, reason} -> {ref, {:error, reason}, false}
      end

    case List.keytake(state.trackers, task_ref, tracker(:id)) do
      nil ->
        :error

      {tracker, trackers} ->
        if demonitor? do
          _ = Process.demonitor(task_ref, [:flush])
        end

        handle_task_continuation(tracker, trackers, task_result, state)
    end
  end

  defp handle_task_continuation(tracker, new_trackers, task_result, state) do
    tracker(tool_name: tool_name, channel: channel, tag: tag) = tracker
    state = %{state | trackers: new_trackers}
    tool = Map.fetch!(state.tools_map, tool_name)

    case Tool.continue(tool, {tag, task_result}, channel) do
      # using the previous channel so we are sure it's the right one
      {:result, result, _chan} ->
        ^channel = Channel.send_result(channel, result)

        {:ok, state}

      {:async, {tag, req}, chan} ->
        # TODO send progress when continuing async with a task without any
        # server request.

        # the tracking process will set the ID of the request
        {_req, state} = track_request(state, tool, tag, req, chan)
        {:ok, state}

      {:error, reason, _chan} ->
        ^channel = Channel.send_error(channel, reason)

        {:ok, state}
    end
  end

  defp initialize(init_req, channel, session_id, opts) do
    # For tools and resources we keep a list of names/prefixes to preserve the
    # original order given in the options. This is especially useful for
    # resources where prefixes can overlap.
    #
    # TODO document that order matters for resources.

    %{
      params: %{
        # Client capabilities must not be enabled before we receive the client
        # initialized notification. We keep them under an __init key and swap the
        # result when we get that notification. We do not provide a struct because.
        #
        # Client capabilities are not used yet anyway.
        capabilities: %MCP.ClientCapabilities{} = real_client_capabilities
      }
    } = init_req

    client_capabilities = %{__init: real_client_capabilities}

    # For now we keep assigns from the initialize request. This is bad since
    # they are nothing special. We should implement the SessionController stuff.
    default_assigns = channel.assigns

    self_extension =
      opts
      |> Keyword.take([:tools, :resources, :prompts])
      |> __MODULE__.SelfExtension.new()

    extensions = Keyword.get(opts, :extensions, [])

    extensions = [self_extension | extensions]
    extensions = Enum.map(extensions, &Extension.expand/1)

    state = %State{
      session_id: session_id,
      client_capabilities: client_capabilities,
      extensions: extensions,
      server_info: build_server_info(opts),
      token_key: random_string(64),
      trackers: empty_trackers(),
      default_assigns: default_assigns,

      # Empty before first extensions call

      tool_names: [],
      tools_map: %{},
      resource_prefixes: [],
      resource_repos: %{},
      prompt_prefixes: [],
      prompt_repos: %{}
    }

    ext_channel = channel_defaults(channel, state)
    state = refresh_extensions(state, ext_channel, :all)

    {:ok, state}
  end

  defp capabilities(state) do
    [
      tools: map_size(state.tools_map) > 0,
      prompts: map_size(state.prompt_repos) > 0,
      resources: map_size(state.resource_repos) > 0
    ]
  end

  defp refresh_extensions(state, channel, :all) do
    state
    |> refresh_extensions(channel, :tools)
    |> refresh_extensions(channel, :resources)
    |> refresh_extensions(channel, :prompts)
  end

  defp refresh_extensions(state, channel, :tools) do
    tools =
      state.extensions
      |> Enum.flat_map(&Extension.tools(&1, channel))
      |> Enum.map(&Tool.expand/1)

    tool_names = Enum.map(tools, & &1.name)
    tools_map = Map.new(tools, fn %{name: name} = tool -> {name, tool} end)

    %{state | tool_names: tool_names, tools_map: tools_map}
  end

  defp refresh_extensions(state, channel, :resources) do
    resources =
      state.extensions
      |> Enum.flat_map(&Extension.resources(&1, channel))
      |> Enum.map(&ResourceRepo.expand/1)

    resource_prefixes = Enum.map(resources, & &1.prefix)
    resource_repos = Map.new(resources, fn %{prefix: prefix} = repo -> {prefix, repo} end)

    %{state | resource_prefixes: resource_prefixes, resource_repos: resource_repos}
  end

  defp refresh_extensions(state, channel, :prompts) do
    prompts =
      state.extensions
      |> Enum.flat_map(&Extension.prompts(&1, channel))
      |> Enum.map(&PromptRepo.expand/1)

    prompt_prefixes = Enum.map(prompts, & &1.prefix)
    prompt_repos = Map.new(prompts, fn %{prefix: prefix} = repo -> {prefix, repo} end)

    %{state | prompt_prefixes: prompt_prefixes, prompt_repos: prompt_repos}
  end

  defp build_server_info(init_opts) do
    name = Keyword.fetch!(init_opts, :server_name)
    version = Keyword.fetch!(init_opts, :server_version)
    title = Keyword.get(init_opts, :server_title, nil)
    MCP.server_info(name: name, version: version, title: title)
  end

  defp check_protocol_version(%MCP.InitializeRequest{} = req) do
    case req do
      %{params: %{protocolVersion: version}} when version in @supported_protocol_versions -> :ok
      %{params: %{protocolVersion: version}} -> {:error, {:unsupported_protocol, version}}
    end
  end

  defp channel_defaults(%Channel{} = channel, state) do
    Channel.with_default_assigns(channel, state.default_assigns)
  end

  defp random_string(len) do
    :crypto.strong_rand_bytes(len) |> Base.encode64(padding: false) |> binary_part(0, len)
  end

  defp encode_pagination(nil, _state) do
    nil
  end

  defp encode_pagination(pagination, state) do
    sign_token(pagination, state)
  end

  defp decode_pagination(nil, _state) do
    {:ok, {_repository_index = 0, _repository_cursor = nil}}
  end

  defp decode_pagination(token, state) do
    case verify_token(token, _max_age = to_timeout(hour: 2), state) do
      {:ok, data} -> {:ok, data}
      {:error, :expired} -> {:error, :expired_cursor}
      {:error, :invalid} -> {:error, :invalid_cursor}
    end
  end

  defp sign_token(data, state) do
    Plug.Crypto.sign(state.token_key, _salt = state.session_id, data)
  end

  defp verify_token(token, max_age, state) do
    Plug.Crypto.verify(state.token_key, _salt = state.session_id, token, max_age: max_age)
  end

  defp reply_pagination_error(err, state) do
    case err do
      {:error, :invalid_cursor} ->
        {:reply, {:error, :invalid_cursor}, state}

      {:error, :expired_cursor} ->
        {:reply, {:error, :expired_cursor}, state}
    end
  end

  defp call_tool(req, tool, channel, _state) do
    Tool.call(tool, req, channel)
  end

  defp list_resources({repo_index, repo_cursor}, channel, state) do
    max_index = length(state.resource_prefixes) - 1

    case resource_repo_at_index(repo_index, state) do
      {:ok, repo} ->
        case ResourceRepo.list_resources(repo, repo_cursor, channel) do
          # no more resources, bump repo index and immediately try next repo
          {[], _} -> list_resources({repo_index + 1, _repo_cursor = nil}, channel, state)
          # some result but no more pages, bump repo index for next request.
          # some edge case, we do not want to return a pagination cursor if this
          # is the last repository
          {list, nil} when repo_index == max_index -> {list, nil}
          {list, nil} -> {list, {repo_index + 1, _repo_cursor = nil}}
          # some results with a cursor so no bump
          {list, repo_cursor} -> {list, {repo_index, repo_cursor}}
        end

      {:error, :end_of_repos} ->
        {[], nil}
    end
  end

  defp resource_repo_at_index(index, state) do
    repo_at_index(state.resource_prefixes, index, state.resource_repos)
  end

  defp find_resource_repo_for_uri(state, uri) do
    find_repo(state.resource_prefixes, uri, state.resource_repos)
  end

  defp list_prompts({repo_index, repo_cursor}, channel, state) do
    max_index = length(state.prompt_prefixes) - 1

    case prompt_repo_at_index(repo_index, state) do
      {:ok, repo} ->
        case PromptRepo.list_prompts(repo, repo_cursor, channel) do
          # no more prompts, bump repo index and immediately try next repo
          {[], _} -> list_prompts({repo_index + 1, _repo_cursor = nil}, channel, state)
          # some result but no more pages, bump repo index for next request.
          # some edge case, we do not want to return a pagination cursor if this
          # is the last repository
          {list, nil} when repo_index == max_index -> {list, nil}
          {list, nil} -> {list, {repo_index + 1, _repo_cursor = nil}}
          # some results with a cursor so no bump
          {list, repo_cursor} -> {list, {repo_index, repo_cursor}}
        end

      {:error, :end_of_repos} ->
        {[], nil}
    end
  end

  defp prompt_repo_at_index(index, state) do
    repo_at_index(state.prompt_prefixes, index, state.prompt_repos)
  end

  defp find_prompt_repo_for_name(state, name) do
    find_repo(state.prompt_prefixes, name, state.prompt_repos)
  end

  defp repo_at_index(oredered_keys, index, map) do
    case Enum.at(oredered_keys, index) do
      nil -> {:error, :end_of_repos}
      prefix -> {:ok, Map.fetch!(map, prefix)}
    end
  end

  defp find_repo(prefixes, identifier, repos) do
    prefixes
    |> Enum.find_value(fn prefix ->
      if String.starts_with?(identifier, prefix) do
        Map.fetch!(repos, prefix)
      end
    end)
    |> case do
      nil -> {:error, :no_matching_repo}
      repo -> {:ok, repo}
    end
  end

  # TODO we should also handle timeouts for trackers. The tools should be able
  # to return a timeout in an :async tuple. On timeout we would deliver the
  # {:error, :timeout} result. But we would need to handle late client replies
  # to return a "too late" error. So when the timeout occurs we should replace
  # the tracker with a :timeout data so we know what happened can can tell the
  # client.

  defp empty_trackers do
    []
  end

  defp track_request(state, tool, tag, req, chan) do
    {track_id, server_request} =
      case req do
        # TODO if an actual elicitation request we must create a new ID and bump
        # it in the state (or use erlang.unique_integer)
        task_ref when is_reference(task_ref) -> {task_ref, nil}
      end

    # storing the request in the trackers. If for some reason a tool returns the
    # same reference twice, we do not support it

    case List.keymember?(state.trackers, track_id, tracker(:id)) do
      true ->
        raise "duplicated track request #{inspect(track_id)} returned from tool #{inspect(tool.name)}"

      false ->
        :ok
    end

    state =
      update_in(
        state.trackers,
        &[tracker(id: track_id, tool_name: tool.name, channel: chan, tag: tag) | &1]
      )

    {server_request, state}
  end
end
