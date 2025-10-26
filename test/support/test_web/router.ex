require GenMcp.Plug.StreamableHttp, as: StreamableHttp
StreamableHttp.defplug(GenMcp.TestWeb.Router.McpMock)
StreamableHttp.defplug(GenMcp.TestWeb.Router.McpStateful)

defmodule GenMcp.TestWeb.Router do
  use Phoenix.Router

  @moduledoc false
  scope "/dummy", GenMcp.TestWeb do
    get "/sse-test", LoopController, :sse
  end

  scope "/mcp" do
    forward "/mock", GenMcp.TestWeb.Router.McpMock, server: GenMcp.Support.ServerMock
  end
end
