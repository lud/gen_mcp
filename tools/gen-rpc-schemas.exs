Mix.install([:jason, :jsv], consolidate_protocols: false)

defmodule CodeWrapper do
  defstruct fun: nil, args: []

  def of(fun, args \\ []) do
    %__MODULE__{fun: fun, args: args}
  end

  defimpl Inspect do
    def inspect(%{fun: fun, args: args}, _) do
      "#{fun}(#{inspect_args(args)})"
    end

    defp inspect_args(args) do
      Enum.map_join(args, ", ", &inspect/1)
    end
  end
end

defmodule Generator do
  def run do
    schema =
      "deps/modelcontextprotocol/schema/2025-06-18/schema.json"
      |> File.read!()
      |> Jason.decode!(keys: :atoms)

    metaschema = schema."$schema"

    defs =
      schema
      |> Map.fetch!(:definitions)
      |> swap_sub_schemas()
      |> Enum.sort()

    modules =
      defs
      |> Stream.map(&generate_module/1)
      |> Enum.join("\n\n")
      |> to_string()

    code = Enum.intersperse([mod_map(defs, metaschema), prelude(), modules], "\n\n")

    File.write!("lib/gen_mcp/entities.ex", code)

    {_, 0} = System.cmd("mix", ~w(format --migrate))

    :ok
  end

  def swap_sub_schema(defs, path, name) do
    {sub_schema, defs} =
      get_and_update_in(defs, path, fn sub -> {sub, %{"$ref": "#/definitions/#{name}"}} end)

    Map.put(defs, name, sub_schema)
  end

  # extract sub obeject schemas from entities and move them as new definitions.
  defp swap_sub_schemas(defs) do
    defs
    |> swap_sub_schema([:InitializeRequest, :properties, :params], :InitializeRequestParams)
    |> swap_sub_schema([:CallToolRequest, :properties, :params], :CallToolRequestParams)
    |> dbg()
  end

  def prelude do
    """
    require GenMcp.JsonDerive, as: JsonDerive

    defmodule #{module_name("Meta")} do
      use JSV.Schema

      def json_schema do
        %{
          additionalProperties: %{},
          description: "See [General Fields](https://modelcontextprotocol.io/specification/2025-06-18/basic#general-fields) for notes on _meta usage.",
          type: "object"
        }
      end
    end
    """
  end

  defp mod_map(defs, metaschema) do
    map = Map.new(defs, fn {name, _} -> {Atom.to_string(name), module_name(name)} end)

    schema = %{
      "$schema": metaschema,
      definitions: map
    }

    """
    defmodule #{module_name("ModMap")} do

      defmacro require_all do
        Enum.map(json_schema().definitions, fn {_, mod} ->
          quote do
            require unquote(mod)
          end
        end)
      end

      def json_schema do
        #{inspect(schema, inspect_opts(limit: :infinity))}
      end
    end
    """
  end

  defp inspect_opts(overrides \\ []) do
    overrides ++ [pretty: true, custom_options: [sort_maps: true]]
  end

  defp generate_module({name, schema}) do
    IO.puts("generating #{name}")
    module = module_name(name)

    case prepare_schema(schema) do
      {:struct, schema} ->
        """
        defmodule #{inspect(module)} do
          use JSV.Schema
          JsonDerive.auto
          defschema #{inspect(schema, inspect_opts())}
        end
        """

      {:generic, schema} ->
        """
        defmodule #{inspect(module)} do
          use JSV.Schema
          def json_schema do
           #{inspect(schema, inspect_opts())}
          end
        end
        """
    end
  end

  defp prepare_schema(schema) do
    schema
    |> jsvize()
    |> classify_fix()
  end

  defp jsvize(schema) do
    schema
    |> JSV.Helpers.Traverse.prewalk(fn
      {:val, %{_meta: meta} = prop} ->
        generic? =
          match?(
            %{
              additionalProperties: %{},
              description: "See [spec" <> _,
              type: "object"
            },
            meta
          ) and map_size(meta) == 3

        if generic? do
          %{prop | _meta: module_name("Meta")}
        else
          prop
        end

      other ->
        elem(other, 1)
    end)
    |> JSV.Helpers.Traverse.postwalk(fn
      {:val, %{"$ref": "#/definitions/" <> name} = schema} ->
        case Map.drop(schema, [:description, :"$schema"]) do
          rest when map_size(rest) == 1 -> module_name(name)
        end

      {:val, %{"$ref": _} = schema} ->
        raise "invalid ref schema: #{inspect(schema)}"

      {:val, %{type: "integer"} = schema} when map_size(schema) == 1 ->
        CodeWrapper.of(:integer)

      {:val, %{type: "integer", description: descr} = schema} when map_size(schema) == 2 ->
        CodeWrapper.of(:integer, [[description: descr]])

      {:val, %{type: "string"} = schema} when map_size(schema) == 1 ->
        CodeWrapper.of(:string)

      {:val, %{type: "string", description: descr} = schema} when map_size(schema) == 2 ->
        CodeWrapper.of(:string, [[description: descr]])

      {:val, %{type: "boolean"} = schema} when map_size(schema) == 1 ->
        CodeWrapper.of(:boolean)

      {:val, %{type: "boolean", description: descr} = schema} when map_size(schema) == 2 ->
        CodeWrapper.of(:boolean, [[description: descr]])

      {:val, %{type: "array", items: items} = schema} when map_size(schema) == 2 ->
        CodeWrapper.of(:array_of, [items])

      {:val, %{type: "string", format: _} = schema} ->
        to_string_format(schema)

      {:val, %{const: value, type: t} = schema} ->
        true =
          case t do
            "string" -> is_binary(value)
          end

        CodeWrapper.of(:const, [value])

      {:val, %{enum: values, type: "string"} = schema} ->
        true = Enum.all?(values, &is_binary/1)
        atoms = Enum.map(values, &String.to_atom/1)

        CodeWrapper.of(:string_enum_to_atom, [atoms])

      other ->
        elem(other, 1)
    end)
  end

  defp to_string_format(schema) do
    case schema.format do
      "uri" ->
        CodeWrapper.of(:uri, [format_schema_to_list(schema)])

      format when format in ["byte", "uri-template"] ->
        CodeWrapper.of(:string_of, [format, format_schema_to_list(schema)])
    end
  end

  defp format_schema_to_list(schema) do
    schema
    |> Map.drop([:type, :format])
    |> Map.to_list()
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp classify_fix(%{type: "object", properties: _} = schema) do
    schema =
      case schema do
        %{required: keys} -> %{schema | required: Enum.map(keys, &String.to_atom/1)}
        _ -> schema
      end

    {:struct, schema}
  end

  defp classify_fix(schema) do
    {:generic, schema}
  end

  def base_module do
    GenMcp.Entities
  end

  defp module_name(name) do
    Module.concat(base_module(), name)
  end
end

raise """
concrete requests should still bear the message id, it's easier to keep track of
it when passing to tools, and easier for users to debug.
"""

Generator.run()
