defmodule GenMCP.JsonDerive do
  @moduledoc false
  alias JSV.Helpers.MapExt

  defmacro auto(serialize_merge \\ nil)

  defmacro auto(nil = _serialize_merge) do
    quote do
      @before_compile unquote(__MODULE__)

      def __normalize__(t) do
        MapExt.from_struct_no_nils(t)
      end
    end
  end

  defmacro auto(serialize_merge) do
    quote do
      @before_compile unquote(__MODULE__)

      def __normalize__(t) do
        Map.merge(MapExt.from_struct_no_nils(t), unquote(serialize_merge))
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
    end
  end
end
