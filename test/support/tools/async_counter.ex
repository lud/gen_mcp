defmodule GenMcp.Test.Tools.AsyncCounter do
  alias GenMcp.Entities.TextContent
  alias JSV.Codec
  require Logger
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

  def call(arguments, channel, _opts) do
    %{"upto" => upto} = arguments
    {:stream, Task.async(fn -> count_upto(upto, 0, channel) end)}
  end

  defp count_upto(upto, n, channel) when n < upto do
    Logger.debug("Counting #{n}/#{upto}")
    GenMcp.Channel.notify()
    Process.sleep(1000)
    count_upto(upto, n + 1, channel)
  end

  defp count_upto(upto, upto, channel) do
    Logger.debug("Counting #{upto}/#{upto}")

    output = %{
      content: [
        %TextContent{type: "text", text: "I counted up to #{upto}"}
      ]
    }

    {:reply, output}
  end
end
