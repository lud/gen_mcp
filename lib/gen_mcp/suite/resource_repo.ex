defmodule GenMCP.Suite.ResourceRepo do
  @moduledoc """
  Defines the behaviour for resource repositories and handles their execution.

  Repositories expose data to the MCP server either via fixed URIs or URI templates.
  This module validates repository definitions and orchestrates URI parsing and content retrieval.

  ## Example

      defmodule MyResourceRepo do
        @behaviour GenMCP.Suite.ResourceRepo

        @impl true
        def prefix(_arg), do: "file:///"

        @impl true
        def list(_cursor, _channel, _arg) do
          resources = [
            %{uri: "file:///readme.txt", name: "README"}
          ]
          {resources, nil}
        end

        @impl true
        def read("file:///readme.txt", _channel, _arg) do
          result = GenMCP.MCP.read_resource_result(
            uri: "file:///readme.txt",
            text: "Hello world"
          )
          {:ok, result}
        end

        def read(_uri, _channel, _arg), do: {:error, :not_found}
      end
  """

  alias GenMCP.MCP
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
  Returns the URI prefix for routing requests.

  ## Examples

      def prefix(_arg), do: "file:///"
  """
  @callback prefix(arg) :: String.t()

  @doc """
  Defines the URI template for dynamic resources.

  Must return a map with `:uriTemplate` and `:name`.

  ## Examples

      def template(_arg) do
        %{uriTemplate: "file:///{path}", name: "File"}
      end
  """
  @callback template(arg) :: template_descriptor

  @doc """
  Returns a page of available resources.

  Receives the pagination token (nil for first page) and the channel context.
  Must return a tuple containing the list of resources and the next cursor (or nil).

  ## Examples

      def list(nil, _channel, _arg) do
        resources = [%{uri: "file:///readme.txt", name: "README"}]
        {resources, nil}
      end
  """
  @callback list(pagination_token :: String.t() | nil, Channel.t(), arg) ::
              {[resource_item], next_cursor :: term | nil}

  @doc """
  Returns the content of a resource.

  Receives the URI string (for direct resources) or a map of template arguments (for templates).
  Must return `{:ok, result}` or an error tuple.

  ## Examples

  Direct resource:

      def read("file:///readme.txt", _channel, _arg) do
        result =
          GenMCP.MCP.read_resource_result(
            uri: "file:///readme.txt",
            text: "Hello world"
          )
        {:ok, result}
      end

  Template resource:

      def read(%{"path" => ["config", "app.json"]}, _channel, _arg) do
        result =
          GenMCP.MCP.read_resource_result(
            uri: "file:///config/app.json",
            text: "{}"
          )
        {:ok, result}
      end
  """
  @callback read(uri_or_template_args, Channel.t(), arg) ::
              {:ok, MCP.ReadResourceResult.t()} | {:error, :not_found | String.t()}
            when uri_or_template_args: String.t() | %{String.t() => term}

  @doc """
  Customizes URI parsing for template resources.

  Called before `c:read/3` to extract arguments from the URI.
  If not implemented, `Texture.UriTemplate.match/2` is used.

  ## Examples

      def parse_uri("file:///" <> path, _arg) do
        {:ok, %{"path" => path}}
      end
  """
  @callback parse_uri(uri :: String.t(), arg) ::
              {:ok, %{String.t() => term}} | {:ok, String.t()} | {:error, String.t()}

  @optional_callbacks template: 1, parse_uri: 2

  @doc false
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
  Lists resources from the repository.

  Delegates to the `c:list/3` callback and returns the resources and next pagination cursor.

  ## Example

      {resources, next_cursor} = GenMCP.Suite.ResourceRepo.list_resources(repo, nil, channel)
  """
  @spec list_resources(resource_repo_descriptor, String.t() | nil, Channel.t()) ::
          {[resource_item], next_cursor :: term | nil}
  def list_resources(repo, cursor, channel) do
    case repo.mod.list(cursor, channel, repo.arg) do
      {list, cursor} when is_list(list) -> {list, cursor}
      other -> exit({:bad_return_value, other})
    end
  end

  @doc """
  Retrieves content for a specific resource URI.

  For template-based repositories, parses the URI (via `c:parse_uri/2` or
  default matching) before calling `c:read/3`.

  Normalizes `{:error, :not_found}` into `{:error, {:resource_not_found, uri}}`
  automatically.

  ## Example

      {:ok, result} = GenMCP.Suite.ResourceRepo.read_resource(repo, "file:///readme.txt", channel)
  """
  @spec read_resource(resource_repo_descriptor, String.t(), Channel.t()) ::
          {:ok, MCP.ReadResourceResult.t()}
          | {:error, {:resource_not_found, String.t()} | String.t()}
  def read_resource(%{template: template} = repo, uri, channel) when is_map(template) do
    with {:ok, uri_or_args} <- parse_uri(repo, uri),
         {:ok, result} <- do_read(repo, uri_or_args, channel) do
      {:ok, result}
    else
      {:error, :not_found} -> {:error, {:resource_not_found, uri}}
      {:error, message} when is_binary(message) -> {:error, message}
      other -> exit({:bad_return_value, other})
    end
  end

  def read_resource(repo, uri, channel) when is_binary(uri) do
    # No template, pass URI directly to read callback
    case do_read(repo, uri, channel) do
      {:ok, %MCP.ReadResourceResult{}} = ok -> ok
      {:error, :not_found} -> {:error, {:resource_not_found, uri}}
      {:error, message} when is_binary(message) -> {:error, message}
      other -> exit({:bad_return_value, other})
    end
  end

  defp do_read(repo, uri_or_args, channel) do
    repo.mod.read(uri_or_args, channel, repo.arg)
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
