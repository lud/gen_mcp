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
    %{"upto" => upto} = arguments
    {:stream, Task.async(fn -> count_upto(upto, 0) end)}
  end

  defp count_upto(upto, n) when n < upto do
    Logger.debug("Counting #{n}/#{upto}")
    Process.sleep(1000)
    count_upto(upto, n + 1)
  end

  defp count_upto(upto, upto) do
    Logger.debug("Counting #{upto}/#{upto}")

    output = %{
      content: [
        %TextContent{type: "text", text: "I counted up to #{upto}"}
      ]
    }

    {:reply, output}
  end
end
