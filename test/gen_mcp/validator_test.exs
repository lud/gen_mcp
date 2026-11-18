defmodule GenMCP.ValidatorTest do
  use ExUnit.Case, async: true

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Validator

  doctest GenMCP.Validator

  defp request_meta do
    %{
      "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities" => %{},
      "io.modelcontextprotocol/clientInfo" => %{"name" => "my-client", "version" => "1.0.0"}
    }
  end

  defp request(method, params) do
    %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}
  end

  describe "skills extension methods" do
    test "skills/list validates to a ListSkillsRequest" do
      assert {:ok, :request,
              %MCP.ListSkillsRequest{
                id: 1,
                params: %MCP.PaginatedRequestParams{
                  _meta: %MCP.RequestMetaObject{
                    "io.modelcontextprotocol/protocolVersion": "2026-07-28"
                  },
                  cursor: nil
                }
              }} =
               Validator.validate_request(request("skills/list", %{"_meta" => request_meta()}))
    end

    test "skills/list carries the pagination cursor" do
      params = %{"_meta" => request_meta(), "cursor" => "page-2"}

      assert {:ok, :request,
              %MCP.ListSkillsRequest{params: %MCP.PaginatedRequestParams{cursor: "page-2"}}} =
               Validator.validate_request(request("skills/list", params))
    end

    test "skills/get validates to a GetSkillRequest" do
      params = %{"_meta" => request_meta(), "uri" => "skill://acme/billing/refunds/SKILL.md"}

      assert {:ok, :request,
              %MCP.GetSkillRequest{
                id: 1,
                params: %MCP.GetSkillRequestParams{
                  _meta: %MCP.RequestMetaObject{
                    "io.modelcontextprotocol/protocolVersion": "2026-07-28"
                  },
                  uri: "skill://acme/billing/refunds/SKILL.md"
                }
              }} = Validator.validate_request(request("skills/get", params))
    end

    test "skills/get without uri is an invalid body" do
      assert {:error, {:invalid_body, %JSV.ValidationError{}}} =
               Validator.validate_request(request("skills/get", %{"_meta" => request_meta()}))
    end

    test "skills/list without _meta is an invalid body" do
      assert {:error, {:invalid_body, %JSV.ValidationError{}}} =
               Validator.validate_request(request("skills/list", %{}))
    end

    test "skills/get without _meta is an invalid body" do
      params = %{"uri" => "skill://acme/billing/refunds/SKILL.md"}

      assert {:error, {:invalid_body, %JSV.ValidationError{}}} =
               Validator.validate_request(request("skills/get", params))
    end

    test "resources/directory/read stays an unknown method" do
      params = %{"_meta" => request_meta(), "uri" => "skill://acme/billing/"}

      assert {:error, {:unknown_method, "resources/directory/read"}} =
               Validator.validate_request(request("resources/directory/read", params))
    end
  end
end
