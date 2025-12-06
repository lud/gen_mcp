defmodule GenMCP.Utils.CallbackExt do
  @moduledoc false
  alias GenMCP.CallbackReturnError

  # TODO We must check the AST to forbid any function call in the mod,fun and
  # args, only literals or variables

  defmacro callback(behaviour, {:dbg, _, [call]}, [{:do, clauses}]) do
    :ok = check_behaviour(behaviour, __CALLER__)
    {mod, fun, args} = Macro.decompose_call(call)

    quote do
      # credo:disable-for-next-line Credo.Check.Warning.Dbg
      case dbg(unquote(call)) do
        unquote(clauses ++ catchall_clause(behaviour, mod, fun, args))
      end
    end
  end

  defmacro callback(behaviour, call, [{:do, clauses}]) do
    :ok = check_behaviour(behaviour, __CALLER__)
    {mod, fun, args} = Macro.decompose_call(call)

    quote do
      case unquote(call) do
        unquote(clauses ++ catchall_clause(behaviour, mod, fun, args))
      end
    end
  end

  defp catchall_clause(behaviour, mod, fun, args) do
    quote do
      other ->
        raise CallbackReturnError,
          mfa: {unquote(mod), unquote(fun), unquote(args)},
          behaviour: unquote(behaviour),
          return_value: other
    end
  end

  defp check_behaviour(mod, %{module: mod}) when is_atom(mod) do
    :ok
  end

  defp check_behaviour(mod, _env) when is_atom(mod) do
    if {:module, mod} == Code.ensure_loaded(mod) and
         function_exported?(mod, :behaviour_info, 1) and
         match?([_ | _], mod.behaviour_info(:callbacks)) do
      :ok
    else
      raise ArgumentError,
            "#{inspect(mod)} is not a behaviour. `require #{inspect(mod)}` may solve the problem"
    end
  end

  defp check_behaviour({:__aliases__, _, _} = ast, env) do
    check_behaviour(Macro.expand_literals(ast, env), env)
  end

  defp check_behaviour({:__MODULE__, _, _} = ast, env) do
    check_behaviour(Macro.expand_literals(ast, env), env)
  end

  # adds a tag inside a result tuple,
  def wrap_result({:ok, v}, tag) do
    {:ok, {tag, v}}
  end

  def wrap_result({:error, v}, tag) do
    {:error, {tag, v}}
  end
end
