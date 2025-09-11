defmodule GenMcp.Tool do
  @optional_funs (Map.keys(GenMcp.Entities.Tool.__struct__()) --
                    [:__struct__, :name, :inputSchema])
                 |> Enum.map(fn
                   k when k in [:description, :title, :_meta, :annotations] -> {k, k}
                   :outputSchema -> {:output_schema, :outputSchema}
                 end)

  def describe(module) do
    _ = Code.ensure_loaded(module)
    info = [name: module.name(), inputSchema: module.input_schema()]

    info =
      Enum.reduce(@optional_funs, info, fn {fun, key}, acc ->
        if function_exported?(module, fun, 0) do
          [{key, apply(module, fun, [])} | acc]
        else
          acc
        end
      end)

    info = Map.new(info)

    info =
      case info do
        %{inputSchema: schema} when is_map(schema) ->
          %{info | inputSchema: normalize_schema(schema)}

        _ ->
          info
      end

    info =
      case info do
        %{outputSchema: schema} when is_map(schema) ->
          %{info | outputSchema: normalize_schema(schema)}

        _ ->
          info
      end

    struct!(GenMcp.Entities.Tool, info)
  end

  defp normalize_schema(schema) do
    schema
    |> JSV.Schema.normalize()
    |> JSV.Helpers.Traverse.prewalk(fn
      {:val, map} when is_map(map) -> Map.delete(map, "jsv-cast")
      other -> elem(other, 1)
    end)
  end

  IO.warn("create behaviour for tools. init is optional")

  def init(module, arg) do
    Code.ensure_loaded!(module)

    if function_exported?(module, :init, 1) do
      do_init(module, arg)
    else
      {:state, arg}
    end
  end

  defp do_init(module, arg) do
    case module.init(arg) do
      :stateless -> {:state, arg}
    end
  end

  def call(module, arguments, channel, state) do
    case validate_input(module, arguments) do
      {:ok, arguments} -> do_call(module, arguments, channel, state)
    end
  end

  defp do_call(module, arguments, channel, opts) do
    module.call(arguments, channel, opts)
  end

  def continue(module, data, channel, state) do
    module.continue(data, channel, state)
  end

  # TODO we should propose to define the input_schema as options to `use
  # GenMcp.Tool` so we can also build the JSV validator at compile time.
  defp validate_input(module, arguments) do
    root = JSV.build!(module.input_schema())
    JSV.validate(arguments, root)
  end
end
