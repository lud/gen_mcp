defmodule GenMCP.Suite.SelfExtension do
  @moduledoc false

  @behaviour GenMCP.Suite.Extension

  def new(opts) do
    %{mod: __MODULE__, arg: opts}
  end

  def tools(_, opts) do
    Keyword.get(opts, :tools, [])
  end

  def resources(_, opts) do
    Keyword.get(opts, :resources, [])
  end

  def prompts(_, opts) do
    Keyword.get(opts, :prompts, [])
  end
end
