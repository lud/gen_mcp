defmodule GenMCP.Suite.SelfExtension do
  @moduledoc false

  @behaviour GenMCP.Suite.Extension

  def new(tools, resources, prompts) do
    %{mod: __MODULE__, arg: %{tools: tools, resources: resources, prompts: prompts}}
  end

  def tools(_, arg) do
    arg.tools
  end

  def resources(_, arg) do
    arg.resources
  end

  def prompts(_, arg) do
    arg.prompts
  end
end
