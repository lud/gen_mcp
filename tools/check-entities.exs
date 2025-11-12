root = JSV.build!(GenMCP.Entities.TextContent)
JSV.validate!(%{"text" => "hello", "type" => "text"}, root)

root = JSV.build!(GenMCP.Entities.CreateMessageRequest)

JSV.validate!(
  %{
    "method" => "sampling/createMessage",
    "params" => %{"maxTokens" => 123, "messages" => [], "includeContext" => "allServers"}
  },
  root
)
