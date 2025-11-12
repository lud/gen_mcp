defmodule GenMCP.Suite.ResourceRepo do
  @moduledoc """
  Behaviour for implementing resource repositories in GenMCP.

  A resource repository provides resources (direct or template-based) to the MCP server.
  Resources are identified by URIs and can be listed and read through this interface.

  ## Direct Resources vs Templates

  - **Direct resources**: Have fixed URIs that are returned by `list/2`.
  - **Template-based resources**: Use URI templates with variables that are expanded at runtime.

  A repository can support both direct resources and templates, or just direct resources.

  ## Required Callbacks

  - `prefix/1` - Returns the URI prefix for routing (mandatory)
  - `list/2` - Lists available resources with pagination support
  - `read/2` - Reads resource contents given a URI or template arguments

  ## Optional Callbacks

  - `template/1` - Returns a URI template if templates are supported
  - `parse_uri/2` - Parses a URI to extract template arguments

  ## Example

      defmodule MyApp.FileRepo do
        @behaviour GenMCP.Suite.ResourceRepo

        @impl true
        def prefix(_arg), do: "file:///"

        @impl true
        def template(_arg), do: nil  # Direct resources only

        @impl true
        def list(nil, _arg) do
          {[
            %{uri: "file:///readme.txt", name: "README"},
            %{uri: "file:///config.json", name: "Config"}
          ], nil}
        end

        @impl true
        def read("file:///readme.txt", _arg) do
          {:ok, [%GenMCP.Entities.TextResourceContents{
            uri: "file:///readme.txt",
            text: "# Welcome"
          }]}
        end
        def read(_, _arg), do: {:error, :not_found}
      end
  """

  alias GenMCP.Entities

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
          Entities.TextResourceContents.t() | Entities.BlobResourceContents.t()
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
  Returns the URI prefix for this repository.

  This is used for routing resource requests to the appropriate repository.
  The prefix must be a non-empty string.

  ## Example

      def prefix(_arg), do: "file:///"
  """
  @callback prefix(arg) :: String.t()

  @doc """
  Returns a map describing the URI template if this repository supports template-based resources.

  The map must contain at least `:uriTemplate` (string) and `:name` (string) keys.
  Optional keys are `:description`, `:mimeType`, and `:title`.

  This callback is optional. If not implemented, the repository only supports direct resources.

  ## Example

      def template(_arg) do
        %{
          uriTemplate: "file:///{path}",
          name: "File",
          description: "A file resource"
        }
      end
  """
  @callback template(arg) :: template_descriptor

  @doc """
  Lists resources available in this repository.

  Returns a tuple with:
  - A list of resource maps (can be empty)
  - An optional pagination token (nil if there's only one page). That cursor is
    serialized so it can be any term.

  The `pagination_token` parameter is `nil` for the first page.

  ## Example

      def list(nil, _arg) do
        {[
          %{uri: "file:///readme.txt", name: "README", description: "Project readme"},
          %{uri: "file:///config.json", name: "Config"}
        ], nil}
      end
  """
  @callback list(pagination_token :: String.t() | nil, arg) ::
              {[resource_item], next_cursor :: term | nil}

  @doc """
  Reads resource contents.

  For direct resources, receives the full URI as a string.
  For template-based resources, receives a map of template arguments.

  Returns:
  - `{:ok, %ReadResourceResult{}}` - Result with list of content blocks (TextResourceContents or BlobResourceContents)
  - `{:error, :not_found}` - Resource not found (will be transformed to proper RPC error)
  - `{:error, message}` - Custom error message as string

  ## Examples

      # Direct resource
      def read(arg, "file:///readme.txt") do
        {:ok, %GenMCP.Entities.ReadResourceResult{
          contents: [
            %GenMCP.Entities.TextResourceContents{
              uri: "file:///readme.txt",
              text: "# Welcome"
            }
          ]
        }}
      end

      # Template-based resource
      def read(arg, %{"path" => path}) do
        case File.read(path) do
          {:ok, content} ->
            {:ok, %GenMCP.Entities.ReadResourceResult{
              contents: [
                %GenMCP.Entities.TextResourceContents{
                  uri: "file:///\#{path}",
                  text: content
                }
              ]
            }}
          {:error, :enoent} ->
            {:error, :not_found}
        end
      end
  """
  @callback read(uri_or_template_args, arg) ::
              {:ok, Entities.ReadResourceResult.t()} | {:error, :not_found | String.t()}
            when uri_or_template_args: String.t() | %{String.t() => term}

  @doc """
  Parses a URI to extract template arguments or validate URI format.

  This callback will be called before calling `c:read/2` if the `c:template/1`
  callback is implemented and returns a string. In that case it must return
  either a map or a string, wrapped in a result tuple. The `c:read/2` callback
  will be called with that value instead of the original URI.

  Returns:
  - `{:ok, %{String.t() => term}}` - Arguments extracted from the URI template.
  - `{:ok, String.t()}` - The original or a different URI.
  - `{:error, String.t()}` - An error with a message.

  ## Example

      def parse_uri("file:///" <> path, _arg) do
        {:ok, %{"path" => path}}
      end
      def parse_uri(_uri, _arg), do: {:error, :invalid_uri}
  """
  @callback parse_uri(uri :: String.t(), arg) ::
              {:ok, %{String.t() => term}} | {:ok, String.t()} | {:error, String.t()}

  @optional_callbacks template: 1, parse_uri: 2

  @doc """
  Transforms `module` and `{module, arg}` into a resource repository descriptor.

  Validates that the repository returns a valid prefix and template.

  ## Examples

      iex> GenMCP.Suite.ResourceRepo.expand(MyRepo)
      %{mod: MyRepo, arg: [], prefix: "file:///", template: nil}

      iex> GenMCP.Suite.ResourceRepo.expand({MyRepo, :custom_arg})
      %{mod: MyRepo, arg: :custom_arg, prefix: "file:///", template: "file:///{path}"}
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
      else
        nil
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

  def list_resources(repo, cursor) do
    case repo.mod.list(cursor, repo.arg) do
      {list, cursor} when is_list(list) -> {list, cursor}
      other -> exit({:bad_return_value, other})
    end
  end

  @doc """
  Reads a resource from the repository.

  This function delegates to the repository's `read/2` callback and normalizes
  the result. The callback should return `{:ok, %ReadResourceResult{}}`.

  - `{:ok, %ReadResourceResult{}}` is passed through as-is
  - `{:error, :not_found}` is transformed to `{:error, {:resource_not_found, uri}}`
  - `{:error, message}` when message is a string is passed through

  ## Parameters

  - `repo` - Repository descriptor map
  - `uri` - The URI of the resource to read

  ## Returns

  - `{:ok, ReadResourceResult.t()}` - Successfully read resource
  - `{:error, {:resource_not_found, uri}}` - Resource not found
  - `{:error, String.t()}` - Custom error message from repository
  """
  @spec read_resource(resource_repo_descriptor, String.t()) ::
          {:ok, Entities.ReadResourceResult.t()}
          | {:error, {:resource_not_found, String.t()} | String.t()}
  def read_resource(%{template: template} = repo, uri) when is_map(template) do
    with {:ok, uri_or_args} <- parse_uri(repo, uri),
         {:ok, result} <- do_read(repo, uri_or_args) do
      {:ok, result}
    else
      {:error, :not_found} -> {:error, {:resource_not_found, uri}}
      {:error, message} when is_binary(message) -> {:error, message}
      other -> exit({:bad_return_value, other})
    end
  end

  def read_resource(repo, uri) when is_binary(uri) do
    # No template, pass URI directly to read callback
    case do_read(repo, uri) do
      {:ok, %Entities.ReadResourceResult{}} = ok -> ok
      {:error, :not_found} -> {:error, {:resource_not_found, uri}}
      {:error, message} when is_binary(message) -> {:error, message}
      other -> exit({:bad_return_value, other})
    end
  end

  defp do_read(repo, uri_or_args) do
    repo.mod.read(uri_or_args, repo.arg)
  end

  defp parse_uri(repo, uri) do
    if function_exported?(repo.mod, :parse_uri, 2) do
      repo.mod.parse_uri(repo.arg, uri)
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
end
