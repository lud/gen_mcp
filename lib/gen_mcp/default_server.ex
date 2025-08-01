defmodule GenMcp.DefaultServer do
  alias GenMcp.Entities.CallToolRequest
  alias GenMcp.Entities.ListToolsRequest
  alias GenMcp.Entities.ServerCapabilities
  alias GenMcp.Entities.Implementation
  require Logger

  def init(opts) do
    opts |> dbg()

    tools =
      opts[:tools]
      |> case do
        list when is_list(list) -> list
        _ -> []
      end
      |> Enum.map(fn
        module when is_atom(module) -> {module.name(), {module, []}}
        {module, arg} when is_atom(module) -> {module.name(), {module, arg}}
      end)

    {:ok, %{tools: tools, log?: true, server_info: opts[:server_info], tasks: %{}}}
  end

  def client_init(req, state) do
    req |> dbg()
    {:reply, %{capabilities: capabilities(state), serverInfo: server_info(state)}, state}
  end

  def capabilities(state) do
    %ServerCapabilities{
      tools:
        case state.tools do
          [] -> nil
          _ -> %{}
        end
    }
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

  def handle_request(%ListToolsRequest{}, state) do
    page = Enum.map(state.tools, fn {_name, tool} -> GenMcp.Tool.describe(tool) end) |> dbg()
    {:reply, %{tools: page}, state}
  end

  # we should pass the request id to the tool for streamed responses
  def handle_request(%CallToolRequest{} = req, channel, state) do
    case List.keyfind(state.tools, req.params.name, 0) do
      {_, tool} ->
        case GenMcp.Tool.call(tool, channel, req.params.arguments) do
          {:reply, reply} ->
            {:reply, reply, state}

          {:stream, %Task{} = task} ->
            {:stream, "", put_in(state.tasks[task.ref], channel) |> dbg()}
        end
    end
  end

  def handle_notification(notif, state) do
    log(state, "received notification: #{inspect(notif)}")
    {:noreply, state}
  end

  defp log(state, level \\ :debug, message) do
    if state.log? do
      Logger.log(level, message)
    else
      :ok
    end
  end
end
