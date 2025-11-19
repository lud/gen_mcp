# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMCP.Suite.ToolTest do
  alias GenMCP.MCP
  alias GenMCP.Suite.Tool
  import GenMCP.Test.Helpers
  use ExUnit.Case, async: true

  defmacro env_mod do
    %{function: {fun, _}, line: line} = __CALLER__

    fun
    |> Atom.to_string()
    |> String.replace(" ", "_")
    |> Kernel.<>(Integer.to_string(line))
    |> Macro.camelize()
    |> List.wrap()
    |> Module.concat()
  end

  describe "with using macro" do
    test "defines nothing" do
      defmodule UseNothing do
        use GenMCP.Suite.Tool, behaviour: false
      end

      assert nil == UseNothing.info(:name, nil)
      assert nil == UseNothing.info(:description, nil)
      assert nil == UseNothing.info(:annotations, nil)
      assert nil == UseNothing.info(:title, nil)

      # Name should be defined
      assert_raise ArgumentError, ~r{must define a valid name}, fn ->
        Tool.describe(UseNothing)
      end
    end

    test "can pass info to 'use'" do
      defmodule UseName do
        use GenMCP.Suite.Tool, behaviour: false, name: "foo"
      end

      # name is defined
      assert "foo" == UseName.info(:name, nil)

      # description is nil
      assert nil == UseName.info(:description, nil)
      assert nil == UseName.info(:annotations, nil)
      assert nil == UseName.info(:title, nil)

      # input_schema should be defined
      assert_raise UndefinedFunctionError, ~r{input_schema/1 is undefined or private}, fn ->
        Tool.describe(UseName)
      end
    end

    test "can override use" do
      # Compilation should put the generated heads after the user heads

      defmodule UseNameCustomDescr do
        use GenMCP.Suite.Tool, behaviour: false, name: "foo"

        def info(:name, _) do
          "bar"
        end

        def info(:description, _) do
          "descr"
        end
      end

      # name is overriden
      assert "bar" == UseNameCustomDescr.info(:name, nil)

      # description is defined
      assert "descr" == UseNameCustomDescr.info(:description, nil)

      # still not defined
      assert nil == UseNameCustomDescr.info(:annotations, nil)
      assert nil == UseNameCustomDescr.info(:title, nil)

      # input_schema should be defined
      assert_raise UndefinedFunctionError, ~r{input_schema/1 is undefined or private}, fn ->
        Tool.describe(UseNameCustomDescr)
      end
    end

    test "supports annotations map in macro" do
      # Checks that maps get macro-escaped

      defmodule UseAnnots do
        use GenMCP.Suite.Tool,
          behaviour: false,
          name: "foo",
          annotations: %{
            destructiveHint: true,
            idempotentHint: true,
            openWorldHint: true,
            readOnlyHint: true,
            title: "hello"
          }
      end

      assert %{
               destructiveHint: true,
               idempotentHint: true,
               openWorldHint: true,
               readOnlyHint: true,
               title: "hello"
             } == UseAnnots.info(:annotations, nil)

      # input_schema should be defined
      assert_raise UndefinedFunctionError, ~r{input_schema/1 is undefined or private}, fn ->
        Tool.describe(UseAnnots)
      end
    end

    test "call will receive validated arguments automatically" do
      defmodule UseInputSchema do
        use GenMCP.Suite.Tool,
          behaviour: false,
          name: "some_name",
          description: "some descr",
          input_schema: %{
            type: :object,
            properties: %{
              foo: %{type: :integer}
            }
          }

        # Use does not define validate request, it is automatically implemented
        # by "use"

        def call(req, chan, _) do
          {:result, {:called_with, req.params.arguments}, chan}
        end
      end

      tool = Tool.expand(UseInputSchema)

      # Valid request is ok

      valid_req = %MCP.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "some_name",
          arguments: %{"foo" => 123}
        }
      }

      assert {:result, {:called_with, %{"foo" => 123}}, _} =
               Tool.call(tool, valid_req, build_channel())

      # invalid request will not hit the call callback if rejected

      bad_req = %MCP.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "some_name",
          arguments: %{"foo" => "not_an_int"}
        }
      }

      assert {:error, {:invalid_params, %JSV.ValidationError{}}, _} =
               Tool.call(tool, bad_req, build_channel())

      assert %{type: :object, properties: %{foo: %{type: :integer}}} =
               UseInputSchema.input_schema(nil)

      assert %GenMCP.MCP.Tool{
               _meta: nil,
               annotations: nil,
               description: "some descr",
               inputSchema: %{
                 "properties" => %{"foo" => %{"type" => "integer"}},
                 "type" => "object"
               },
               name: "some_name",
               outputSchema: nil,
               title: nil
             } == Tool.describe(UseInputSchema)
    end

    test "user defined validation will take precedence" do
      defmodule UseCustomValidator do
        use GenMCP.Suite.Tool,
          behaviour: false,
          name: "some_name",
          input_schema: %{
            type: :object,
            properties: %{
              foo: %{type: :integer}
            }
          }

        # ALLOW ANYTHING
        def validate_request(req, _) do
          {:ok, req}
        end

        def call(req, chan, _) do
          {:result, {:called_with, req.params.arguments}, chan}
        end
      end

      tool = Tool.expand(UseCustomValidator)

      # invalid request is allowed by user validator

      bad_req = %MCP.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "some_name",
          arguments: %{"foo" => "not_an_int"}
        }
      }

      assert {:result, {:called_with, %{"foo" => "not_an_int"}}, _} =
               Tool.call(tool, bad_req, build_channel())
    end

    test "output schema with use" do
      defmodule UseOutputSchema do
        use GenMCP.Suite.Tool,
          behaviour: false,
          name: "some_name",
          input_schema: %{type: :null},
          output_schema: %{
            type: :object,
            properties: %{
              result: %{type: :string}
            }
          }
      end

      # output_schema/1 callback returns the schema as-is
      assert %{
               type: :object,
               properties: %{result: %{type: :string}}
             } == UseOutputSchema.output_schema(nil)

      # Tool.describe should normalize the schema
      assert %GenMCP.MCP.Tool{
               _meta: nil,
               annotations: nil,
               description: nil,
               inputSchema: %{"type" => "null"},
               name: "some_name",
               outputSchema: %{
                 "properties" => %{"result" => %{"type" => "string"}},
                 "type" => "object"
               },
               title: nil
             } == Tool.describe(UseOutputSchema)
    end
  end

  describe "without using macro" do
    test "defines nothing" do
      defmodule RawNothing do
        def info(_, _) do
          nil
        end
      end

      # Name should be defined
      assert_raise ArgumentError, ~r{must define a valid name}, fn ->
        Tool.describe(RawNothing)
      end
    end

    test "can pass info to 'use'" do
      defmodule RawName do
        def info(:name, _) do
          "foo"
        end

        def info(_, _) do
          nil
        end
      end

      # name is defined
      assert "foo" == RawName.info(:name, nil)

      # description is nil
      assert nil == RawName.info(:description, nil)
      assert nil == RawName.info(:annotations, nil)
      assert nil == RawName.info(:title, nil)

      # input_schema should be defined
      assert_raise UndefinedFunctionError, ~r{input_schema/1 is undefined or private}, fn ->
        Tool.describe(RawName)
      end
    end

    test "can override use" do
      # Compilation should put the generated heads after the user heads

      defmodule RawNameCustomDescr do
        def info(:name, _) do
          "bar"
        end

        def info(:description, _) do
          "descr"
        end

        def info(_, _) do
          nil
        end
      end

      # name is overriden
      assert "bar" == RawNameCustomDescr.info(:name, nil)

      # description is defined
      assert "descr" == RawNameCustomDescr.info(:description, nil)

      # still not defined
      assert nil == RawNameCustomDescr.info(:annotations, nil)
      assert nil == RawNameCustomDescr.info(:title, nil)

      # input_schema should be defined
      assert_raise UndefinedFunctionError, ~r{input_schema/1 is undefined or private}, fn ->
        Tool.describe(RawNameCustomDescr)
      end
    end

    test "supports annotations map in macro" do
      # Checks that maps get macro-escaped

      defmodule RawAnnots do
        def info(:name, _) do
          inspect(__MODULE__)
        end

        def info(:annotations, _) do
          %{
            destructiveHint: true,
            idempotentHint: true,
            openWorldHint: true,
            readOnlyHint: true,
            title: "hello"
          }
        end

        def info(_, _) do
          nil
        end
      end

      # input_schema should be defined
      assert_raise UndefinedFunctionError, ~r{input_schema/1 is undefined or private}, fn ->
        Tool.describe(RawAnnots)
      end
    end

    test "validate_request is called if defined" do
      defmodule RawInputSchema do
        def info(:name, _) do
          "some_name"
        end

        def info(_, _) do
          nil
        end

        def input_schema(_) do
          # validate_request and input schema are user defined and not used at
          # the same time.
          #
          # input schema is called when describing a tool (MCP list tools
          # method), validate_request is called on tool call, if defined.
          #
          # So it's possible to have an input_schema that is not used in
          # validate_request if the users decide to validate the request by
          # other means (like using Ecto embedded schemas for instance.)
          %{type: :nothing_related}
        end

        def validate_request(req, _) do
          case(req.params.arguments) do
            %{"foo" => n} when is_integer(n) -> {:ok, req}
            _ -> {:error, :bad_int}
          end
        end

        def call(req, chan, _) do
          {:result, {:called_with, req.params.arguments}, chan}
        end
      end

      tool = Tool.expand(RawInputSchema)

      # Valid request is ok

      valid_req = %MCP.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "some_name",
          arguments: %{"foo" => 123}
        }
      }

      assert {:result, {:called_with, %{"foo" => 123}}, _} =
               Tool.call(tool, valid_req, build_channel())

      # invalid request will not hit the call callback if rejected

      bad_req = %MCP.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "some_name",
          arguments: %{"foo" => "not_an_int"}
        }
      }

      assert {:error, {:invalid_params, :bad_int}, _} =
               Tool.call(tool, bad_req, build_channel())

      assert %{type: :nothing_related} =
               RawInputSchema.input_schema(nil)

      assert %GenMCP.MCP.Tool{
               _meta: nil,
               annotations: nil,
               description: nil,
               inputSchema: %{
                 "type" => "nothing_related"
               },
               name: "some_name",
               outputSchema: nil,
               title: nil
             } == Tool.describe(RawInputSchema)
    end

    test "call will not be validated without defining validate_request" do
      defmodule RawCustomValidator do
        def info(:name, _) do
          "some_name"
        end

        def info(_, _) do
          nil
        end

        def call(req, chan, _) do
          {:result, {:called_with, req.params.arguments}, chan}
        end
      end

      tool = Tool.expand(RawCustomValidator)

      # invalid request is allowed by user validator

      bad_req = %MCP.CallToolRequest{
        id: 1001,
        method: "tools/call",
        params: %MCP.CallToolRequestParams{
          name: "some_name",
          arguments: %{"foo" => "not_an_int"}
        }
      }

      assert {:result, {:called_with, %{"foo" => "not_an_int"}}, _} =
               Tool.call(tool, bad_req, build_channel())
    end

    test "output schema with raw module" do
      defmodule RawOutputSchema do
        def info(:name, _) do
          "some_name"
        end

        def info(_, _) do
          nil
        end

        def input_schema(_) do
          nil
        end

        def output_schema(_) do
          %{
            type: :object,
            properties: %{
              result: %{type: :string}
            }
          }
        end
      end

      # output_schema/1 callback should return the schema as-is
      assert %{
               type: :object,
               properties: %{result: %{type: :string}}
             } == RawOutputSchema.output_schema(nil)

      # Tool.describe should normalize the schema
      assert %GenMCP.MCP.Tool{
               _meta: nil,
               annotations: nil,
               description: nil,
               inputSchema: nil,
               name: "some_name",
               outputSchema: %{
                 "properties" => %{"result" => %{"type" => "string"}},
                 "type" => "object"
               },
               title: nil
             } == Tool.describe(RawOutputSchema)
    end
  end

  describe "encoding errors" do
    test "invalid params errors" do
      # Custom message

      assert {400, %{code: -32602, message: "some string"}} =
               check_error({:invalid_params, "some string"})

      # JSV Validation

      jsv_root = JSV.build!(%{type: :integer})
      {:error, jsv_err} = JSV.validate("not_an_int", jsv_root)

      assert {400,
              %{
                code: -32602,
                data: %{
                  valid: false,
                  details: [
                    %{
                      errors: [%{message: "value is not of type integer"}],
                      valid: false
                    }
                  ]
                },
                message: "Invalid Parameters"
              }} = check_error({:invalid_params, jsv_err})

      # Any term
      #
      # Testing with a pid, we do not return the data
      assert {400, %{code: -32602, message: "Invalid Parameters"}} ==
               check_error({:invalid_params, self()})
    end
  end
end
