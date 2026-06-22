defmodule GenMCP.Suite.Tool do
  @moduledoc ~S"""
  Behaviour for a tool served by a `GenMCP.Suite`.

  A tool is an operation a client invokes with a `tools/call` request. You
  implement this behaviour in a module, list it in a Suite's `:tools`, and the
  Suite advertises the tool in `tools/list` and routes matching calls to it. A
  tool declares its name and the schema of its arguments, validates incoming
  arguments against that schema, and runs the call.

  `use GenMCP.Suite.Tool` generates the metadata and validation callbacks from a
  few options, leaving you to implement `c:call/3`. Keep the tool a thin adapter:
  push the real work into a plain module with no library concern, so the tool
  only validates arguments and shapes the result.

      defmodule MyApp.Calculator do
        def add(a, b) do
          a + b
        end
      end

      defmodule MyApp.AddTool do
        use GenMCP.Suite.Tool,
          name: "add",
          description: "Adds two numbers and returns the sum.",
          input_schema: %{
            type: :object,
            properties: %{
              a: %{type: :number},
              b: %{type: :number}
            },
            required: [:a, :b]
          }

        alias GenMCP.MCP.V2607, as: MCP

        @impl true
        def call(request, _channel, _arg) do
          %{"a" => a, "b" => b} = request.params.arguments
          {:result, MCP.call_tool_result(text: "#{MyApp.Calculator.add(a, b)}")}
        end
      end

  Here `:input_schema` is a plain JSON Schema map, so `request.params.arguments`
  reaches `c:call/3` as a map with string keys. A schema can also be a `JSV`
  module that casts the arguments into a struct; see the "JSV integration"
  section.

  ### Wiring a tool into a server

  Tools are served by a `GenMCP.Suite`, which is the default `:server` for
  `GenMCP.Transport.StreamableHTTP`. List the tool module in the `:tools` option
  and pass the Suite options straight to the transport plug in your router:

      # In your router
      forward "/mcp", GenMCP.Transport.StreamableHTTP,
        server_name: "My App",
        server_version: "1.0.0",
        tools: [MyApp.AddTool]

  Pass `{MyApp.AddTool, arg}` instead of the bare module to attach a configuration
  term, handed to every callback as its last argument (see "Provider arguments").

  ### Validating arguments

  With an `:input_schema`, `use GenMCP.Suite.Tool` generates `c:validate_request/2`,
  which validates `request.params.arguments` against the schema before `c:call/3`
  runs. An invalid request is answered with an invalid-parameters error and
  `c:call/3` is never reached.

  The validated arguments reach `c:call/3` as `request.params.arguments`. Their
  form depends on the schema:

    * a plain map schema keeps them as a map with string keys;
    * a schema module built with `defschema` casts them into that struct.

  To validate by other means, for example casting with an `Ecto` embedded schema,
  implement `c:validate_request/2` yourself. When you do, `use GenMCP.Suite.Tool`
  skips generating one, and the `:input_schema` is then used only to describe the
  tool in `tools/list`.

  ### JSV integration

  The `:input_schema` and `:output_schema` options each accept either a plain JSON
  Schema map (as in the example above) or a `JSV` schema module. A schema module
  built with `defschema` also defines a struct, and validation casts the arguments
  into it, so `c:call/3` receives a struct instead of a string-keyed map:

      defmodule MyApp.AddTool do
        use GenMCP.Suite.Tool,
          name: "add",
          description: "Adds two numbers and returns the sum.",
          input_schema: Add

        use JSV.Schema

        alias GenMCP.MCP.V2607, as: MCP

        defschema Add,
          a: number(),
          b: number()

        @impl true
        def call(request, _channel, _arg) do
          %Add{a: a, b: b} = request.params.arguments
          {:result, MCP.call_tool_result(text: "#{MyApp.Calculator.add(a, b)}")}
        end
      end

  The schema module can be named before it is defined, as above with
  `input_schema: Add` written over the `defschema Add`. `use GenMCP.Suite.Tool`
  builds the `JSV` root from a `@before_compile` hook, which runs after the whole
  module body, so the schema module already exists by the time the root is built.

  A schema module may reference other schema modules as subschemas. The schema the
  Suite advertises in `tools/list` is self-contained: the referenced definitions
  are inlined into it.

  #### Build options

  The generated `c:validate_request/2` validates against a `JSV` root built at
  compile time with `formats: true` and `atoms: true`. Pass `:jsv_build_opts` to
  merge options on top of those defaults. Each key you give wins over the default,
  so to change `:formats` or `:atoms` set them explicitly:

      use GenMCP.Suite.Tool,
        name: "schedule_meeting",
        input_schema: Input,
        jsv_build_opts: [
          formats: [MyApp.Formats | JSV.default_format_validator_modules()]
        ]

  See `JSV.build/2` for the full list of options.

  ### Streaming tools

  A tool does not have to answer in one step. When `c:call/3` returns `{:stream,
  state}`, the worker stays alive and every process message it then receives is
  handed to `c:handle_message/4` with that `state`. Each `c:handle_message/4` call
  returns the same shapes as `c:call/3`: `{:stream, new_state}` to keep waiting,
  `{:result, result}` to finish, or `{:error, reason}` to fail. While streaming, a
  tool can push interim progress to the client with `GenMCP.Mux.Channel.send_progress/4`
  on the `channel` it was given. If the client disconnects first, the optional
  `c:handle_close/3` runs so the tool can clean up.

  This makes the tool the active streaming handler for the request. Subscribe to
  your own event source (a `Phoenix.PubSub` topic, progress messages from a job
  queue) before returning `{:stream, state}`, then translate the messages you
  receive in `c:handle_message/4`.

  ### Provider arguments

  Every tool callback ends with `arg`, the configuration term attached to the
  module as `{module, arg}` in the Suite's `:tools` (a bare module is treated as
  `{module, []}`). It lets one generic tool module behave differently in different
  Suites.

  The callbacks that act on a request, `c:call/3`, `c:handle_message/4`, and
  `c:handle_close/3`, also receive the request-scoped `t:GenMCP.Mux.Channel.t/0`
  as their second-to-last argument. It carries the read-only client `meta` and
  authorization assigns, and is how a tool sends progress, logs, and
  notifications. See `GenMCP.Suite` for the shared provider conventions.
  """

  import GenMCP.Utils.CallbackExt

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel

  @type tool_annotations :: %{
          optional(:__struct__) => MCP.ToolAnnotations,
          optional(:destructiveHint) => boolean,
          optional(:idempotentHint) => boolean,
          optional(:openWorldHint) => boolean,
          optional(:readOnlyHint) => boolean,
          optional(:title) => String.t()
        }
  @type tool :: module | {module, arg} | tool_descriptor
  @type tool_descriptor :: %{
          required(:name) => String.t(),
          required(:mod) => module,
          required(:arg) => arg
        }
  @type info_key :: :name | :title | :description | :annotations | :_meta
  @type arg :: term
  @type schema :: term
  @type state :: term

  @type client_state :: term

  @type call_result ::
          {:result, MCP.CallToolResult.t()}
          | {:stream, state}
          | {:input_required,
             %{
               optional(binary) =>
                 GenMCP.MCP.V2607.CreateMessageRequest.t()
                 | GenMCP.MCP.V2607.ListRootsRequest.t()
                 | GenMCP.MCP.V2607.ElicitRequest.t()
             }, client_state}
          | {:error, String.t()}

  @type request :: term

  @type client_response :: term
  # MCP.CreateMessageResult.t()
  # | MCP.ListRootsResult.t()
  # | MCP.ElicitResult.t()
  #

  @doc """
  Returns the tool metadata for the given key.

  The Suite calls this once per metadata field to build the `tools/list` entry.
  `:name` must return a non-blank string; the other keys may return `nil` when the
  tool does not set them. The recognized keys are:

    * `:name` - the tool's name, used by clients to call it. Required.
    * `:description` - a human-readable description, or `nil`.
    * `:title` - a short display title, or `nil`.
    * `:annotations` - a `t:tool_annotations/0` map of behaviour hints
      (`:readOnlyHint`, `:destructiveHint`, and so on), or `nil`.
    * `:_meta` - a free-form metadata map passed through to the client, or `nil`.

  `use GenMCP.Suite.Tool` generates this callback from the `:name`,
  `:description`, `:title`, `:annotations`, and `:_meta` options, with a catch-all
  clause returning `nil`. Implement it by hand only when the metadata is computed
  rather than static:

      def info(:name, _arg), do: "search_files"
      def info(:description, _arg), do: "Searches for files matching a glob."
      def info(:annotations, _arg), do: %{readOnlyHint: true}
      def info(_key, _arg), do: nil
  """
  @callback info(:name, arg) :: String.t()
  @callback info(:description, arg) :: nil | String.t()
  @callback info(:title, arg) :: nil | String.t()
  @callback info(:annotations, arg) :: nil | tool_annotations
  @callback info(:_meta, arg) :: nil | map()

  @doc """
  Returns the schema describing the tool's accepted arguments.

  The Suite normalizes this to JSON Schema and sends it as the tool's
  `inputSchema` in `tools/list`, so clients know what arguments to provide. The
  return may be a plain schema map or a `defschema` module:

      def input_schema(_arg) do
        %{
          type: :object,
          properties: %{query: %{type: :string}},
          required: [:query]
        }
      end

  `use GenMCP.Suite.Tool` generates this callback from the `:input_schema`
  option, and from the same option also generates `c:validate_request/2` that
  enforces the schema on each call.
  """
  @callback input_schema(arg) :: schema

  @doc """
  Returns the schema describing the tool's structured result, or `nil`.

  Optional. When given, the Suite normalizes it to JSON Schema and advertises it
  as the tool's `outputSchema` in `tools/list`, so clients know the shape of the
  `structuredContent` to expect. It is purely descriptive and is not enforced
  against the result at runtime.

  `use GenMCP.Suite.Tool` generates this callback from the `:output_schema`
  option. Like `c:input_schema/1`, the return may be a plain schema map or a
  `defschema` module:

      def output_schema(_arg) do
        %{
          type: :object,
          properties: %{files: %{type: :array, items: %{type: :string}}}
        }
      end
  """
  @callback output_schema(arg) :: nil | schema

  @doc """
  Validates, and optionally transforms, the request before `c:call/3` runs.

  Returns `{:ok, request}` to proceed (with a possibly rewritten request), or
  `{:error, reason}` to reject the call with an invalid-parameters error, in which
  case `c:call/3` is never invoked. The `reason` may be a message string, a
  `JSV.ValidationError`, or any exception.

  `use GenMCP.Suite.Tool` generates this callback from the `:input_schema` option:
  it validates `request.params.arguments` against the schema and, on success,
  replaces them with the validated value (a struct when the schema is a
  `defschema` module). Defining `c:validate_request/2` yourself stops it from
  generating one, which is how you validate by other means:

      def validate_request(request, _arg) do
        case request.params.arguments do
          %{"limit" => n} when n in 1..100 -> {:ok, request}
          _ -> {:error, "limit must be between 1 and 100"}
        end
      end
  """
  @callback validate_request(MCP.CallToolRequest.t(), arg) ::
              {:ok, MCP.CallToolRequest.t()} | {:error, String.t() | Exception.t()}

  @doc ~S"""
  Runs the tool call and returns its result.

  This is the one callback every tool implements. It receives the `request` (with
  arguments already validated by `c:validate_request/2`), the request-scoped
  `channel`, and the configured `arg`. Build the result with the
  `GenMCP.MCP.V2607` helpers, most often `GenMCP.MCP.V2607.call_tool_result/1`.

  Note the return tuples carry no channel: the channel is for sending interim
  output during the call, not for handing back.

      @impl true
      def call(request, _channel, _arg) do
        %{"city" => city} = request.params.arguments
        {:result, MCP.call_tool_result(text: "It is sunny in #{city}.")}
      end

  ### Return values

    * `{:result, result}` answers the call. `result` is a
      `t:GenMCP.MCP.V2607.CallToolResult.t/0`, typically from
      `GenMCP.MCP.V2607.call_tool_result/1`. Pass `error: message` to that helper
      to return a tool-level error the model can read, as opposed to a protocol
      error.
    * `{:stream, state}` keeps the worker alive as the request's streaming
      handler. `state` is carried to the next `c:handle_message/4`. See the
      "Streaming tools" section of the module doc.
    * `{:error, reason}` fails the call with a protocol error. `reason` is a
      message string.
    * `{:input_required, requests, client_state}` asks the client to satisfy one
      or more nested requests (sampling, roots, or elicitation) before retrying.
      `requests` is a map of request id to request struct, and `client_state` is
      node-portable plain data the Suite seals into the opaque `requestState` it
      returns, then hands back as `request.params.requestState` on the retry.

  Returning a tool-level error from a successful call, rather than a protocol
  error, lets the client see the message:

      def call(_request, _channel, _arg) do
        {:result, MCP.call_tool_result(error: "Upstream service unavailable")}
      end
  """
  @callback call(MCP.CallToolRequest.t(), Channel.t(), arg) :: call_result

  @doc """
  Handles a process message delivered to a streaming tool.

  Invoked once for every message the worker process receives after `c:call/3` (or
  a previous `c:handle_message/4`) returned `{:stream, state}`. The `message` is
  whatever was sent to the worker, `channel` is the request-scoped channel,
  `state` is the term carried from the previous return, and `arg` is the
  configured argument. Returns the same shapes as `c:call/3`.

  Match on the messages your tool subscribed to. The example below forwards a job
  result from the application's own queue and finishes the call:

      @impl true
      def handle_message({:job_finished, result}, _channel, _state, _arg) do
        {:result, MCP.call_tool_result(text: result)}
      end

  Return `{:stream, new_state}` instead to keep waiting, accumulating progress in
  `new_state`, and emit interim updates with `GenMCP.Mux.Channel.send_progress/4`:

      def handle_message({:chunk, data}, channel, acc, _arg) do
        GenMCP.Mux.Channel.send_progress(channel, length(acc) + 1, nil, "received chunk")
        {:stream, [data | acc]}
      end

      def handle_message(:done, _channel, acc, _arg) do
        {:result, MCP.call_tool_result(text: Enum.join(Enum.reverse(acc)))}
      end
  """
  @callback handle_message(term, Channel.t(), state, arg) :: call_result

  @doc """
  Runs cleanup when the client disconnects during a streaming call.

  Optional. Invoked when the client closes the connection while this tool is the
  active streaming handler (after `c:call/3` returned `{:stream, state}`). The
  `channel` is already closed, so nothing more can be sent; `state` is the latest
  streaming state and `arg` the configured argument. The return value is ignored
  and the worker stops afterward, so use it only for side-effecting cleanup such
  as unsubscribing from your event source.

      @impl true
      def handle_close(_channel, _state, _arg) do
        :ok
      end
  """
  @callback handle_close(Channel.t(), state, arg) :: term

  @doc """
  Returns the cache hint `{scope, ttl_ms}` for the tool, as `{:public | :private,
  milliseconds}`.

  Optional. When implemented, the value is used as the tool's cache hint;
  otherwise the no-cache default from `GenMCP.MCP.V2607.default_cache_control/0`
  applies. Use `:public` for results safe to share across clients and `:private`
  for per-caller results.

  `use GenMCP.Suite.Tool` generates this callback from the `:cache_control`
  option, given as the `{scope, ttl_ms}` tuple itself:

      use GenMCP.Suite.Tool,
        name: "list_countries",
        input_schema: %{},
        cache_control: {:public, :timer.minutes(5)}

  Implement it by hand instead when the hint is computed from `arg`:

      @impl true
      def cache_control(_arg) do
        {:public, :timer.minutes(5)}
      end
  """
  @callback cache_control(arg) :: {:public | :private, non_neg_integer()}

  @optional_callbacks validate_request: 2,
                      handle_message: 4,
                      handle_close: 3,
                      output_schema: 1,
                      cache_control: 1

  # TODO(doc) we need to document how to `use` in @moduledoc, with an example on
  # how to use JSV schemas

  defmacro __using__(opts) do
    quote do
      @gen_mcp_suite_too_opts unquote(Macro.escape(opts))
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(env) do
    opts = Module.get_attribute(env.module, :gen_mcp_suite_too_opts)

    quote do
      # The behaviour option is only used to remove warnings from tests, to test
      # incomplete tool implementation.
      case unquote(opts[:behaviour]) do
        false -> :ok
        _ -> @behaviour unquote(__MODULE__)
      end

      unquote(def_infos(opts))

      unquote(
        def_validator(
          opts[:input_schema],
          opts[:jsv_build_opts],
          _validate_request? = not Module.defines?(env.module, {:validate_request, 2})
        )
      )

      unquote(def_output_schema(opts[:output_schema]))
      unquote(def_cache_control(opts[:cache_control]))
    end
  end

  defp def_infos(infos) do
    quote bind_quoted: binding() do
      @impl true

      keys = [:name, :title, :description, :annotations, :_meta]

      values =
        Enum.flat_map(keys, fn k ->
          case Keyword.fetch(infos, k) do
            {:ok, v} ->
              GenMCP.Suite.Tool.__validate_use__(k, v)
              [{k, v}]

            :error ->
              []
          end
        end)

      values =
        if length(values) < length(keys) do
          values ++ [:catchall]
        else
          values
        end

      Enum.each(values, fn
        {k, v} ->
          def info(unquote(k), _arg) do
            unquote(Macro.escape(v))
          end

        :catchall ->
          def info(_key, _arg) do
            nil
          end
      end)
    end
  end

  # No input schema defined, maybe it will be implemented by hand, so we do not
  # raise here.
  defp def_validator(nil, _, _) do
    []
  end

  defp def_validator(input_opt, _jsv_build_opts, false = _validate_request?) do
    quote bind_quoted: [input_opt: input_opt] do
      @impl true
      def input_schema(_arg) do
        unquote(Macro.escape(input_opt))
      end
    end
  end

  defp def_validator(input_opt, jsv_build_opts, true = _validate_request?) do
    quote bind_quoted: [input_opt: input_opt, jsv_build_opts: jsv_build_opts] do
      jsv_build_opts = jsv_build_opts || []
      GenMCP.Suite.Tool.__validate_use__(:jsv_build_opts, jsv_build_opts)
      build_opts = Keyword.merge([formats: true, atoms: true], jsv_build_opts)
      GenMCP.Suite.Tool.__validate_use__(:input_schema, input_opt)

      @jsv_input_root JSV.build!(input_opt, build_opts)

      @impl true
      def input_schema(_arg) do
        unquote(Macro.escape(input_opt))
      end

      @impl true
      def validate_request(req, _) do
        %{params: params} = req

        arguments =
          case params do
            %{arguments: arguments} -> arguments
            %{} -> nil
          end

        case JSV.validate(arguments, @jsv_input_root) do
          {:ok, new_arguments} ->
            req = %{req | params: %{params | arguments: new_arguments}}
            {:ok, req}

          {:error, e} ->
            {:error, e}
        end
      end
    end
  end

  defp def_output_schema(nil) do
    []
  end

  defp def_output_schema(output_opt) do
    quote bind_quoted: [output_opt: output_opt] do
      @impl true
      def output_schema(_arg) do
        unquote(Macro.escape(output_opt))
      end
    end
  end

  # No cache_control option: the callback is optional, so we leave it
  # unimplemented rather than generate a function that returns a default.
  defp def_cache_control(nil) do
    []
  end

  defp def_cache_control(cache_opt) do
    quote bind_quoted: [cache_opt: cache_opt] do
      GenMCP.Suite.Tool.__validate_use__(:cache_control, cache_opt)

      @impl true
      def cache_control(_arg) do
        unquote(Macro.escape(cache_opt))
      end
    end
  end

  @doc """
  Normalizes a tool spec into a `t:tool_descriptor/0`.

  Accepts the three forms a Suite's `:tools` entry may take: a bare `module`, a
  `{module, arg}` tuple, or an already-built descriptor. It loads the module,
  reads its name via `c:info/2`, and returns `%{name: name, mod: module, arg:
  arg}`, raising `ArgumentError` when the tool does not define a non-blank name.
  `GenMCP.Suite` calls this to resolve every configured tool.
  """
  @spec expand(tool) :: tool_descriptor
  def expand(%{name: _, mod: _, arg: _} = tool) do
    tool
  end

  def expand(mod) when is_atom(mod) do
    expand({mod, []})
  end

  def expand({mod, arg}) when is_atom(mod) do
    Code.ensure_loaded!(mod)
    name = mod.info(:name, arg)

    if !is_binary(name) or String.trim(name) == "" do
      raise ArgumentError, "tool #{inspect(mod)} must define a valid name"
    end

    %{name: name, mod: mod, arg: arg}
  end

  @doc """
  Builds the `t:GenMCP.MCP.V2607.Tool.t/0` entry for a `tools/list` response.

  Gathers the tool's metadata through `c:info/2` and normalizes its
  `c:input_schema/1` and `c:output_schema/1` to JSON Schema. Accepts any tool spec
  form (it runs `expand/1` first). `GenMCP.Suite` calls this for every tool when
  answering `tools/list`.
  """
  @spec describe(tool) :: MCP.Tool.t()
  def describe(tool) do
    %{mod: mod, arg: arg, name: name} = expand(tool)

    %MCP.Tool{
      name: name,
      _meta: mod.info(:_meta, arg),
      annotations: mod.info(:annotations, arg),
      description: mod.info(:description, arg),
      title: mod.info(:title, arg),
      inputSchema: normalize_schema(mod.input_schema(arg)),
      outputSchema: normalize_schema(output_schema(mod, arg))
    }
  end

  @doc """
  Returns the cache hint `{scope, ttl_ms}` for a tool descriptor.

  Delegates to the tool's optional `c:cache_control/1` callback, falling back to
  `GenMCP.MCP.V2607.default_cache_control/0` when the tool does not implement it.
  `GenMCP.Suite` uses the hint when caching the tool's response.
  """
  @spec cache_control(tool_descriptor) :: {:public | :private, non_neg_integer()}
  def cache_control(tool) do
    %{mod: mod, arg: arg} = tool

    if function_exported?(mod, :cache_control, 1) do
      callback __MODULE__, mod.cache_control(arg) do
        {scope, ttl} when scope in [:public, :private] and is_integer(ttl) and ttl >= 0 ->
          {scope, ttl}
      end
    else
      MCP.default_cache_control()
    end
  end

  defp output_schema(mod, arg) do
    if function_exported?(mod, :output_schema, 1) do
      mod.output_schema(arg)
    end
  end

  defp normalize_schema(schema) when is_atom(schema) when is_map(schema) do
    schema
    |> JSV.Schema.normalize_collect(as_root: true)
    |> JSV.Helpers.Traverse.prewalk(fn
      {:val, map} when is_map(map) -> Map.drop(map, ["jsv-cast", "x-jsv-cast"])
      other -> elem(other, 1)
    end)
  end

  @doc false
  def __validate_use__(:name = k, value) do
    if is_binary(value) && String.trim(value) != "" do
      :ok
    else
      raise_invalid_use_info(k, value, "must be a non blank string")
    end
  end

  def __validate_use__(k, value) when k in [:title, :description] do
    if is_nil(value) || (is_binary(value) && String.trim(value) != "") do
      :ok
    else
      raise_invalid_use_info(k, value, "must be a non blank string")
    end
  end

  def __validate_use__(k, value) when k in [:annotations, :_meta] do
    if is_nil(value) || is_map(value) do
      :ok
    else
      raise_invalid_use_info(k, value, "must be a map")
    end
  end

  def __validate_use__(:input_schema = k, value) do
    if is_map(value) || (is_atom(value) && JSV.Schema.schema_module?(value)) do
      :ok
    else
      raise_invalid_use_info(k, value, "must be a map or a module-based schema")
    end
  end

  def __validate_use__(:jsv_build_opts = k, value) do
    if Keyword.keyword?(value) do
      :ok
    else
      raise_invalid_use_info(k, value, "must be a keyword list")
    end
  end

  def __validate_use__(:cache_control = k, value) do
    case value do
      {scope, ttl} when scope in [:public, :private] and is_integer(ttl) and ttl >= 0 ->
        :ok

      _ ->
        raise_invalid_use_info(k, value, "must be a {:public | :private, non_neg_integer} tuple")
    end
  end

  @spec raise_invalid_use_info(atom, term, binary) :: no_return()
  defp raise_invalid_use_info(key, value, errmsg) do
    raise ArgumentError,
          "option #{inspect(key)} given to `use #{inspect(__MODULE__)}` #{errmsg}, got: #{inspect(value)}"
  end

  defmacrop __call_tool__({_, _, _} = call) do
    quote do
      callback __MODULE__, unquote(call) do
        {:result, %MCP.CallToolResult{}} = result -> result
        {:stream, state} -> {:stream, state}
        {:error, reason} -> {:error, cast_error(reason)}
        {:input_required, %{} = input_requests, %{} = request_state} = resp -> resp
      end
    end
  end

  @doc """
  Validates the request and invokes the tool's `c:call/3` callback.

  Runs the tool's `c:validate_request/2` first (the generated one, or a custom
  one the tool defines); on failure it returns `{:error, {:invalid_params,
  reason}}` and `c:call/3` is not called. On success it dispatches to `c:call/3`
  and returns its result. `GenMCP.Suite` calls this when handling a `tools/call`
  request.
  """
  @spec call(tool_descriptor, MCP.CallToolRequest.t(), Channel.t()) :: call_result
  def call(tool, %MCP.CallToolRequest{} = req, channel) do
    %{params: %MCP.CallToolRequestParams{name: name}} = req
    %{mod: mod, arg: arg, name: ^name} = tool

    case validate_request(tool, req) do
      {:ok, req} -> __call_tool__(mod.call(req, channel, arg))
      {:error, {:invalid_params, reason}} -> {:error, {:invalid_params, reason}}
      {:error, reason} -> {:error, {:invalid_params, reason}}
    end
  end

  # TODO(optim) cache exported optional in expand phase
  defp validate_request(tool, req) do
    %{mod: mod, arg: arg} = tool

    if function_exported?(mod, :validate_request, 2) do
      callback __MODULE__, mod.validate_request(req, arg) do
        {:ok, req} -> {:ok, req}
        {:error, _} = err -> err
      end
    else
      {:ok, req}
    end
  end

  defp cast_error(e) when is_binary(e) do
    e
  end

  defp cast_error(%JSV.ValidationError{} = e) do
    e
  end

  # We allow Tool.call callback to return invalid params if users want to
  # perform parameter validation here directly. The errors module will skip the
  # reason if it does not know how to stringify it.
  defp cast_error({:invalid_params, _} = e) do
    e
  end

  defp cast_error(%{__exception__: true} = e) do
    Exception.message(e)
  end

  defp cast_error(e) do
    to_string(e)
  rescue
    Protocol.UndefinedError -> inspect(e)
  end

  @doc """
  Dispatches a streaming message to the tool's `c:handle_message/4` callback.

  Invoked by `GenMCP.Suite` for each process message the worker receives while
  this tool is the active streaming handler. The `state` is the term the tool
  last returned in `{:stream, state}`. Returns the callback's result.
  """
  @spec handle_message(tool_descriptor, term, Channel.t(), state) :: call_result
  def handle_message(tool, message, channel, state) do
    %{mod: mod, arg: arg} = tool
    __call_tool__(mod.handle_message(message, channel, state, arg))
  end

  @doc """
  Dispatches a client-close to the tool's optional `c:handle_close/3` callback.

  Invoked by `GenMCP.Suite` when the client disconnects while this tool is the
  active streaming handler. A no-op returning `:ok` when the tool does not
  implement `c:handle_close/3`. The return value is ignored.
  """
  @spec handle_close(tool_descriptor, Channel.t(), state) :: term
  def handle_close(tool, channel, state) do
    %{mod: mod, arg: arg} = tool

    if function_exported?(mod, :handle_close, 3) do
      mod.handle_close(channel, state, arg)
    else
      :ok
    end
  end
end
