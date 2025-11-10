defmodule GenMcp.McpJestTest do
  import GenMcp.Test.Client
  use ExUnit.Case, async: true

  defp url do
    URI.merge(GenMcp.TestWeb.Endpoint.url(), "/mcp/real")
  end

  @tag :skip
  test "execute Calculator" do
    assert {_, 0} =
             System.cmd(
               "npx",
               ~w(mcp-jest --transport streamable-http --url #{url()} --tools Calculator),
               into: IO.stream()
             )
  end
end
