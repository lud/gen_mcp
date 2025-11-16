defmodule GenMCP.MCP do
  alias GenMCP.MCP
  alias GenMCP.Suite.Tool

  defp require_key!(keywords, key, errmsg) do
    case :lists.keyfind(key, 1, keywords) do
      {^key, value} -> value
      false -> raise KeyError, key: key, term: keywords, message: errmsg
    end
  end

  defmacro cur_fun do
    {function, arity} = __ENV__.function
    _mfa = Exception.format_mfa(__ENV__.module, function, arity)
  end

  def intialize_result(opts) do
    %MCP.InitializeResult{
      capabilities: Keyword.get(opts, :capabilities, %{}),
      serverInfo: Keyword.fetch!(opts, :server_info),
      protocolVersion: "2025-06-18"
    }
  end

  def capabilities(opts) do
    attrs =
      Enum.flat_map(opts, fn
        {key, value} when is_map(value) -> [{key, value}]
        {key, true} -> [{key, %{}}]
        _ -> []
      end)

    struct!(MCP.ServerCapabilities, attrs)
  end

  def server_info(opts) do
    %MCP.Implementation{
      name: require_key!(opts, :name, "option :name is required by #{cur_fun()}"),
      version: require_key!(opts, :version, "option :version is required by #{cur_fun()}"),
      title: Keyword.get(opts, :title, nil)
    }
  end

  # TODO handle cursor

  @doc """
  Returns a description of the given tools. Tools already described (as a
  `#{inspect(MCP.Tool)}` struct) are included as they are in the result's
  list of tools.

  Pagination is not yet supported for tools
  """
  @spec list_tools_result([Tool.tool() | MCP.Tool.t()]) :: MCP.ListToolsResult.t()
  def list_tools_result(tools) do
    %MCP.ListToolsResult{
      tools:
        Enum.map(tools, fn
          %MCP.Tool{} = tool -> tool
          tool -> GenMCP.Suite.Tool.describe(tool)
        end)
    }
  end

  # TODO(doc): A building block for other helpers like call_tool_result/1 or
  # get_prompt_result/1. Accepts tuples and transforms then in various MCP content
  # entities.
  def content_block(content_opts)

  def content_block({:text, text}) when is_binary(text) do
    %MCP.TextContent{text: text}
  end

  def content_block({:resource, %{text: text, uri: uri} = resource})
      when is_binary(text) and is_binary(uri) do
    %MCP.EmbeddedResource{resource: resource}
  end

  def content_block({:resource, %{blob: blob, uri: uri} = resource})
      when is_binary(blob) and is_binary(uri) do
    %MCP.EmbeddedResource{resource: resource}
  end

  def content_block({:link, %{name: name, uri: uri} = link})
      when is_binary(name) and is_binary(uri) do
    struct(MCP.ResourceLink, link)
  end

  def content_block({:image, {mime_type, data}}) when is_binary(mime_type) and is_binary(data) do
    %MCP.ImageContent{mimeType: mime_type, data: data}
  end

  def content_block({:audio, {mime_type, data}}) when is_binary(mime_type) and is_binary(data) do
    %MCP.AudioContent{mimeType: mime_type, data: data}
  end

  def content_block(other) do
    raise ArgumentError, "unsupported content block definition: #{inspect(other)}"
  end

  def call_tool_result(all_content) when is_list(all_content) do
    {content, {structured_content, error_or_nil?}} =
      Enum.flat_map_reduce(all_content, {nil, nil}, &flat_map_reduce_tool_result/2)

    %MCP.CallToolResult{
      content: content,
      structuredContent: structured_content,
      isError: error_or_nil?
    }
  end

  defp flat_map_reduce_tool_result({:error, error?}, {structured_content, error_or_nil?})
       when is_boolean(error?) do
    {[], {structured_content, error? || error_or_nil?}}
  end

  defp flat_map_reduce_tool_result({:error, errmsg}, {structured_content, _error_or_nil?})
       when is_binary(errmsg) do
    {[content_block({:text, errmsg})], {structured_content, true}}
  end

  defp flat_map_reduce_tool_result({:error, nil}, {structured_content, error_or_nil?}) do
    {[], {structured_content, error_or_nil?}}
  end

  defp flat_map_reduce_tool_result(content, {structured_content, error_or_nil?})
       when is_struct(content, MCP.TextContent)
       when is_struct(content, MCP.AudioContent)
       when is_struct(content, MCP.ImageContent)
       when is_struct(content, MCP.EmbeddedResource)
       when is_struct(content, MCP.ResourceLink) do
    {[content], {structured_content, error_or_nil?}}
  end

  # structured content is accepted if currently nil
  defp flat_map_reduce_tool_result(map, {nil, error_or_nil?}) when is_map(map) do
    json = JSV.Codec.encode!(map)
    as_text = content_block({:text, json})
    {[as_text], {map, error_or_nil?}}
  end

  defp flat_map_reduce_tool_result(map, {existing, _error_or_nil?}) when is_map(map) do
    raise ArgumentError,
          "cannot return multiple structured content, tried to add #{inspect(map)} with existing content: #{inspect(existing)}"
  end

  defp flat_map_reduce_tool_result(elem, {structured_content, error_or_nil?}) do
    {[content_block(elem)], {structured_content, error_or_nil?}}
  end

  defp flat_map_reduce_tool_result(other, _) do
    raise ArgumentError, "unsupported tool result content definition: #{inspect(other)}"
  end

  def list_resources_result(resources, next_cursor) do
    %MCP.ListResourcesResult{
      resources: resources,
      nextCursor: next_cursor
    }
  end

  def list_resource_templates_result(templates) do
    %MCP.ListResourceTemplatesResult{
      resourceTemplates: templates
    }
  end

  # TODO(doc) expects either a keyword, in that case it returns a single content
  # in the list, using `resource_contents/1` to cast the options. Otherwise it
  # expects a list of maps (content structs or custom maps)
  def read_resource_result([{k, _} | _] = opts) when is_atom(k) do
    true = Keyword.keyword?(opts)
    contents = resource_contents(opts)

    %MCP.ReadResourceResult{contents: [contents]}
  end

  def read_resource_result([%{} | _] = contents) do
    true = Enum.all?(contents, &is_map/1)

    %MCP.ReadResourceResult{contents: contents}
  end

  def resource_contents(opts) do
    uri = require_key!(opts, :uri, "option :uri is required by #{cur_fun()}")
    mime_type = Keyword.get(opts, :mime_type)
    meta = Keyword.get(opts, :_meta)

    cond do
      Keyword.has_key?(opts, :text) ->
        text = Keyword.fetch!(opts, :text)

        %MCP.TextResourceContents{
          _meta: meta,
          uri: uri,
          text: text,
          mimeType: mime_type
        }

      Keyword.has_key?(opts, :blob) ->
        blob = Keyword.fetch!(opts, :blob)

        %MCP.BlobResourceContents{
          _meta: meta,
          uri: uri,
          blob: blob,
          mimeType: mime_type
        }

      true ->
        raise ArgumentError, "resource_contents/1 requires either :text or :blob option"
    end
  end

  def list_prompts_result(prompts, next_cursor) do
    %MCP.ListPromptsResult{
      prompts: prompts,
      nextCursor: next_cursor
    }
  end

  # TODO(doc): Accepts a list
  def get_prompt_result(opts) do
    {description, opts} =
      case List.keytake(opts, :description, 0) do
        {{:description, description}, opts} -> {description, opts}
        nil -> {nil, opts}
      end

    messages = Enum.map(opts, &map_prompt_message/1)

    %MCP.GetPromptResult{messages: messages, description: description}
  end

  # Map with role and content keys allow to pass custom, invalid elements or
  # MCP.PromptMessage structs.
  defp map_prompt_message(%{role: role, content: _} = elem)
       when is_binary(role)
       when is_atom(role) do
    elem
  end

  defp map_prompt_message({:assistant, text}) when is_binary(text) do
    %MCP.PromptMessage{role: "assistant", content: content_block({:text, text})}
  end

  defp map_prompt_message({_, _} = elem) do
    case content_block(elem) do
      %MCP.ResourceLink{} ->
        raise ArgumentError, "unsupported ResourceLink content in prompt message"

      content ->
        %MCP.PromptMessage{role: "user", content: content}
    end
  end

  defp map_prompt_message(other) do
    raise ArgumentError, "unsupported content block definition for prompt: #{inspect(other)}"
  end
end
