defmodule GenMcp.TestWeb.Router do
  use Phoenix.Router

  @moduledoc false
  scope "/dummy", GenMcp.TestWeb do
    get "/sse-test", LoopController, :sse
  end

  scope "/mcp" do
    forward "/basic", GenMcp.Plug.StreamableHttp, tools: [GenMcp.Test.Tools.Calculator]
  end
end
