require GenMcp.Plug.StreamableHttp, as: StreamableHttp
StreamableHttp.defplug(GenMcp.TestWeb.Router.McpMock)
StreamableHttp.defplug(GenMcp.TestWeb.Router.McpReal)

defmodule GenMcp.TestWeb.Router do
  use Phoenix.Router

  @moduledoc false
  scope "/dummy", GenMcp.TestWeb do
    get "/sse-test", LoopController, :sse
  end

  scope "/mcp" do
    forward "/mock", GenMcp.TestWeb.Router.McpMock, server: GenMcp.Support.ServerMock

    forward "/real", GenMcp.TestWeb.Router.McpReal,
      server_name: "Real Server",
      server_version: "0.0.1"
  end
end
