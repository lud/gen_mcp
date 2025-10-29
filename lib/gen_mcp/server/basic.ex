defmodule GenMcp.Server.Basic do
  alias GenMcp.Mux.Channel
  alias GenMcp.Tool
  alias GenMcp.Server
  alias GenMcp.Mcp.Entities
  require Logger

  @behaviour GenMcp.Server

  defmodule State do
    # We keep tools both as a list and as a map
    @enforce_keys [:status, :server_info, :tool_names, :tools_map]
    defstruct @enforce_keys
  end

  @impl true
  def init(opts) do
    tools =
      opts
      |> Keyword.get(:tools, [])
      |> Enum.map(&Tool.expand/1)

    tool_names = Enum.map(tools, & &1.name)
    tools_map = Map.new(tools, fn %{name: name} = tool -> {name, tool} end)

    {:ok,
     %State{
       status: :starting,
       server_info: build_server_info(opts),
       tool_names: tool_names,
       tools_map: tools_map
     }}
  end

  @impl true
  def handle_request(
        %Entities.InitializeRequest{} = req,
        _chan_info,
        %{status: :starting} = state
      ) do
    with :ok <- check_protocol_version(req) do
      init_result =
        Server.intialize_result(
          capabilities: Server.capabilities(tools: true),
          server_info: Server.server_info(name: "Mock Server", version: "foo", title: "stuff")
        )

      {:reply, {:result, init_result}, %{state | status: :server_initialized}}
    else
      {:error, reason} = err -> {:stop, reason, err, state}
    end
  end

  def handle_request(%Entities.InitializeRequest{} = req, _chan_info, state) do
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
        channel = build_channel(chan_info, req) |> dbg()

        case call_tool(req, tool, channel, state) do
          {:result, result, _chan} -> {:reply, {:result, result}, state}
          {:error, reason, _chan} -> {:reply, {:error, reason}, state}
        end

      _ ->
        {:reply, {:error, {:unknown_tool, tool_name}}, state}
    end
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

  defp build_server_info(init_opts) do
    name = Keyword.fetch!(init_opts, :server_name)
    version = Keyword.fetch!(init_opts, :server_version)
    title = Keyword.get(init_opts, :server_title, nil)
    Server.server_info(name: name, version: version, title: title)
  end

  @supported_protocol_versions GenMcp.supported_protocol_versions()

  defp check_protocol_version(%Entities.InitializeRequest{} = req) do
    case req do
      %{params: %{protocolVersion: version}} when version in @supported_protocol_versions -> :ok
      %{params: %{protocolVersion: version}} -> {:error, {:unsupported_protocol, version}}
    end
  end

  defp build_channel(chan_info, req) do
    Channel.from_client(chan_info, req)
  end

  defp call_tool(req, tool, channel, state) do
    binding() |> IO.inspect(limit: :infinity, label: "binding()")
    Tool.call(tool, req, channel)
  end
end
