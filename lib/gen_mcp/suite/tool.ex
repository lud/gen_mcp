defmodule GenMCP.Suite.Tool do
  @moduledoc """
  Defines the behaviour for implementing MCP tools in `GenMCP.Suite`.

  Tools are the primary mechanism for clients to execute operations on the
  server. Each tool implementation provides metadata, input validation,
  execution logic, and optional asynchronous continuation handling.

  ## Implementation Patterns

  Use `use GenMCP.Suite.Tool` with options to auto-generate common callbacks:

      use GenMCP.Suite.Tool,
        name: "search_files",
        description: "Searches for files matching a pattern",
        input_schema: %{
          type: :object,
          properties: %{query: %{type: :string}},
          required: [:query]
        }

  Auto-generates `c:info/2`, `c:input_schema/1`, and `c:validate_request/2` with JSON
  schema validation.

  ## Synchronous Tool Example

      defmodule MySearchTool do
        use GenMCP.Suite.Tool,
          name: "search_files",
          input_schema: %{
            type: :object,
            properties: %{
              query: %{type: :string}
            }
          }

        alias GenMCP.MCP

        @impl true
        def call(req, channel, _arg) do
          # Arguments are string keys unless using a JSV module based schema or a
          # custom validate_request function.
          %{"query" => query} = req.params.arguments

          text = generate_text_response(query)
          {:result, MCP.call_tool_result(text: text), channel}
        end
      end

  ## Asynchronous Tool Example

      defmodule MyAsyncTool do
        use GenMCP.Suite.Tool,
          name: "expensive_search",
          input_schema: %{}

        alias GenMCP.MCP

        @impl true
        def call(req, channel, _arg) do
          task = Task.async(fn -> perform_expensive_search(req) end)
          {:async, {:search_task, task}, channel}
        end

        @impl true
        def continue({:search_task, {:ok, document}}, channel, _arg) do
          {:result, MCP.call_tool_result(text: document), channel}
        end
      end
  """

  import GenMCP.Utils.CallbackExt

  alias GenMCP.MCP
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
  @type tag :: term
  @type call_result ::
          {:result, MCP.CallToolResult.t(), Channel.t()}
          # TODO allow elicitation/sampling request
          # | {:request, {tag, term}, Channel.t()}
          | {:async, {tag, reference() | Task.t()}, Channel.t()}
          | {:error, String.t(), Channel.t()}

  @type request :: term

  @typedoc """
  This is not supported yet
  """
  @type client_response :: term
  # MCP.CreateMessageResult.t()
  # | MCP.ListRootsResult.t()
  # | MCP.ElicitResult.t()
  #

  @doc """
  Returns tool metadata for the specified key.

  Invoked by `describe/1` to gather tool metadata.

  With `use GenMCP.Suite.Tool` with metadata options, this callback is
  auto-generated.

  ## Examples

      def info(:name, _arg), do: "search_files"
      def info(:description, _arg), do: "Searches for files matching a pattern"
      def info(:_meta, _arg), do: %{"ui/resourceUri" => "ui://pages/some-page"}
      def info(:annotations, _arg), do: %{readOnlyHint: true}
      def info(_, _), do: nil
  """
  @callback info(:name, arg) :: String.t()
  @callback info(:description, arg) :: nil | String.t()
  @callback info(:title, arg) :: nil | String.t()
  @callback info(:annotations, arg) :: nil | tool_annotations
  @callback info(:_meta, arg) :: nil | map()

  @doc """
  Returns the JSON schema defining accepted tool arguments.

  Sent to clients in `tools/list` responses to describe expected parameters.

  Auto-generated with `use GenMCP.Suite.Tool` with an `:input_schema` option.

  ## Examples

      def input_schema(_arg) do
        %{
          type: :object,
          properties: %{
            query: %{type: :string},
            limit: %{type: :integer, default: 10}
          },
          required: [:query]
        }
      end
  """
  @callback input_schema(arg) :: schema

  @doc """
  Returns the JSON schema defining tool result structure, or `nil` if
  unspecified.

  Defines the structured outputs returned by the tool if any. Entirely optional
  and not enforced at runtime.

  Auto-generated with `use GenMCP.Suite.Tool` with an `:output_schema` option.

  ## Examples

      def output_schema(_arg) do
        %{
          type: :object,
          properties: %{
            files: %{type: :array, items: %{type: :string}}
          }
        }
      end
  """
  @callback output_schema(arg) :: nil | schema

  @doc """
  Validates and optionally transforms the incoming call request.

  Invoked before `c:call/3`.

  Auto-generated with JSON schema validation when using `use GenMCP.Suite.Tool`
  with an `:input_schema` option.

  ## Examples

      def validate_request(req, _arg) do
        case req.params.arguments do
          %{"limit" => n} when n > 0 and n <= 100 -> {:ok, req}
          _ -> {:error, "limit must be between 1 and 100"}
        end
      end
  """
  @callback validate_request(MCP.CallToolRequest.t(), arg) ::
              {:ok, MCP.CallToolRequest.t()} | {:error, String.t()}

  @doc """
  Executes the tool call and returns a result, error, or async continuation.

  Receives validated request parameters if `c:validate_request/2` is defined.
  When using `use GenMCP.Suite.Tool`, JSON schema validation is automatically
  implemented, ensuring `req.params.arguments` conforms to the schema.

  ## Async calls

  When returning `{:async, {tag, ref}, channel}`, the `c:continue/3` callback
  will be invoked with `{tag, {:ok, value}}` if the server process receives a
  `{ref, value}` message with the same `ref`.

  This works automatically with tasks. It is possible to directly return the
  task struct as in `{:async, {tag, task}, channel}`.

  Note that `Task.async/1` may crash the server process, you may want to use
  `Task.Supervisor.async_nolink/2` in which case a `:DOWN` message from the task
  will be delivered as with the same tag as `{tag, {:error, reason}}`.

  This should also work with manually monitored processes, given the monitored
  process obtains the ref to send the `{ref, result}` value back to the calling
  process.

  ## Channel and Assigns

  The channel provides access to assigns copied from the `Plug.Conn` struct
  (from the HTTP request that delivered the tool call request) and can be
  modified via `GenMCP.Mux.Channel.assign/3` to keep state before entering the
  `c:continue/3` callback.

  Assigning modifies the channel, so the last updated channel must always be
  returned from your callback.

  ## Examples

  Synchronous execution:

      def call(req, channel, _arg) do
        %{"query" => query} = req.params.arguments
        entity = perform_search(query)

        # With structured output (entity is a map), mind the list wrapper
        {:result, MCP.call_tool_result([entity]), channel}

        # Without structured output
        {:result, MCP.call_tool_result(text: Jason.encode!(entity)), channel}
      end

  Asynchronous with Task:

      def call(req, channel, _arg) do
        task = Task.async(fn -> expensive_operation(req) end)
        {:async, {:search_task, task}, channel}
      end

  Error handling:

      def call(_req, channel, _arg) do
        {:error, "Resource not available", channel}
      end
  """
  @callback call(MCP.CallToolRequest.t(), Channel.t(), arg) :: call_result

  @doc """
  Continues processing after async work completes.

  Invoked when `c:call/3` returns `{:async, {tag, ref_or_task}, channel}` and
  the task finishes.

  The first tuple element contains the tag and the wrapped task result (either
  `{:ok, result}` for success or `{:error, reason}` for failures with non-linked
  tasks). Returns same result types as `c:call/3`. Can chain another async
  operation by returning `{:async, {new_tag, new_ref}, channel}`.

  ## Examples

  Basic continuation:

      def continue({:search_task, {:ok, results}}, channel, _arg) do
        {:result, MCP.call_tool_result(text: Jason.encode!(results)), channel}
      end

  Error handling:

      def continue({:search_task, {:error, reason}}, channel, _arg) do
        {:error, "Search failed: \#{reason}", channel}
      end

  Chaining async operations:

      def continue({:step1, {:ok, intermediate}}, channel, _arg) do
        task = Task.async(fn -> step2(intermediate) end)
        {:async, {:step2, task}, channel}
      end
  """
  @callback continue({tag, {:ok, term} | {:error, term}}, Channel.t(), arg) ::
              call_result

  @optional_callbacks validate_request: 2, continue: 3, output_schema: 1

  defmacro __using__(opts) do
    quote do
      import GenMCP.Mux.Channel, only: [assign: 3]

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
      unquote(def_validator(opts[:input_schema]))
      unquote(def_output_schema(opts[:output_schema]))
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
  defp def_validator(nil) do
    []
  end

  defp def_validator(input_opt) do
    quote bind_quoted: [input_opt: input_opt] do
      GenMCP.Suite.Tool.__validate_use__(:input_schema, input_opt)

      @jsv_input_root JSV.build!(input_opt)

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

  @doc """
  Returns a descriptor for the given `module` or `{module, arg}` tuple.
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
  Builds an MCP tool description suitable for `tools/list` responses.

  Gathers metadata via `c:info/2` callbacks and normalizes input/output schemas
  to JSON schema format. Invoked by `GenMCP.Suite` when handling
  `ListToolsRequest`.

  ## Examples

      iex> Tool.describe(MySearchTool)
      %GenMCP.MCP.Tool{
        name: "search_files",
        description: "Searches for files matching a pattern",
        inputSchema: %{"type" => "object", "properties" => ...},
        annotations: %{readOnlyHint: true}
      }

      iex> Tool.describe({MySearchTool, [repo_path: "/data"]})
      %GenMCP.MCP.Tool{name: "search_files", ...}
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

  defp output_schema(mod, arg) do
    if function_exported?(mod, :output_schema, 1) do
      mod.output_schema(arg)
    end
  end

  defp normalize_schema(schema) when is_atom(schema) do
    if JSV.Schema.schema_module?(schema) do
      do_normalize_schema(schema.json_schema())
    else
      do_normalize_schema(schema)
    end
  end

  defp normalize_schema(schema) do
    do_normalize_schema(schema)
  end

  defp do_normalize_schema(schema) do
    schema
    |> JSV.Schema.normalize()
    |> JSV.Helpers.Traverse.prewalk(fn
      {:val, map} when is_map(map) -> Map.delete(map, "jsv-cast")
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
      raise_invalid_use_info(k, value, "must be a map")
    end
  end

  @spec raise_invalid_use_info(atom, term, binary) :: no_return()
  defp raise_invalid_use_info(key, value, errmsg) do
    raise ArgumentError,
          "option #{inspect(key)} given to `use #{inspect(__MODULE__)}` #{errmsg}, got: #{inspect(value)}"
  end

  defmacrop handle_result(call) do
    quote do
      callback __MODULE__, unquote(call) do
        {:result, _result, %Channel{}} = result ->
          result

        {:async, {tag, %Task{ref: ref}}, %Channel{} = chan} ->
          {:async, {tag, ref}, chan}

        {:async, {tag, ref}, %Channel{} = chan} when is_reference(ref) ->
          {:async, {tag, ref}, chan}

        {:error, _reason, %Channel{}} = err ->
          err
      end
    end
  end

  @doc """
  Invokes the tool's `c:call/3` callback with request validation.

  Performs optional validation via `c:validate_request/2` before dispatching to
  the tool implementation. Returns `{:error, {:invalid_params, reason},
  channel}` if validation fails. Called by `GenMCP.Suite` when handling
  `CallToolRequest`.

  ## Examples

      req = %GenMCP.MCP.CallToolRequest{
        params: %{name: "search_files", arguments: %{"query" => "*.ex"}}
      }
      Tool.call(tool_descriptor, req, channel)
      #=> {:result, %GenMCP.MCP.CallToolResult{...}, channel}

      # With validation error
      Tool.call(tool_descriptor, invalid_req, channel)
      #=> {:error, {:invalid_params, "limit must be positive"}, channel}
  """
  @spec call(tool_descriptor, MCP.CallToolRequest.t(), Channel.t()) :: call_result
  def call(tool, %MCP.CallToolRequest{} = req, channel) do
    %{params: %MCP.CallToolRequestParams{name: name}} = req
    %{mod: mod, arg: arg, name: ^name} = tool

    case validate_request(tool, req) do
      {:ok, req} -> handle_result(mod.call(req, channel, arg))
      {:error, term} -> invalid_params(req, term, channel)
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

  defp invalid_params(_req, reason, channel) do
    {:error, {:invalid_params, reason}, channel}
  end

  @doc """
  Dispatches continuation logic to the tool's `c:continue/3` callback.

  Invoked by `GenMCP.Suite` when an async task completes. The continuation tuple
  contains the tag from the original `{:async, {tag, ref}, channel}` return and
  the wrapped task result. Task results are wrapped as `{:ok, result}` for
  normal completion or `{:error, reason}` for failures.

  ## Examples

      Tool.continue(tool_descriptor, {:search_task, {:ok, results}}, channel)
      #=> {:result, %GenMCP.MCP.CallToolResult{...}, channel}

      Tool.continue(tool_descriptor, {:search_task, {:error, :timeout}}, channel)
      #=> {:error, "Search timed out", channel}
  """
  @spec continue(tool_descriptor, {tag, client_response | term}, Channel.t()) :: call_result
  def continue(tool, {_tag, _result} = cont, channel) do
    %{mod: mod, arg: arg} = tool
    handle_result(mod.continue(cont, channel, arg))
  end
end
