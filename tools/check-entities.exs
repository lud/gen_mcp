root = JSV.build!(GenMCP.MCP.V2607.TextContent, atoms: false)
JSV.validate!(%{"text" => "hello", "type" => "text"}, root)

root = JSV.build!(GenMCP.MCP.V2607.ListToolsRequest, atoms: false)

# In 2026 every request carries client identity/capabilities/version inline via
# the required `_meta` (RequestMetaObject) rather than an `initialize` handshake.
JSV.validate!(
  %{
    "id" => 1,
    "jsonrpc" => "2.0",
    "method" => "tools/list",
    "params" => %{
      "_meta" => %{
        "io.modelcontextprotocol/clientCapabilities" => %{},
        "io.modelcontextprotocol/clientInfo" => %{
          "name" => "check-entities",
          "version" => "0.0.0"
        },
        "io.modelcontextprotocol/protocolVersion" => "2026-07-28"
      }
    }
  },
  root
)

# Build a schema that can be anything, so all schemas must be buildable

schema = %{anyOf: Map.values(GenMCP.MCP.V2607.ModMap.json_schema().definitions)}

case JSV.build(schema, atoms: false) do
  {:ok, _} ->
    :ok

  {:error,
   %JSV.BuildError{
     reason: {:invalid_sub_schema, location, "Elixir.GenMCP.MCP.V2607." <> mod_as_string},
     action: :building_subschema
   }} ->
    raise """


    generating schemas requires configuring the #{mod_as_string} schema
    used in #{location}


    """

  {:error, %JSV.BuildError{} = e} ->
    raise e
end
