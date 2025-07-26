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
      |> Map.new(fn
        module when is_atom(module) -> {module.name(), {module, []}}
        {module, arg} when is_atom(module) -> {module.name(), {module, arg}}
      end)

    {:ok, %{tools: tools, log?: true, server_info: opts[:server_info]}}
  end

  def client_init(req, state) do
    req |> dbg()
    {:reply, %{capabilities: capabilities(state), serverInfo: server_info(state)}, state}
  end

  def capabilities(state) do
    %ServerCapabilities{
      tools:
        case map_size(state.tools) do
          0 -> nil
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

  def handle_request(%ListToolsRequest{} = req, state) do
    page = Enum.map(state.tools, fn {_name, tool} -> GenMcp.Tool.describe(tool) end) |> dbg()
    {:reply, %{tools: page}, state}
  end

  # we should pass the request id to the tool for streamed responses
  def handle_request(%CallToolRequest{} = req, state) do
    with {:ok, tool} <- Map.fetch(state.tools, req.params.name) do
      case GenMcp.Tool.call(tool, req.params.arguments) do
        {:reply, reply} -> {:reply, reply, state}
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
