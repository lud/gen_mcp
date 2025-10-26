defmodule GenMcp.Server do
  alias GenMcp.Mcp.Entities
  alias GenMcp.Mux.Channel

  require(Elixir.GenMcp.Mcp.Entities.ModMap).require_all()

  @type state :: term

  @callback init(term) :: {:ok, state}

  @type request :: Entities.InitializeRequest.t()
  @type result :: Entities.InitializeResult.t()
  @type notification :: Entities.InitializedNotification.t()

  @callback handle_request(request, Channel.chan_info(), state) :: {:result, result, state}
  @callback handle_notification(notification, state) :: {:noreply, state}
  @callback handle_info(term, state) :: {:noreply, state}

  def intialize_result(opts) do
    %Entities.InitializeResult{
      capabilities: Keyword.get(opts, :capabilities, %{}),
      serverInfo: Keyword.fetch!(opts, :server_info),
      protocolVersion: "2025-06-18"
    }
  end

  def capabilities(opts) do
    attrs =
      Enum.flat_map(opts, fn
        {key, value} when is_map(value) -> [{key, value}]
        {key, true} -> [{key, %{}}]
        _ -> []
      end)

    struct!(Entities.ServerCapabilities, attrs)
  end

  def server_info(opts) do
    %Entities.Implementation{
      name: Keyword.fetch!(opts, :name),
      version: Keyword.fetch!(opts, :version),
      title: Keyword.get(opts, :title, nil)
    }
  end

  def list_tools_result(tools) do
    %{
      tools:
        Enum.map(tools, fn
          tool when is_atom(tool) -> GenMcp.Tool.describe(tool)
          tool when is_map(tool) -> tool
        end)
    }
  end

  def call_tool_result(opts) when is_list(opts) do
    %Entities.CallToolResult{
      # structuredContent: structured,
      content: Keyword.get(opts, :content, []),
      structuredContent: Keyword.get(opts, :structured_content, []),
      isError: Keyword.get(opts, :is_error, false)
    }
  end
end
