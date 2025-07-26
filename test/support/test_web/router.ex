defmodule GenMcp.TestWeb.Router do
  use Phoenix.Router

  @moduledoc false

  pipeline :mcp do
  end

  scope "/dummy", GenMcp.TestWeb do
    pipe_through :mcp

    get "/sse-test", LoopController, :sse
  end

  forward "/mcp", GenMcp.Plug.StreamableHttp, tools: [GenMcp.Test.Tools.Calculator]
end
