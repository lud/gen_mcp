defmodule GenMcp.DefaultServer do
  alias GenMcp.Mcp.Entities.CallToolRequest
  alias GenMcp.Mcp.Entities.Implementation
  alias GenMcp.Mcp.Entities.ListToolsRequest
  require Logger

  def init(opts) do
    {tools, ordered_tools_names} =
      opts[:tools]
      |> case do
        list when is_list(list) -> list
        _ -> []
      end
      |> Enum.map_reduce([], fn item, names ->
        {module, opts} =
          case item do
            module when is_atom(module) -> {module, []}
            {module, arg} when is_atom(module) -> {module, arg}
          end

        tool = %{module: module, opts: opts, mode: :init, state: nil}
        name = module.name()
        pair = {name, tool}

        {pair, [name | names]}
      end)
      |> case do
        {pairs, names} -> {Map.new(pairs), :lists.reverse(names)}
      end

    {:ok,
     %{
       tools: tools,
       ordered_tools_names: ordered_tools_names,
       log?: true,
       server_info: opts[:server_info],
       refs: %{}
     }}
  end

  def client_init(_req, state) do
    {:reply, initialization_result(state), state}
  end

  defp initialization_result(state) do
    %{capabilities: capabilities(state), serverInfo: server_info(state)}
  end

  def capabilities(state) do
    capabilities = %{}

    capabilities =
      case state.tools do
        [] -> capabilities
        _ -> Map.put(capabilities, :tools, %{})
      end

    capabilities
  end

  def server_info(state) do
    case state.server_info do
      nil ->
        %Implementation{
          name: "genmcp-generic-server",
          title: "Unnamed GenMcp Server",
          version: "0.0.1"
        }
    end
  end

  def handle_request(%ListToolsRequest{}, _channel, state) do
    page =
      Enum.map(state.ordered_tools_names, fn name ->
        module = Map.fetch!(state.tools, name).module
        GenMcp.Tool.describe(module)
      end)

    {:reply, %{tools: page}, state}
  end

  # we should pass the request id to the tool for streamed responses
  def handle_request(%CallToolRequest{} = req, channel, state) do
    tool_name = req.params.name

    case Map.fetch(state.tools, tool_name) do
      {:ok, tool} ->
        state = ensure_tool_initialized(state, tool_name, tool)
        tool_state = tool_state(state, tool_name)
        result = GenMcp.Tool.call(tool.module, req.params.arguments, channel, tool_state)
        handle_tool_call_result(result, tool_name, channel, state)

      :error ->
        {:error, {:unknown_tool, req.params.name}, state}
    end
  end

  defp ensure_tool_initialized(state, tool_name, tool) do
    case tool do
      %{module: module, mode: :init, opts: opts} ->
        case GenMcp.Tool.init(module, opts) do
          {:state, tool_state} ->
            put_in(state.tools[tool_name], %{tool | mode: :state, state: tool_state})
        end
    end
  end

  def handle_notification(notif, state) do
    log(state, "received notification: #{inspect(notif)}")
    {:noreply, state}
  end

  def handle_info({ref, data}, %{refs: refs} = state) when is_map_key(refs, ref) do
    handle_ref(ref, data, state)
  end

  defp handle_tool_call_result(result, tool_name, channel, state) do
    case result do
      {:reply, reply} ->
        {:reply, reply, state}

      {:async, %Task{} = task, tool_state} ->
        state = put_in(state.refs[task.ref], {channel, {:tool, tool_name}, task})
        state = put_tool_state(state, tool_name, tool_state)
        {:stream, state}
    end
  end

  defp put_tool_state(state, tool_name, tool_state) do
    case Map.fetch!(state.tools, tool_name) do
      %{module: module, mode: :state} = tool ->
        put_in(state.tools[tool_name], %{tool | state: tool_state})
    end
  end

  defp handle_ref(ref, data, state) do
    {{channel, {kind, name}, ref_from}, state} = pop_in(state.refs[ref])

    # If the reference is a task, and we are trapping exits, we need to ignore
    # the normal exit message
    case ref_from do
      %Task{pid: pid} ->
        :erlang.demonitor(ref, [:flush])

        :ok =
          case Process.info(self(), :trap_exit) do
            {:trap_exit, true} ->
              receive do
                {:EXIT, ^pid, :normal} -> :ok
                {:EXIT, ^pid, reason} -> exit(reason)
              end

            {:trap_exit, false} ->
              :ok
          end
    end

    case kind do
      :tool ->
        continue_tool(name, data, channel, state)
    end
  end

  # TODO allow to return a new async task
  defp continue_tool(tool_name, data, channel, state) do
    tool = Map.fetch!(state.tools, tool_name)
    tool_state = tool_state(state, tool_name)
    result = GenMcp.Tool.continue(tool.module, data, channel, tool_state)
    handle_tool_call_result(result, tool, channel, state)
  end

  def tool_state(state, tool_name) do
    case Map.fetch!(state.tools, tool_name) do
      %{mode: :state, state: state} -> state
    end
  end

  defp log(state, level \\ :debug, message) do
    if state.log? do
      Logger.log(level, message)
    else
      :ok
    end
  end
end
