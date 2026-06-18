defmodule GenMCP.Tools.ListModuleFunctions do
  @generated_functions [
    {:__info__, 1},
    {:__struct__, 0},
    {:__struct__, 1},
    {:behaviour_info, 1},
    {:module_info, 0},
    {:module_info, 1},
    {:schema, 0},
    {:json_schema, 0}
  ]

  def run do
    app = Mix.Project.config()[:app]

    app
    |> app_modules()
    |> Enum.filter(&source_in_lib?/1)
    |> Enum.reject(&protocol_impl?/1)
    |> Enum.sort_by(&Atom.to_string/1)
    |> Enum.each(&print_module/1)
  end

  defp app_modules(app) do
    case Application.spec(app, :modules) do
      nil ->
        raise "could not determine modules for #{inspect(app)}"

      modules ->
        modules
    end
  end

  defp source_in_lib?(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        module
        |> :erlang.get_module_info(:compile)
        |> Keyword.fetch!(:source)
        |> List.to_string()
        |> Path.relative_to_cwd()
        |> String.starts_with?("lib/")

      {:error, _reason} ->
        false
    end
  end

  defp print_module(module) do
    callbacks = callbacks(module)
    callables = exported_callables(module)

    if callbacks != [] or callables != [] do
      IO.puts("## #{inspect(module)}\n")

      Enum.each(callbacks, fn {name, arity} ->
        IO.puts("- @callback #{name}/#{arity}")
      end)

      Enum.each(callables, fn
        {:function, name, arity} ->
          IO.puts("- def #{name}/#{arity}")

        {:macro, name, arity} ->
          IO.puts("- defmacro #{name}/#{arity}")
      end)

      IO.puts("")
    end
  end

  defp callbacks(module) do
    module
    |> apply(:behaviour_info, [:callbacks])
    |> Enum.reject(fn {name, _arity} -> internal_function_name?(name) end)
    |> Enum.sort_by(fn {name, arity} -> {Atom.to_string(name), arity} end)
  rescue
    UndefinedFunctionError ->
      []
  end

  defp exported_callables(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        docs
        |> Enum.filter(&callable_doc?/1)
        |> Enum.map(fn {{kind, name, arity}, _, _, _, _} -> {kind, name, arity} end)
        |> Enum.sort_by(&callable_sort_key/1)

      {:error, _reason} ->
        exported_callables_fallback(module)
    end
  end

  defp exported_callables_fallback(module) do
    functions =
      module.__info__(:functions)
      |> Enum.reject(&generated_function?/1)
      |> Enum.reject(fn {name, _arity} -> internal_function_name?(name) end)
      |> Enum.map(fn {name, arity} -> {:function, name, arity} end)

    macros =
      module.__info__(:macros)
      |> Enum.reject(fn {name, _arity} -> internal_function_name?(name) end)
      |> Enum.map(fn {name, arity} -> {:macro, name, arity} end)

    Enum.sort_by(functions ++ macros, &callable_sort_key/1)
  end

  defp callable_doc?({{kind, name, arity}, _, _, _, _}) when kind in [:function, :macro] do
    not generated_function?({name, arity}) and not internal_function_name?(name)
  end

  defp callable_doc?(_other) do
    false
  end

  defp callable_sort_key({kind, name, arity}) do
    {Atom.to_string(name), arity, callable_kind_order(kind)}
  end

  defp callable_kind_order(:function) do
    0
  end

  defp callable_kind_order(:macro) do
    1
  end

  defp generated_function?(function) do
    function in @generated_functions
  end

  defp internal_function_name?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("__")
  end

  defp protocol_impl?(mod) do
    case Code.ensure_loaded(mod) do
      {:module, ^mod} -> function_exported?(mod, :__impl__, 1)
      _ -> false
    end
  end
end

GenMCP.Tools.ListModuleFunctions.run()
