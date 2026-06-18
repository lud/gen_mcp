defmodule GenMCP.Tools.ListModuleFunctions do
  @generated_functions [
    {:__info__, 1},
    {:__struct__, 0},
    {:__struct__, 1},
    {:behaviour_info, 1},
    {:module_info, 0},
    {:module_info, 1}
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
    IO.puts("## #{inspect(module)}\n")

    module
    |> exported_functions()
    |> Enum.each(fn {name, arity} ->
      IO.puts("- #{name}/#{arity}")
    end)

    IO.puts("")
  end

  defp exported_functions(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        docs
        |> Enum.filter(&function_doc?/1)
        |> Enum.map(fn {{:function, name, arity}, _, _, _, _} -> {name, arity} end)
        |> Enum.sort_by(fn {name, arity} -> {Atom.to_string(name), arity} end)

      {:error, _reason} ->
        module.__info__(:functions)
        |> Enum.reject(&generated_function?/1)
        |> Enum.reject(fn {name, _arity} -> internal_function_name?(name) end)
        |> Enum.sort_by(fn {name, arity} -> {Atom.to_string(name), arity} end)
    end
  end

  defp function_doc?({{:function, name, arity}, _, _, _, _}) do
    not generated_function?({name, arity}) and not internal_function_name?(name)
  end

  defp function_doc?(_other) do
    false
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
