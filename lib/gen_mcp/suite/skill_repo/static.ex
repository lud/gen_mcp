defmodule GenMCP.Suite.SkillRepo.Static do
  @moduledoc """
  A `GenMCP.Suite.SkillRepo` that serves a directory of Agent Skills shipped in
  your application's `priv` directory.

  Write your skills as plain directories, each with a `SKILL.md`, and `use` this
  module to turn the directory into a skill repository. The skill entries, with
  the digest and size of every file, are computed when the module compiles, so
  the manifests always describe the files you ship.

  Given this tree in the `:my_app` application:

      priv/skills/
        refunds/
          SKILL.md
          scripts/refund.py
        onboarding/
          SKILL.md

  The repository is one module:

      defmodule MyApp.Skills do
        use GenMCP.Suite.SkillRepo.Static,
          otp_app: :my_app,
          dir: "skills",
          prefix: "skill://my-app/"
      end

  Give it to the Suite through its `:skills` option, in your router:

      forward "/mcp", GenMCP.Transport.StreamableHTTP,
        server_name: "My App",
        server_version: "1.0.0",
        skills: [MyApp.Skills]

  The server now answers `skills/list` and `skills/get` with the two skills, and
  serves their files through `resources/read`.

  The frontmatter of each `SKILL.md` is parsed with `:yamerl` at compile time.
  Add it to the dependencies of your project: `{:yamerl, "~> 0.10"}`.

  ## Options

  * `:otp_app` - required, the application the module belongs to. The files are
    read from its `priv` directory.
  * `:dir` - required, the directory of skills, relative to `priv`.
  * `:prefix` - required, the URI prefix of the repository, such as
    `"skill://my-app/"`. Use complete path segments, and a prefix of its own for
    each repository. A trailing slash is added when missing.
  * `:extensions` - a list of file extensions with their leading dot, such as
    `[".md", ".py"]`. Only the files with one of these extensions are served.
    The `SKILL.md` of each skill is always served. Defaults to every file.
  * `:page_size` - the number of skills in a `skills/list` page. Defaults to
    `20`.

  ## Directory layout and URIs

  Each direct subdirectory of `:dir` that contains a `SKILL.md` is a skill.
  Every file under it, at any depth, is a file of that skill and appears in its
  manifest.

  A skill is served under the `name` of its frontmatter: with the prefix
  `skill://my-app/`, a `SKILL.md` declaring `name: refunds` has the URI
  `skill://my-app/refunds/SKILL.md`, and its script is
  `skill://my-app/refunds/scripts/refund.py`. Each skill of a directory declares
  a different name.

  To organize skills in a deeper hierarchy, define one module per directory,
  each with a longer prefix such as `skill://my-app/billing/`.

  Compilation fails with an `ArgumentError` when a `SKILL.md` has no valid
  frontmatter, when `name` or `description` is missing, or when two skills
  declare the same name. A name that departs from the Agent Skills naming rules
  (at most 64 lowercase letters, digits and single hyphens) emits a warning. See
  `GenMCP.MCP.V2607.skill_entry_from_path/3`, which builds each entry.

  ## Compilation and releases

  The module recompiles when a file of the directory is edited, added or
  removed, so the manifests follow your changes during development.

  The contents of the files are read from disk on every `resources/read`, from
  the `priv` directory of `:otp_app`. Files with valid UTF-8 content are served
  as text and the others as base64 blobs, each with the MIME type of its
  extension. A release ships `priv` with the application, so the files are
  served there the same way.

  ## Generated callbacks

  The module implements `GenMCP.Suite.SkillRepo` and
  `GenMCP.Suite.ResourceRepo`. All the generated callbacks are overridable:

  * `c:GenMCP.Suite.ResourceRepo.prefix/1`, generated from the `:prefix` option.
  * `c:GenMCP.Suite.ResourceRepo.read/3`, serving the files.
  * `c:GenMCP.Suite.ResourceRepo.list/3`, returning an empty listing. Override
    it, and give the module in the Suite's `:resources` option too, to advertise
    the files in `resources/list`.
  * `c:GenMCP.Suite.SkillRepo.list_skills/3`, paging by the `:page_size` option.
  * `c:GenMCP.Suite.SkillRepo.get_skill/3`.

  Define `c:GenMCP.Suite.ResourceRepo.cache_control/1` in the module to set the
  cache hint of its results:

      defmodule MyApp.Skills do
        use GenMCP.Suite.SkillRepo.Static,
          otp_app: :my_app,
          dir: "skills",
          prefix: "skill://my-app/"

        @impl true
        def cache_control(_arg), do: {:public, 60_000}
      end
  """

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Utils.SkillFiles
  alias __MODULE__

  @opts_schema NimbleOptions.new!(
                 otp_app: [type: :atom, required: true],
                 dir: [type: :string, required: true],
                 prefix: [type: :string, required: true],
                 extensions: [type: {:or, [{:list, :string}, nil]}, default: nil],
                 page_size: [type: :pos_integer, default: 20]
               )

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use GenMCP.Suite.SkillRepo

      @before_compile Static

      gen_mcp_static_skills = Static.__compile__(opts)

      Enum.each(gen_mcp_static_skills.external_resources, fn path ->
        Module.put_attribute(__MODULE__, :external_resource, path)
      end)

      @gen_mcp_skills_abs_dir gen_mcp_static_skills.abs_dir
      @gen_mcp_skills_listing_hash gen_mcp_static_skills.listing_hash
      @gen_mcp_skills_prefix gen_mcp_static_skills.prefix
      @gen_mcp_skills_by_uri gen_mcp_static_skills.skills_by_uri
      @gen_mcp_skills_files Map.take(gen_mcp_static_skills, [:otp_app, :dir, :index])
      @gen_mcp_skills_pages Map.take(gen_mcp_static_skills, [:skills, :page_size])

      @doc false
      def __mix_recompile__? do
        Static.__listing_hash__(@gen_mcp_skills_abs_dir) !=
          @gen_mcp_skills_listing_hash
      end

      @impl GenMCP.Suite.ResourceRepo
      def prefix(_arg) do
        @gen_mcp_skills_prefix
      end

      @impl GenMCP.Suite.ResourceRepo
      def list(_cursor, _channel, _arg) do
        {[], nil}
      end

      @impl GenMCP.Suite.ResourceRepo
      def read(uri, _channel, arg) do
        Static.__read__(@gen_mcp_skills_files, uri, cache_control(arg))
      end

      @impl GenMCP.Suite.SkillRepo
      def list_skills(cursor, _channel, _arg) do
        Static.__page__(@gen_mcp_skills_pages, cursor)
      end

      @impl GenMCP.Suite.SkillRepo
      def get_skill(uri, _channel, _arg) do
        case @gen_mcp_skills_by_uri do
          %{^uri => skill} -> {:ok, skill}
          _ -> {:error, :not_found}
        end
      end

      defoverridable prefix: 1, list: 3, read: 3, list_skills: 3, get_skill: 3
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    if !Module.defines?(env.module, {:cache_control, 1}, :def) do
      quote do
        @impl GenMCP.Suite.ResourceRepo
        def cache_control(_arg) do
          MCP.default_cache_control()
        end
      end
    end
  end

  @doc false
  def __compile__(opts) do
    opts = NimbleOptions.validate!(opts, @opts_schema)
    otp_app = Keyword.fetch!(opts, :otp_app)
    dir = Keyword.fetch!(opts, :dir)
    prefix = opts |> Keyword.fetch!(:prefix) |> with_trailing_slash()
    abs_dir = Path.expand(Path.join("priv", dir))

    check_otp_app!(otp_app)
    check_extensions!(opts[:extensions])

    if !File.dir?(abs_dir) do
      raise ArgumentError, "skills directory #{abs_dir} does not exist"
    end

    entries =
      abs_dir
      |> File.ls!()
      |> Enum.sort()
      |> Enum.filter(&File.regular?(Path.join([abs_dir, &1, "SKILL.md"])))
      |> Enum.map(fn skill_dir ->
        skill_md = Path.join([abs_dir, skill_dir, "SKILL.md"])

        {skill, files} =
          MCP.skill_entry_from_path(skill_md, prefix, extensions: opts[:extensions])

        {skill_dir, skill, files}
      end)

    check_duplicates!(entries, abs_dir)

    skills = Enum.map(entries, fn {_, skill, _} -> skill end)

    index =
      for {skill_dir, _, files} <- entries, {uri, info} <- files, into: %{} do
        {uri, %{info | path: Path.join(skill_dir, info.path)}}
      end

    %{
      otp_app: otp_app,
      dir: dir,
      prefix: prefix,
      page_size: Keyword.fetch!(opts, :page_size),
      skills: skills,
      skills_by_uri: Map.new(skills, &{&1.uri, &1}),
      index: index,
      abs_dir: abs_dir,
      external_resources: Enum.map(index, fn {_, info} -> Path.join(abs_dir, info.path) end),
      listing_hash: __listing_hash__(abs_dir)
    }
  end

  defp with_trailing_slash(prefix) do
    if String.ends_with?(prefix, "/") do
      prefix
    else
      prefix <> "/"
    end
  end

  defp check_otp_app!(otp_app) do
    case Mix.Project.config()[:app] do
      nil ->
        :ok

      ^otp_app ->
        :ok

      app ->
        raise ArgumentError,
              "skills are read from the priv directory of #{inspect(app)}, " <>
                "but :otp_app is #{inspect(otp_app)}"
    end
  end

  defp check_extensions!(nil) do
    :ok
  end

  defp check_extensions!(extensions) do
    Enum.each(extensions, fn ext ->
      if !String.starts_with?(ext, ".") do
        raise ArgumentError,
              "skill file extensions must start with a dot, got: #{inspect(ext)}"
      end
    end)
  end

  defp check_duplicates!(entries, abs_dir) do
    entries
    |> Enum.group_by(fn {_, skill, _} -> skill.uri end, fn {skill_dir, _, _} -> skill_dir end)
    |> Enum.each(fn
      {_uri, [_]} ->
        :ok

      {uri, skill_dirs} ->
        raise ArgumentError,
              "skill directories #{inspect(skill_dirs)} in #{abs_dir} declare the same skill #{uri}"
    end)
  end

  @doc false
  def __listing_hash__(abs_dir) do
    if File.dir?(abs_dir) do
      :erlang.phash2(SkillFiles.list_files_sorted(abs_dir))
    end
  end

  @doc false
  def __page__(data, cursor) do
    offset =
      case cursor do
        nil -> 0
        n when is_integer(n) and n >= 0 -> n
      end

    page = Enum.slice(data.skills, offset, data.page_size)
    next = offset + data.page_size

    if next < length(data.skills) do
      {page, next}
    else
      {page, nil}
    end
  end

  @doc false
  # sobelow_skip ["Traversal.FileModule"]
  def __read__(data, uri, {cache_scope, ttl_ms}) do
    case data.index do
      %{^uri => %{path: path, text?: text?, mime_type: mime_type}} ->
        bytes = File.read!(Application.app_dir(data.otp_app, ["priv", data.dir, path]))

        body =
          if text? do
            [text: bytes]
          else
            [blob: Base.encode64(bytes)]
          end

        {:ok,
         MCP.read_resource_result(
           [uri: uri, mime_type: mime_type, cache_scope: cache_scope, ttl_ms: ttl_ms] ++ body
         )}

      _ ->
        {:error, :not_found}
    end
  end
end
