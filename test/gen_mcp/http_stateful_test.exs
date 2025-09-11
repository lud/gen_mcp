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

  test "sending non json rpc" do
    assert %{
             status: 400,
             body: %{
               "error" => %{"code" => 1, "data" => nil, "message" => "invalid JSON-RPC payload"},
               "jsonrpc" => "2.0"
             }
           } = Req.post!(url(), json: %{"hello" => "world"})

    # same if we send non-json request (it's not parsed) (parse error should be handled differently)

    assert %{
             status: 400,
             body: %{
               "error" => %{"code" => 1, "data" => nil, "message" => "invalid JSON-RPC payload"},
               "jsonrpc" => "2.0"
             }
           } = Req.post!(url(), body: "hello")
  end

  test "send invalid request" do
    assert %{
             # We still get the ID if provided
             "id" => 123,
             "jsonrpc" => "2.0",
             "error" => %{
               "code" => 2,
               "data" => %{"details" => _, "valid" => false},
               "message" => "request validation failed"
             }
           } =
             post_invalid_message(path(), %{
               jsonrpc: "2.0",
               id: 123,
               method: "initialize",
               params: %{
                 # missing capabilities in payload
                 clientInfo: %{name: "test client", version: "0.0.0"},
                 protocolVersion: "2025-06-18"
               }
             }).body
  end

  test "calling a sync tool" do
    assert %{
             "id" => 456,
             "jsonrpc" => "2.0",
             "result" => %{
               "content" => [
                 %{"text" => "{\"result\":15}", "type" => "text"}
               ],
               "structuredContent" => %{"result" => 15}
             }
           } =
             post_message(path(), %{
               jsonrpc: "2.0",
               id: 456,
               method: "tools/call",
               params: %{
                 _meta: %{progressToken: "hello"},
                 name: "Calculator",
                 arguments: %{operator: "+", operands: [7, 8]}
               }
             }).body
  end
end
