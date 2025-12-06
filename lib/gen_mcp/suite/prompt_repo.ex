defmodule GenMCP.Suite.PromptRepo do
  @moduledoc """
  Defines the behaviour for implementing prompt repositories.

  Prompts are reusable templates for LLM interactions. A repository groups
  related prompts under a common namespace (prefix).

  ## Example

      defmodule MyPromptRepo do
        @behaviour GenMCP.Suite.PromptRepo

        @impl true
        def prefix(_arg), do: "my_prompts"

        @impl true
        def list(_cursor, _channel, _arg) do
          prompts = [
            %{name: "greeting", description: "Say hello", arguments: []}
          ]
          {prompts, nil}
        end

        @impl true
        def get("greeting", _args, _channel, _arg) do
          result = %GenMCP.MCP.GetPromptResult{
            description: "Say hello",
            messages: [
              %GenMCP.MCP.PromptMessage{
                role: "user",
                content: %GenMCP.MCP.TextContent{type: "text", text: "Hello!"}
              }
            ]
          }
          {:ok, result}
        end

        def get(_name, _args, _channel, _arg), do: {:error, :not_found}
      end
  """
  import GenMCP.Utils.CallbackExt

  alias GenMCP.MCP
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
  Returns the prefix for prompts in this repository.

  The prefix is used to namespace prompts to avoid collisions when multiple
  repositories are used.

  ## Examples

      def prefix(_arg), do: "my_app"
  """
  @callback prefix(arg) :: String.t()

  @doc """
  Lists available prompts in the repository.

  Supports pagination via a cursor. Returns a tuple `{prompts, next_cursor}`.
  If `next_cursor` is `nil`, there are no more pages.

  ## Examples

      def list(nil, _channel, _arg) do
        {[%{name: "prompt1"}], "page2"}
      end

      def list("page2", _channel, _arg) do
        {[%{name: "prompt2"}], nil}
      end
  """
  @callback list(pagination_token :: String.t() | nil, Channel.t(), arg) ::
              {[prompt_item], next_cursor :: term | nil}

  @doc """
  Retrieves a specific prompt by name with arguments.

  Arguments are passed as a map and are not automatically validated against the
  prompt's definition.

  ## Examples

      def get("greeting", %{"name" => name}, _channel, _arg) do
        result =
          GenMCP.MCP.get_prompt_result(
            description: "Say hello",
            assistant: "Hello \#{name}, how can I help you?",
            text: "Hello, ..."
          )

        {:ok, result}
      end

      def get("unknown", _args, _channel, _arg) do
        {:error, :not_found}
      end
  """
  @callback get(name :: String.t(), arguments :: %{binary => term}, Channel.t(), arg) ::
              {:ok, MCP.GetPromptResult.t()} | {:error, :not_found | String.t()}

  @doc """
  Returns a descriptor for the given `module` or `{module, arg}` tuple.
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

  def get_prompt(repo, name, arguments, channel) do
    callback __MODULE__, repo.mod.get(name, arguments, channel, repo.arg) do
      {:ok, %MCP.GetPromptResult{}} = ok -> ok
      {:error, :not_found} -> {:error, {:prompt_not_found, name}}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, {:invalid_params, _reason}} = err -> err
    end
  end

  def list_prompts(repo, cursor, channel) do
    callback __MODULE__, repo.mod.list(cursor, channel, repo.arg) do
      {list, cursor} when is_list(list) -> {list, cursor}
    end
  end
end
