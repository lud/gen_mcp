defmodule GenMCP.MCP.V2607 do
  @moduledoc """
  Helpers for building MCP `2026-07-28` (V2607) payload structs.

  Replicated from `GenMCP.MCP` (the `2025-11-25` vocabulary). Only the builders
  that work unchanged under the stateless core are implemented; helpers that need
  genuinely new 2026 logic (`server/discover`, the removed `initialize`
  handshake) raise a `TODO` so the gap is loud rather than silent.

  ## `resultType`

  Every 2026 result carries a required `resultType` field. These builders always
  set `"complete"`. The `"input-required"` variant is **not** an option here — it
  is produced by the multi-round-trip path (`InputRequiredResult`, spec 007) from
  the `{:input_required, …}` handler return, driven by the request, not chosen by
  a result builder.

  ## Cache hints

  The list/read results additionally declare (and enforce) `cacheScope` / `ttlMs`
  (cache hints, spec 005). Until that work lands they default to **no caching** —
  `:private` + `ttlMs: 0` — which is schema-valid and preserves today's behaviour.
  """

  alias GenMCP.MCP.V2607.AudioContent
  alias GenMCP.MCP.V2607.BlobResourceContents
  alias GenMCP.MCP.V2607.CallToolResult
  alias GenMCP.MCP.V2607.DiscoverResult
  alias GenMCP.MCP.V2607.EmbeddedResource
  alias GenMCP.MCP.V2607.GetPromptResult
  alias GenMCP.MCP.V2607.ImageContent
  alias GenMCP.MCP.V2607.Implementation
  alias GenMCP.MCP.V2607.ListPromptsResult
  alias GenMCP.MCP.V2607.ListResourcesResult
  alias GenMCP.MCP.V2607.ListResourceTemplatesResult
  alias GenMCP.MCP.V2607.ListToolsResult
  alias GenMCP.MCP.V2607.PromptMessage
  alias GenMCP.MCP.V2607.ReadResourceResult
  alias GenMCP.MCP.V2607.ResourceLink
  alias GenMCP.MCP.V2607.ServerCapabilities
  alias GenMCP.MCP.V2607.TextContent
  alias GenMCP.MCP.V2607.TextResourceContents
  alias GenMCP.Suite.Tool

  # The default result type. Result builders never accept this as an option; the
  # "input-required" variant is produced by the MRTR path (spec 007), not here.
  #
  # TODO(spec 007): the framework sets "input-required" when a handler returns
  # `{:input_required, …}` (a separate `InputRequiredResult`), keyed on the
  # request. These builders stay "complete".
  @result_type_complete "complete"

  # Cache hints (`cacheScope` / `ttlMs`, spec 005) are not implemented yet, but
  # the schema marks them required (and enforced) on the list/read results.
  # Default to "no caching" — private + immediately stale — which is schema-valid
  # and preserves today's behaviour.
  #
  # TODO(spec 005): derive real per-result cache hints.
  @default_cache_scope :private
  @default_ttl_ms 0

  @doc false
  def default_cache_scope do
    @default_cache_scope
  end

  @doc false
  def default_ttl_ms do
    @default_ttl_ms
  end

  def default_cache_control do
    {default_cache_scope(), default_ttl_ms()}
  end

  defp require_key!(keywords, key, errmsg) do
    case :lists.keyfind(key, 1, keywords) do
      {^key, value} -> value
      false -> raise KeyError, key: key, term: keywords, message: errmsg
    end
  end

  defmacrop cur_fun do
    {function, arity} = __CALLER__.function
    _mfa = Exception.format_mfa(__ENV__.module, function, arity)
  end

  @doc """
  Builds a `%GenMCP.MCP.V2607.DiscoverResult{}` for `server/discover`.
  """
  def discover_result(opts) do
    %DiscoverResult{
      cacheScope: :private,
      ttlMs: @default_ttl_ms,
      resultType: @result_type_complete,
      capabilities: capabilities(Keyword.get(opts, :capabilities, %{})),
      serverInfo: server_info(opts),
      supportedVersions: ["2026-07-28"]
    }
  end

  @doc """
  Normalizes capability flags/maps into `%GenMCP.MCP.V2607.ServerCapabilities{}`.

  Passing `true` for a key yields an empty map; maps pass through; anything else
  leaves the field `nil`. A `%GenMCP.MCP.V2607.ServerCapabilities{}` struct is
  returned as-is.
  """
  @spec capabilities(keyword() | ServerCapabilities.t() | map) :: ServerCapabilities.t()
  def capabilities(%ServerCapabilities{} = caps) do
    caps
  end

  def capabilities(opts) do
    attrs =
      Enum.flat_map(opts, fn
        {key, value} when is_map(value) -> [{key, value}]
        {key, true} -> [{key, %{}}]
        _ -> []
      end)

    struct!(ServerCapabilities, attrs)
  end

  @doc """
  Builds `%GenMCP.MCP.V2607.Implementation{}` (server/client info).

  `:name` and `:version` are required; `:title` is optional.
  """
  @spec server_info(keyword()) :: Implementation.t()
  def server_info(opts) do
    %Implementation{
      name: require_key!(opts, :name, "option :name is required by #{cur_fun()}"),
      version: require_key!(opts, :version, "option :version is required by #{cur_fun()}"),
      title: Keyword.get(opts, :title)
    }
  end

  # TODO handle cursor

  @doc """
  Builds `%GenMCP.MCP.V2607.ListToolsResult{}`.

  Structs already shaped as `%GenMCP.MCP.V2607.Tool{}` are left untouched; other
  entries go through `GenMCP.Suite.Tool.describe/1`. Pagination is not supported
  yet.
  """
  @spec list_tools_result([Tool.tool() | GenMCP.MCP.V2607.Tool.t()], keyword) ::
          ListToolsResult.t()
  def list_tools_result(tools, opts \\ []) do
    %ListToolsResult{
      resultType: @result_type_complete,
      cacheScope: Keyword.get(opts, :cache_scope, @default_cache_scope),
      ttlMs: Keyword.get(opts, :ttl_ms, @default_ttl_ms),
      tools:
        Enum.map(tools, fn
          %GenMCP.MCP.V2607.Tool{} = tool -> tool
          tool -> Tool.describe(tool)
        end)
    }
  end

  @doc """
  Normalizes content shortcuts into the MCP structs tools and prompts expect.

  Supported shortcuts: `{:text, binary}`, `{:resource, %{uri, text}}`,
  `{:resource, %{uri, blob}}`, `{:link, %{name, uri}}`, `{:image, {mime, data}}`,
  `{:audio, {mime, data}}`.
  """
  def content_block(content_opts)

  def content_block({:text, text}) when is_binary(text) do
    %TextContent{text: text}
  end

  def content_block({:resource, %{text: text, uri: uri} = resource})
      when is_binary(text) and is_binary(uri) do
    %EmbeddedResource{resource: resource}
  end

  def content_block({:resource, %{blob: blob, uri: uri} = resource})
      when is_binary(blob) and is_binary(uri) do
    %EmbeddedResource{resource: resource}
  end

  def content_block({:link, %{name: name, uri: uri} = link})
      when is_binary(name) and is_binary(uri) do
    struct(ResourceLink, link)
  end

  def content_block({:image, {mime_type, data}}) when is_binary(mime_type) and is_binary(data) do
    %ImageContent{mimeType: mime_type, data: data}
  end

  def content_block({:audio, {mime_type, data}}) when is_binary(mime_type) and is_binary(data) do
    %AudioContent{mimeType: mime_type, data: data}
  end

  def content_block(other) do
    raise ArgumentError, "unsupported content block definition: #{inspect(other)}"
  end

  @doc """
  Builds `%GenMCP.MCP.V2607.CallToolResult{}`.

  The list may contain content shortcuts (`text:`, `image:`, …), literal content
  structs, or structured payloads (`data:` / `_data:` / a naked map). Errors via
  `error: true` or `error: "message"`.
  """
  def call_tool_result(all_content) when is_list(all_content) do
    {content, {structured_content, error_or_nil?}} =
      Enum.flat_map_reduce(all_content, {nil, nil}, &flat_map_reduce_tool_result/2)

    %CallToolResult{
      resultType: @result_type_complete,
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

  defp flat_map_reduce_tool_result({:data, map}, acc) when is_map(map) do
    add_structured_content(map, acc, _mirror_text? = true)
  end

  defp flat_map_reduce_tool_result({:_data, map}, acc) when is_map(map) do
    add_structured_content(map, acc, _mirror_text? = false)
  end

  defp flat_map_reduce_tool_result(content, {structured_content, error_or_nil?})
       when is_struct(content, TextContent)
       when is_struct(content, AudioContent)
       when is_struct(content, ImageContent)
       when is_struct(content, EmbeddedResource)
       when is_struct(content, ResourceLink) do
    {[content], {structured_content, error_or_nil?}}
  end

  defp flat_map_reduce_tool_result(map, acc) when is_map(map) do
    add_structured_content(map, acc, _mirror_text? = true)
  end

  defp flat_map_reduce_tool_result(elem, {structured_content, error_or_nil?}) do
    {[content_block(elem)], {structured_content, error_or_nil?}}
  end

  defp add_structured_content(map, {nil, error_or_nil?}, mirror_text?) do
    extra =
      if mirror_text? do
        [content_block({:text, JSV.Codec.encode!(map)})]
      else
        []
      end

    {extra, {map, error_or_nil?}}
  end

  defp add_structured_content(map, {existing, _error_or_nil?}, _mirror_text?) do
    raise ArgumentError,
          "cannot return multiple structured content, tried to add #{inspect(map)} with existing content: #{inspect(existing)}"
  end

  @doc """
  Wraps `resources` and an optional cursor into
  `%GenMCP.MCP.V2607.ListResourcesResult{}`.
  """
  @spec list_resources_result([term()], term() | nil, keyword) :: ListResourcesResult.t()
  def list_resources_result(resources, next_cursor, opts \\ []) do
    %ListResourcesResult{
      resultType: @result_type_complete,
      cacheScope: Keyword.get(opts, :cache_scope, @default_cache_scope),
      ttlMs: Keyword.get(opts, :ttl_ms, @default_ttl_ms),
      resources: resources,
      nextCursor: next_cursor
    }
  end

  @doc """
  Wraps template entries into `%GenMCP.MCP.V2607.ListResourceTemplatesResult{}`.
  Pagination is not supported.
  """
  @spec list_resource_templates_result([term()], keyword) :: ListResourceTemplatesResult.t()
  def list_resource_templates_result(templates, opts \\ []) do
    %ListResourceTemplatesResult{
      resultType: @result_type_complete,
      cacheScope: Keyword.get(opts, :cache_scope, @default_cache_scope),
      ttlMs: Keyword.get(opts, :ttl_ms, @default_ttl_ms),
      resourceTemplates: templates
    }
  end

  @doc """
  Wraps resource content helpers into `%GenMCP.MCP.V2607.ReadResourceResult{}`.

  Options `:uri` with `:text` or `:blob` build a single content entry; Pre-made
  content structs can be given as a list with the `:contents` option. In that
  case, previously mentioned options are ignored.
  """
  @spec read_resource_result(keyword) :: ReadResourceResult.t()
  def read_resource_result(opts) do
    # Note that we will take _meta for the main ReadResourceResult object
    {wrapper_opts, opts} = Keyword.split(opts, [:cache_scope, :ttl_ms, :_meta])

    contents =
      case :proplists.get_value(:contents, opts) do
        :undefined ->
          {content_opts, _opts} = Keyword.split(opts, [:uri, :mime_type, :blob, :text])
          [resource_contents(content_opts)]

        contents when is_list(contents) ->
          Enum.each(contents, fn
            m when is_map(m) -> :ok
            other -> raise ArgumentError, "invalid :contents item: #{inspect(other)}"
          end)

          contents
      end

    %ReadResourceResult{
      resultType: @result_type_complete,
      _meta: Keyword.get(wrapper_opts, :_meta),
      cacheScope: Keyword.get(wrapper_opts, :cache_scope, @default_cache_scope),
      ttlMs: Keyword.get(wrapper_opts, :ttl_ms, @default_ttl_ms),
      contents: contents
    }
  end

  @doc """
  Builds `%GenMCP.MCP.V2607.TextResourceContents{}` or
  `%GenMCP.MCP.V2607.BlobResourceContents{}` from keyword options.

  Requires `:uri` and either `:text` or `:blob`; `:mime_type` and `:_meta` are
  optional.
  """
  @spec resource_contents(keyword()) :: TextResourceContents.t() | BlobResourceContents.t()
  def resource_contents(opts) do
    uri = require_key!(opts, :uri, "option :uri is required by #{cur_fun()}")
    mime_type = Keyword.get(opts, :mime_type)
    meta = Keyword.get(opts, :_meta)

    cond do
      Keyword.has_key?(opts, :text) ->
        %TextResourceContents{
          _meta: meta,
          uri: uri,
          text: Keyword.fetch!(opts, :text),
          mimeType: mime_type
        }

      Keyword.has_key?(opts, :blob) ->
        %BlobResourceContents{
          _meta: meta,
          uri: uri,
          blob: Keyword.fetch!(opts, :blob),
          mimeType: mime_type
        }

      true ->
        raise ArgumentError, "resource_contents/1 requires either :text or :blob option"
    end
  end

  @doc """
  Wraps prompt entries and an optional cursor into
  `%GenMCP.MCP.V2607.ListPromptsResult{}`.
  """
  @spec list_prompts_result([term()], term() | nil, keyword) :: ListPromptsResult.t()
  def list_prompts_result(prompts, next_cursor, opts \\ []) do
    %ListPromptsResult{
      resultType: @result_type_complete,
      cacheScope: Keyword.get(opts, :cache_scope, @default_cache_scope),
      ttlMs: Keyword.get(opts, :ttl_ms, @default_ttl_ms),
      prompts: prompts,
      nextCursor: next_cursor
    }
  end

  @doc """
  Builds `%GenMCP.MCP.V2607.GetPromptResult{}` from keyword helpers or explicit
  prompt entries.

  `text:` and `assistant:` become alternating user/assistant messages; an
  optional `description:` is honored; tuples/structs convert via `content_block/1`.
  """
  @spec get_prompt_result(keyword() | [term()]) :: GetPromptResult.t()
  def get_prompt_result(opts) do
    {description, opts} =
      case List.keytake(opts, :description, 0) do
        {{:description, description}, opts} -> {description, opts}
        nil -> {nil, opts}
      end

    messages = Enum.map(opts, &map_prompt_message/1)

    %GetPromptResult{
      resultType: @result_type_complete,
      messages: messages,
      description: description
    }
  end

  defp map_prompt_message(%{role: role, content: _} = elem)
       when is_binary(role)
       when is_atom(role) do
    elem
  end

  defp map_prompt_message({:assistant, text}) when is_binary(text) do
    %PromptMessage{role: "assistant", content: content_block({:text, text})}
  end

  defp map_prompt_message({_, _} = elem) do
    case content_block(elem) do
      %ResourceLink{} ->
        raise ArgumentError, "unsupported ResourceLink content in prompt message"

      content ->
        %PromptMessage{role: "user", content: content}
    end
  end

  defp map_prompt_message(other) do
    raise ArgumentError, "unsupported content block definition for prompt: #{inspect(other)}"
  end
end
