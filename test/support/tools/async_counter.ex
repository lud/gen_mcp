defmodule GenMcp.Test.Tools.AsyncCounter do
  alias JSV.Codec
  alias GenMcp.Entities.TextContent
  use JSV.Schema

  def name() do
    "AsyncCounter"
  end

  def title do
    "Asynchronous Counter"
  end

  def description do
    "A counter that will stream numbers to the clients"
  end

  def input_schema do
    %{
      type: :object,
      properties: %{
        upto: pos_integer()
      },
      required: [:upto]
    }
  end

  def call(arguments, _opts) do
    arguments |> dbg()

    {:reply, "output"}
  end
end
