require GenMcp.Plug.StreamableHttp, as: StreamableHttp
StreamableHttp.delegate(GenMcp.TestWeb.Router.McpBasic)
StreamableHttp.delegate(GenMcp.TestWeb.Router.McpStateful)

defmodule GenMcp.TestWeb.Router do
  use Phoenix.Router

  @moduledoc false
  scope "/dummy", GenMcp.TestWeb do
    get "/sse-test", LoopController, :sse
  end

  scope "/mcp" do
    forward "/basic", GenMcp.TestWeb.Router.McpBasic,
      tools: [
        GenMcp.Test.Tools.Calculator,
        GenMcp.Test.Tools.AsyncCounter,
        GenMcp.Test.Tools.Sleeper
      ]

    forward "/stateful", GenMcp.TestWeb.Router.McpStateful,
      tools: [
        GenMcp.Test.Tools.Calculator,
        GenMcp.Test.Tools.AsyncCounter,
        GenMcp.Test.Tools.Sleeper
      ]
  end
end
