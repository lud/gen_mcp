defmodule GenMcp.JsonDerive do
  @moduledoc false

  defmacro auto do
    quote do
      if Code.ensure_loaded?(JSON.Encoder) do
        @derive JSON.Encoder
      end

      if Code.ensure_loaded?(Jason.Encoder) do
        @derive Jason.Encoder
      end
    end
  end
end
