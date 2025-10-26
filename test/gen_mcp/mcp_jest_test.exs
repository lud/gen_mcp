defmodule GenMcp.McpJestTest do
  import GenMcp.Test.Client
  use ExUnit.Case, async: true

  defp basic_path do
    "/mcp/basic"
  end

  @tag :skip
  test "execute Calculator" do
    assert {_, 0} =
             System.cmd(
               "npx",
               ~w(mcp-jest --transport streamable-http --url #{new(url: basic_path())} --tools Calculator),
               into: IO.stream()
             )
  end
end
