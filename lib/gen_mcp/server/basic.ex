defmodule GenMcp.Server.Basic do
  alias GenMcp.Mcp.Entities
  alias GenMcp.Mux.Channel
  alias GenMcp.ResourceRepo
  alias GenMcp.Server
  alias GenMcp.Tool
  require Logger
  require Record

  @behaviour GenMcp.Server

  @supported_protocol_versions GenMcp.supported_protocol_versions()

  defmodule State do
    # We keep tools both as a list and as a map
    @enforce_keys [
      :status,
      :server_info,
      :tool_names,
      :tools_map,
      :resource_prefixes,
      :repos_map,
      :token_key,
      :token_salt,
      :trackers
    ]
    defstruct @enforce_keys
  end

  Record.defrecordp(:tracker, id: nil, tool_name: nil, channel: nil, tag: nil)

  @impl true
  def init(opts) do
    # For tools and resources we keep a list of names/prefixes to preserve the
    # original order given in the options. This is especially useful for
    # resources where prefixes can overlap.
    #
    # TODO document that order matters for resources.

    tools =
      opts
      |> Keyword.get(:tools, [])
      |> Enum.map(&Tool.expand/1)

    tool_names = Enum.map(tools, & &1.name)
    tools_map = Map.new(tools, fn %{name: name} = tool -> {name, tool} end)

    resources =
      opts
      |> Keyword.get(:resources, [])
      |> Enum.map(&ResourceRepo.expand/1)

    resource_prefixes = Enum.map(resources, & &1.prefix)
    repos_map = Map.new(resources, fn %{prefix: prefix} = repo -> {prefix, repo} end)

    {:ok,
     %State{
       status: :starting,
       server_info: build_server_info(opts),
       tool_names: tool_names,
       tools_map: tools_map,
       resource_prefixes: resource_prefixes,
       repos_map: repos_map,
       token_key: random_string(64),
       token_salt: random_string(8),
       trackers: empty_trackers()
     }}
  end

  @impl true
  def handle_request(
        %Entities.InitializeRequest{} = req,
        _chan_info,
        %{status: :starting} = state
      ) do
    case check_protocol_version(req) do
      :ok ->
        init_result =
          Server.intialize_result(
            capabilities: Server.capabilities(tools: true, resources: true),
            server_info: Server.server_info(name: "Mock Server", version: "foo", title: "stuff")
          )

        {:reply, {:result, init_result}, %{state | status: :server_initialized}}

      {:error, reason} = err ->
        {:stop, reason, err, state}
    end
  end

  def handle_request(%Entities.InitializeRequest{} = _req, _chan_info, state) do
    reason = :already_initialized
    {:stop, reason, {:error, reason}, state}
  end

  def handle_request(_req, _, %{status: status} = state)
      when status in [:starting, :server_initialized] do
    {:error, :not_initialized, state}
  end

  # TODO handle cursor?
  def handle_request(%Entities.ListToolsRequest{}, _, state) do
    %{tool_names: tool_names, tools_map: tools_map} = state

    tools =
      Enum.map(tool_names, fn
        name -> tools_map |> Map.fetch!(name) |> Tool.describe()
      end)

    {:reply, {:result, Server.list_tools_result(tools)}, state}
  end

  def handle_request(%Entities.CallToolRequest{} = req, chan_info, state) do
    tool_name = req.params.name

    case state.tools_map do
      %{^tool_name => tool} ->
        channel = build_channel(chan_info, req)

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

  def handle_request(%Entities.ListResourcesRequest{} = req, _chan_info, state) do
    cursor =
      case req do
        %{params: %{cursor: global_cursor}} when is_binary(global_cursor) -> global_cursor
        _ -> nil
      end

    case decode_resource_pagination(cursor, state) do
      {:ok, pagination} ->
        {resources, next_pagination} = list_resources(pagination, state)

        result =
          Server.list_resources_result(
            resources,
            encode_resource_pagination(next_pagination, state)
          )

        {:reply, {:result, result}, state}

      {:error, :invalid_cursor} ->
        {:reply, {:error, :invalid_cursor}, state}

      {:error, :expired_cursor} ->
        {:reply, {:error, :expired_cursor}, state}
    end
  end

  def handle_request(%Entities.ReadResourceRequest{} = req, _chan_info, state) do
    uri = req.params.uri

    case find_repo_for_uri(state, uri) do
      {:ok, repo} ->
        case ResourceRepo.read_resource(repo, uri) do
          {:ok, result} -> {:reply, {:result, result}, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, :no_matching_repo} ->
        {:reply, {:error, {:resource_not_found, uri}}, state}
    end
  end

  def handle_request(%Entities.ListResourceTemplatesRequest{}, _chan_info, state) do
    templates =
      Enum.flat_map(state.resource_prefixes, fn prefix ->
        case Map.fetch!(state.repos_map, prefix).template do
          nil ->
            []

          %{uriTemplate: parsed_template} = tpl_desc ->
            # Build the ResourceTemplate struct using the raw template string
            [
              struct!(
                Entities.ResourceTemplate,
                tpl_desc
                |> Map.put(:uriTemplate, parsed_template.raw)
                |> Map.drop([:__struct__])
              )
            ]
        end
      end)

    result = Server.list_resource_templates_result(templates)
    {:reply, {:result, result}, state}
  end

  def handle_request(req, _, state) do
    Logger.warning("""
    received unsupported request when status=#{inspect(state.status)}:

    #{inspect(req)}
    """)

    {:reply, {:error, :unsupported_request, req}, state}
  end

  @impl true
  def handle_notification(%Entities.InitializedNotification{}, state) do
    {:noreply, %{state | status: :client_initialized}}
  end

  @impl true
  def handle_info({task_ref, _} = msg, state) when is_reference(task_ref) do
    state =
      with :error <- handle_task_info(msg, state) do
        log_unhandled_info(msg)
        state
      else
        {:ok, state} -> state
      end

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason} = msg, state) do
    state =
      with :error <- handle_task_info(msg, state) do
        # No error log on stale down messages
        # TODO monitor channels and look for channel disconnection

        state
      else
        {:ok, state} -> state
      end

    {:noreply, state}
  end

  def handle_info(msg, state) do
    log_unhandled_info(msg)
    {:noreply, state}
  end

  defp log_unhandled_info(msg) do
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

  defp build_server_info(init_opts) do
    name = Keyword.fetch!(init_opts, :server_name)
    version = Keyword.fetch!(init_opts, :server_version)
    title = Keyword.get(init_opts, :server_title, nil)
    Server.server_info(name: name, version: version, title: title)
  end

  defp check_protocol_version(%Entities.InitializeRequest{} = req) do
    case req do
      %{params: %{protocolVersion: version}} when version in @supported_protocol_versions -> :ok
      %{params: %{protocolVersion: version}} -> {:error, {:unsupported_protocol, version}}
    end
  end

  defp build_channel(chan_info, req) do
    Channel.from_client(chan_info, req)
  end

  defp random_string(len) do
    :crypto.strong_rand_bytes(len) |> Base.encode64(padding: false) |> binary_part(0, len)
  end

  defp encode_resource_pagination(nil, _state) do
    nil
  end

  defp encode_resource_pagination(pagination, state) do
    sign_token(pagination, state)
  end

  defp decode_resource_pagination(nil, _state) do
    {:ok, {_repository_index = 0, _repository_cursor = nil}}
  end

  defp decode_resource_pagination(token, state) do
    case verify_token(token, _max_age = :timer.hours(2), state) do
      {:ok, data} -> {:ok, data}
      {:error, :expired} -> {:error, :expired_cursor}
      {:error, :invalid} -> {:error, :invalid_cursor}
    end
  end

  defp sign_token(data, state) do
    Plug.Crypto.sign(state.token_key, state.token_salt, data)
  end

  defp verify_token(token, max_age, state) do
    Plug.Crypto.verify(state.token_key, state.token_salt, token, max_age: max_age)
  end

  defp call_tool(req, tool, channel, _state) do
    Tool.call(tool, req, channel)
  end

  defp list_resources({repo_index, repo_cursor}, state) do
    max_index = length(state.resource_prefixes) - 1

    case resource_repo_at_index(repo_index, state) do
      {:ok, repo} ->
        case ResourceRepo.list_resources(repo, repo_cursor) do
          # no more resources, bump repo index and immediately try next repo
          {[], _} -> list_resources({repo_index + 1, _repo_cursor = nil}, state)
          # some result but no more pages, bump repo index for next request.
          # some edge case, we do not want to return a pagination cursor if this
          # is the last repository
          {list, nil} when repo_index == max_index -> {list, nil}
          {list, nil} -> {list, {repo_index + 1, _repo_cursor = nil}}
          # some results with a cursor so no bump
          {list, repo_cursor} -> {list, {repo_index, repo_cursor}}
        end

      {:error, :no_more_repos} ->
        {[], nil}
    end
  end

  defp resource_repo_at_index(index, state) do
    case Enum.at(state.resource_prefixes, index) do
      nil -> {:error, :no_more_repos}
      prefix -> {:ok, Map.fetch!(state.repos_map, prefix)}
    end
  end

  defp find_repo_for_uri(state, uri) do
    # Match against prefixes in declaration order (first match wins)
    state.resource_prefixes
    |> Enum.find_value(fn prefix ->
      if String.starts_with?(uri, prefix) do
        Map.fetch!(state.repos_map, prefix)
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
