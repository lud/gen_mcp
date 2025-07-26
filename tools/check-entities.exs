root = JSV.build!(GenMcp.Entities.TextContent)
JSV.validate!(%{"text" => "hello", "type" => "text"}, root)

root = JSV.build!(GenMcp.Entities.CreateMessageRequest)

JSV.validate!(
  %{
    "method" => "sampling/createMessage",
    "params" => %{"maxTokens" => 123, "messages" => [], "includeContext" => "allServers"}
  },
  root
)
