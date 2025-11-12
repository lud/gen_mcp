require GenMCP.Plug.StreamableHttp, as: StreamableHttp
StreamableHttp.defplug(GenMCP.TestWeb.Router.McpMock)
StreamableHttp.defplug(GenMCP.TestWeb.Router.McpReal)

defmodule GenMCP.TestWeb.Router do
  use Phoenix.Router

  @moduledoc false
  scope "/dummy", GenMCP.TestWeb do
    get "/sse-test", LoopController, :sse
  end

  scope "/mcp" do
    forward "/mock", GenMCP.TestWeb.Router.McpMock, server: GenMCP.Support.ServerMock

    forward "/real", GenMCP.TestWeb.Router.McpReal,
      server_name: "Real Server",
      server_version: "0.0.1"
  end
end
