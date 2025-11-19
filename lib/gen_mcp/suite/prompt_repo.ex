defmodule GenMCP.Suite.PromptRepo do
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

  @callback prefix(arg) :: String.t()

  @callback list(pagination_token :: String.t() | nil, Channel.t(), arg) ::
              {[prompt_item], next_cursor :: term | nil}

  @doc """
  Returns the prompt result with contents. Arguments are not automatically
  validated.
  """
  @callback get(name :: String.t(), arguments :: %{binary => term}, Channel.t(), arg) ::
              {:ok, MCP.GetPromptResult.t()} | {:error, :not_found | String.t()}

  @doc false
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
    case repo.mod.get(name, arguments, channel, repo.arg) do
      {:ok, %MCP.GetPromptResult{}} = ok -> ok
      {:error, :not_found} -> {:error, {:prompt_not_found, name}}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, {:invalid_params, _reason}} = err -> err
      other -> exit({:bad_return_value, other})
    end
  end

  def list_prompts(repo, cursor, channel) do
    case repo.mod.list(cursor, channel, repo.arg) do
      {list, cursor} when is_list(list) -> {list, cursor}
      other -> exit({:bad_return_value, other})
    end
  end
end
