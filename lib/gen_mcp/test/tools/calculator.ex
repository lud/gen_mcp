defmodule GenMcp.Test.Tools.Calculator do
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
        operator: string_enum_to_atom(~w(+ - * /)a),
        operands: array_of(number(), description: "Two numbers to compute with the operator.")
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
        %{"operator" => :+, "operands" => items} -> Enum.reduce(items, &(&1 + &2))
        %{"operator" => :-, "operands" => items} -> Enum.reduce(items, &(&1 - &2))
        %{"operator" => :/, "operands" => items} -> Enum.reduce(items, &(&1 / &2))
        %{"operator" => :*, "operands" => items} -> Enum.reduce(items, &(&1 * &2))
      end

    output = %{structuredContent: %{result: result}, content: []}
    {:reply, output}
  end
end
