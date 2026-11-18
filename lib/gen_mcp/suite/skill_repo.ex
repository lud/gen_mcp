defmodule GenMCP.Suite.SkillRepo do
  @moduledoc ~S"""
  Behaviour for a repository of Agent Skills served by a `GenMCP.Suite`.

  A skill is a directory of instructions for an agent: a `SKILL.md` file with a
  YAML frontmatter, and the files that support it. The
  `io.modelcontextprotocol/skills` protocol extension lets a host discover the
  skills of a server with `skills/list` and `skills/get`, then load their files
  on demand with the ordinary `resources/read`.

  A skill repository is therefore a `GenMCP.Suite.ResourceRepo` that also
  describes its skills. It implements both behaviours in one module:

  * `c:list_skills/3` and `c:get_skill/3`, defined here, return skill entries. An
    entry is a `t:GenMCP.MCP.V2607.Skill.t/0` holding the URI of the `SKILL.md`,
    its frontmatter, and a manifest with the digest and size of every file.
  * `c:GenMCP.Suite.ResourceRepo.prefix/1` and
    `c:GenMCP.Suite.ResourceRepo.read/3` serve the files. The bytes returned for
    a file must be the ones its manifest entry describes, because hosts verify
    them.

  To serve a directory of skill files shipped with your application, use
  `GenMCP.Suite.SkillRepo.Static`, which implements all of this at compile time.
  Implement the behaviour yourself when the skills come from somewhere else, for
  example a database.

  ## Minimal implementation

  A repository that serves playbooks as skills, one `SKILL.md` each. The
  playbooks live in a plain `MyApp.Playbooks` module, whose `fetch/1` returns the
  description of a playbook and its Markdown, starting with the frontmatter. The
  repository only turns them into entries and file contents:

      defmodule MyApp.PlaybookSkills do
        use GenMCP.Suite.SkillRepo

        alias GenMCP.MCP.V2607, as: MCP

        @prefix "skill://my-app/"

        @impl true
        def prefix(_arg), do: @prefix

        @impl true
        def list(_cursor, _channel, _arg), do: {[], nil}

        @impl true
        def list_skills(_cursor, _channel, _arg) do
          skills =
            for name <- MyApp.Playbooks.names() do
              {:ok, playbook} = MyApp.Playbooks.fetch(name)
              entry(name, playbook)
            end

          {skills, nil}
        end

        @impl true
        def get_skill(uri, _channel, _arg) do
          with {:ok, name} <- playbook_name(uri),
               {:ok, playbook} <- MyApp.Playbooks.fetch(name) do
            {:ok, entry(name, playbook)}
          else
            :error -> {:error, :not_found}
          end
        end

        @impl true
        def read(uri, _channel, _arg) do
          with {:ok, name} <- playbook_name(uri),
               {:ok, %{markdown: markdown}} <- MyApp.Playbooks.fetch(name) do
            {:ok, MCP.read_resource_result(uri: uri, text: markdown, mime_type: "text/markdown")}
          else
            :error -> {:error, :not_found}
          end
        end

        defp playbook_name(uri) do
          case String.split(uri, "/") do
            ["skill:", "", "my-app", name, "SKILL.md"] -> {:ok, name}
            _ -> :error
          end
        end

        defp entry(name, playbook) do
          %{description: description, markdown: markdown} = playbook
          uri = "#{@prefix}#{name}/SKILL.md"
          digest = "sha256:" <> Base.encode16(:crypto.hash(:sha256, markdown), case: :lower)

          MCP.skill(
            uri: uri,
            frontmatter: %{"name" => name, "description" => description},
            resources: [%{uri: uri, digest: digest, size: byte_size(markdown)}]
          )
        end
      end

  `use GenMCP.Suite.SkillRepo` declares both behaviours, so the compiler reports
  a callback you forgot.

  ### Wiring a repository into the server

  A skill repository is given to the Suite through its `:skills` option. Because
  the Suite is the default `:server`, those options are passed straight to the
  transport plug in your router. Each entry is a bare module or a `{module, arg}`
  tuple, where `arg` is handed back to every callback as the trailing argument:

      # In your router
      forward "/mcp", GenMCP.Transport.StreamableHTTP,
        server_name: "My App",
        server_version: "1.0.0",
        skills: [MyApp.PlaybookSkills]

  With a skill repository configured, `server/discover` declares the
  `io.modelcontextprotocol/skills` extension and the `resources` capability.

  ## Skill URIs and the prefix

  The URI of a skill is the URI of its `SKILL.md`. The path before `/SKILL.md`
  is the skill's root: its last segment is the skill's `name`, and every file of
  the skill has a URI under that root, such as
  `skill://my-app/refunds/scripts/refund.py`. One repository holds as many skills
  as you like under its prefix.

  The Suite routes `skills/get` and `resources/read` to the first repository
  whose prefix the requested URI starts with, and that repository's answer is
  final. Make every prefix a sequence of complete path segments ending with a
  slash, such as `skill://my-app/`, and give each repository a prefix of its own.
  The trailing slash keeps `skill://my-app/` apart from `skill://my-app-tools/`.

  ## Serving the files

  On `resources/read`, the Suite consults the skill repositories before the
  resource repositories of the `:resources` option, so the files of a skill are
  always served by the repository that published their digests.

  Skills have their own listing, so `c:GenMCP.Suite.ResourceRepo.list/3` usually
  returns `{[], nil}`. To advertise the files in `resources/list` as well, give
  the module in the `:resources` option too and return them from `list/3`.

  The optional `c:GenMCP.Suite.ResourceRepo.cache_control/1` sets the cache hint
  of the `skills/list` and `skills/get` results of the repository.

  ## Provider arguments

  The arguments the callbacks receive follow the conventions shared by all Suite
  providers, documented in `GenMCP.Suite`:

  * `channel` is the request-scoped `t:GenMCP.Mux.Channel.t/0`, carrying
    read-only client `meta` and auth assigns, so a repository can tailor the
    skills it exposes to the caller.
  * `arg` is the value configured alongside the module as `{module, arg}` (a bare
    module is treated as `{module, []}`). It is the trailing argument of every
    callback.
  """
  import GenMCP.Utils.CallbackExt

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.Suite.ResourceRepo

  @type arg :: term
  @type skill_repo :: ResourceRepo.resource_repo()
  @type skill_repo_descriptor :: ResourceRepo.resource_repo_descriptor()

  @doc """
  Lists the skills this repository advertises for `skills/list`.

  Returns a `{skills, next_cursor}` tuple. Each element of `skills` is a
  `t:GenMCP.MCP.V2607.Skill.t/0`, built with `GenMCP.MCP.V2607.skill/1`, whose
  URI begins with the repository's prefix. An entry always carries the complete
  manifest of its skill. `next_cursor` carries pagination: return `nil` on the
  last page, or a term that the Suite hands back as the `pagination_token` of the
  next call.

  The `pagination_token` is `nil` on the first call. `channel` is the
  request-scoped `t:GenMCP.Mux.Channel.t/0`, and `arg` is the configured value.

  A single-page repository ignores the token and returns `nil` as the cursor:

      @impl true
      def list_skills(_cursor, _channel, _arg) do
        skills = [
          MCP.skill(
            uri: "skill://my-app/report/SKILL.md",
            frontmatter: %{"name" => "report", "description" => "Build a report"},
            resources: :dynamic
          )
        ]

        {skills, nil}
      end

  To paginate, return a token on every page but the last, and resume from it on
  the next call:

      @impl true
      def list_skills(nil, _channel, _arg), do: {first_page(), "page-2"}
      def list_skills("page-2", _channel, _arg), do: {second_page(), nil}
  """
  @callback list_skills(pagination_token :: String.t() | nil, Channel.t(), arg) ::
              {[MCP.Skill.t()], next_cursor :: term | nil}

  @doc """
  Returns the entry of one skill, for `skills/get`.

  `uri` is the URI of the skill's `SKILL.md`. Return `{:ok, skill}` with its
  `t:GenMCP.MCP.V2607.Skill.t/0`, or `{:error, :not_found}` when the URI names no
  skill of this repository, which the Suite reports to the client as an invalid
  params error.

  Answer for every skill the repository serves. A host calls `skills/get` with a
  URI it already knows, for instance from an earlier session, so look the skill
  up directly, including the skills that `c:list_skills/3` leaves out of its
  listing.

  `channel` is the request-scoped `t:GenMCP.Mux.Channel.t/0`, and `arg` is the
  configured value.

      @impl true
      def get_skill("skill://my-app/report/SKILL.md" = uri, _channel, _arg) do
        skill =
          MCP.skill(
            uri: uri,
            frontmatter: %{"name" => "report", "description" => "Build a report"},
            resources: :dynamic
          )

        {:ok, skill}
      end

      def get_skill(_uri, _channel, _arg), do: {:error, :not_found}
  """
  @callback get_skill(uri :: String.t(), Channel.t(), arg) ::
              {:ok, MCP.Skill.t()} | {:error, :not_found}

  @doc """
  Declares the `GenMCP.Suite.ResourceRepo` and `GenMCP.Suite.SkillRepo`
  behaviours on the calling module.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour GenMCP.Suite.ResourceRepo
      @behaviour GenMCP.Suite.SkillRepo
    end
  end

  @doc """
  Normalizes a skill repository spec into a descriptor map.

  A skill repository is expanded exactly as a resource repository: see
  `GenMCP.Suite.ResourceRepo.expand/1`.
  """
  @spec expand(skill_repo) :: skill_repo_descriptor
  defdelegate expand(skill_repo), to: ResourceRepo

  @doc """
  Invokes the repository's `c:list_skills/3` to list its skills.

  Given a descriptor from `expand/1`, calls the repository module's
  `c:list_skills/3` with the pagination `cursor`, the request `channel`, and the
  descriptor's `arg`, and returns the `{skills, next_cursor}` tuple it produces.
  `GenMCP.Suite` uses this to answer a `skills/list`.
  """
  @spec list_skills(skill_repo_descriptor, term | nil, Channel.t()) ::
          {[MCP.Skill.t()], next_cursor :: term | nil}
  def list_skills(repo, cursor, channel) do
    callback __MODULE__, repo.mod.list_skills(cursor, channel, repo.arg) do
      {list, cursor} when is_list(list) -> {list, cursor}
    end
  end

  @doc """
  Invokes the repository's `c:get_skill/3` to fetch the entry of the skill at
  `uri`.

  Given a descriptor from `expand/1`, returns `{:ok, skill}` with the
  `t:GenMCP.MCP.V2607.Skill.t/0` from the callback. A `{:error, :not_found}` from
  the callback becomes `{:error, {:skill_not_found, uri}}`. `GenMCP.Suite` uses
  this to answer a `skills/get`.
  """
  @spec get_skill(skill_repo_descriptor, String.t(), Channel.t()) ::
          {:ok, MCP.Skill.t()} | {:error, {:skill_not_found, String.t()}}
  def get_skill(repo, uri, channel) do
    callback __MODULE__, repo.mod.get_skill(uri, channel, repo.arg) do
      {:ok, %MCP.Skill{}} = ok -> ok
      {:error, :not_found} -> {:error, {:skill_not_found, uri}}
    end
  end
end
