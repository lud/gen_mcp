defmodule GenMCP.Test.Extensions.PizzazTest do
  use ExUnit.Case, async: true

  import GenMCP.Test.Client

  alias GenMCP.MCP

  @url "/mcp/pizza"

  def client do
    new(url: @url)
  end

  test "initializes correctly" do
    resp =
      client()
      |> post_message(%MCP.InitializeRequest{
        id: 1,
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %MCP.Implementation{name: "test", version: "1.0"},
          protocolVersion: "2025-06-18"
        }
      })
      |> expect_status(200)

    assert %{
             "result" => %{
               "serverInfo" => %{"name" => "Pizza Server", "version" => "0.1.0"}
             }
           } = resp.body
  end

  test "lists tools" do
    session_id = init_session()

    resp =
      client()
      |> Req.Request.put_header("mcp-session-id", session_id)
      |> post_message(%MCP.ListToolsRequest{
        id: 2,
        params: %{}
      })
      |> expect_status(200)

    tools = resp.body["result"]["tools"]
    assert length(tools) == 5
    assert Enum.find(tools, &(&1["name"] == "pizza-map"))
    assert Enum.find(tools, &(&1["name"] == "pizza-shop"))
  end

  test "calls a tool" do
    session_id = init_session()

    resp =
      client()
      |> Req.Request.put_header("mcp-session-id", session_id)
      |> post_message(%MCP.CallToolRequest{
        id: 3,
        params: %MCP.CallToolRequestParams{
          name: "pizza-map",
          arguments: %{"pizzaTopping" => "pepperoni"}
        }
      })
      |> expect_status(200)

    result = resp.body["result"]
    assert result["content"] == [%{"type" => "text", "text" => "Rendered a pizza map!"}]
    assert result["structuredContent"] == %{"pizzaTopping" => "pepperoni"}
    assert result["_meta"]["openai/toolInvocation/invoking"] == "Hand-tossing a map"
  end

  test "lists resources" do
    session_id = init_session()

    resp =
      client()
      |> Req.Request.put_header("mcp-session-id", session_id)
      |> post_message(%MCP.ListResourcesRequest{
        id: 4,
        params: %{}
      })
      |> expect_status(200)

    resources = resp.body["result"]["resources"]
    assert length(resources) == 5
    assert Enum.find(resources, &(&1["uri"] == "ui://widget/pizza-map.html"))
  end

  test "reads a resource" do
    session_id = init_session()

    resp =
      client()
      |> Req.Request.put_header("mcp-session-id", session_id)
      |> post_message(%MCP.ReadResourceRequest{
        id: 5,
        params: %MCP.ReadResourceRequestParams{
          uri: "ui://widget/pizza-map.html"
        }
      })
      |> expect_status(200)

    contents = resp.body["result"]["contents"]
    assert length(contents) == 1
    assert hd(contents)["text"] =~ "<!doctype html>"
    assert hd(contents)["mimeType"] == "text/html+skybridge"
  end

  defp init_session do
    resp =
      client()
      |> post_message(%MCP.InitializeRequest{
        id: 1,
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %MCP.Implementation{name: "test", version: "1.0"},
          protocolVersion: "2025-06-18"
        }
      })
      |> expect_status(200)

    List.first(resp.headers["mcp-session-id"])
  end
end
