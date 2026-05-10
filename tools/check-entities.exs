root = JSV.build!(GenMCP.MCP.TextContent, atoms: false)
JSV.validate!(%{"text" => "hello", "type" => "text"}, root)

root = JSV.build!(GenMCP.MCP.ListToolsRequest, atoms: false)

JSV.validate!(
  %{
    "id" => 1,
    "jsonrpc" => "2.0",
    "method" => "tools/list",
    "params" => %{}
  },
  root
)

# Build a schema that can be anything, so all schemas must be buildable

schema = %{anyOf: Map.values(GenMCP.MCP.ModMap.json_schema().definitions)}

case JSV.build(schema, atoms: false) do
  {:ok, _} ->
    :ok

  {:error,
   %JSV.BuildError{
     reason: {:invalid_sub_schema, location, "Elixir.GenMCP.MCP." <> mod_as_string},
     action: :building_subschema
   }} ->
    raise """


    generating schemas requires configuring the #{mod_as_string} schema
    used in #{location}


    """

  {:error, %JSV.BuildError{} = e} ->
    raise e
end
