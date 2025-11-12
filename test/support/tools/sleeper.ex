defmodule GenMCP.Test.Tools.Sleeper do
  alias GenMCP.Entities.TextContent
  require Logger
  use JSV.Schema

  def name do
    "Sleeper"
  end

  def title do
    "A Sleeping Tool"
  end

  def description do
    "A task that will sleep for a given amount of seconds"
  end

  def input_schema do
    %{
      type: :object,
      properties: %{
        seconds: pos_integer()
      },
      required: [:seconds]
    }
  end

  def call(arguments, _channel, _state) do
    %{"seconds" => seconds} = arguments

    {:async,
     Task.async(fn ->
       Process.sleep(seconds * 1000)
       {:slept, seconds}
     end), :some_state}
  end

  def next({:slept, seconds}, _channel, :some_state) do
    output = %{
      content: [
        %TextContent{type: "text", text: "I slept for #{seconds} seconds"}
      ]
    }

    {:reply, output}
  end
end
