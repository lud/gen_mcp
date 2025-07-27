defmodule GenMcp.Test.Tools.Calculator do
  alias JSV.Codec
  alias GenMcp.Entities.TextContent
  use JSV.Schema

  @name "calculator"

  def name() do
    "Calculator"
  end

  def title do
    "Basic Calculator"
  end

  def description do
    "A test calculator that can only do basic operations for demo purposes."
  end

  def input_schema do
    %{
      type: :object,
      properties: %{
        operator: string_enum_to_atom(~w(+ - * / phash)a),
        operands:
          array_of(number(),
            description: "Two numbers to compute with the operator.",
            minItems: 2,
            maxItems: 2
          )
      },
      required: [:operator, :operands]
    }
  end

  def output_schema do
    props(result: number())
  end

  def annotations do
    %{idempotentHint: true, openWorldHint: false, title: title()}
  end

  def call(arguments, _opts) do
    result =
      case arguments do
        %{"operator" => :+, "operands" => [a, b]} -> a + b
        %{"operator" => :-, "operands" => [a, b]} -> a - b
        %{"operator" => :/, "operands" => [a, b]} -> a / b
        %{"operator" => :*, "operands" => [a, b]} -> a * b
        %{"operator" => :phash, "operands" => [a, b]} -> :erlang.phash2(a, b)
      end

    structured = %{result: result}

    output = %{
      structuredContent: structured,
      content: [
        %TextContent{type: "text", text: Codec.encode!(structured)}
      ]
    }

    {:reply, output}
  end
end
