defmodule GenMCP.Utils.CallbackExt do
  @moduledoc false
  alias GenMCP.CallbackReturnError

  # TODO We must check the AST to forbid any function call in the mod,fun and
  # args, only literals or variables

  defmacro callback(behaviour, {:dbg, _, [call]}, [{:do, clauses}]) do
    {mod, fun, args} = Macro.decompose_call(call)

    quote do
      unquote(require_behaviour(behaviour, __CALLER__))

      # credo:disable-for-next-line Credo.Check.Warning.Dbg
      case dbg(unquote(call)) do
        unquote(clauses ++ catchall_clause(behaviour, mod, fun, args))
      end
    end
  end

  defmacro callback(behaviour, call, [{:do, clauses}]) do
    {mod, fun, args} = Macro.decompose_call(call)

    quote do
      unquote(require_behaviour(behaviour, __CALLER__))

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

  defp require_behaviour(behaviour, %{module: caller_mod} = env) do
    behaviour = Macro.expand_literals(behaviour, env)

    if behaviour == caller_mod do
      :ok
    else
      quote bind_quoted: [behaviour: behaviour] do
        if {:module, behaviour} == Code.ensure_loaded(behaviour) and
             function_exported?(behaviour, :behaviour_info, 1) and
             match?([_ | _], behaviour.behaviour_info(:callbacks)) do
          :ok
        else
          raise ArgumentError,
                "#{inspect(behaviour)} is not a behaviour"
        end
      end
    end
  end

  # adds a tag inside a result tuple,
  def wrap_result({:ok, v}, tag) do
    {:ok, {tag, v}}
  end

  def wrap_result({:error, v}, tag) do
    {:error, {tag, v}}
  end
end
