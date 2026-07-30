defmodule GenMCP.Suite.PromptRepo do
  @moduledoc ~S"""
  Behaviour for a repository of prompts served by a `GenMCP.Suite`.

  Prompts are reusable message templates a client can fetch and replay to an
  LLM. A prompt repository groups related prompts under a common name prefix,
  answers `prompts/list` to advertise them, and answers `prompts/get` to build a
  concrete prompt from the arguments the client supplies.

  The prefix is what ties the two requests together. The Suite routes a
  `prompts/get` to the repository whose prefix the requested name starts with,
  so every name a repository lists must begin with its prefix, and the prefixes
  of the configured repositories must not collide.

  A repository is a thin adapter: keep the prompt text and argument shapes in a
  plain module of your own, and let the callbacks route to it. The three
  required callbacks answer one question each, which prefix the prompts live
  under (`c:prefix/1`), which prompts exist (`c:list/3`), and how to build one
  (`c:get/4`).

  ## Minimal implementation

  A repository that serves a single `greeting` prompt under the `support/`
  prefix. `c:list/3` advertises it, and `c:get/4` fills in the customer name the
  client passed, building the result with the `GenMCP.MCP.V2607` helpers:

      defmodule MyApp.SupportPrompts do
        @behaviour GenMCP.Suite.PromptRepo

        alias GenMCP.MCP.V2607, as: MCP

        @impl true
        def prefix(_arg), do: "support/"

        @impl true
        def list(_cursor, _channel, _arg) do
          prompts = [
            %{
              name: "support/greeting",
              description: "Greet a customer by name",
              arguments: [%{name: "name", description: "Customer name", required: true}]
            }
          ]

          {prompts, nil}
        end

        @impl true
        def get("support/greeting", %{"name" => name}, _channel, _arg) do
          result =
            MCP.get_prompt_result(
              description: "Greet a customer by name",
              text: "Greet #{name} warmly and ask how you can help."
            )

          {:ok, result}
        end

        def get(_name, _arguments, _channel, _arg), do: {:error, :not_found}
      end

  ### Wiring a repository into the server

  A repository is given to the Suite through its `:prompts` option. Because the
  Suite is the default `:server`, those options are passed straight to the
  transport plug in your router. Each entry is a bare module or a `{module, arg}`
  tuple, where `arg` is handed back to every callback as the trailing argument:

      # In your router
      forward "/mcp", GenMCP.Transport.StreamableHTTP,
        server_name: "My App",
        server_version: "1.0.0",
        prompts: [MyApp.SupportPrompts]

  ## Provider arguments

  The arguments the callbacks receive follow the conventions shared by all Suite
  providers, documented in `GenMCP.Suite`:

  * `channel` is the request-scoped `t:GenMCP.Mux.Channel.t/0`, carrying
    read-only client `meta` and auth assigns. `c:list/3` and `c:get/4` receive
    it as the second-to-last argument, so a repository can tailor what it
    exposes to the caller.
  * `arg` is the value configured alongside the module as `{module, arg}` (a bare
    module is treated as `{module, []}`). It is the trailing argument of every
    callback, letting one generic repository module be configured differently in
    different Suites.
  """
  import GenMCP.Utils.CallbackExt

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel

  @type prompt_repo :: module | {module, arg} | prompt_repo_descriptor
  @type prompt_repo_descriptor :: %{
          required(:mod) => module,
          required(:arg) => arg,
          required(:prefix) => String.t()
        }

  @type prompt_item :: %{
          required(:name) => String.t(),
          optional(:title) => String.t(),
          optional(:description) => String.t(),
          optional(:arguments) => [prompt_argument]
        }

  @type prompt_argument :: %{
          required(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:required) => boolean
        }

  @type arg :: term

  @doc """
  Returns the name prefix shared by this repository's prompts.

  Every name that `c:list/3` returns must start with this prefix, because the
  Suite uses it to route a `prompts/get` to the right repository: it picks the
  repository whose prefix the requested name starts with. The prefixes of the
  configured repositories must therefore be distinct. `arg` is the value
  configured alongside the module.

      @impl true
      def prefix(_arg), do: "support/"
  """
  @callback prefix(arg) :: String.t()

  @doc """
  Lists the prompts this repository advertises for `prompts/list`.

  Returns a `{prompts, next_cursor}` tuple. Each element of `prompts` is a
  `t:prompt_item/0` map describing one prompt, whose `:name` must begin with the
  repository's `c:prefix/1`. `next_cursor` carries pagination: return `nil` on
  the last page, or an opaque token that the Suite hands back as the
  `pagination_token` of the next call to fetch the following page.

  The `pagination_token` is `nil` on the first call. `channel` is the
  request-scoped `t:GenMCP.Mux.Channel.t/0`, and `arg` is the configured value.

  A single-page repository ignores the token and returns `nil` as the cursor:

      @impl true
      def list(_cursor, _channel, _arg) do
        prompts = [
          %{name: "support/greeting", description: "Greet a customer by name"}
        ]

        {prompts, nil}
      end

  To paginate, return a token on every page but the last, and resume from it on
  the next call:

      @impl true
      def list(nil, _channel, _arg), do: {first_page(), "page-2"}
      def list("page-2", _channel, _arg), do: {second_page(), nil}
  """
  @callback list(pagination_token :: String.t() | nil, Channel.t(), arg) ::
              {[prompt_item], next_cursor :: term | nil}

  @doc ~S"""
  Builds the prompt identified by `name` for `prompts/get`.

  `name` is the full name the client requested, including the repository prefix.
  `arguments` is the map of argument values the client supplied, keyed by string.
  The arguments are passed through as is, they are not validated against the
  prompt's declared `arguments`, so match and check the keys you need.

  Return `{:ok, result}` where `result` is a
  `t:GenMCP.MCP.V2607.GetPromptResult.t/0` built with
  `GenMCP.MCP.V2607.get_prompt_result/1`. Return `{:error, :not_found}` when the
  name does not match a prompt this repository serves, or `{:error, message}`
  with a string `message` to report an invalid request to the client.

  `channel` is the request-scoped `t:GenMCP.Mux.Channel.t/0`, and `arg` is the
  configured value.

  Match the name and required arguments in the head, and build the messages with
  the `GenMCP.MCP.V2607` helpers:

      @impl true
      def get("support/greeting", %{"name" => name}, _channel, _arg) do
        result =
          GenMCP.MCP.V2607.get_prompt_result(
            description: "Greet a customer by name",
            text: "Greet #{name} warmly and ask how you can help."
          )

        {:ok, result}
      end

      def get(_name, _arguments, _channel, _arg), do: {:error, :not_found}
  """
  @callback get(name :: String.t(), arguments :: %{binary => term}, Channel.t(), arg) ::
              {:ok, MCP.GetPromptResult.t()} | {:error, :not_found | String.t()}

  @doc """
  Returns the cache hint for this repository's prompt listing.

  This optional callback sets how `prompts/list` results from the repository may
  be cached. Return `{scope, ttl_ms}`, where `scope` is `:public` or `:private`
  and `ttl_ms` is a non-negative lifetime in milliseconds. When the callback is
  not implemented, the Suite uses the no-cache default from
  `GenMCP.MCP.V2607.default_cache_control/0`.

      @impl true
      def cache_control(_arg), do: {:public, 60_000}
  """
  @callback cache_control(arg) :: {:public | :private, non_neg_integer()}

  @optional_callbacks cache_control: 1

  @doc """
  Normalizes a prompt repository spec into a descriptor map.

  Accepts the three forms a repository may be configured as and returns a
  `t:prompt_repo_descriptor/0`, the `%{mod: module, arg: term, prefix: binary}`
  shape the Suite works with internally:

  * a bare `module`, treated as `{module, []}`,
  * a `{module, arg}` tuple,
  * an already-built descriptor map, returned unchanged.

  For the bare module and tuple forms the module is loaded with
  `Code.ensure_loaded!/1` and its `c:prefix/1` is called to fill in the
  descriptor's prefix. This raises if the module does not exist, or if
  `c:prefix/1` returns a value that is not a string.

  `GenMCP.Suite` calls this when it gathers the prompt repositories to serve.
  """
  @spec expand(prompt_repo) :: prompt_repo_descriptor
  def expand(mod) when is_atom(mod) do
    expand({mod, []})
  end

  def expand({mod, arg}) when is_atom(mod) do
    Code.ensure_loaded!(mod)
    prefix = mod.prefix(arg)

    if !is_binary(prefix) do
      raise ArgumentError,
            "prompt repo #{inspect(mod)} must return a string prefix, got: #{inspect(prefix)}"
    end

    %{
      mod: mod,
      arg: arg,
      prefix: prefix
    }
  end

  def expand(%{prefix: prefix, mod: mod, arg: _} = descriptor)
      when is_binary(prefix) and is_atom(mod) do
    descriptor
  end

  @doc """
  Invokes the repository's `c:get/4` to build the prompt named `name`.

  Given a descriptor from `expand/1`, calls the repository module's `c:get/4`
  with `name`, the client `arguments`, the request `channel`, and the
  descriptor's `arg`, then normalizes the result. A `{:error, :not_found}` from
  the callback becomes `{:error, {:prompt_not_found, name}}`; a string error and
  an invalid-params error are passed through. `GenMCP.Suite` uses this to answer
  a `prompts/get`.
  """
  def get_prompt(repo, name, arguments, channel) do
    callback __MODULE__, repo.mod.get(name, arguments, channel, repo.arg) do
      {:ok, %MCP.GetPromptResult{}} = ok -> ok
      {:error, :not_found} -> {:error, {:prompt_not_found, name}}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, {:invalid_params, _reason}} = err -> err
    end
  end

  @doc """
  Invokes the repository's `c:list/3` to list its prompts.

  Given a descriptor from `expand/1`, calls the repository module's `c:list/3`
  with the pagination `cursor`, the request `channel`, and the descriptor's
  `arg`, and returns the `{prompts, next_cursor}` tuple it produces.
  `GenMCP.Suite` uses this to answer a `prompts/list`.
  """
  def list_prompts(repo, cursor, channel) do
    callback __MODULE__, repo.mod.list(cursor, channel, repo.arg) do
      {list, cursor} when is_list(list) -> {list, cursor}
    end
  end

  @doc """
  Returns the cache hint for the repository's prompt listing.

  Given a descriptor from `expand/1`, calls the optional `c:cache_control/1`
  callback when the repository module exports it, returning its `{scope, ttl_ms}`
  hint. When the callback is not implemented, returns the no-cache default from
  `GenMCP.MCP.V2607.default_cache_control/0`. `GenMCP.Suite` uses this to set the
  cache hints on a `prompts/list` result.
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
