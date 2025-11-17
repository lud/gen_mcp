defmodule GenMCP.Suite.Tool do
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
  @type info_key :: :name | :title | :description | :annotations
  @type arg :: term
  @type schema :: term
  @type result :: term
  @type tag :: term
  @type call_result ::
          {:result, result, Channel.t()}
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

  @type json_encodable ::
          %{optional(binary | atom | number) => json_encodable}
          | [json_encodable]
          | number
          | binary
          | boolean
          | nil

  @doc """
  Returns metadata information a  bout the tool based on the requested key.

  The `key` parameter determines which metadata is retrieved (`:name`, `:title`,
  `:description`, or `:annotations`).
  """
  @callback info(:name, arg) :: String.t()
  @callback info(:description, arg) :: nil | String.t()
  @callback info(:title, arg) :: nil | String.t()
  @callback info(:annotations, arg) :: nil | tool_annotations

  @doc """
  Returns the input schema that defines what arguments the tool accepts.

  The returned schema must be a valid JSON schema (or a module exporting a
  `json_schema/0` function). It should define the expected arguments from a
  `CallToolRequest`.
  """
  @callback input_schema(arg) :: schema

  @doc """
  Returns the output schema that defines the structure of tool results.

  Unlike `input_schema/1`, this may return `nil` if no output schema is defined.

  Structured content returned by tools must be valid against their output
  schema.
  """
  @callback output_schema(arg) :: nil | schema

  @doc """
  Validates the request and returns it. It can swap the arguments in the request
  for a cast version or a completely different map/struct.

  The returned request will be given to `c:call/3`.

  Error can be any term but will be encoded as an invalid parameters error.
  """
  @callback validate_request(MCP.CallToolRequest.t(), arg) ::
              {:ok, MCP.CallToolRequest.t()} | {:error, String.t() | json_encodable}

  @doc """
  Processes a tool call request and returns the result.

  The `request` contains the full call information including parameters and
  arguments to validate against the input schema. The arguments are not
  validated automatically, this is the role of the optional
  `c:validate_request/2` callback.

  The `channel` provides access to the client connection and authorization
  context via `channel.assigns`. It can be used to send progress notifications
  to the HTTP connection that delivered the request.

  The callback can return a result tuple, request a server response, or indicate
  async processing.
  """
  @callback call(MCP.CallToolRequest.t(), Channel.t(), arg) :: call_result

  @doc """
  Continues processing the tool request after `c:call/3` has returned a value.

  The `key` indicates whether this is a response to a server request
  (`{:response, tag}`) or an async result (`{:async, ref}`). The `response`
  contains the result value, and the `channel` is associated with the original
  client request and provides authorization context. The `arg` provides
  implementation-specific options. This callback returns the same result types
  as `call/3`.
  """
  @callback continue({tag, client_response | (task_result :: term)}, Channel.t(), arg) ::
              call_result

  @optional_callbacks validate_request: 2, continue: 3, output_schema: 1

  defmacro __using__(opts) do
    quote do
      @gen_mcp_suite_too_opts unquote(Macro.escape(opts))
      @before_compile unquote(__MODULE__)
      import GenMCP.Mux.Channel, only: [assign: 3]
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
    end
  end

  defp def_infos(infos) do
    quote bind_quoted: binding() do
      @impl true

      keys = [:name, :title, :description, :annotations]

      values =
        Enum.flat_map(keys, fn k ->
          case Keyword.fetch(infos, k) do
            {:ok, v} -> [{k, v}]
            :error -> []
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

  @doc """
  Transforms `module` and `{module, arg}` into a tool descriptor.
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

  @spec describe(tool) :: MCP.Tool.t()
  def describe(tool) do
    %{mod: mod, arg: arg, name: name} = expand(tool)

    %MCP.Tool{
      name: name,
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
    else
      nil
    end
  end

  defp normalize_schema(schema) do
    schema
    |> JSV.Schema.normalize()
    |> JSV.Helpers.Traverse.prewalk(fn
      {:val, map} when is_map(map) -> Map.delete(map, "jsv-cast")
      other -> elem(other, 1)
    end)
  end

  @doc """
  This is a thin wrapper around the tool `c:call/3` callback that also performs
  input validation.
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
      case mod.validate_request(req, arg) do
        {:ok, req} -> {:ok, req}
        {:error, _} = err -> err
        other -> exit({:bad_return_value, other})
      end
    else
      {:ok, req}
    end
  end

  defp invalid_params(_req, reason, channel) do
    {:error, {:invalid_params, reason}, channel}
  end

  def continue(tool, {_tag, _result} = cont, channel) do
    %{mod: mod, arg: arg} = tool
    handle_result(mod.continue(cont, channel, arg))
  end

  defp handle_result(result) do
    case result do
      {:result, _result, %Channel{}} = result -> result
      {:async, {tag, %Task{ref: ref}}, %Channel{} = chan} -> {:async, {tag, ref}, chan}
      {:async, {tag, ref}, %Channel{} = chan} when is_reference(ref) -> {:async, {tag, ref}, chan}
      {:error, _reason, %Channel{}} = err -> err
      other -> exit({:bad_return_value, other})
    end
  end
end
