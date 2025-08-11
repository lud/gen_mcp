defmodule GenMcp.TestWeb.Router do
  use Phoenix.Router
  require GenMcp.Plug.StreamableHttp, as: StreamableHttp

  @moduledoc false
  scope "/dummy", GenMcp.TestWeb do
    get "/sse-test", LoopController, :sse
  end

  scope "/mcp" do
    forward "/basic", StreamableHttp.delegate(__MODULE__.McpBasic),
      tools: [
        GenMcp.Test.Tools.Calculator,
        GenMcp.Test.Tools.AsyncCounter,
        GenMcp.Test.Tools.Sleeper
      ]

    forward "/stateful", StreamableHttp.delegate(__MODULE__.McpStateful)
  end
end
