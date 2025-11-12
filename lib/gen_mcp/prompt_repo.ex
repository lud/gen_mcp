defmodule GenMcp.PromptRepo do
  alias GenMcp.Mcp.Entities

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

  @callback list(pagination_token :: String.t() | nil, arg) ::
              {[prompt_item], next_cursor :: term | nil}

  @callback get(name :: String.t(), arguments :: %{binary => term}, arg) ::
              {:ok, Entities.GetPromptResult.t()} | {:error, :not_found | String.t()}

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

  IO.warn("""
  @todo offer a helper that validates arguments given a map of arguments and a
  list of ::prompt_argument

  """)

  IO.warn("""
  @todo document that the arguments are not validated by default
  @todo accept an invalid_params response
  """)

  def get_prompt(repo, name, arguments) do
    case repo.mod.get(name, arguments, repo.arg) do
      {:ok, %Entities.GetPromptResult{}} = ok -> ok
      {:error, :not_found} -> {:error, {:prompt_not_found, name}}
      {:error, message} when is_binary(message) -> {:error, message}
      other -> exit({:bad_return_value, other})
    end
  end

  def list_prompts(repo, cursor) do
    case repo.mod.list(cursor, repo.arg) do
      {list, cursor} when is_list(list) -> {list, cursor}
      other -> exit({:bad_return_value, other})
    end
  end
end
