defmodule GenMCP.Test.Tools.ErlangHasher do
  use GenMCP.Suite.Tool,
    name: "ErlangHasher",
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

  @impl true
  def call(req, channel, _arg) do
    args = req.params.arguments

    subject = Map.fetch!(args, "subject")
    range = Map.fetch!(args, "range")

    hash_value = :erlang.phash2(subject, range)
    result_text = Integer.to_string(hash_value)

    result = MCP.call_tool_result(text: result_text)

    {:result, result, channel}
  end
end
