defmodule GenMCP.SuiteIntegrationTest do
  use ExUnit.Case, async: false

  import GenMCP.Test.Client
  import Mox

  alias GenMCP.Mux

  setup [:set_mox_global, :verify_on_exit!]

  defp client(opts) when is_list(opts) do
    headers =
      case Keyword.get(opts, :session_id, nil) do
        nil -> %{}
        sid when is_binary(sid) -> %{"mcp-session-id" => sid}
      end

    url = Keyword.fetch!(opts, :url)

    new(headers: headers, url: url)
  end

  @mcp_url "/mcp/real"

  test "basic tool listing/calling scenario" do
    # Initialize the server
    init_resp =
      client(url: @mcp_url)
      |> post_message(%{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{
          capabilities: %{},
          clientInfo: %{name: "test client", version: "0.0.0"},
          protocolVersion: "2025-06-18"
        }
      })
      |> expect_status(200)

    session_id = expect_session_header(init_resp)

    assert %{
             "jsonrpc" => "2.0",
             "id" => 1,
             "result" => %{
               "capabilities" => %{"tools" => %{}},
               "serverInfo" => %{
                 "name" => "Real Server",
                 "version" => "0.0.1",
                 "title" => "GenMCP own development server"
               }
             }
           } = body(init_resp)

    # Send initialized notification
    assert "" =
             client(session_id: session_id, url: @mcp_url)
             |> post_message(%{
               jsonrpc: "2.0",
               method: "notifications/initialized",
               params: %{}
             })
             |> expect_status(202)
             |> body()

    # List tools
    list_tools_resp =
      client(session_id: session_id, url: @mcp_url)
      |> post_message(%{
        jsonrpc: "2.0",
        id: 2,
        method: "tools/list",
        params: %{}
      })
      |> expect_status(200)

    assert %{
             "jsonrpc" => "2.0",
             "id" => 2,
             "result" => %{
               "tools" => tools
             }
           } = body(list_tools_resp)

    # Verify we have the tools we expect
    tool_names = Enum.map(tools, & &1["name"])
    assert "ErlangHasher" in tool_names
    assert "Addition" in tool_names

    # Find the ErlangHasher tool details
    erlang_hasher = Enum.find(tools, &(&1["name"] == "ErlangHasher"))

    assert erlang_hasher["description"] ==
             "Returns the hash for a number in a defined range, according to Erlang documentation"

    # Call the ErlangHasher tool
    call_tool_resp =
      client(session_id: session_id, url: @mcp_url)
      |> post_message(%{
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: %{
          name: "ErlangHasher",
          arguments: %{
            subject: "test string",
            range: 1000
          }
        }
      })
      |> expect_status(200)

    expected_hash = to_string(:erlang.phash2("test string", 1000))

    assert %{
             "jsonrpc" => "2.0",
             "id" => 3,
             "result" => %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => ^expected_hash
                 }
               ]
             }
           } = body(call_tool_resp)

    # Simulate session timeout
    #
    # TODO we need a better way to do that

    session_pid = Mux.whereis(session_id)
    assert is_pid(session_pid)
    assert %{session_timeout_ref: tref} = :sys.get_state(session_pid)
    ref = Process.monitor(session_pid)
    send(session_pid, {:timeout, tref, :session_timeout})
    assert_receive {:DOWN, ^ref, :process, ^session_pid, {:shutdown, :session_timeout}}

    # Session will not be restarted
    Process.sleep(100)
    assert nil == Mux.whereis(session_id)

    # Now the session_is down, call the tool again, the session should be
    # restored because the /mcp/real uses the disk storage

    client(session_id: session_id, url: @mcp_url)
    |> post_message(%{
      jsonrpc: "2.0",
      id: 4,
      method: "tools/call",
      params: %{
        name: "ErlangHasher",
        arguments: %{
          subject: "test string",
          range: 1000
        }
      }
    })
    |> expect_status(200)

    # The session has been started to respond

    assert is_pid(Mux.whereis(session_id))

    # Finally we can delete the session

    client(session_id: session_id, url: @mcp_url)
    |> Req.delete!()
    |> expect_status(204)

    assert nil == Mux.whereis(session_id)
  end
end
