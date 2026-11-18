defmodule GenMCP.MCP.V2607 do
  @moduledoc """
  Builders and struct vocabulary for the MCP `2026-07-28` protocol version.

  The structs under `GenMCP.MCP.V2607.*` mirror the MCP schema for this protocol
  version: requests, results, content blocks, capabilities, and so on. This
  module exposes builder functions that turn convenient Elixir terms (keyword
  lists, tuples, and maps) into those structs, so handler code returns readable
  values instead of hand-writing nested struct literals.

  These builders are what handler callbacks reach for when they return a result.
  A tool's `c:GenMCP.Suite.Tool.call/3`, a prompt repository's
  `c:GenMCP.Suite.PromptRepo.get/4`, and a resource repository's
  `c:GenMCP.Suite.ResourceRepo.read/3` all build their return value with one of
  the functions here. The module is conventionally aliased as `MCP`:

      alias GenMCP.MCP.V2607, as: MCP

  The most common builder is `call_tool_result/1`, which assembles the content,
  optional structured content, and error flag of a tool's response:

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result = MCP.call_tool_result(text: "42")
      iex> match?(%MCP.CallToolResult{content: [%MCP.TextContent{text: "42"}]}, result)
      true

  ### Builder groups

  The builders fall into a few families:

  * **Tool calls**: `call_tool_result/1` aggregates content, structured content,
    and the error flag. `content_block/1` builds one content block on its own.
  * **Listings**: `list_tools_result/2`, `list_resources_result/3`,
    `list_resource_templates_result/2`, and `list_prompts_result/3` wrap a
    collection (and, where paginated, a cursor) in the matching result struct.
  * **Reads**: `read_resource_result/1` and `resource_contents/1` build the
    contents returned for a `resources/read`. `get_prompt_result/1` builds a
    prompt's messages.
  * **Skills**: `skill/1` builds one skill entry, and `list_skills_result/3` and
    `get_skill_result/1` build the answers to `skills/list` and `skills/get`.
    `skill_entry_from_path/3` builds an entry from a skill directory on disk.
  * **Discovery**: `discover_result/1`, `capabilities/1`, and `server_info/1`
    build the `server/discover` response and its parts.

  ### Cache hints

  The list and read builders accept optional flat `:cache_scope` and `:ttl_ms`
  options that populate the `cacheScope` / `ttlMs` fields the schema requires.
  When omitted, they default to the no-cache hint returned by
  `default_cache_control/0` (private, immediately stale). Passing only one of the
  two fills the other with that same no-cache default.
  """
  alias GenMCP.MCP.V2607.AudioContent
  alias GenMCP.MCP.V2607.BlobResourceContents
  alias GenMCP.MCP.V2607.CallToolResult
  alias GenMCP.MCP.V2607.DiscoverResult
  alias GenMCP.MCP.V2607.EmbeddedResource
  alias GenMCP.MCP.V2607.GetPromptResult
  alias GenMCP.MCP.V2607.GetSkillResult
  alias GenMCP.MCP.V2607.ImageContent
  alias GenMCP.MCP.V2607.Implementation
  alias GenMCP.MCP.V2607.ListPromptsResult
  alias GenMCP.MCP.V2607.ListResourcesResult
  alias GenMCP.MCP.V2607.ListResourceTemplatesResult
  alias GenMCP.MCP.V2607.ListSkillsResult
  alias GenMCP.MCP.V2607.ListToolsResult
  alias GenMCP.MCP.V2607.PromptMessage
  alias GenMCP.MCP.V2607.ReadResourceResult
  alias GenMCP.MCP.V2607.ResourceLink
  alias GenMCP.MCP.V2607.ResultMetaObject
  alias GenMCP.MCP.V2607.ServerCapabilities
  alias GenMCP.MCP.V2607.Skill
  alias GenMCP.MCP.V2607.SkillResource
  alias GenMCP.MCP.V2607.TextContent
  alias GenMCP.MCP.V2607.TextResourceContents
  alias GenMCP.Suite.Tool

  alias GenMCP.Utils.SkillFiles

  @typedoc """
  Describes one file of a skill read by `skill_entry_from_path/3`: its path
  relative to the skill directory, whether its content is valid UTF-8, and its
  MIME type.
  """
  @type skill_file_info :: %{path: String.t(), text?: boolean, mime_type: String.t()}

  # The default result type. Result builders never accept this as an option; the
  # "input_required" variant is produced by the MRTR path (spec 007), not here.
  #
  # TODO(spec 007): the framework sets "input_required" when a handler returns
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

  @doc """
  Returns the default cache control used when no cache hint is given.

  The list and read builders fall back to this `{scope, ttl_ms}` tuple for their
  `:cache_scope` and `:ttl_ms` options. It is the no-cache hint: a private scope
  with an immediately stale TTL, which is schema-valid and tells clients not to
  reuse the result.
  """
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
  Builds the `GenMCP.MCP.V2607.DiscoverResult` returned for `server/discover`.

  In the stateless 2026 core, `server/discover` is where the server advertises
  who it is and what it can do. This builder fills that response: it sets the
  supported protocol versions and
  marks the result as a no-cache snapshot.

  ### Options

  * `:name` - the server name, required (passed to `server_info/1`).
  * `:version` - the server version, required (passed to `server_info/1`).
  * `:title` - an optional human-friendly server title.
  * `:capabilities` - capability flags or maps, passed to `capabilities/1`.
    Defaults to no advertised capabilities.

  ### Examples

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result = MCP.discover_result(name: "MyServer", version: "1.0.0", capabilities: [tools: true])
      iex> info = result._meta."io.modelcontextprotocol/serverInfo"
      iex> {info.name, result.capabilities.tools, result.supportedVersions}
      {"MyServer", %{}, ["2026-07-28"]}
  """
  def discover_result(opts) do
    %DiscoverResult{
      cacheScope: :private,
      ttlMs: @default_ttl_ms,
      resultType: @result_type_complete,
      capabilities: capabilities(Keyword.get(opts, :capabilities, %{})),
      _meta: %ResultMetaObject{"io.modelcontextprotocol/serverInfo": server_info(opts)},
      supportedVersions: ["2026-07-28"]
    }
  end

  @doc """
  Normalizes capability flags into a `GenMCP.MCP.V2607.ServerCapabilities` struct.

  Each entry of the keyword list or map sets one capability field:

  * a value of `true` becomes an empty map `%{}` (the capability is enabled with
    no extra options),
  * a map value is kept as given (use this to pass sub-options such as
    `listChanged: true`),
  * any other value (`false`, `nil`) leaves the field `nil`, meaning the
    capability is not advertised.

  A `GenMCP.MCP.V2607.ServerCapabilities` struct passed in is returned unchanged.

  ### Examples

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> caps = MCP.capabilities(tools: true, resources: %{subscribe: true}, prompts: false)
      iex> {caps.tools, caps.resources, caps.prompts}
      {%{}, %{subscribe: true}, nil}
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
  Builds the `GenMCP.MCP.V2607.Implementation` struct describing the server.

  This is the `io.modelcontextprotocol/serverInfo` metadata carried in the
  `_meta` of the `server/discover` response.

  ### Options

  * `:name` - the server name, required. Raises `KeyError` if missing.
  * `:version` - the server version, required. Raises `KeyError` if missing.
  * `:title` - an optional human-friendly title.

  ### Examples

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> info = MCP.server_info(name: "MyServer", version: "1.0.0")
      iex> {info.name, info.version, info.title}
      {"MyServer", "1.0.0", nil}
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
  Wraps a list of tools into a `GenMCP.MCP.V2607.ListToolsResult`.

  This is what a Suite answers a `tools/list` request with. Each element is
  either a ready `GenMCP.MCP.V2607.Tool` struct, which is kept as is, or a tool
  definition (`t:GenMCP.Suite.Tool.tool/0`: a module, a `{module, arg}` pair, or
  a descriptor map), which is converted with `GenMCP.Suite.Tool.describe/1`.

  ### Options

  * `:cache_scope` - the `cacheScope` cache hint. Defaults to the no-cache hint
    (see `default_cache_control/0`).
  * `:ttl_ms` - the `ttlMs` cache hint. Same default.

  ### Examples

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> tool = %MCP.Tool{name: "add", inputSchema: %{"type" => "object"}}
      iex> result = MCP.list_tools_result([tool])
      iex> [%MCP.Tool{name: name}] = result.tools
      iex> name
      "add"
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
  Builds a single content block struct from a shorthand term.

  Tools and prompts return content blocks. This builder turns a compact tuple
  into the matching struct so callers do not write struct literals by hand. It is
  used on its own when you need one block, and internally by `call_tool_result/1`
  and `get_prompt_result/1` for each entry they receive.

  The accepted shorthands are:

  * `{:text, text}` - a `GenMCP.MCP.V2607.TextContent`.
  * `{:image, {mime_type, data}}` - a `GenMCP.MCP.V2607.ImageContent`, with
    base64-encoded `data`.
  * `{:audio, {mime_type, data}}` - a `GenMCP.MCP.V2607.AudioContent`, with
    base64-encoded `data`.
  * `{:resource, %{uri: uri, text: text}}` or `{:resource, %{uri: uri, blob:
    blob}}` - a `GenMCP.MCP.V2607.EmbeddedResource`.
  * `{:link, %{name: name, uri: uri}}` - a `GenMCP.MCP.V2607.ResourceLink`. Extra
    keys in the map are carried onto the struct.

  Any other term raises `ArgumentError`.

  ### Examples

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> %MCP.TextContent{text: text} = MCP.content_block({:text, "hello"})
      iex> text
      "hello"

  An image block carries its MIME type and base64 payload:

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> block = MCP.content_block({:image, {"image/png", "aGVsbG8="}})
      iex> {block.mimeType, block.data}
      {"image/png", "aGVsbG8="}
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
  Builds the `GenMCP.MCP.V2607.CallToolResult` a tool returns from a `tools/call`.

  Pass a list (a keyword list reads well, since keys may repeat) of entries. Each
  entry contributes to the result's `content`, its `structuredContent`, or its
  `isError` flag:

  * **Content shorthands** (`{:text, _}`, `{:image, _}`, `{:audio, _}`,
    `{:resource, _}`, `{:link, _}`) are turned into content blocks by
    `content_block/1` and appended to `content`.
  * **Literal content structs** (a `GenMCP.MCP.V2607.TextContent` and the other
    content structs) are appended to `content` unchanged. You may mix shorthands
    and structs in the same list.
  * **`{:data, map}`** sets `structuredContent` to the map and also mirrors it
    into `content` as a JSON-encoded text block.
  * **`{:_data, map}`** sets `structuredContent` without the text mirror. A bare
    map entry behaves like `{:data, map}`.
  * **`{:error, true}`** sets `isError` to `true`. The flag is sticky: once any
    entry sets it, a later `{:error, false}` does not clear it. `{:error,
    false}` and `{:error, nil}` on their own leave the flag unset.
  * **`{:error, message}`** with a binary appends the message as a text block and
    sets `isError` to `true`.

  Only one structured content may be set; a second `:data`, `:_data`, or bare map
  raises `ArgumentError`. The result's `resultType` is always `"complete"`.

  ### Examples

  The common case is a single text result:

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result = MCP.call_tool_result(text: "42")
      iex> match?(%MCP.CallToolResult{content: [%MCP.TextContent{text: "42"}], isError: nil}, result)
      true

  Return structured data alongside a human-readable summary. With `:data` the map
  is both set as `structuredContent` and mirrored as a JSON text block; use
  `:_data` to set the structured content without the extra text block:

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result = MCP.call_tool_result(text: "3 rows", data: %{rows: 3})
      iex> result.structuredContent
      %{rows: 3}
      iex> length(result.content)
      2

  Flag a failure with `error:`; a binary message is added as text content:

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result = MCP.call_tool_result(error: "boom")
      iex> match?(%MCP.CallToolResult{content: [%MCP.TextContent{text: "boom"}], isError: true}, result)
      true
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
  Wraps resources and a cursor into a `GenMCP.MCP.V2607.ListResourcesResult`.

  This is the answer to a `resources/list` request. The `resources` are placed in
  the result as given, and `next_cursor` becomes `nextCursor` (pass `nil` for the
  last page).

  ### Options

  * `:cache_scope` - the `cacheScope` cache hint. Defaults to the no-cache hint
    (see `default_cache_control/0`).
  * `:ttl_ms` - the `ttlMs` cache hint. Same default.

  ### Examples

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result = MCP.list_resources_result([], "next-page")
      iex> {result.resources, result.nextCursor}
      {[], "next-page"}
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
  Wraps skill entries and a cursor into a `GenMCP.MCP.V2607.ListSkillsResult`.

  This is the answer to a `skills/list` request of the
  `io.modelcontextprotocol/skills` extension. The `skills` are placed in the
  result as given, and `next_cursor` becomes `nextCursor` (pass `nil` for the
  last page). Build each entry with `skill/1`.

  ### Options

  * `:cache_scope` - the `cacheScope` cache hint. Defaults to the no-cache hint
    (see `default_cache_control/0`).
  * `:ttl_ms` - the `ttlMs` cache hint. Same default.

  ### Examples

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> skill =
      ...>   MCP.skill(
      ...>     uri: "skill://acme/refunds/SKILL.md",
      ...>     frontmatter: %{"name" => "refunds", "description" => "Process refunds"},
      ...>     resources: :dynamic
      ...>   )
      iex> result = MCP.list_skills_result([skill], "next-page")
      iex> {length(result.skills), result.nextCursor}
      {1, "next-page"}
  """
  @spec list_skills_result([Skill.t()], term() | nil, keyword) :: ListSkillsResult.t()
  def list_skills_result(skills, next_cursor, opts \\ []) do
    %ListSkillsResult{
      resultType: @result_type_complete,
      cacheScope: Keyword.get(opts, :cache_scope, @default_cache_scope),
      ttlMs: Keyword.get(opts, :ttl_ms, @default_ttl_ms),
      skills: skills,
      nextCursor: next_cursor
    }
  end

  @doc """
  Builds the `GenMCP.MCP.V2607.GetSkillResult` returned for `skills/get`.

  There are two ways to give the skill entry:

  * **Flat form**: pass `:uri`, `:frontmatter` and `:resources`. The entry is
    built for you with `skill/1`.
  * **`:skill` form**: pass `:skill` with an entry already built by `skill/1` or
    `skill_entry_from_path/3`. The flat options are then ignored.

  ### Options

  * `:uri`, `:frontmatter`, `:resources`, `:_meta` - the entry in the flat form,
    as described in `skill/1`.
  * `:skill` - a `GenMCP.MCP.V2607.Skill`, used instead of the flat options.
  * `:cache_scope` - the `cacheScope` cache hint. Defaults to the no-cache hint
    (see `default_cache_control/0`).
  * `:ttl_ms` - the `ttlMs` cache hint. Same default.

  ### Examples

  The flat form builds the entry and the result in one call:

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result =
      ...>   MCP.get_skill_result(
      ...>     uri: "skill://acme/refunds/SKILL.md",
      ...>     frontmatter: %{"name" => "refunds", "description" => "Process refunds"},
      ...>     resources: :dynamic,
      ...>     cache_scope: :public,
      ...>     ttl_ms: 60_000
      ...>   )
      iex> {result.skill.uri, result.skill.resources, result.cacheScope, result.ttlMs}
      {"skill://acme/refunds/SKILL.md", "dynamic", :public, 60_000}
  """
  @spec get_skill_result(keyword) :: GetSkillResult.t()
  def get_skill_result(opts) do
    {wrapper_opts, opts} = Keyword.split(opts, [:cache_scope, :ttl_ms])

    skill =
      case :proplists.get_value(:skill, opts) do
        :undefined -> skill(opts)
        %Skill{} = skill -> skill
      end

    %GetSkillResult{
      resultType: @result_type_complete,
      cacheScope: Keyword.get(wrapper_opts, :cache_scope, @default_cache_scope),
      ttlMs: Keyword.get(wrapper_opts, :ttl_ms, @default_ttl_ms),
      skill: skill
    }
  end

  @doc ~S"""
  Builds one `GenMCP.MCP.V2607.Skill`, the entry describing a skill.

  A skill entry is what `skills/list` and `skills/get` return for each skill:
  the URI of its `SKILL.md`, the frontmatter of that file, and the manifest of
  the files that make up the skill. Hosts compare the digest and size of each
  manifest entry with the bytes they receive from `resources/read`, so both must
  describe the raw bytes of the file.

  ### Options

  * `:uri` - the URI of the skill's `SKILL.md`, required. Its last segment before
    `/SKILL.md` is the skill's `name`.
  * `:frontmatter` - the YAML frontmatter of `SKILL.md` as a map with string
    keys, required. It carries at least `"name"` and `"description"`, and every
    other key the author wrote, unchanged.
  * `:resources` - the manifest, required. Either a list with one entry per file
    of the skill, `SKILL.md` included, or `:dynamic` for a skill whose content is
    generated on demand. Each file entry is a map with `:uri`, `:digest`
    (`"sha256:"` followed by 64 lowercase hexadecimal characters) and `:size`
    (the length in bytes), or a `GenMCP.MCP.V2607.SkillResource`.
  * `:_meta` - optional metadata attached to the entry.

  ### Examples

  An entry with a one-file manifest, computing the digest and size from the
  content that `resources/read` serves:

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> content = "---\nname: refunds\ndescription: Process refunds\n---\n"
      iex> digest = "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)
      iex> skill =
      ...>   MCP.skill(
      ...>     uri: "skill://acme/refunds/SKILL.md",
      ...>     frontmatter: %{"name" => "refunds", "description" => "Process refunds"},
      ...>     resources: [
      ...>       %{uri: "skill://acme/refunds/SKILL.md", digest: digest, size: byte_size(content)}
      ...>     ]
      ...>   )
      iex> [%MCP.SkillResource{uri: uri, size: size}] = skill.resources
      iex> {uri, size}
      {"skill://acme/refunds/SKILL.md", 51}

  A skill generated on demand declares a dynamic manifest:

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> skill =
      ...>   MCP.skill(
      ...>     uri: "skill://acme/report/SKILL.md",
      ...>     frontmatter: %{"name" => "report", "description" => "Build a report"},
      ...>     resources: :dynamic
      ...>   )
      iex> skill.resources
      "dynamic"
  """
  @spec skill(keyword) :: Skill.t()
  def skill(opts) do
    %Skill{
      uri: require_key!(opts, :uri, "option :uri is required by #{cur_fun()}"),
      frontmatter:
        require_key!(opts, :frontmatter, "option :frontmatter is required by #{cur_fun()}"),
      resources:
        opts
        |> require_key!(:resources, "option :resources is required by #{cur_fun()}")
        |> skill_resources(),
      _meta: Keyword.get(opts, :_meta)
    }
  end

  defp skill_resources(dynamic) when dynamic in [:dynamic, "dynamic"] do
    "dynamic"
  end

  defp skill_resources(resources) when is_list(resources) do
    Enum.map(resources, fn
      %SkillResource{} = resource -> resource
      %{uri: _, digest: _, size: _} = resource -> struct!(SkillResource, resource)
    end)
  end

  @doc """
  Builds a skill entry from a skill directory on disk.

  `skill_md_path` is the path of a `SKILL.md` file. The directory that contains
  it is the skill: every file under it, at any depth, belongs to the skill. The
  function reads them all and returns `{skill, files}`:

  * `skill` is the `GenMCP.MCP.V2607.Skill` entry, with the frontmatter parsed
    from `SKILL.md` and a manifest holding the SHA-256 digest and the size of
    each file.
  * `files` maps the URI of each file to
    `%{path: relative_path, text?: boolean, mime_type: mime_type}`. `path` is
    relative to the skill directory, `text?` tells whether the content is valid
    UTF-8, and `mime_type` comes from `MIME.from_path/1`. Use it to serve the
    files in `c:GenMCP.Suite.ResourceRepo.read/3`: return a UTF-8 file as `:text`
    and any other file as a base64 `:blob`, so the bytes the host receives are
    the ones the digest covers.

  The skill's URI is `base_uri`, then the frontmatter `name`, then `/SKILL.md`.
  Each file gets the URI of the skill directory followed by its relative path.
  The name and the path segments are URI-encoded, and a `/` separates `base_uri`
  from the name when `base_uri` does not end with one. The name of the directory
  on disk plays no part.

  The frontmatter is the YAML block between the two `---` lines at the top of
  `SKILL.md`. It is parsed with `:yamerl`, an optional dependency to add to your
  project: `{:yamerl, "~> 0.10"}`. Keys are strings and YAML `null` values are
  `nil`.

  This function is made for compile time, as `GenMCP.Suite.SkillRepo.Static`
  uses it. It raises an `ArgumentError` when `SKILL.md` has no frontmatter, when
  the frontmatter is invalid YAML, or when `name` or `description` is missing. It
  emits a warning when the name departs from the Agent Skills naming rules (at
  most 64 lowercase letters, digits and single hyphens), and when the skill
  exceeds 512 files or 16 MiB, the sizes every host accepts.

  ### Options

  * `:extensions` - a list of file extensions with their leading dot, such as
    `[".md", ".py"]`. Only the files with one of these extensions are part of
    the skill. The `SKILL.md` given as `skill_md_path` is always included.
    Defaults to every file.

  ### Examples

  Building the entry of a skill kept in the application's `priv` directory:

      {skill, files} =
        MCP.skill_entry_from_path(
          "priv/skills/refunds/SKILL.md",
          "skill://acme/",
          extensions: [".md", ".json"]
        )

      skill.uri
      #=> "skill://acme/refunds/SKILL.md"

      files["skill://acme/refunds/references/policy.md"]
      #=> %{path: "references/policy.md", text?: true, mime_type: "text/markdown"}
  """
  @spec skill_entry_from_path(Path.t(), String.t(), keyword) ::
          {Skill.t(), %{String.t() => skill_file_info}}
  def skill_entry_from_path(skill_md_path, base_uri, opts \\ []) do
    SkillFiles.skill_entry_from_path(skill_md_path, base_uri, opts)
  end

  @doc """
  Wraps templates into a `GenMCP.MCP.V2607.ListResourceTemplatesResult`.

  This is the answer to a `resources/templates/list` request. The `templates` are
  placed in the result as given.

  ### Options

  * `:cache_scope` - the `cacheScope` cache hint. Defaults to the no-cache hint
    (see `default_cache_control/0`).
  * `:ttl_ms` - the `ttlMs` cache hint. Same default.

  ### Examples

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result = MCP.list_resource_templates_result([])
      iex> result.resourceTemplates
      []
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
  Builds the `GenMCP.MCP.V2607.ReadResourceResult` returned for `resources/read`.

  There are two ways to give the contents:

  * **Single content (flat form)**: pass `:uri` together with `:text` or `:blob`
    (and optional `:mime_type`). One content entry is built for you with
    `resource_contents/1`.
  * **Multiple contents (`:contents` form)**: pass `:contents` with a list of
    content structs (built by `resource_contents/1`) or plain maps. When
    `:contents` is given, the flat `:uri` / `:text` / `:blob` / `:mime_type`
    options are ignored. The list may be empty.

  ### Options

  * `:uri` - the resource URI for the flat form. Required there; raises
    `KeyError` if missing.
  * `:text` or `:blob` - the resource body for the flat form. One is required;
    raises `ArgumentError` if neither is given.
  * `:mime_type` - optional MIME type for the flat form.
  * `:contents` - a list of content entries, used instead of the flat options.
  * `:_meta` - metadata set on the result object itself. This is distinct from a
    per-content `_meta`, which you attach through `resource_contents/1`.
  * `:cache_scope` - the `cacheScope` cache hint. Defaults to the no-cache hint
    (see `default_cache_control/0`).
  * `:ttl_ms` - the `ttlMs` cache hint. Same default.

  ### Examples

  The flat form covers the usual single-file read:

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result = MCP.read_resource_result(uri: "file:///readme.txt", text: "# Welcome")
      iex> [%MCP.TextResourceContents{uri: uri, text: text}] = result.contents
      iex> {uri, text}
      {"file:///readme.txt", "# Welcome"}

  Use the `:contents` form to return several entries, building each with
  `resource_contents/1`:

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result =
      ...>   MCP.read_resource_result(
      ...>     contents: [
      ...>       MCP.resource_contents(uri: "file:///a.txt", text: "first"),
      ...>       MCP.resource_contents(uri: "file:///b.png", blob: "aGk=", mime_type: "image/png")
      ...>     ]
      ...>   )
      iex> length(result.contents)
      2
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
  Builds one resource content entry for `read_resource_result/1`.

  Returns a `GenMCP.MCP.V2607.TextResourceContents` when `:text` is given, or a
  `GenMCP.MCP.V2607.BlobResourceContents` when `:blob` is given. Use this to
  assemble the `:contents` list passed to `read_resource_result/1` when a read
  returns more than one entry.

  ### Options

  * `:uri` - the content URI, required. Raises `KeyError` if missing.
  * `:text` - the text body. Produces a `TextResourceContents`.
  * `:blob` - the base64-encoded binary body. Produces a `BlobResourceContents`.
    Provide exactly one of `:text` or `:blob`, otherwise it raises
    `ArgumentError`.
  * `:mime_type` - optional MIME type.
  * `:_meta` - optional metadata attached to this content entry.

  ### Examples

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> contents = MCP.resource_contents(uri: "file:///a.txt", text: "hi", mime_type: "text/plain")
      iex> {contents.uri, contents.text, contents.mimeType}
      {"file:///a.txt", "hi", "text/plain"}
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
  Wraps prompts and a cursor into a `GenMCP.MCP.V2607.ListPromptsResult`.

  This is the answer to a `prompts/list` request. The `prompts` are placed in the
  result as given, and `next_cursor` becomes `nextCursor` (pass `nil` for the
  last page).

  ### Options

  * `:cache_scope` - the `cacheScope` cache hint. Defaults to the no-cache hint
    (see `default_cache_control/0`).
  * `:ttl_ms` - the `ttlMs` cache hint. Same default.

  ### Examples

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result = MCP.list_prompts_result([], nil)
      iex> {result.prompts, result.nextCursor}
      {[], nil}
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
  Builds the `GenMCP.MCP.V2607.GetPromptResult` returned for `prompts/get`.

  Pass a list of message entries (a keyword list reads well, since keys repeat),
  plus an optional `:description`. Each message entry becomes a
  `GenMCP.MCP.V2607.PromptMessage`:

  * `{:text, binary}` - a `"user"` message carrying text content.
  * `{:assistant, binary}` - an `"assistant"` message carrying text content.
  * other content shorthands (`{:image, _}`, `{:audio, _}`, `{:resource, _}`) -
    a `"user"` message carrying that content, built by `content_block/1`. A
    `{:link, _}` shorthand is rejected, since a resource link is not a valid
    prompt message content.
  * a ready `%{role: role, content: content}` map or `GenMCP.MCP.V2607.PromptMessage`
    struct is kept as is. Use this to pair the `"assistant"` role with non-text
    content.

  The optional `:description` entry sets the result's `description`.

  ### Examples

  The keyword shorthands cover a simple user/assistant exchange:

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result = MCP.get_prompt_result(text: "hello", assistant: "hi there", description: "greeting")
      iex> result.description
      "greeting"
      iex> Enum.map(result.messages, & &1.role)
      ["user", "assistant"]

  To give the assistant role non-text content, pass a full message struct, since
  the `{:assistant, _}` shorthand only takes text:

      iex> alias GenMCP.MCP.V2607, as: MCP
      iex> result =
      ...>   MCP.get_prompt_result([
      ...>     {:text, "describe this sound"},
      ...>     %MCP.PromptMessage{
      ...>       role: "assistant",
      ...>       content: MCP.content_block({:audio, {"audio/mp3", "aGk="}})
      ...>     }
      ...>   ])
      iex> Enum.map(result.messages, & &1.role)
      ["user", "assistant"]
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
