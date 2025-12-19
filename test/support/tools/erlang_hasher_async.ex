defmodule GenMCP.Test.Tools.ErlangHasherAsync do
  use GenMCP.Suite.Tool,
    name: "ErlangHasherAsync",
    description:
      "Returns the hash for a number in a defined range, according to Erlang documentation",
    title: "Erlang Hasher",
    input_schema: %{
      type: "object",
      properties: %{
        subject: %{
          type: "string",
          description: "The subject string to hash"
        },
        range: %{
          type: "integer",
          description: "The range for the hash function (1 to 4294967296 inclusive)",
          minimum: 1,
          maximum: 4_294_967_296
        }
      },
      required: ["subject", "range"]
    }

  alias GenMCP.MCP
  alias GenMCP.Mux.Channel

  @impl true
  def call(req, channel, _arg) do
    args = req.params.arguments
    {:async, {:hash, Task.async(fn -> run(args, channel) end)}, channel}
  end

  defp run(args, channel) do
    Enum.each(1..100, fn i ->
      {:ok, _} = Channel.send_progress(channel, i, 100)
    end)

    subject = Map.fetch!(args, "subject")
    range = Map.fetch!(args, "range")
    _hash_value = :erlang.phash2(subject, range)
  end

  @impl true
  def continue({:hash, {:ok, hash_value}}, channel, _arg) do
    result_text = Integer.to_string(hash_value)
    result = MCP.call_tool_result(text: result_text)
    {:result, result, channel}
  end
end
