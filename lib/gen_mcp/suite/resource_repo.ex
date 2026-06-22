defmodule GenMCP.Suite.ResourceRepo do
  @moduledoc ~S"""
  Behaviour for a repository of resources served by a `GenMCP.Suite`.

  A resource is addressable content a client can discover and read: a file, a
  database record, a rendered document. A resource repository groups related
  resources under a common URI prefix, answers `resources/list` to advertise the
  concrete ones, and answers `resources/read` to return the contents of a URI.

  The prefix is what ties the requests together. The Suite routes a
  `resources/read` to the repository whose prefix the requested URI starts with,
  so every URI a repository lists must begin with its prefix, and the prefixes of
  the configured repositories must not collide.

  A repository is a thin adapter: keep the real content (the files, the rows) in
  a module or store of your own, and let the callbacks route to it. The two
  required callbacks answer one question each, which prefix the resources live
  under (`c:prefix/1`) and what a URI's contents are (`c:read/3`), while
  `c:list/3` advertises the concrete URIs a client can discover.

  ## Minimal implementation

  A repository that serves two static Markdown resources under the
  `file:///docs/` prefix. `c:list/3` advertises them, and `c:read/3` returns the
  contents of a URI, built with the `GenMCP.MCP.V2607` helpers:

      defmodule MyApp.DocsResources do
        @behaviour GenMCP.Suite.ResourceRepo

        alias GenMCP.MCP.V2607, as: MCP

        @pages %{
          "file:///docs/intro.md" => "# Introduction\n\nWelcome.",
          "file:///docs/guide.md" => "# Guide\n\nStep one."
        }

        @impl true
        def prefix(_arg), do: "file:///docs/"

        @impl true
        def list(_cursor, _channel, _arg) do
          resources =
            for {uri, _body} <- @pages do
              %{uri: uri, name: Path.basename(uri), mimeType: "text/markdown"}
            end

          {resources, nil}
        end

        @impl true
        def read(uri, _channel, _arg) do
          case @pages do
            %{^uri => body} ->
              {:ok, MCP.read_resource_result(uri: uri, text: body, mime_type: "text/markdown")}

            _ ->
              {:error, :not_found}
          end
        end
      end

  ### Wiring a repository into the server

  A repository is given to the Suite through its `:resources` option. Because the
  Suite is the default `:server`, those options are passed straight to the
  transport plug in your router. Each entry is a bare module or a `{module, arg}`
  tuple, where `arg` is handed back to every callback as the trailing argument:

      # In your router
      forward "/mcp", GenMCP.Transport.StreamableHTTP,
        server_name: "My App",
        server_version: "1.0.0",
        resources: [MyApp.DocsResources]

  ## Templated resources

  A repository can serve a whole family of URIs with a single URI template
  instead of listing every concrete one. Implement the optional `c:template/1` to
  declare an [RFC 6570](https://www.rfc-editor.org/rfc/rfc6570) URI template, such
  as `file:///users/{id}`. The template changes how `c:read/3` is called: a
  `resources/read` whose URI matches the template is parsed into the template
  variables, and `c:read/3` receives those variables as a map rather than the raw
  URI string.

      @impl true
      def template(_arg) do
        %{uriTemplate: "file:///users/{id}", name: "User record"}
      end

      @impl true
      def read(%{"id" => id}, _channel, _arg) do
        user = MyApp.Accounts.fetch_user!(id)
        {:ok, MCP.read_resource_result(uri: "file:///users/#{id}", text: user.bio)}
      end

  By default the URI is matched against the template to extract the variables.
  Implement the optional `c:parse_uri/2` to take over that step, for example to
  decode or validate the URI yourself before `c:read/3` runs.

  ## Provider arguments

  The arguments the callbacks receive follow the conventions shared by all Suite
  providers, documented in `GenMCP.Suite`:

  * `channel` is the request-scoped `t:GenMCP.Mux.Channel.t/0`, carrying
    read-only client `meta` and auth assigns. `c:list/3` and `c:read/3` receive
    it as the second-to-last argument, so a repository can tailor what it exposes
    to the caller.
  * `arg` is the value configured alongside the module as `{module, arg}` (a bare
    module is treated as `{module, []}`). It is the trailing argument of every
    callback, letting one generic repository module be configured differently in
    different Suites.
  """
  import GenMCP.Utils.CallbackExt

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel

  @type resource_item :: %{
          required(:uri) => String.t(),
          required(:name) => String.t(),
          optional(:description) => nil | String.t(),
          optional(:mimeType) => nil | String.t(),
          optional(:size) => nil | integer()
        }
  @type template_descriptor :: %{
          required(:uriTemplate) => String.t(),
          required(:name) => String.t(),
          optional(:description) => nil | String.t(),
          optional(:mimeType) => nil | String.t(),
          optional(:title) => nil | String.t()
        }
  @type contents :: [
          MCP.TextResourceContents.t() | MCP.BlobResourceContents.t()
        ]
  @type arg :: term
  @type resource_repo :: module | {module, arg} | resource_repo_descriptor
  @type resource_repo_descriptor :: %{
          required(:mod) => module,
          required(:arg) => arg,
          required(:prefix) => String.t(),
          optional(:template) => String.t() | nil
        }

  @doc """
  Returns the URI prefix shared by this repository's resources.

  Every URI that `c:list/3` returns, and every URI the repository can read, must
  start with this prefix, because the Suite uses it to route a `resources/read`
  to the right repository: it picks the repository whose prefix the requested URI
  starts with. The prefixes of the configured repositories must therefore be
  distinct. `arg` is the value configured alongside the module.

      @impl true
      def prefix(_arg), do: "file:///docs/"
  """
  @callback prefix(arg) :: String.t()

  @doc """
  Declares the URI template this repository serves, for templated resources.

  Implement this optional callback when the repository answers a family of URIs
  described by one [RFC 6570](https://www.rfc-editor.org/rfc/rfc6570) template
  rather than a fixed list. Return a `t:template_descriptor/0` map with at least
  `:uriTemplate` (the template string) and `:name`. The template is advertised
  through `resources/templates/list`, and it changes how `c:read/3` is called:
  the matched URI is parsed into the template variables and those variables are
  handed to `c:read/3` as a map.

  The template string is parsed once when the repository is configured, so an
  invalid template raises at startup.

      @impl true
      def template(_arg) do
        %{
          uriTemplate: "file:///users/{id}",
          name: "User record",
          description: "A user's profile",
          mimeType: "application/json"
        }
      end
  """
  @callback template(arg) :: template_descriptor

  @doc """
  Lists the concrete resources this repository advertises for `resources/list`.

  Returns a `{resources, next_cursor}` tuple. Each element of `resources` is a
  `t:resource_item/0` map describing one resource, whose `:uri` must begin with
  the repository's `c:prefix/1`. `next_cursor` carries pagination: return `nil`
  on the last page, or an opaque token that the Suite hands back as the
  `pagination_token` of the next call to fetch the following page.

  The `pagination_token` is `nil` on the first call. `channel` is the
  request-scoped `t:GenMCP.Mux.Channel.t/0`, and `arg` is the configured value.

  A single-page repository ignores the token and returns `nil` as the cursor:

      @impl true
      def list(_cursor, _channel, _arg) do
        resources = [
          %{uri: "file:///docs/intro.md", name: "intro.md", mimeType: "text/markdown"}
        ]

        {resources, nil}
      end

  To paginate, return a token on every page but the last, and resume from it on
  the next call:

      @impl true
      def list(nil, _channel, _arg), do: {first_page(), "page-2"}
      def list("page-2", _channel, _arg), do: {second_page(), nil}
  """
  @callback list(pagination_token :: String.t() | nil, Channel.t(), arg) ::
              {[resource_item], next_cursor :: term | nil}

  @doc ~S"""
  Reads the resource a URI points to, for `resources/read`.

  The first argument is what the Suite resolved from the requested URI. For a
  repository without a template it is the URI string itself. For a templated
  repository (see `c:template/1`) it is the map of variables parsed out of the
  URI, so match the variables you declared.

  Return `{:ok, result}` where `result` is a
  `t:GenMCP.MCP.V2607.ReadResourceResult.t/0` built with
  `GenMCP.MCP.V2607.read_resource_result/1`. Return `{:error, :not_found}` when
  the URI names no resource the repository serves, which the Suite reports to the
  client as a resource-not-found error, or `{:error, message}` with a string
  `message` to report another problem.

  `channel` is the request-scoped `t:GenMCP.Mux.Channel.t/0`, and `arg` is the
  configured value.

  Reading a direct resource, matching on the URI string:

      @impl true
      def read("file:///docs/intro.md" = uri, _channel, _arg) do
        {:ok, MCP.read_resource_result(uri: uri, text: "# Introduction", mime_type: "text/markdown")}
      end

      def read(_uri, _channel, _arg), do: {:error, :not_found}

  Reading a templated resource, matching on the parsed variables:

      @impl true
      def read(%{"id" => id}, _channel, _arg) do
        case MyApp.Accounts.fetch_user(id) do
          {:ok, user} ->
            {:ok, MCP.read_resource_result(uri: "file:///users/#{id}", text: user.bio)}

          :error ->
            {:error, :not_found}
        end
      end
  """
  @callback read(uri_or_template_args, Channel.t(), arg) ::
              {:ok, MCP.ReadResourceResult.t()} | {:error, :not_found | String.t()}
            when uri_or_template_args: String.t() | %{String.t() => term}

  @doc ~S"""
  Parses a requested URI into the value passed to `c:read/3`, for templated
  resources.

  Implement this optional callback to take over URI parsing for a templated
  repository. When it is not implemented, the Suite matches the URI against the
  `c:template/1` template and passes the extracted variables to `c:read/3`. When
  it is implemented, the Suite calls it instead and passes its result straight to
  `c:read/3`, so you control exactly what `c:read/3` receives.

  Return `{:ok, value}` to proceed to `c:read/3` with `value` (a map of
  variables, a parsed term, or anything `c:read/3` expects), or `{:error,
  message}` with a string `message` to reject the URI before any read happens.
  `arg` is the configured value.

      @impl true
      def parse_uri("file:///users/" <> id, _arg) when id != "" do
        {:ok, %{"id" => id}}
      end

      def parse_uri(uri, _arg) do
        {:error, "unsupported user URI: #{uri}"}
      end
  """
  @callback parse_uri(uri :: String.t(), arg) ::
              {:ok, %{String.t() => term}} | {:ok, String.t()} | {:error, String.t()}

  @doc """
  Returns the cache hint for this repository's resource listing.

  This optional callback sets how `resources/list` results from the repository
  may be cached. Return `{scope, ttl_ms}`, where `scope` is `:public` or
  `:private` and `ttl_ms` is a non-negative lifetime in milliseconds. When the
  callback is not implemented, the Suite uses the no-cache default from
  `GenMCP.MCP.V2607.default_cache_control/0`.

      @impl true
      def cache_control(_arg), do: {:public, 60_000}
  """
  @callback cache_control(arg) :: {:public | :private, non_neg_integer()}

  @optional_callbacks template: 1, parse_uri: 2, cache_control: 1

  @doc """
  Normalizes a resource repository spec into a descriptor map.

  Accepts the three forms a repository may be configured as and returns a
  `t:resource_repo_descriptor/0`, the
  `%{mod: module, arg: term, prefix: binary, template: term}` shape the Suite
  works with internally:

  * a bare `module`, treated as `{module, []}`,
  * a `{module, arg}` tuple,
  * an already-built descriptor map, returned unchanged.

  For the bare module and tuple forms the module is loaded with
  `Code.ensure_loaded!/1` and its `c:prefix/1` is called to fill in the
  descriptor's prefix. If the module exports `c:template/1`, that callback is
  called too and its `:uriTemplate` is parsed once and stored in the descriptor.
  This raises if the module does not exist, if `c:prefix/1` returns a value that
  is not a string, or if `c:template/1` returns a map without a string
  `:uriTemplate` and `:name`.

  `GenMCP.Suite` calls this when it gathers the resource repositories to serve.
  """
  @spec expand(resource_repo) :: resource_repo_descriptor
  def expand(mod) when is_atom(mod) do
    expand({mod, []})
  end

  def expand({mod, arg}) when is_atom(mod) do
    Code.ensure_loaded!(mod)
    prefix = mod.prefix(arg)

    if !is_binary(prefix) do
      raise ArgumentError,
            "resource repo #{inspect(mod)} must return a string prefix, got: #{inspect(prefix)}"
    end

    template =
      if function_exported?(mod, :template, 1) do
        case mod.template(arg) do
          %{uriTemplate: uri_template, name: name} = tpl_desc
          when is_binary(uri_template) and is_binary(name) ->
            parsed = Texture.UriTemplate.parse!(uri_template)
            Map.put(tpl_desc, :uriTemplate, parsed)

          invalid ->
            raise ArgumentError,
                  "resource repo #{inspect(mod)} must return a map with :uriTemplate and :name keys, got: #{inspect(invalid)}"
        end
      end

    %{
      mod: mod,
      arg: arg,
      prefix: prefix,
      template: template
    }
  end

  def expand(%{prefix: prefix, mod: mod, arg: _, template: tpl} = descriptor)
      when is_binary(prefix) and is_atom(mod) and (is_binary(tpl) or is_nil(tpl)) do
    descriptor
  end

  @doc """
  Invokes the repository's `c:list/3` to list its resources.

  Given a descriptor from `expand/1`, calls the repository module's `c:list/3`
  with the pagination `cursor`, the request `channel`, and the descriptor's
  `arg`, and returns the `{resources, next_cursor}` tuple it produces.
  `GenMCP.Suite` uses this to answer a `resources/list`.
  """
  @spec list_resources(resource_repo_descriptor, String.t() | nil, Channel.t()) ::
          {[resource_item], next_cursor :: term | nil}
  def list_resources(repo, cursor, channel) do
    callback __MODULE__, repo.mod.list(cursor, channel, repo.arg) do
      {list, cursor} when is_list(list) -> {list, cursor}
    end
  end

  @doc """
  Invokes the repository's `c:read/3` to read the resource at `uri`.

  Given a descriptor from `expand/1`, resolves `uri` and calls the repository
  module's `c:read/3`. When the repository has a template, the `uri` is first
  parsed into its template variables, by the repository's `c:parse_uri/2` if it
  exports one, otherwise by matching against the template. The parsed variables,
  or the raw `uri` for a repository without a template, are passed to `c:read/3`
  along with the `channel` and the descriptor's `arg`.

  Returns `{:ok, result}` with the `t:GenMCP.MCP.V2607.ReadResourceResult.t/0`
  from the callback. A `{:error, :not_found}` from `c:read/3` becomes `{:error,
  {:resource_not_found, uri}}`; a string error from `c:read/3` or `c:parse_uri/2`
  is passed through. `GenMCP.Suite` uses this to answer a `resources/read`.
  """
  @spec read_resource(resource_repo_descriptor, String.t(), Channel.t()) ::
          {:ok, MCP.ReadResourceResult.t()}
          | {:error, {:resource_not_found, String.t()} | String.t()}
  def read_resource(%{template: template} = repo, uri, channel) when is_map(template) do
    with {:ok, uri_or_args} <- parse_uri(repo, uri),
         {:ok, result} <- do_read(repo, uri, uri_or_args, channel) do
      {:ok, result}
    else
      {:error, _} = err -> err
    end
  end

  def read_resource(repo, uri, channel) when is_binary(uri) do
    # No template, pass URI directly to read callback
    do_read(repo, uri, uri, channel)
  end

  defp do_read(repo, original_uri, uri_or_args, channel) do
    callback __MODULE__, repo.mod.read(uri_or_args, channel, repo.arg) do
      {:ok, %MCP.ReadResourceResult{}} = ok -> ok
      {:error, :not_found} -> {:error, {:resource_not_found, original_uri}}
      {:error, message} when is_binary(message) -> {:error, message}
    end
  end

  defp parse_uri(repo, uri) do
    if function_exported?(repo.mod, :parse_uri, 2) do
      callback __MODULE__, repo.mod.parse_uri(uri, repo.arg) do
        {:ok, v} -> {:ok, v}
        {:error, _} = err -> err
      end
    else
      match_uri_template(repo.template.uriTemplate, uri)
    end
  end

  defp match_uri_template(template, uri) do
    case Texture.UriTemplate.match(template, uri) do
      {:ok, params} ->
        {:ok, params}

      {:error, e} ->
        {:error, "expected uri matching template #{template.raw}, #{Exception.message(e)}"}
    end
  end

  @doc """
  Returns the cache hint for the repository's resource listing.

  Given a descriptor from `expand/1`, calls the optional `c:cache_control/1`
  callback when the repository module exports it, returning its `{scope, ttl_ms}`
  hint. When the callback is not implemented, returns the no-cache default from
  `GenMCP.MCP.V2607.default_cache_control/0`. `GenMCP.Suite` uses this to set the
  cache hints on a resource listing result.
  """
  def cache_control(repo) do
    if function_exported?(repo.mod, :cache_control, 1) do
      callback __MODULE__, repo.mod.cache_control(repo.arg) do
        {scope, ttl} when scope in [:public, :private] and is_integer(ttl) and ttl >= 0 ->
          {scope, ttl}
      end
    else
      MCP.default_cache_control()
    end
  end
end
