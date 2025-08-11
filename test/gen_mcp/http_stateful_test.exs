defmodule GenMcp.HttpStatefulTest do
  import GenMcp.Test.Client
  use ExUnit.Case, async: true

  defp path do
    "/mcp/stateful"
  end

  defp url do
    url(path())
  end

  @tag :skip
  test "what to do with GET by default??"

  test "we can run the initialization" do
    assert %{
             "id" => 123,
             "jsonrpc" => "2.0",
             "result" => %{
               "capabilities" => %{"tools" => %{}},
               "protocolVersion" => "2025-06-18",
               "serverInfo" => %{
                 "name" => _,
                 "title" => _,
                 "version" => _
               }
             }
           } =
             post_message(path(), %{
               jsonrpc: "2.0",
               id: 123,
               method: "initialize",
               params: %{
                 capabilities: %{},
                 clientInfo: %{name: "test client", version: "0.0.0"},
                 protocolVersion: "2025-06-18"
               }
             }).body

    assert "" =
             post_message(path(), %{
               jsonrpc: "2.0",
               method: "notifications/initialized",
               params: %{}
             }).body
  end
end
