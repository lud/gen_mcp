defmodule GenMCP.Suite.Tool do
  alias GenMCP.Entities
  alias GenMCP.Mux.Channel

  @type tool_annotations :: %{
          optional(:__struct__) => Entities.ToolAnnotations,
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
          | {:request, {tag, term}, Channel.t()}
          | {:async, {tag, reference() | Task.t()}, Channel.t()}
          | {:error, String.t(), Channel.t()}

  @type request :: term
  @type client_response ::
          Entities.CreateMessageResult.t()
          | Entities.ListRootsResult.t()
          | Entities.ElicitResult.t()

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
  Processes a tool call request and returns the result.

  The `request` contains the full call information including parameters and
  arguments to validate against the input schema.

  The callback can return a result tuple, request a server response, or indicate
  async processing.

  The `channel` can be used to send progress notifications to the HTTP
  connection that delivered the request.
  """
  @callback call(Entities.CallToolRequest.t(), Channel.t(), arg) :: call_result

  @doc """
  Continues processing the tool request after `c:call/3` has returned a value.


  The `key` indicates whether this is a response to a server request
  (`{:response, tag}`) or an async result (`{:async, ref}`). The `response`
  contains the result value, and the `channel` is associated with the original
  client request. The `arg` provides implementation-specific options. This
  callback returns the same result types as `call/3`.
  """
  @callback continue({tag, client_response | (task_result :: term)}, Channel.t(), arg) ::
              call_result

  # * name - it's the name matching a call too request params. names given to an
  #   instance of the DefaultServer must be unique
  # * mod - the module implementing the Tool behaviour
  # * arg - the last argument given to all behaviour calls
  # * info - an optional map with the following optional keys
  #     - title
  #     - description
  #     - annotations

  @doc """
  Transforms `module` and `{module, arg}` into a tool descriptor.
  """
  @spec expand(tool) :: tool_descriptor
  def expand(%{name: _} = tool) do
    tool
  end

  def expand(mod) when is_atom(mod) do
    expand({mod, []})
  end

  def expand({mod, arg}) when is_atom(mod) do
    Code.ensure_loaded!(mod)
    name = mod.info(:name, arg)

    if !is_binary(name) or String.trim(name) == "" do
      raise ArgumentError, "tool #{inspect(mod)} must return a valid name"
    end

    %{name: name, mod: mod, arg: arg}
  end

  @spec describe(tool) :: Entities.Tool.t()
  def describe(tool) do
    %{mod: mod, arg: arg, name: name} = expand(tool)

    %Entities.Tool{
      name: name,
      annotations: mod.info(:annotations, arg),
      description: mod.info(:description, arg),
      title: mod.info(:title, arg),
      inputSchema: normalize_schema(mod.input_schema(arg)),
      outputSchema: normalize_schema(mod.output_schema(arg))
    }
  end

  defp normalize_schema(schema) do
    schema
    |> JSV.Schema.normalize()
    |> JSV.Helpers.Traverse.prewalk(fn
      {:val, map} when is_map(map) -> Map.delete(map, "jsv-cast")
      other -> elem(other, 1)
    end)
  end

  IO.warn("""
  @todo document that the arguments are not validated by default
  @todo accept an invalid_params response
  """)

  @doc """
  This is a thin wrapper around the tool `c:call/3` callback that also performs
  input validation.
  """
  @spec call(tool_descriptor, Entities.CallToolRequest.t(), Channel.t()) :: call_result
  def call(tool, %Entities.CallToolRequest{} = req, channel) do
    %{params: %Entities.CallToolRequestParams{name: name}} = req
    %{mod: mod, arg: arg, name: ^name} = tool
    handle_result(mod.call(req, channel, arg))
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
