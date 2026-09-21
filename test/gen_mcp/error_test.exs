defmodule GenMCP.ErrorTest do
  use ExUnit.Case

  alias GenMCP.Error

  doctest GenMCP.Error

  defp message(schema, data) do
    {:error, jsv_error} = JSV.validate(data, JSV.build!(schema))
    {200, %{code: -32_602, message: message}} = Error.cast_error({:invalid_params, jsv_error})
    message
  end

  describe "invalid parameters message" do
    test "names the missing property" do
      schema = %{
        "type" => "object",
        "required" => ["prompt", "kind"],
        "properties" => %{"prompt" => %{"type" => "string"}, "kind" => %{"type" => "string"}}
      }

      assert "Invalid Parameters: property 'kind' is required" =
               message(schema, %{"prompt" => "a prompt"})

      assert "Invalid Parameters: properties 'prompt' and 'kind' are required" =
               message(schema, %{})
    end

    test "points at the offending value" do
      schema = %{
        "type" => "object",
        "properties" => %{"kind" => %{"enum" => ["visibility", "perception"]}}
      }

      assert "Invalid Parameters: at #/kind: value must be one of the enum values:" <> _ =
               message(schema, %{"kind" => "sentiment"})
    end

    test "drops the outer findings that only restate the path to the inner one" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "services" => %{"type" => "array", "items" => %{"enum" => ["openai_chat"]}}
        }
      }

      message = message(schema, %{"services" => ["mistral_chat"]})

      assert message =~ "at #/services/0: value must be one of the enum values"
      refute message =~ "did not conform to the property schema"
      refute message =~ "does not validate the 'items' schema"
    end

    test "keeps actionable applicator findings" do
      schema = %{
        "type" => "object",
        "properties" => %{"known" => %{"type" => "integer"}},
        "additionalProperties" => false
      }

      message = message(schema, %{"known" => "not an integer", "extra" => true})

      assert message =~ "at #/known: value is not of type integer"
      assert message =~ "additional properties are not allowed but found property 'extra'"
    end

    test "restates a combinator that carries its branches under it" do
      schema = %{"anyOf" => [%{"type" => "integer"}, %{"type" => "boolean"}]}

      assert "Invalid Parameters: value did not conform to any of the given schemas" =
               message(schema, "a string")
    end

    test "counts the findings it leaves out" do
      schema = %{
        "type" => "object",
        "properties" => Map.new(~w(a b c d e), &{&1, %{"type" => "integer"}})
      }

      message = message(schema, Map.new(~w(a b c d e), &{&1, "not an integer"}))

      assert message =~ "(and 2 more)"
      assert message |> String.split("; ") |> length() == 3
    end

    test "falls back to the bare message when nothing can be summarized" do
      assert {200, %{code: -32_602, message: "Invalid Parameters"}} =
               Error.cast_error({:invalid_params, self()})
    end
  end
end
