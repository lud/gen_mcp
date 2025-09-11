defmodule GenMcp.Test.Tools.MemoryAdd do
  alias JSV.Codec
  alias GenMcp.Entities.TextContent
  use JSV.Schema

  def name() do
    "MemoryAdd"
  end

  def title do
    "Add memory item"
  end

  def description do
    "Registers a new piece of text in memory."
  end

  def input_schema do
    props(item: string())
  end

  def output_schema do
    props([])
  end

  def annotations do
    %{idempotentHint: false, openWorldHint: false, title: title()}
  end

  def call(arguments, channel, _state) do
    raise "not implemented"
  end
end
