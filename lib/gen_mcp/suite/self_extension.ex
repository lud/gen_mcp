defmodule GenMCP.Suite.SelfExtension do
  @moduledoc false

  @behaviour GenMCP.Suite.Extension

  def new(tools, resources, prompts, skills) do
    %{
      mod: __MODULE__,
      arg: %{tools: tools, resources: resources, prompts: prompts, skills: skills}
    }
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

  def skills(_, arg) do
    arg.skills
  end
end
