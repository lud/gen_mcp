root = JSV.build!(GenMCP.MCP.TextContent)
JSV.validate!(%{"text" => "hello", "type" => "text"}, root)

root = JSV.build!(GenMCP.MCP.ListToolsRequest)

JSV.validate!(
  %{
    "method" => "tools/list",
    "params" => %{}
  },
  root
)
