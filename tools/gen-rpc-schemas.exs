Mix.install([:jason, :jsv], consolidate_protocols: false)

# This module receives a fun and args, and implements inspect so we can render a
# call
#
# For instance if fun is :string and args is [[description: "hello"]], we can render
#
#     string(description: "hello")
#
defmodule CodeWrapper do
  defstruct fun: nil, args: []

  def of(fun, args \\ []) do
    %__MODULE__{fun: fun, args: args}
  end

  defimpl Inspect do
    def inspect(%{fun: fun, args: args}, _) do
      # args =
      #   update_in(args, [Access.at(-1)], fn kv ->
      #     if Keyword.keyword?(kv) && Keyword.has_key?(kv, :description) do
      #       # && String.contains?(Keyword.fetch!(kv, :description), "\n")

      #       IO.puts("replaced description")
      #       Keyword.update!(kv, :description, &DescriptionWrapper.of/1)
      #     else
      #       kv
      #     end
      #   end)

      "#{fun}(#{inspect_args(args)})"
    end

    defp inspect_args(args) do
      Enum.map_join(args, ", ", &inspect/1)
    end
  end
end

defmodule DescriptionWrapper do
  defstruct [:description]

  def of(description) do
    %__MODULE__{description: description}
  end

  defimpl Inspect do
    def inspect(%{description: description}, _) do
      to_string("""
      ~SD\"""
      #{hardwrap(description)}
      \"""\
      """)
    end

    defp hardwrap(text) do
      text
      |> String.replace("\n\n", "--double-line-break--")
      |> String.replace("\n", " ")
      |> String.split("--double-line-break--")
      |> Enum.map(fn line -> hardwrap_line(line, 70) end)
      |> Enum.join("\n\n")
    end

    defp hardwrap_line(line, width) do
      words =
        line
        |> String.split(" ", trim: true)
        |> Enum.map(&{&1, String.length(&1)})

      words
      |> Enum.reduce({0, [], []}, fn {word, len}, {line_len, this_line, lines} ->
        cond do
          line_len == 0 -> {len, [word | this_line], lines}
          line_len + 1 + len > width -> {len, [word], [:lists.reverse(this_line) | lines]}
          :_ -> {line_len + 1 + len, [word, " " | this_line], lines}
        end
      end)
      |> case do
        {_, [], lines} -> lines
        {_, current, lines} -> [:lists.reverse(current) | lines]
      end
      |> :lists.reverse()
      |> Enum.join("\n")

      # Fancy stuff. We need to reverse the lines but also map them so if one line
      # starts with a backtick we insert a backspace before so the text aligns
      # more naturally.
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
      |> inherit_schemas()
      |> swap_sub_schemas()
      |> Enum.sort()

    modules =
      defs
      |> Stream.map(&generate_module/1)
      |> Enum.join("\n\n")
      |> to_string()

    code = Enum.intersperse([prelude(), mod_map(defs, metaschema), modules], "\n\n")

    File.write!("lib/gen_mcp/mcp/entities.ex", code)

    {_, 0} = System.cmd("mix", ~w(format --migrate))

    :ok
  end

  defp module_config(name) do
    case name do
      :CallToolRequest -> [msg_id: true, request_meta: true]
      :CompleteRequest -> [msg_id: true, request_meta: true]
      :GetPromptRequest -> [msg_id: true, request_meta: true]
      :InitializeRequest -> [msg_id: true, request_meta: true]
      :ListPromptsRequest -> [msg_id: true, request_meta: true]
      :ListResourcesRequest -> [msg_id: true, request_meta: true]
      :ListResourceTemplatesRequest -> [msg_id: true, request_meta: true]
      :ListToolsRequest -> [msg_id: true, request_meta: true]
      :PingRequest -> [msg_id: true, request_meta: true]
      :ReadResourceRequest -> [msg_id: true, request_meta: true]
      :SetLevelRequest -> [msg_id: true, request_meta: true]
      :SubscribeRequest -> [msg_id: true, request_meta: true]
      :UnsubscribeRequest -> [msg_id: true, request_meta: true]
      _ -> []
    end
  end

  defp requires_message_id?(name) do
    true == Keyword.get(module_config(name), :msg_id)
  end

  defp use_request_meta?(name) do
    true == Keyword.get(module_config(name), :request_meta)
  end

  defp inherit_schemas(defs) do
    Map.new(defs, fn {name, schema} ->
      schema =
        schema
        |> enforce_id(name)
        |> enforce_request_meta(name)

      {name, schema}
    end)
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
  end

  def prelude do
    """
    require GenMcp.JsonDerive, as: JsonDerive

    # Support modkit renaming
    defmodule #{inspect(base_module())} do
      @moduledoc false
    end

    defmodule #{inspect(module_name("Meta"))} do
      use JSV.Schema

      def json_schema do
        %{
          additionalProperties: %{},
          description: "See [General Fields](https://modelcontextprotocol.io/specification/2025-06-18/basic#general-fields) for notes on _meta usage.",
          properties: %{progressToken: GenMcp.Mcp.Entities.ProgressToken},
          type: "object"
        }
      end
    end

    defmodule #{inspect(module_name("RequestMeta"))} do
      use JSV.Schema

      def json_schema do
        %{
          additionalProperties: %{},
          description: "See [General Fields](https://modelcontextprotocol.io/specification/2025-06-18/basic#general-fields) for notes on _meta usage.",
          properties: %{progressToken: GenMcp.Mcp.Entities.ProgressToken},
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
    defmodule #{inspect(module_name("ModMap"))} do

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

    case prepare_schema(schema, name) do
      {:struct, schema} ->
        """
        defmodule #{inspect(module)} do
          use JSV.Schema
          JsonDerive.auto
          defschema #{inspect(schema, inspect_opts())}
          @type t :: %__MODULE__{}
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

    # |> tap(&IO.puts/1)
  end

  defp prepare_schema(schema, name) do
    schema
    |> use_schema_api()
    |> maybe_format_for_struct()
    |> case do
      {:struct, schema} -> {:struct, Map.put(schema, :title, Atom.to_string(name))}
      {:generic, _} = gen -> gen
    end
  end

  # Adds the :id property into schema requests so we keep it on casting to
  # structs. The given official JSON schema does not inherit properties from the
  # generic request in specific requests.
  defp enforce_id(schema, name) do
    if requires_message_id?(name) do
      case schema do
        %{properties: %{id: _}} ->
          raise "id already defined"

        %{properties: props} ->
          %{schema | properties: Map.put(props, :id, %{"$ref": "#/definitions/RequestId"})}
      end
    else
      schema
    end
  end

  defp enforce_request_meta(schema, name) do
    if use_request_meta?(name) do
      put_in(schema, [:properties, :params, :properties, :_meta], %{
        "$ref": "#/definitions/RequestMeta"
      })
    else
      schema
    end
  end

  defp use_schema_api(schema) do
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
      {:val, %{description: description} = map} when is_binary(description) ->
        if String.contains?(description, "\n") || String.length(description) > 50 do
          Map.update!(map, :description, &DescriptionWrapper.of/1)
        else
          map
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

      {:val, %{type: "number"} = schema} when map_size(schema) == 1 ->
        CodeWrapper.of(:number)

      {:val, %{type: "number", description: descr} = schema} when map_size(schema) == 2 ->
        CodeWrapper.of(:number, [[description: descr]])

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

      {:val, %{const: value, type: t}} ->
        true =
          case t do
            "string" -> is_binary(value)
          end

        CodeWrapper.of(:const, [value])

      {:val, %{enum: values, type: "string"}} ->
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

  defp maybe_format_for_struct(%{type: "object", properties: _} = schema) do
    schema =
      case schema do
        %{required: keys} -> %{schema | required: Enum.map(keys, &String.to_atom/1)}
        _ -> schema
      end

    {:struct, schema}
  end

  defp maybe_format_for_struct(schema) do
    {:generic, schema}
  end

  def base_module do
    GenMcp.Mcp.Entities
  end

  defp module_name(name) do
    Module.concat(base_module(), name)
  end
end

Generator.run()
