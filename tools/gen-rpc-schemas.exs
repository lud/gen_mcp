alias JSV.Helpers.Traverse

Mix.install([:jason, :jsv, :nimble_options], consolidate_protocols: false)
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
      to_string(~s'''
      ~SD"""
      #{hardwrap(description)}
      """\
      ''')
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
    end
  end
end

defmodule Context do
  defstruct [:mod_prefix, :mod_config]

  def mod_config(%{mod_config: mod_config}, name) do
    case Keyword.fetch(mod_config, name) do
      {:ok, cfg} ->
        cfg

      :error ->
        raise """
        Missing configuration for schema #{inspect(name)} in :mod_config option

            # Add the following into config

            #{name}: [],

            # Or add a skip

            #{name}: :nogen
        """
    end
  end

  def mod_config(ctx, name, key, default) do
    Keyword.get(mod_config(ctx, name), key, default)
  end

  def flagged?(ctx, name, flag) do
    case mod_config(ctx, name) do
      list when is_list(list) -> true == Keyword.get(list, flag)
      other -> raise "flags should not be called for #{inspect(other)} modules"
    end
  end

  # `:lax` definitions are not generated as modules; a `$ref` to one is rendered
  # as an accept-any schema (see Codegen.schema_with_jsv_helpers_deep/2).
  def lax?(ctx, name) when is_binary(name) do
    :lax == mod_config(ctx, String.to_atom(name))
  end
end

defmodule Codegen do
  def module_name(name, ctx) do
    Module.concat(ctx.mod_prefix, name)
  end

  def schema_hardwrap_description_deep(schema, _ctx) do
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

  def schema_with_jsv_helpers_deep(schema, ctx) do
    Traverse.postwalk(schema, fn
      {:val, %{"$ref": "#/$defs/" <> name} = schema} ->
        case Map.drop(schema, [:description, :"$schema"]) do
          rest when map_size(rest) == 1 ->
            if Context.lax?(ctx, name) do
              # Schema-in-data definitions (elicitation field descriptors:
              # PrimitiveSchemaDefinition and the *Schema / *EnumSchema variants)
              # are not modeled as structs; accept any value where they appear.
              %{}
            else
              module_name(name, ctx)
            end
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
        to_string_format_schema(schema)

      {:val, %{const: _} = schema} ->
        to_const_schema(schema)

      {:val, %{enum: values, type: "string"}} ->
        true = Enum.all?(values, &is_binary/1)
        atoms = Enum.map(values, &String.to_atom/1)

        CodeWrapper.of(:string_enum_to_atom, [atoms])

      other ->
        elem(other, 1)
    end)
  end

  defp to_string_format_schema(schema) do
    case schema.format do
      "uri" ->
        CodeWrapper.of(:uri, [format_schema_to_list(schema)])

      format when format in ["byte", "uri-template"] ->
        CodeWrapper.of(:string_of, [format, format_schema_to_list(schema)])
    end
  end

  defp to_const_schema(%{const: value} = schema) do
    :ok =
      case schema do
        %{type: "string"} -> :ok
        %{type: other} -> raise "unsupported const type: #{inspect(other)}"
        _ -> :ok
      end

    true = is_binary(value)

    # Besides :const and :type, a const subschema may carry a :description
    # (e.g. the `mode` discriminators on the elicitation request params). Keep
    # it on the rendered `const/2` helper; nothing else is expected.
    case Map.drop(schema, [:const, :type, :description]) do
      empty when map_size(empty) == 0 -> :ok
    end

    case schema do
      %{description: descr} -> CodeWrapper.of(:const, [value, [description: descr]])
      _ -> CodeWrapper.of(:const, [value])
    end
  end

  defp format_schema_to_list(schema) do
    schema
    |> Map.drop([:type, :format])
    |> Map.to_list()
    |> Enum.sort_by(&elem(&1, 0))
  end

  def render_struct_module(module, schema, render_opts) do
    skip_keys = Enum.sort(Keyword.get(render_opts, :skip_keys, []))
    keep_nils = Enum.sort(Keyword.get(render_opts, :keep_nils, %{}))
    serialize_merge = Keyword.get(render_opts, :serialize_merge, %{})
    method = Keyword.get(render_opts, :method)

    keep_nils =
      Enum.sort(
        case schema do
          %{required: [_ | _] = required} -> Enum.uniq((keep_nils ++ required) -- skip_keys)
          _ -> keep_nils -- skip_keys
        end
      )

    """
    defmodule #{inspect(module)} do
      use JSV.Schema

      JsonDerive.auto(_merge = #{inspect(serialize_merge)}, _keep_nils = #{inspect(keep_nils)})

      #{if skip_keys == [] do
      ""
    else
      "@skip_keys #{inspect(skip_keys)}"
    end}

      defschema #{inspect(schema, inspect_opts())}

      @type t :: %__MODULE__{}

      #{if method do
      "def method, do: #{inspect(method)}"
    end}

    end
    """
  end

  def render_schema_module(module, schema, render_opts \\ []) do
    """
    defmodule #{inspect(module)} do

    #{if Keyword.get(render_opts, :use_jsv, true) do
      "use JSV.Schema"
    end}

      #{Keyword.get(render_opts, :body, "")}

      def json_schema do
       #{inspect(schema, inspect_opts())}
      end
    end
    """
  end

  defp inspect_opts(overrides \\ []) do
    overrides ++ [pretty: true, custom_options: [sort_maps: true]]
  end
end

defmodule Generator do
  require Record

  Record.defrecordp(:entity, name: nil, schema: nil, render_opts: [], kind: nil)

  @subscriptions_listen_link "{@link SubscriptionsListenRequestsubscriptions/listen}"
  @cancelled_notification_method "notifications/cancelled"

  def run(source_schema_path, opts) do
    opts =
      NimbleOptions.validate!(opts,
        output_path: [type: :string, required: true],
        mod_prefix: [type: :atom, required: true],
        mod_config: [type: :keyword_list, required: true]
      )

    ctx = %Context{mod_prefix: opts[:mod_prefix], mod_config: opts[:mod_config]}

    schema =
      source_schema_path
      |> File.read!()
      |> Jason.decode!(keys: :atoms)

    defs = Map.fetch!(schema, :"$defs")
    validate_mod_config!(defs, ctx)

    metaschema = schema."$schema"
    info = build_info(schema)

    entitys =
      defs
      |> Enum.map(fn {name, schema} -> entity(name: name, schema: schema, render_opts: []) end)
      |> filter_schemas(ctx)
      |> Stream.map(&process_schema(&1, ctx))
      |> Enum.sort_by(fn entity(name: name) -> name end)

    # We can now generate the modules
    generated_modules = Enum.map_join(entitys, "\n\n", &generate_module(&1, ctx))

    IO.puts("generation done")

    generated_block = [
      prelude(ctx, info),
      mod_map(entitys, metaschema, ctx),
      generated_modules
    ]

    code = Enum.intersperse(generated_block, "\n\n")

    File.write!(opts[:output_path], code)
    IO.puts("wrote #{opts[:output_path]}, formatting...")

    case System.cmd("mix", ~w(format --migrate), into: IO.stream()) do
      {_, 0} ->
        IO.puts("schemas module generated")
        :ok

      {_, 1} ->
        IO.puts([IO.ANSI.red(), "Schemas generated with invalid syntax", IO.ANSI.reset()])
    end
  end

  defp skip_definition?(name, ctx) do
    Context.mod_config(ctx, name) in [:nogen, :lax]
  end

  defp validate_mod_config!(defs, ctx) do
    existing_names = defs |> Map.keys() |> MapSet.new()

    stale_names =
      ctx.mod_config
      |> Keyword.keys()
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(existing_names, &1))
      |> Enum.sort()

    case stale_names do
      [] ->
        :ok

      _ ->
        names = Enum.map_join(stale_names, "\n", &"  * #{inspect(&1)}")

        raise """
        Found stale schema entries in :mod_config. Remove or rename them to match the current source schema:

        #{names}
        """
    end
  end

  defp filter_schemas(defs, ctx) do
    Enum.reject(defs, fn entity(name: name) -> skip_definition?(name, ctx) end)
  end

  defp process_schema(entity, ctx) do
    entity
    |> skip_request_fields()
    |> skip_content_type(ctx)
    |> classify_schema()
    |> use_schema_api(ctx)
  end

  # TODO(spec008) listener request is not needed anymore
  def prelude(ctx, info) do
    [
      """
      # quokka:skip-module-directives

      require GenMCP.JsonDerive, as: JsonDerive
      """,
      ~s'''
      defmodule #{inspect(Codegen.module_name("ListenerRequest", ctx))} do
        @moduledoc """
        Represents a GET request from the StreamableHTTP client.
        """

        defstruct []
        @type t :: %__MODULE__{}
      end
      ''',
      render_info_module(ctx, info)
    ]
  end

  defp build_info(schema) do
    subscription_notification_methods =
      schema
      |> Map.fetch!(:"$defs")
      |> Enum.flat_map(fn {_, def_schema} ->
        case subscription_notification_method(def_schema) do
          nil -> []
          method -> [method]
        end
      end)
      |> Enum.uniq()
      |> Enum.sort()

    %{subscription_notification_methods: subscription_notification_methods}
  end

  defp subscription_notification_method(def_schema) do
    description = Map.get(def_schema, :description, "")

    with method when is_binary(method) <- get_in(def_schema, [:properties, :method, :const]),
         true <- String.starts_with?(method, "notifications/"),
         true <- method != @cancelled_notification_method,
         true <- subscription_listen_notification?(description) do
      method
    else
      _ -> nil
    end
  end

  defp subscription_listen_notification?(description) when is_binary(description) do
    description = String.replace(description, ~r/\s+/, " ")

    String.contains?(description, @subscriptions_listen_link)
  end

  defp render_info_module(ctx, info) do
    module = Codegen.module_name("Info", ctx)

    ~s'''
    defmodule #{inspect(module)} do
      @moduledoc false

      @subscription_notification_methods #{inspect(info.subscription_notification_methods)}

      @spec subscription_notification_methods() :: [String.t()]
      def subscription_notification_methods, do: @subscription_notification_methods

      def subscription_notification_method?(method)

      Enum.each(@subscription_notification_methods, fn method ->
        def subscription_notification_method?(unquote(method)) do
          true
        end
      end)

      def subscription_notification_method?(method) when is_binary(method) do
        false
      end
    end
    '''
  end

  defp mod_map(defs, metaschema, ctx) do
    map =
      Map.new(defs, fn entity(name: name) ->
        {Atom.to_string(name), Codegen.module_name(name, ctx)}
      end)

    schema = %{
      "$schema": metaschema,
      definitions: map
    }

    Codegen.render_schema_module(Codegen.module_name("ModMap", ctx), schema,
      use_jsv: false,
      body: """

        defmacro require_all do
          Enum.map(json_schema().definitions, fn {_, mod} ->
            quote do
              require unquote(mod)
            end
          end)
        end

      """
    )
  end

  defp classify_schema(entity) do
    entity(schema: schema, kind: nil, name: name) = entity

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

    entity(entity, kind: kind, schema: schema)
  end

  defp skip_request_fields(entity) do
    entity(schema: schema) = entity

    # Notifications have method + jsonrpc but no id (unlike requests)
    has_method_const = match?(%{const: _}, schema[:properties][:method])
    has_jsonrpc = Map.has_key?(schema[:properties] || %{}, :jsonrpc)

    if has_method_const and has_jsonrpc do
      entity
      |> with_method()
      |> with_skipped_consts([:method, :jsonrpc])
    else
      entity
    end
  end

  defp skip_content_type(entity, ctx) do
    entity(name: name) = entity

    if Context.flagged?(ctx, name, :content_block) do
      with_skipped_consts(entity, [:type])
    else
      entity
    end
  end

  defp with_method(entity) do
    entity(schema: schema, render_opts: render_opts) = entity
    entity(entity, render_opts: Keyword.put(render_opts, :method, schema.properties.method.const))
  end

  defp with_skipped_consts(entity, keys) do
    entity(schema: schema, render_opts: render_opts) = entity

    serialize_merge =
      Enum.reduce(keys, %{}, fn key, serialize_merge ->
        case schema do
          %{properties: %{^key => %{const: val}}} ->
            Map.put(serialize_merge, key, val)

          _ ->
            raise """
            schema does not define const for key #{inspect(key)}

            SCHEMA
            #{inspect(schema, pretty: true)}
            """
        end
      end)

    entity(entity,
      render_opts:
        Keyword.merge(render_opts,
          skip_keys: Map.keys(serialize_merge),
          serialize_merge: serialize_merge
        )
    )
  end

  defp use_schema_api(entity, ctx) do
    entity(schema: schema) = entity

    schema =
      schema
      |> Codegen.schema_hardwrap_description_deep(ctx)
      |> Codegen.schema_with_jsv_helpers_deep(ctx)

    entity(entity, schema: schema)
  end

  defp generate_module(entity, ctx) do
    entity(name: name, schema: schema, render_opts: render_opts, kind: kind) = entity

    IO.puts("generating #{name}")
    module = Codegen.module_name(name, ctx)
    keep_nils = Context.mod_config(ctx, name, :keep_nils, [])
    render_opts = Keyword.put(render_opts, :keep_nils, keep_nils)

    case kind do
      :struct ->
        Codegen.render_struct_module(module, schema, render_opts)

      :generic ->
        Codegen.render_schema_module(module, schema, render_opts)
    end
  end
end

Generator.run("deps/modelcontextprotocol/schema/draft/schema.json",
  output_path: "lib/gen_mcp/mcp/v2607/entities.ex",
  mod_prefix: GenMCP.MCP.V2607,
  # Allow/deny table reconciled against the 2026-07-28 draft `$defs`
  # (150 definitions). The generate-set is the transitive `$ref` closure of the
  # supported RPC surface; everything else is `:nogen`. Re-diff `$defs` vs this
  # list whenever the schema SHA is bumped in mix.exs.
  mod_config: [
    Annotations: [],
    AudioContent: [content_block: true],
    BaseMetadata: :nogen,
    BlobResourceContents: [],
    BooleanSchema: :lax,
    CacheableResult: [],
    CallToolRequest: [],
    CallToolRequestParams: [],
    CallToolResult: [],
    CallToolResultResponse: :nogen,
    CancelledNotification: [],
    CancelledNotificationParams: [],
    ClientCapabilities: [],
    ClientNotification: :nogen,
    ClientRequest: :nogen,
    ClientResult: :nogen,
    CompleteRequest: :nogen,
    CompleteRequestParams: :nogen,
    CompleteResult: :nogen,
    CompleteResultResponse: :nogen,
    ContentBlock: [],
    CreateMessageRequest: [],
    CreateMessageRequestParams: [],
    CreateMessageResult: [],
    Cursor: :nogen,
    DiscoverRequest: [],
    DiscoverResult: [],
    DiscoverResultResponse: :nogen,
    ElicitRequest: [],
    ElicitRequestFormParams: [],
    ElicitRequestParams: [],
    ElicitRequestURLParams: [],
    ElicitResult: [],
    EmbeddedResource: [content_block: true],
    EmptyResult: :nogen,
    EnumSchema: :lax,
    Error: [],
    GetPromptRequest: [],
    GetPromptRequestParams: [],
    GetPromptResult: [],
    GetPromptResultResponse: :nogen,
    HeaderMismatchError: :nogen,
    Icon: [],
    Icons: [],
    ImageContent: [content_block: true],
    Implementation: [],
    InputRequest: [],
    InputRequests: [],
    InputRequiredResult: [],
    InputResponse: [],
    InputResponseRequestParams: [],
    InputResponses: [],
    InternalError: :nogen,
    InvalidParamsError: :nogen,
    InvalidRequestError: :nogen,
    JSONArray: [],
    JSONObject: [],
    JSONRPCErrorResponse: [keep_nils: [:id]],
    JSONRPCMessage: :nogen,
    JSONRPCNotification: :nogen,
    JSONRPCRequest: [],
    JSONRPCResponse: [],
    JSONRPCResultResponse: [],
    JSONValue: [],
    LegacyTitledEnumSchema: :lax,
    ListPromptsRequest: [],
    ListPromptsResult: [],
    ListPromptsResultResponse: :nogen,
    ListResourceTemplatesRequest: [],
    ListResourceTemplatesResult: [],
    ListResourceTemplatesResultResponse: :nogen,
    ListResourcesRequest: [],
    ListResourcesResult: [],
    ListResourcesResultResponse: :nogen,
    ListRootsRequest: [],
    ListRootsResult: [],
    ListToolsRequest: [],
    ListToolsResult: [],
    ListToolsResultResponse: :nogen,
    LoggingLevel: [],
    LoggingMessageNotification: [],
    LoggingMessageNotificationParams: [],
    MetaObject: [],
    MethodNotFoundError: :nogen,
    MissingRequiredClientCapabilityError: :nogen,
    ModelHint: [],
    ModelPreferences: [],
    MultiSelectEnumSchema: :lax,
    Notification: :nogen,
    NotificationMetaObject: [],
    NotificationParams: [],
    NumberSchema: :lax,
    PaginatedRequest: :nogen,
    PaginatedRequestParams: [],
    PaginatedResult: :nogen,
    ParseError: :nogen,
    PrimitiveSchemaDefinition: :lax,
    ProgressNotification: [],
    ProgressNotificationParams: [],
    ProgressToken: [],
    Prompt: [],
    PromptArgument: [],
    PromptListChangedNotification: [],
    PromptMessage: [],
    PromptReference: :nogen,
    ReadResourceRequest: [],
    ReadResourceRequestParams: [],
    ReadResourceResult: [],
    ReadResourceResultResponse: :nogen,
    Request: :nogen,
    RequestId: [],
    RequestMetaObject: [],
    RequestParams: [],
    Resource: [],
    ResourceContents: :nogen,
    ResourceLink: [content_block: true],
    ResourceListChangedNotification: [],
    ResourceRequestParams: :nogen,
    ResourceTemplate: [],
    ResourceTemplateReference: :nogen,
    ResourceUpdatedNotification: [],
    ResourceUpdatedNotificationParams: [],
    Result: [],
    ResultType: :nogen,
    Role: [],
    Root: [],
    SamplingMessage: [],
    SamplingMessageContentBlock: [],
    ServerCapabilities: [],
    ServerNotification: :nogen,
    ServerResult: :nogen,
    SingleSelectEnumSchema: :lax,
    StringSchema: :lax,
    SubscriptionFilter: [],
    SubscriptionsAcknowledgedNotification: [],
    SubscriptionsAcknowledgedNotificationParams: [],
    SubscriptionsListenRequest: [],
    SubscriptionsListenRequestParams: [],
    SubscriptionsListenResult: [],
    SubscriptionsListenResultMeta: [],
    TextContent: [content_block: true],
    TextResourceContents: [],
    TitledMultiSelectEnumSchema: :lax,
    TitledSingleSelectEnumSchema: :lax,
    Tool: [],
    ToolAnnotations: [],
    ToolChoice: [],
    ToolListChangedNotification: [],
    ToolResultContent: [],
    ToolUseContent: [],
    UnsupportedProtocolVersionError: :nogen,
    UntitledMultiSelectEnumSchema: :lax,
    UntitledSingleSelectEnumSchema: :lax
  ]
)
