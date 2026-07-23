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
