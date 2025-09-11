defmodule GenMcp.DefaultServer do
  alias GenMcp.Entities.CallToolRequest
  alias GenMcp.Entities.ListToolsRequest
  alias GenMcp.Entities.ServerCapabilities
  alias GenMcp.Entities.Implementation
  require Logger

  def init(opts) do
    {tools, ordered_tools_names} =
      opts[:tools]
      |> case do
        list when is_list(list) -> list
        _ -> []
      end
      |> Enum.map_reduce([], fn item, names ->
        {name, _} =
          pair =
          case item do
            module when is_atom(module) -> {module.name(), {module, :nostate, []}}
            {module, arg} when is_atom(module) -> {module.name(), {module, :nostate, arg}}
          end

        {pair, [name | names]}
      end)
      |> case do
        {pairs, names} -> {Map.new(pairs), :lists.reverse(names)}
      end
      |> dbg()

    {:ok,
     %{
       tools: tools,
       ordered_tools_names: ordered_tools_names,
       log?: true,
       server_info: opts[:server_info],
       refs: %{}
     }}
  end

  def client_init(req, state) do
    {:reply, initialization_result(state), state}
  end

  def initialization_result(state) do
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
        {module, _, _} = Map.fetch!(state.tools, name)
        GenMcp.Tool.describe(module)
      end)

    {:reply, %{tools: page}, state}
  end

  # we should pass the request id to the tool for streamed responses
  def handle_request(%CallToolRequest{} = req, channel, state) do
    tool_name = req.params.name

    case Map.fetch(state.tools, tool_name) do
      {:ok, {module, _, _} = tool} ->
        {state, tool_state} = ensure_tool_initialized(state, tool_name, tool)
        result = GenMcp.Tool.call(module, req.params.arguments, channel, tool_state)
        handle_tool_call_result(result, tool, channel, state)

      :error ->
        {:error, GenMcp.Error.unknown_tool(req.params.name), state}
    end
  end

  defp ensure_tool_initialized(state, tool_name, tool) do
    binding() |> IO.inspect(limit: :infinity, label: "binding()")

    {_state, _tool_state} =
      case tool do
        {module, :nostate, arg} ->
          case GenMcp.Tool.init(module, arg) do
            {:state, tool_state} ->
              state = put_in(state.tools[tool_name], {module, :state, tool_state})
              {state, tool_state}
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

  defp handle_tool_call_result(result, tool, channel, state) do
    case result do
      {:reply, reply} ->
        {:reply, reply, state}

      {:async, %Task{} = task, tool_state} ->
        state = put_in(state.refs[task.ref], {channel, {:tool, tool}, task, tool_state})
        {:stream, state}
    end
  end

  defp handle_ref(ref, data, state) do
    {{channel, {kind, impl}, ref_from, sub_state}, state} = pop_in(state.refs[ref])

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
      :tool -> continue_tool(impl, data, sub_state, channel, state)
    end
  end

  # TODO allow to return a new async task
  defp continue_tool({module, _, _} = tool, data, tool_state, channel, state) do
    result = GenMcp.Tool.next(module, data, channel, tool_state)
    handle_tool_call_result(result, tool, channel, state)
  end

  defp log(state, level \\ :debug, message) do
    if state.log? do
      Logger.log(level, message)
    else
      :ok
    end
  end
end
