defmodule GenMCP.CallbackReturnError do
  @moduledoc """
  Exception raised when a behaviour callback returns a value the library cannot use.

  The library invokes the callbacks you implement (for example the ones in
  `GenMCP.Suite.Tool` or `GenMCP.Suite.ResourceRepo`) and matches their result
  against the return shapes each callback documents. When an implementation
  returns something none of those shapes match, the library raises this
  exception instead of carrying the bad value further. It is a programming error
  in the callback, not a runtime condition a client can trigger, so it surfaces
  as a raised exception during development.

  The struct carries three fields that identify the offending callback:

    * `:mfa` - the `{module, function, args}` of the callback that was invoked,
      where `args` is the actual argument list (its length gives the arity shown
      in the message).
    * `:behaviour` - the behaviour module the callback is implementing, for
      example `GenMCP.Suite.Tool`.
    * `:return_value` - the value the callback returned that could not be
      accepted.
  """
  defexception [:mfa, :return_value, :behaviour]

  def message(t) do
    %{mfa: {m, f, args}, return_value: return_value, behaviour: behaviour} = t
    a = length(args)

    "invalid return value from #{inspect(m)}.#{f}/#{a} implementing" <>
      " behaviour #{inspect(behaviour)}, got: #{inspect(return_value)}"
  end
end
