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
    channel |> dbg()
    {:async, Task.async(fn -> count_upto(upto, 0, channel) end), :some_state}
  end

  defp count_upto(upto, n, channel) when n < upto do
    Logger.debug("Counting #{n}/#{upto}")
    GenMcp.Channel.send_progress(channel, n, upto)
    Process.sleep(100)
    count_upto(upto, n + 1, channel)
  end

  defp count_upto(upto, upto, channel) do
    Logger.debug("Counting #{upto}/#{upto}")

    {:count_done, upto}
  end

  def next({:count_done, upto}, :some_state, _channel, _opts) do
    output = %{
      content: [
        %TextContent{type: "text", text: "I counted up to #{upto}"}
      ]
    }

    {:reply, output}
  end
end
