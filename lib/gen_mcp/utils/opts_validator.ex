defmodule GenMCP.Utils.OptsValidator do
  @moduledoc false

  # Options in the library are carried around between different modules where
  # each one requires a subset of options.
  #
  # We want to use NimbleOptions because it is already used by JSV which is a
  # dependency, and NimbleOptions is nice. But it does not support ignoring
  # unknown keys, so we will just add that layer on top of it.

  # Returns {self_opts, other_opts} where self_opts contains all options from
  # keys that were known to the schema.
  def validate_take_opts(opts, %NimbleOptions{schema: schema} = nimble) do
    self_keys = Keyword.keys(schema)
    {self_opts, other_opts} = Keyword.split(opts, self_keys)

    case NimbleOptions.validate(self_opts, nimble) do
      {:ok, self_opts} -> {:ok, self_opts, other_opts}
      {:error, _} = err -> err
    end
  end

  def validate_take_opts!(opts, nimble) do
    case validate_take_opts(opts, nimble) do
      {:ok, self_opts, other_opts} -> {self_opts, other_opts}
      {:error, reason} -> raise reason
    end
  end
end
