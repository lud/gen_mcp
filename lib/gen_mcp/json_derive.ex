defmodule GenMCP.JsonDerive do
  @moduledoc false
  alias JSV.Helpers.MapExt

  defmacro auto do
    quote do
      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      if Code.ensure_loaded?(JSON.Encoder) do
        defimpl JSON.Encoder do
          def encode(v, encoder) do
            encoder.(MapExt.from_struct_no_nils(v))
          end
        end
      end

      if Code.ensure_loaded?(Jason.Encoder) do
        defimpl Jason.Encoder do
          def encode(v, opts) do
            Jason.Encode.map(MapExt.from_struct_no_nils(v), opts)
          end
        end
      end
    end
  end
end
