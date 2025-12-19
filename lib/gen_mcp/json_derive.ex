defmodule GenMCP.JsonDerive do
  @moduledoc false

  def skip_nil_values(%_{} = struct, keep) do
    struct
    |> Map.from_struct()
    |> Map.filter(fn {k, v} -> v != nil or k in keep end)
  end

  defmacro auto(serialize_merge \\ nil, keep_nils \\ [])

  defmacro auto(serialize_merge, keep_nils) do
    quote do
      @before_compile unquote(__MODULE__)
      @keep_nils unquote(keep_nils)

      serialize_merge = unquote(serialize_merge)
      @doc false
      case map_size(serialize_merge) do
        0 ->
          def __normalize__(t) do
            unquote(__MODULE__).skip_nil_values(t, @keep_nils)
          end

        _ ->
          def __normalize__(t) do
            Map.merge(
              unquote(__MODULE__).skip_nil_values(t, @keep_nils),
              unquote(serialize_merge)
            )
          end
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      if Code.ensure_loaded?(JSON.Encoder) do
        defimpl JSON.Encoder do
          def encode(%mod{} = struct, encoder) do
            normal = mod.__normalize__(struct)
            encoder.(normal, encoder)
          end
        end
      end

      if Code.ensure_loaded?(Jason.Encoder) do
        defimpl Jason.Encoder do
          def encode(%mod{} = struct, opts) do
            normal = mod.__normalize__(struct)
            Jason.Encode.map(normal, opts)
          end
        end
      end

      defimpl JSV.Normalizer.Normalize do
        def normalize(%mod{} = t) do
          mod.__normalize__(t)
        end
      end
    end
  end
end
