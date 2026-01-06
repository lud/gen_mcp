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

    IO.puts("generation done")

    generated_block = [
      prelude(),
      mod_map(confs, metaschema),
      generated_modules
    ]

    code = Enum.intersperse(generated_block, "\n\n")

    output_path = "lib/gen_mcp/mcp/entities.ex"
    File.write!(output_path, code)
    IO.puts("wrote #{output_path}, formatting...")

    {_, 0} = System.cmd("mix", ~w(format --migrate))
    IO.puts("schemas module generated")
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
        :nogen

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
        :nogen

      :SubscribeRequest ->
        [rpc_request: true]

      :UnsubscribeRequest ->
        [rpc_request: true]

      :Annotations ->
        []

      :AudioContent ->
        [content_block: true]

      :BaseMetadata ->
        :nogen

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
        :nogen

      :ClientRequest ->
        :nogen

      :ClientResult ->
        :nogen

      :CompleteResult ->
        :nogen

      :ContentBlock ->
        []

      :CreateMessageRequest ->
        :nogen

      :CreateMessageResult ->
        :nogen

      :Cursor ->
        :nogen

      :ElicitRequest ->
        :nogen

      :ElicitResult ->
        :nogen

      :EmbeddedResource ->
        [content_block: true]

      :EmptyResult ->
        :nogen

      :EnumSchema ->
        :nogen

      :GetPromptResult ->
        []

      :ImageContent ->
        [content_block: true]

      :Implementation ->
        []

      :InitializedNotification ->
        []

      :InitializeResult ->
        []

      :JSONRPCError ->
        []

      :JSONRPCMessage ->
        :nogen

      :JSONRPCNotification ->
        :nogen

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
        :nogen

      :ListRootsResult ->
        :nogen

      :ListToolsResult ->
        []

      :LoggingLevel ->
        :nogen

      :LoggingMessageNotification ->
        :nogen

      :ModelHint ->
        :nogen

      :ModelPreferences ->
        :nogen

      :Notification ->
        :nogen

      :NumberSchema ->
        :nogen

      :PaginatedRequest ->
        :nogen

      :PaginatedResult ->
        :nogen

      :PrimitiveSchemaDefinition ->
        :nogen

      :ProgressNotification ->
        []

      :ProgressToken ->
        []

      :Prompt ->
        []

      :PromptArgument ->
        []

      :PromptListChangedNotification ->
        :nogen

      :PromptMessage ->
        []

      :PromptReference ->
        :nogen

      :ReadResourceResult ->
        []

      :Request ->
        :nogen

      :RequestId ->
        []

      :Resource ->
        []

      :ResourceContents ->
        :nogen

      :ResourceLink ->
        [content_block: true]

      :ResourceListChangedNotification ->
        :nogen

      :ResourceTemplate ->
        []

      :ResourceTemplateReference ->
        :nogen

      :ResourceUpdatedNotification ->
        :nogen

      :Result ->
        []

      :Role ->
        []

      :Root ->
        :nogen

      :RootsListChangedNotification ->
        []

      :SamplingMessage ->
        :nogen

      :ServerCapabilities ->
        []

      :ServerNotification ->
        :nogen

      :ServerRequest ->
        :nogen

      :ServerResult ->
        :nogen

      :StringSchema ->
        :nogen

      :TextContent ->
        [content_block: true]

      :TextResourceContents ->
        []

      :Tool ->
        []

      :ToolAnnotations ->
        []

      :ToolListChangedNotification ->
        :nogen
    end
  end

  defp skip_definition?(name) do
    :nogen == module_config(name)
  end

  defp request_params_schema?(name) do
    true == Keyword.get(module_config(name), :rpc_request_params)
  end

  defp rpc_request?(name) do
    true == Keyword.get(module_config(name), :rpc_request)
  end

  defp content_block?(name) do
    true == Keyword.get(module_config(name), :content_block)
  end

  defp filter_schemas(defs) do
    Enum.reject(defs, fn conf(name: name) -> skip_definition?(name) end)
  end

  defp process_schema(conf) do
    conf
    |> enforce_request_params_meta()
    |> skip_request_fields()
    |> skip_content_type()
    |> classify_schema()
    |> use_schema_api()
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

    defmodule #{inspect(module_name("ListenerRequest"))} do
      @moduledoc \"""
      Represents a GET request from the StreamableHTTP client.
      \"""

      defstruct []
      @type t :: %__MODULE__{}
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
          schema = Map.put(schema, :required, Enum.map(required, &String.to_atom/1))

          {:struct, schema}

        %{type: "object", properties: _} ->
          {:struct, schema}

        _ ->
          {:generic, schema}
      end

    schema = Map.put_new(schema, :title, "MCP:" <> Atom.to_string(name))

    conf(conf, kind: kind, schema: schema)
  end

  defp enforce_request_params_meta(conf) do
    conf(schema: schema, name: name) = conf

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

  defp skip_request_fields(conf) do
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

  defp skip_content_type(conf) do
    conf(name: name, schema: schema, opts: opts) = conf

    if content_block?(name) do
      %{const: type} = schema.properties.type
      conf(conf, opts: Keyword.merge(opts, skip_keys: [:type], serialize_merge: %{type: type}))
    else
      conf
    end
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

      {:val, %{const: value} = constschema} ->
        :ok =
          case constschema do
            %{type: "string"} -> :ok
            %{type: other} -> raise "unsupported const type: #{inspect(other)}"
            _ -> :ok
          end

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
    serialize_merge = Keyword.get(opts, :serialize_merge, %{})

    serialize_keep =
      case schema do
        %{required: [_ | _] = keys} -> keys -- (skip_keys || [])
        _ -> []
      end

    case kind do
      :struct ->
        """
        defmodule #{inspect(module)} do
          use JSV.Schema

          JsonDerive.auto(#{inspect(serialize_merge)}, #{inspect(serialize_keep)})

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
