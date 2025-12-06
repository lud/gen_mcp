defmodule GenMCP.CallbackReturnError do
  @moduledoc """
  Error raised when a behaviour implementation callback does not respect return
  signatures.
  """

  defexception [:mfa, :return_value, :behaviour]

  def message(t) do
    %{mfa: {m, f, args}, return_value: return_value, behaviour: behaviour} = t
    a = length(args)

    "invalid return value from #{inspect(m)}.#{f}/#{a} implementing" <>
      " behaviour #{inspect(behaviour)}, got: #{inspect(return_value)}"
  end
end
