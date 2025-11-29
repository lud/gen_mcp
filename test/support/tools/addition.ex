defmodule GenMCP.Test.Tools.Addition do
  use GenMCP.Suite.Tool,
    name: "Addition",
    description: "Adds two numbers",
    input_schema: %{
      type: "object",
      properties: %{
        a: %{type: "number"},
        b: %{type: "number"}
      },
      required: ["a", "b"]
    }

  require Logger

  @impl true
  def call(req, channel, _arg) do
    %{"a" => a, "b" => b} = req.params.arguments
    Logger.info("Addition was called")
    result = GenMCP.MCP.call_tool_result(text: "#{a + b}")
    {:result, result, channel}
  end
end
