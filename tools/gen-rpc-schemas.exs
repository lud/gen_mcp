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
      |> Enum.map_join("\n\n", fn line -> hardwrap_line(line, 70) end)
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
  alias JSV.Helpers.Traverse

  require Record

  @jsonrpc_vsn "2.0"

  Record.defrecordp(:conf, name: nil, schema: nil, opts: [], kind: nil)

  def run do
    schema =
      "deps/modelcontextprotocol/schema/2025-06-18/schema.json"
      |> File.read!()
      |> Jason.decode!(keys: :atoms)

    metaschema = schema."$schema"

    confs =
      schema
      |> Map.fetch!(:definitions)
      |> Enum.map(fn {name, schema} -> conf(name: name, schema: schema, opts: []) end)
      |> filter_schemas()
      # index by name so we can target schemas by name and add new confs to the
      # definitions
      |> Map.new(fn conf(name: name) = conf -> {name, conf} end)
      |> swap_sub_schemas()

      # Back to list and sort
      |> Map.values()
      |> Stream.map(&process_schema/1)
      |> Enum.sort_by(fn conf(name: name) -> name end)

    # We can now generate the modules
    generated_modules = Enum.map_join(confs, "\n\n", &generate_module/1)

    generated_block = [
      prelude(),
      mod_map(confs, metaschema),
      generated_modules
    ]

    code = Enum.intersperse(generated_block, "\n\n")

    File.write!("lib/gen_mcp/mcp/entities.ex", code)

    {_, 0} = System.cmd("mix", ~w(format --migrate))

    :ok
  end

  defp module_config(name) do
    case name do
      # Custom additions
      :CallToolRequestParams ->
        [rpc_request_params: true]

      :CancelledNotificationParams ->
        [rpc_request_params: true]

      :GetPromptRequestParams ->
        [rpc_request_params: true]

      :InitializeRequestParams ->
        [rpc_request_params: true]

      :ListPromptsRequestParams ->
        [rpc_request_params: true]

      :ListResourcesRequestParams ->
        [rpc_request_params: true]

      :ListResourceTemplatesRequestParams ->
        [rpc_request_params: true]

      :ReadResourceRequestParams ->
        [rpc_request_params: true]

      # Existing definitions

      :CallToolRequest ->
        [rpc_request: true]

      :CompleteRequest ->
        # [ rpc_request: true]
        :skip

      :GetPromptRequest ->
        [rpc_request: true]

      :InitializeRequest ->
        [rpc_request: true]

      :ListPromptsRequest ->
        [rpc_request: true]

      :ListResourcesRequest ->
        [rpc_request: true]

      :ListResourceTemplatesRequest ->
        [rpc_request: true]

      :ListToolsRequest ->
        [rpc_request: true]

      :PingRequest ->
        [rpc_request: true]

      :ReadResourceRequest ->
        [rpc_request: true]

      :SetLevelRequest ->
        # [ rpc_request: true]
        :skip

      :SubscribeRequest ->
        [rpc_request: true]

      :UnsubscribeRequest ->
        [rpc_request: true]

      :Annotations ->
        []

      :AudioContent ->
        [set_default_resource_type: true]

      :BaseMetadata ->
        :skip

      :BlobResourceContents ->
        []

      :BooleanSchema ->
        []

      :CallToolResult ->
        []

      :CancelledNotification ->
        []

      :ClientCapabilities ->
        []

      :ClientNotification ->
        :skip

      :ClientRequest ->
        :skip

      :ClientResult ->
        :skip

      :CompleteRequest ->
        :skip

      :CompleteResult ->
        :skip

      :ContentBlock ->
        []

      :CreateMessageRequest ->
        :skip

      :CreateMessageResult ->
        :skip

      :Cursor ->
        :skip

      :ElicitRequest ->
        :skip

      :ElicitResult ->
        :skip

      :EmbeddedResource ->
        [set_default_resource_type: true]

      :EmptyResult ->
        :skip

      :EnumSchema ->
        :skip

      :GetPromptResult ->
        []

      :ImageContent ->
        [set_default_resource_type: true]

      :Implementation ->
        []

      :InitializedNotification ->
        []

      :InitializeResult ->
        []

      :JSONRPCError ->
        []

      :JSONRPCMessage ->
        :skip

      :JSONRPCNotification ->
        :skip

      :JSONRPCRequest ->
        []

      :JSONRPCResponse ->
        []

      :ListPromptsResult ->
        []

      :ListResourcesResult ->
        []

      :ListResourceTemplatesResult ->
        []

      :ListRootsRequest ->
        :skip

      :ListRootsResult ->
        :skip

      :ListToolsResult ->
        []

      :LoggingLevel ->
        :skip

      :LoggingMessageNotification ->
        :skip

      :ModelHint ->
        :skip

      :ModelPreferences ->
        :skip

      :Notification ->
        :skip

      :NumberSchema ->
        :skip

      :PaginatedRequest ->
        :skip

      :PaginatedResult ->
        :skip

      :PrimitiveSchemaDefinition ->
        :skip

      :ProgressNotification ->
        []

      :ProgressToken ->
        []

      :Prompt ->
        []

      :PromptArgument ->
        []

      :PromptListChangedNotification ->
        :skip

      :PromptMessage ->
        []

      :PromptReference ->
        :skip

      :ReadResourceResult ->
        []

      :Request ->
        :skip

      :RequestId ->
        []

      :Resource ->
        []

      :ResourceContents ->
        :skip

      :ResourceLink ->
        [set_default_resource_type: true]

      :ResourceListChangedNotification ->
        :skip

      :ResourceTemplate ->
        []

      :ResourceTemplateReference ->
        :skip

      :ResourceUpdatedNotification ->
        :skip

      :Result ->
        []

      :Role ->
        []

      :Root ->
        :skip

      :RootsListChangedNotification ->
        []

      :SamplingMessage ->
        :skip

      :ServerCapabilities ->
        []

      :ServerNotification ->
        :skip

      :ServerRequest ->
        :skip

      :ServerResult ->
        :skip

      :StringSchema ->
        :skip

      :TextContent ->
        [set_default_resource_type: true]

      :TextResourceContents ->
        []

      :Tool ->
        []

      :ToolAnnotations ->
        []

      :ToolListChangedNotification ->
        :skip
    end
  end

  defp skip_definition?(name) do
    :skip == module_config(name)
  end

  defp request_params_schema?(name) do
    true == Keyword.get(module_config(name), :rpc_request_params)
  end

  defp rpc_request?(name) do
    true == Keyword.get(module_config(name), :rpc_request)
  end

  defp set_default_resource_type?(name) do
    true == Keyword.get(module_config(name), :set_default_resource_type)
  end

  defp filter_schemas(defs) do
    Enum.reject(defs, fn conf(name: name) -> skip_definition?(name) end)
  end

  defp process_schema(conf) do
    conf(name: name) = conf

    conf
    |> enforce_request_params_meta(name)
    |> skip_request_fields(name)
    |> resource_type_as_default(name)
    |> use_schema_api()
    |> classify_schema()
  end

  # update the conf identified by confname by:
  #
  # * lookup the schema_path in the conf schema
  # * copy that schema (named new_schema_name) in the confmap under key new_schema_name
  # * replace the original schema place with a ref to that new schema
  def swap_sub_schema(confmap, parent_name, schema_path, new_schema_name) do
    # Lookup the parent schema from the confs map
    parent_conf = Map.fetch!(confmap, parent_name)
    conf(schema: parent_schema) = parent_conf

    # Locate the sub schema under path, extract it and replace it in the
    # parent schema (under path) by a ref to a new created confmap entry
    # (done later)
    {sub_schema, parent_schema} =
      get_and_update_in(parent_schema, schema_path, fn sub_schema ->
        {sub_schema, %{"$ref": "#/definitions/#{new_schema_name}"}}
      end)

    # Update the parent and sub schema in the confs
    #

    parent_conf = conf(parent_conf, schema: parent_schema)
    sub_conf = conf(name: new_schema_name, schema: sub_schema, opts: [])

    Map.merge(confmap, %{
      parent_name => parent_conf,
      new_schema_name => sub_conf
    })
  rescue
    e in ArgumentError ->
      case Map.fetch(confmap, parent_name) do
        {:ok, conf(schema: schema)} ->
          IO.warn("check if #{inspect(schema_path)} is defined in #{inspect(schema)}", [])

        :error ->
          IO.warn("could not find schema def #{inspect(parent_name)}")
      end

      reraise e, __STACKTRACE__
  end

  # extract sub obeject schemas from entities and move them as new definitions.
  defp swap_sub_schemas(confmap) do
    confmap
    |> swap_sub_schema(:InitializeRequest, [:properties, :params], :InitializeRequestParams)
    |> swap_sub_schema(:CallToolRequest, [:properties, :params], :CallToolRequestParams)
    |> swap_sub_schema(:ListResourcesRequest, [:properties, :params], :ListResourcesRequestParams)
    |> swap_sub_schema(
      :ListResourceTemplatesRequest,
      [:properties, :params],
      :ListResourceTemplatesRequestParams
    )
    |> swap_sub_schema(:ReadResourceRequest, [:properties, :params], :ReadResourceRequestParams)
    |> swap_sub_schema(:ListPromptsRequest, [:properties, :params], :ListPromptsRequestParams)
    |> swap_sub_schema(:GetPromptRequest, [:properties, :params], :GetPromptRequestParams)
    |> swap_sub_schema(
      :CancelledNotification,
      [:properties, :params],
      :CancelledNotificationParams
    )
  end

  def prelude do
    """
    require GenMCP.JsonDerive, as: JsonDerive

    defmodule #{inspect(module_name("Meta"))} do
      use JSV.Schema

      def json_schema do
        %{
          additionalProperties: %{},
          description: "See [General Fields](https://modelcontextprotocol.io/specification/2025-06-18/basic#general-fields) for notes on _meta usage.",
          properties: %{progressToken: #{inspect(base_module())}.ProgressToken},
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
          properties: %{progressToken: #{inspect(base_module())}.ProgressToken},
          type: "object"
        }
      end
    end
    """
  end

  defp mod_map(defs, metaschema) do
    map = Map.new(defs, fn conf(name: name) -> {Atom.to_string(name), module_name(name)} end)

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

  defp classify_schema(conf) do
    conf(schema: schema, kind: nil, name: name) = conf

    {kind, schema} =
      case schema do
        %{type: "object", properties: _, required: required} ->
          schema =
            Map.merge(schema, %{
              required: Enum.map(required, &String.to_atom/1),
              title: Atom.to_string(name)
            })

          {:struct, schema}

        %{type: "object", properties: _} ->
          schema =
            Map.put(schema, :title, Atom.to_string(name))

          {:struct, schema}

        _ ->
          {:generic, schema}
      end

    conf(conf, kind: kind, schema: schema)
  end

  defp enforce_request_params_meta(conf, name) do
    conf(schema: schema) = conf

    schema =
      if request_params_schema?(name) do
        put_in(schema, [:properties, :_meta], %{
          "$ref": "#/definitions/RequestMeta"
        })
      else
        schema
      end

    conf(conf, schema: schema)
  end

  defp skip_request_fields(conf, name) do
    # Requests schemas in the official dependency do not inherit the generic
    # JSONRPCRequest `jsonrpc` and `id` fields, so we add them back.
    #
    # We will also skip the `jsonrpc` and `method` properties in the struct, as
    # they can be infered from the struct name.
    #
    # Finally we will add back the `jsonrpc` and `method` properties when the
    # schema is serialized.

    conf(name: name, schema: schema, opts: opts) = conf

    if rpc_request?(name) do
      %{const: method} = schema.properties.method

      schema = %{
        schema
        | properties:
            Map.merge(schema.properties, %{
              id: %{"$ref": "#/definitions/RequestId"},
              jsonrpc: %{const: @jsonrpc_vsn}
            })
      }

      conf(conf,
        schema: schema,
        opts:
          Keyword.merge(opts,
            skip_keys: [:method, :jsonrpc],
            serialize_merge: %{method: method, jsonrpc: @jsonrpc_vsn}
          )
      )
    else
      conf
    end
  end

  defp resource_type_as_default(conf, name) do
    conf(name: name, schema: schema) = conf

    schema =
      if set_default_resource_type?(name) do
        # This is done so we do not have to specify the type when creating a struct
        schema =
          update_in(schema.properties.type, fn %{const: type} = subschema ->
            Map.put(subschema, :default, type)
          end)

        # As we set is as default we will not require it anymore
        schema =
          update_in(schema.required, fn required ->
            true = "type" in required
            required -- ["type"]
          end)

        schema
      else
        schema
      end

    conf(conf, schema: schema)
  end

  defp use_schema_api(conf) do
    conf(schema: schema) = conf

    schema =
      schema
      |> traverse_replace_default_meta()
      |> trawverse_hardwrap_descriptions()
      |> traverse_use_schema_helpers()

    conf(conf, schema: schema)
  end

  defp traverse_replace_default_meta(schema) do
    Traverse.prewalk(schema, fn
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
  end

  defp trawverse_hardwrap_descriptions(schema) do
    Traverse.postwalk(schema, fn
      {:val, %{description: description} = map} when is_binary(description) ->
        if String.contains?(description, "\n") || String.length(description) > 50 do
          Map.update!(map, :description, &DescriptionWrapper.of/1)
        else
          map
        end

      other ->
        elem(other, 1)
    end)
  end

  defp traverse_use_schema_helpers(schema) do
    Traverse.postwalk(schema, fn
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

      {:val, %{const: value, type: t} = constschema} ->
        "string" = t
        true = is_binary(value)

        # If the const is a method we may have defined it as a default
        extra_args =
          case constschema do
            %{default: ^value} ->
              [[default: value]]

            %{default: other} ->
              raise "bad default value, should be #{inspect(value)}, got: #{inspect(other)}"

            _ ->
              []
          end

        CodeWrapper.of(:const, [value | extra_args])

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

  def base_module do
    GenMCP.MCP
  end

  defp module_name(name) do
    Module.concat(base_module(), name)
  end

  defp generate_module(conf) do
    conf(name: name, schema: schema, opts: opts, kind: kind) = conf
    IO.puts("generating #{name}")
    module = module_name(name)
    skip_keys = Keyword.get(opts, :skip_keys, nil)
    serialize_merge = Keyword.get(opts, :serialize_merge, nil)

    case kind do
      :struct ->
        """
        defmodule #{inspect(module)} do
          use JSV.Schema

          JsonDerive.auto(#{serialize_merge && inspect(serialize_merge)})

          #{skip_keys && "@skip_keys #{inspect(skip_keys)}"}

          defschema #{inspect(schema, inspect_opts())}

          @type t :: %__MODULE__{}
        end
        """

      :generic ->
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

  defp inspect_opts(overrides \\ []) do
    overrides ++ [pretty: true, custom_options: [sort_maps: true]]
  end
end

Generator.run()
