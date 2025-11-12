defmodule GenMCP.JsonDerive do
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

IO.warn("""
@todo use a macro to define JSON normalizers like this, instead of deriving

JsonDerive.spec(some_field: spec, some_other: spec)

Spec is:

* true - keep the field as-is
* :not_nil - keep if not nil
* {:sub, [sub_field: spec, sub_other: spec]} - apply to sub fields
* [...] - apply in order. [:not_nil, {:sub, _}]

""")
