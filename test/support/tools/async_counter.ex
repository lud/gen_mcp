defmodule GenMCP.Test.Tools.AsyncCounter do
  alias GenMCP.Entities.TextContent
  require Logger
  use JSV.Schema

  def name do
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
        upto: pos_integer(),
        sleep: pos_integer(default: 100)
      },
      required: [:upto]
    }
  end

  def call(arguments, channel, _state) do
    %{"upto" => upto} = arguments
    sleep = Map.get(arguments, "sleep", 100)
    {:async, Task.async(fn -> count_upto(upto, 0, sleep, channel) end), :some_state}
  end

  defp count_upto(upto, n, sleep, channel) when n < upto do
    Logger.debug("Counting #{n}/#{upto}")
    GenMCP.Mux.Channel.send_progress(channel, n, upto)
    Process.sleep(sleep)
    count_upto(upto, n + 1, sleep, channel)
  end

  defp count_upto(upto, upto, _sleep, _channel) do
    Logger.debug("Counting #{upto}/#{upto}")

    {:count_done, upto}
  end

  def continue({:count_done, upto}, _channel, :some_state) do
    output = %{
      content: [
        %TextContent{type: "text", text: "I counted up to #{upto}"}
      ]
    }

    {:reply, output}
  end
end
