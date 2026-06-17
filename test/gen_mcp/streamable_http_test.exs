# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMCP.StreamableHTTPTest do
  use ExUnit.Case, async: false

  import GenMCP.Test.Client
  import Mox

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.Support.ServerMock
  alias GenMCP.Support.ToolMock

  @mcp_url "/mcp/mock"
  @protocol_version GenMCP.protocol_version()

  setup [:set_mox_global, :verify_on_exit!]

  # Stateless client: no `mcp-session-id` header anywhere. The authoritative
  # protocol version travels in the `MCP-Protocol-Version` HTTP header
  # (SEP-1442). Extra headers can be merged for the "stray header" cases.
  defp client(opts) when is_list(opts) do
    url = Keyword.fetch!(opts, :url)

    headers =
      Map.merge(
        %{"mcp-protocol-version" => @protocol_version},
        Keyword.get(opts, :headers, %{})
      )

    new(headers: headers, url: url, retry: false)
  end

  # The 2026-07-28 transport is stateless: for every JSON-RPC message the
  # transport builds ephemeral server state with `init/1`, then dispatches the
  # message with `handle_request/3` (or `handle_notification/3`). State is never
  # carried between requests. `init/1` no longer receives a session id; it gets
  # the validated server opts, and per-request data arrives via the request and
  # channel.
  #
  # Handlers return unified tags: terminal `{:result, result}` / `{:error,
  # reason}` (no state — the worker ends), or `{:stream, state}` to enter the
  # wrapper receive loop, where Erlang messages are delivered to
  # `handle_message/3` (the rename of `handle_info`) — which returns
  # `{:stream, state}` to continue or `{:result, _}` / `{:error, _}` /
  # `{:stop, _}` to end. Notifications return `:ok`. The channel is input-only
  # and never returned.
  defp expect_request(handler, init_state \\ :server_state) do
    ServerMock
    |> expect(:init, fn _opts -> {:ok, init_state} end)
    |> expect(:handle_request, handler)
  end

  defp expect_notification(handler, init_state \\ :server_state) do
    ServerMock
    |> expect(:init, fn _opts -> {:ok, init_state} end)
    |> expect(:handle_notification, handler)
  end

  describe "stateless transport invariants" do
    test "a successful response carries no mcp-session-id header" do
      expect_request(fn %MCP.ListToolsRequest{}, _channel, _state ->
        {:result, MCP.list_tools_result([])}
      end)

      client(url: @mcp_url)
      |> post_message(%{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}})
      |> expect_status(200)
      |> refute_session_header()
    end

    test "a non-initialization request succeeds with no session header" do
      # Under the stateful protocol this returned 400 ("session id not
      # provided"). Statelessly it is just a normal request.
      expect_request(fn %MCP.ListToolsRequest{}, _channel, _state ->
        {:result, MCP.list_tools_result([])}
      end)

      assert %{"id" => 7, "jsonrpc" => "2.0", "result" => %{"tools" => []}} =
               client(url: @mcp_url)
               |> post_message(%{jsonrpc: "2.0", id: 7, method: "tools/list", params: %{}})
               |> expect_status(200)
               |> body()
    end

    test "rejects a request whose MCP-Protocol-Version header disagrees with the body _meta version" do
      # Header/body agreement is a transport-layer concern, so individual
      # GenMCP implementations do not need to re-check it. Per the draft spec's
      # Server Validation section, the transport MUST answer 400 with a
      # `HeaderMismatch` (-32001) JSON-RPC error, and the server behaviour is
      # never invoked.
      #
      # TODO(tighten): also assert the error message names the mismatching
      # field/values once the transport rework fixes the wording.
      resp =
        new(url: @mcp_url, headers: %{"mcp-protocol-version" => @protocol_version}, retry: false)
        |> post_invalid_message(%{
          jsonrpc: "2.0",
          id: 1,
          method: "tools/list",
          # Otherwise-valid _meta; only the body protocol version disagrees with
          # the header, so -32001 can only be the mismatch.
          params: %{
            _meta: request_meta(%{"io.modelcontextprotocol/protocolVersion" => "1999-01-01"})
          }
        })
        |> expect_status(400)

      assert %{"error" => %{"code" => -32_001}} = resp.body
      Mox.verify!(ServerMock)
    end

    test "rejects a request that omits the MCP-Protocol-Version header" do
      # We support a single protocol version, so a missing header MUST be
      # rejected (we do not fall back to treating it as 2025-03-26).
      resp =
        new(url: @mcp_url, retry: false)
        |> post_invalid_message(%{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}})
        |> expect_status(400)

      assert %{"error" => %{"code" => -32_001}} = resp.body
      Mox.verify!(ServerMock)
    end

    test "rejects a request whose MCP-Protocol-Version is a known-but-unsupported version" do
      # The header is well-formed AND agrees with the body `_meta`, but names a
      # version this server does not implement. This is the case the old code
      # got wrong: it fell through to the catch-all and reported a *missing*
      # header. It is neither missing (-32001) nor a header/body mismatch
      # (-32001) — it is an `UnsupportedProtocolVersionError` (-32004, HTTP 400)
      # whose `data` lists the versions the server supports, per the draft
      # Streamable HTTP spec. The server behaviour is never invoked.
      unsupported = "2025-06-18"

      resp =
        new(url: @mcp_url, headers: %{"mcp-protocol-version" => unsupported}, retry: false)
        |> post_invalid_message(%{
          jsonrpc: "2.0",
          id: 1,
          method: "tools/list",
          params: %{
            _meta: request_meta(%{"io.modelcontextprotocol/protocolVersion" => unsupported})
          }
        })
        |> expect_status(400)

      assert %{
               "error" => %{
                 "code" => -32_004,
                 "message" => message,
                 "data" => %{
                   "requested" => ^unsupported,
                   "supported" => supported
                 }
               }
             } = resp.body

      # `data.supported` is the list the client should retry from; it must
      # include the version this server actually speaks.
      assert is_list(supported)
      assert @protocol_version in supported

      # The message must describe an unsupported version — not a missing or
      # mismatched header, the two failures this case used to be confused with.
      assert message =~ "Unsupported protocol version"
      refute message =~ "Missing"
      refute message =~ "mismatch"

      Mox.verify!(ServerMock)
    end

    test "a stray mcp-session-id request header is ignored" do
      expect_request(fn %MCP.ListToolsRequest{}, _channel, _state ->
        {:result, MCP.list_tools_result([])}
      end)

      client(url: @mcp_url, headers: %{"mcp-session-id" => "ignored-by-server"})
      |> post_message(%{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}})
      |> expect_status(200)
      |> refute_session_header()
    end

    test "a Last-Event-ID request header is ignored (streams are not resumable)" do
      expect_request(fn %MCP.ListToolsRequest{}, _channel, _state ->
        {:result, MCP.list_tools_result([])}
      end)

      client(url: @mcp_url, headers: %{"last-event-id" => "42"})
      |> post_message(%{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}})
      |> expect_status(200)
    end

    test "GET to the MCP endpoint is 405 Method Not Allowed" do
      # The GET stream endpoint and protocol-level sessions were removed in
      # 2026-07-28. The opt-in `subscriptions/listen` stream (spec 008) replaces
      # it; bare GET is rejected.
      assert %{status: 405} = Req.get!(client(url: @mcp_url))
    end

    test "DELETE to the MCP endpoint is 405 Method Not Allowed" do
      # No sessions to terminate.
      assert %{status: 405} = Req.delete!(client(url: @mcp_url))
    end

    test "init/1 receives the forwarded server options on every request" do
      # The /mcp/mock route forwards `foo: :bar` past the wrapper options; the
      # per-request worker hands them to `init/1` verbatim (there is no session
      # id argument anymore).
      ServerMock
      |> expect(:init, fn opts ->
        assert :bar = Keyword.fetch!(opts, :foo)
        {:ok, :server_state}
      end)
      |> expect(:handle_request, fn %MCP.ListToolsRequest{}, _channel, :server_state ->
        {:result, MCP.list_tools_result([])}
      end)

      client(url: @mcp_url)
      |> post_message(%{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}})
      |> expect_status(200)
    end

    test "two sequential requests with no shared state each succeed independently" do
      # Load-balancer invariant: each request stands alone, fanning out to any
      # node would behave the same.
      for id <- [101, 102] do
        expect_request(fn %MCP.ListToolsRequest{}, _channel, _state ->
          {:result, MCP.list_tools_result([])}
        end)

        assert %{"id" => ^id, "result" => %{"tools" => []}} =
                 client(url: @mcp_url)
                 |> post_message(%{jsonrpc: "2.0", id: id, method: "tools/list", params: %{}})
                 |> expect_status(200)
                 |> refute_session_header()
                 |> body()
      end
    end
  end

  describe "origin validation (DNS-rebinding protection)" do
    # The spec REQUIRES validating the Origin header on all incoming
    # connections: present-and-unknown Origin → 403 Forbidden, body MAY be an
    # id-less JSON-RPC error. Absent Origin (non-browser clients) is accepted —
    # every other test in this file posts without one. The allowlist is the
    # `allowed_origins` plug option; the default is to reject any Origin.

    test "a request with an unknown Origin is rejected with 403 before dispatch" do
      # /mcp/mock has no allowed_origins configured: any present Origin is
      # rejected, the body is never read, the server behaviour never invoked.
      resp =
        client(url: @mcp_url, headers: %{"origin" => "http://evil.example"})
        |> post_invalid_message(%{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}})
        |> expect_status(403)

      assert %{"error" => %{"data" => %{"origin" => "http://evil.example"}}, "id" => nil} =
               resp.body

      Mox.verify!(ServerMock)
    end

    test "a request with an allowlisted Origin is dispatched normally" do
      expect_request(fn %MCP.ListToolsRequest{}, _channel, _state ->
        {:result, MCP.list_tools_result([])}
      end)

      assert %{"id" => 1, "result" => %{"tools" => []}} =
               client(url: "/mcp/mock-origins", headers: %{"origin" => "https://app.example.com"})
               |> post_message(%{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}})
               |> expect_status(200)
               |> body()
    end

    test "a request with an Origin not in the allowlist is rejected with 403" do
      resp =
        client(url: "/mcp/mock-origins", headers: %{"origin" => "https://other.example.com"})
        |> post_invalid_message(%{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}})
        |> expect_status(403)

      assert %{"error" => %{}, "id" => nil} = resp.body
      Mox.verify!(ServerMock)
    end

    test "GET with an unknown Origin is rejected with 403, not 405" do
      # Origin validation guards every verb on the endpoint.
      assert %{status: 403} =
               Req.get!(client(url: @mcp_url, headers: %{"origin" => "http://evil.example"}))
    end
  end

  describe "routing headers (Mcp-Method / Mcp-Name)" do
    # The transport validates the REQUIRED routing headers against the body
    # (draft transport spec, Request Metadata → Server Validation): missing or
    # mismatching headers are rejected with 400 + -32001 (HeaderMismatch) and
    # the server behaviour is never invoked. The test client mirrors them on
    # every conforming POST; `mirror_headers: false` opts out.

    test "rejects a request that omits the Mcp-Method header" do
      resp =
        client(url: @mcp_url)
        |> post_invalid_message(
          %{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}},
          mirror_headers: false
        )
        |> expect_status(400)

      assert %{"error" => %{"code" => -32_001}, "id" => 1} = resp.body
      Mox.verify!(ServerMock)
    end

    test "rejects a request whose Mcp-Method header disagrees with the body method" do
      resp =
        client(url: @mcp_url, headers: %{"mcp-method" => "tools/call"})
        |> post_invalid_message(
          %{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}},
          mirror_headers: false
        )
        |> expect_status(400)

      assert %{"error" => %{"code" => -32_001}, "id" => 1} = resp.body
      Mox.verify!(ServerMock)
    end

    test "rejects a notification that omits the Mcp-Method header" do
      resp =
        client(url: @mcp_url)
        |> post_invalid_message(
          %{jsonrpc: "2.0", method: "notifications/cancelled", params: %{requestId: "x"}},
          mirror_headers: false
        )
        |> expect_status(400)

      assert %{"error" => %{"code" => -32_001}, "id" => nil} = resp.body
      Mox.verify!(ServerMock)
    end

    test "rejects a tools/call that omits the Mcp-Name header" do
      resp =
        client(url: @mcp_url, headers: %{"mcp-method" => "tools/call"})
        |> post_invalid_message(
          %{
            jsonrpc: "2.0",
            id: 1,
            method: "tools/call",
            params: %{name: "SomeTool", arguments: %{}}
          },
          mirror_headers: false
        )
        |> expect_status(400)

      assert %{"error" => %{"code" => -32_001}, "id" => 1} = resp.body
      Mox.verify!(ServerMock)
    end

    test "rejects a tools/call whose Mcp-Name header disagrees with params.name" do
      resp =
        client(url: @mcp_url, headers: %{"mcp-method" => "tools/call", "mcp-name" => "OtherTool"})
        |> post_invalid_message(
          %{
            jsonrpc: "2.0",
            id: 1,
            method: "tools/call",
            params: %{name: "SomeTool", arguments: %{}}
          },
          mirror_headers: false
        )
        |> expect_status(400)

      assert %{"error" => %{"code" => -32_001}, "id" => 1} = resp.body
      Mox.verify!(ServerMock)
    end

    test "resources/read mirrors params.uri in Mcp-Name" do
      # Positive path: the conforming client mirrors `params.uri`, the transport
      # validates it and dispatches.
      expect_request(fn %MCP.ReadResourceRequest{}, _channel, _state ->
        {:error, {:resource_not_found, "file:///x.txt"}}
      end)

      client(url: @mcp_url)
      |> post_message(%{
        jsonrpc: "2.0",
        id: 1,
        method: "resources/read",
        params: %{uri: "file:///x.txt"}
      })
      |> expect_status(200)
    end

    test "Mcp-Name is not required for methods outside tools/call, resources/read, prompts/get" do
      # Every other conforming test in this file already posts without Mcp-Name;
      # this pins the tolerance explicitly for tools/list.
      expect_request(fn %MCP.ListToolsRequest{}, _channel, _state ->
        {:result, MCP.list_tools_result([])}
      end)

      client(url: @mcp_url)
      |> post_message(%{jsonrpc: "2.0", id: 1, method: "tools/list", params: %{}})
      |> expect_status(200)
    end
  end

  describe "server/discover" do
    test "discovery request round-trips through the transport" do
      # `server/discover` replaces the `initialize` handshake for capability
      # discovery. The transport routes the method to the server behaviour and
      # serializes its DiscoverResult; what the Suite puts in it is exercised
      # in the Suite tests.
      expect_request(fn %MCP.DiscoverRequest{} = req, _channel, _state ->
        assert %MCP.DiscoverRequest{id: 1} = req

        {:result,
         MCP.discover_result(
           name: "foo",
           version: "0.0.1",
           capabilities: MCP.capabilities(tools: true, logging: true)
         )}
      end)

      assert %{
               "id" => 1,
               "jsonrpc" => "2.0",
               "result" => %{
                 "resultType" => "complete",
                 "capabilities" => %{"tools" => %{}, "logging" => %{}},
                 "serverInfo" => %{"name" => "foo", "version" => "0.0.1"},
                 "supportedVersions" => ["2026-07-28"]
               }
             } =
               client(url: @mcp_url)
               |> post_message(%{
                 jsonrpc: "2.0",
                 id: 1,
                 method: "server/discover",
                 params: %{}
               })
               |> expect_status(200)
               |> refute_session_header()
               |> body()
    end
  end

  describe "bad requests" do
    test "unknown RPC method is 404 Not Found with a -32601 error body" do
      # The draft spec requires 404 (not 200) for an unimplemented method; the
      # JSON-RPC error body distinguishes this from a bare 404 served by a
      # legacy HTTP+SSE endpoint.
      assert %{
               status: 404,
               body: %{
                 "error" => %{
                   "code" => -32_601,
                   "data" => %{"method" => "some_unknownw_method"},
                   "message" => "Unknown method some_unknownw_method"
                 },
                 "id" => 123,
                 "jsonrpc" => "2.0"
               }
             } =
               post_invalid_message(client(url: @mcp_url), %{
                 jsonrpc: "2.0",
                 id: 123,
                 method: "some_unknownw_method",
                 params: %{foo: "bar"}
               })
    end

    test "sending non json rpc" do
      assert %{
               "error" => %{"code" => -32_600, "message" => "Invalid RPC request"},
               "id" => nil,
               "jsonrpc" => "2.0"
             } =
               client(url: @mcp_url)
               |> Req.post!(json: %{"hello" => "world"})
               |> expect_status(400)
               |> body()

      assert %{
               "error" => %{"code" => -32_600, "message" => "Invalid RPC request"},
               "id" => nil,
               "jsonrpc" => "2.0"
             } =
               client(url: @mcp_url)
               |> Req.post!(body: "hello")
               |> expect_status(400)
               |> body()
    end

    test "send invalid request params" do
      assert %{
               "id" => 123,
               "jsonrpc" => "2.0",
               "error" => %{
                 "code" => -32_602,
                 "data" => %{"details" => _, "valid" => false},
                 "message" => "Invalid Parameters"
               }
             } =
               post_invalid_message(client(url: @mcp_url), %{
                 jsonrpc: "2.0",
                 id: 123,
                 method: "tools/call",
                 # missing the required `name`
                 params: %{arguments: %{}}
               }).body
    end
  end

  describe "tools" do
    test "list tools" do
      expect_request(fn %MCP.ListToolsRequest{id: 123, params: %{}}, channel, _state ->
        # Real HTTP client, so the channel client is the request process, not
        # the test pid.
        assert %Channel{client: pid, meta: meta} = channel
        assert is_pid(pid)

        # The transport extracts the `io.modelcontextprotocol/*` request
        # `_meta` fields into the channel's read-only `meta`.
        assert %{
                 client_info: %MCP.Implementation{name: "test-client", version: "1.0.0"},
                 client_capabilities: %MCP.ClientCapabilities{},
                 protocol_version: @protocol_version
               } = meta

        resp = MCP.list_tools_result([{ToolMock, :tool1}, {ToolMock, :tool2}])
        {:result, resp}
      end)

      ToolMock
      |> stub(:info, fn
        :name, :tool1 -> "Tool1"
        :title, :tool1 -> "Tool 1 title"
        :description, :tool1 -> "Tool 1 descr"
        :annotations, :tool1 -> %{title: "Tool 1 subtitle", destructiveHint: true}
        :_meta, :tool1 -> %{"some" => "meta"}
        :name, :tool2 -> "Tool2"
        :title, :tool2 -> nil
        :description, :tool2 -> nil
        :annotations, :tool2 -> nil
        :_meta, :tool2 -> nil
      end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)
      |> stub(:output_schema, fn
        :tool1 -> %{type: :object}
        :tool2 -> nil
      end)

      assert %{
               "id" => 123,
               "jsonrpc" => "2.0",
               "result" => %{
                 "tools" => [
                   %{
                     "name" => "Tool1",
                     "annotations" => %{"title" => "Tool 1 subtitle", "destructiveHint" => true},
                     "title" => "Tool 1 title",
                     "description" => "Tool 1 descr",
                     "inputSchema" => %{"type" => "object"},
                     "outputSchema" => %{"type" => "object"},
                     "_meta" => %{"some" => "meta"}
                   },
                   %{
                     "name" => "Tool2",
                     "inputSchema" => %{"type" => "object"}
                   }
                 ],
                 "cacheScope" => "private",
                 "resultType" => "complete",
                 "ttlMs" => 0
               }
             } ==
               post_message(client(url: @mcp_url), %{
                 jsonrpc: "2.0",
                 id: 123,
                 method: "tools/list",
                 params: %{}
               }).body
    end

    test "calling a sync tool" do
      expect_request(fn req, _channel, _state ->
        assert %MCP.CallToolRequest{
                 id: 456,
                 params: %MCP.CallToolRequestParams{
                   _meta: %{progressToken: "hello"},
                   arguments: %{"some" => "arg"},
                   name: "SomeTool"
                 }
               } = req

        {:result, MCP.call_tool_result(text: "hello")}
      end)

      assert %{
               "id" => 456,
               "jsonrpc" => "2.0",
               "result" => %{"content" => [%{"text" => "hello", "type" => "text"}]}
             } =
               client(url: @mcp_url)
               |> post_message(%{
                 jsonrpc: "2.0",
                 id: 456,
                 method: "tools/call",
                 params: %{
                   _meta: request_meta(%{progressToken: "hello"}),
                   name: "SomeTool",
                   arguments: %{some: "arg"}
                 }
               })
               |> body()
    end

    test "calling an unknown tool" do
      expect_request(fn req, _channel, _state ->
        assert %MCP.CallToolRequest{
                 id: 456,
                 params: %MCP.CallToolRequestParams{arguments: %{}, name: "SomeUnknownTool"}
               } = req

        {:error, {:unknown_tool, "swapped-tool-name"}}
      end)

      assert %{
               "error" => %{
                 "code" => -32_602,
                 "message" => "Unknown tool swapped-tool-name",
                 "data" => %{"tool" => "swapped-tool-name"}
               },
               "id" => 456,
               "jsonrpc" => "2.0"
             } ==
               client(url: @mcp_url)
               |> post_message(%{
                 jsonrpc: "2.0",
                 id: 456,
                 method: "tools/call",
                 params: %{name: "SomeUnknownTool", arguments: %{}}
               })
               |> expect_status(200)
               |> body()
    end

    test "an explicitly streaming tool answers over SSE even with no progress" do
      # Returning `{:stream, state}` commits the response to `text/event-stream`
      # (eager SSE) even when no intermediate progress is emitted; the result is
      # produced from a continuation in `handle_message/3`.
      ServerMock
      |> expect(:init, fn _opts -> {:ok, :server_state} end)
      |> expect(:handle_request, fn req, _channel, state ->
        assert %MCP.CallToolRequest{
                 id: 456,
                 params: %MCP.CallToolRequestParams{
                   arguments: %{"arg" => 123},
                   name: "SomeAsyncTool"
                 }
               } = req

        send(self(), :produce_result)
        {:stream, state}
      end)
      |> expect(:handle_message, fn :produce_result, _channel, _state ->
        {:result, MCP.call_tool_result(audio: {"wav", "some-base-64"})}
      end)

      resp =
        post_message(client(url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 456,
          method: "tools/call",
          params: %{name: "SomeAsyncTool", arguments: %{arg: 123}}
        })

      # SSE responses use the event-stream content type and disable reverse-proxy
      # buffering so events are flushed immediately (spec SHOULD).
      assert ["text/event-stream" <> _] = resp.headers["content-type"]
      assert ["no"] = resp.headers["x-accel-buffering"]

      assert "event: message\ndata: " <> json = resp.body

      assert %{
               "id" => 456,
               "jsonrpc" => "2.0",
               "result" => %{
                 "content" => [
                   %{"type" => "audio", "data" => "some-base-64", "mimeType" => "wav"}
                 ]
               }
             } = JSV.Codec.decode!(json)
    end

    test "async tool emits progress notifications then the result on the SSE stream" do
      token = "some-progress-token"

      ServerMock
      |> expect(:init, fn _opts -> {:ok, :server_state} end)
      |> expect(:handle_request, fn _req, channel, state ->
        assert %Channel{progress_token: ^token} = channel
        send(self(), :some_info1)
        {:stream, state}
      end)
      |> expect(:handle_message, fn :some_info1, channel, state ->
        :ok = Channel.send_progress(channel, 0, 3, "zero")
        send(self(), :some_info2)
        {:stream, state}
      end)
      |> expect(:handle_message, fn :some_info2, channel, state ->
        :ok = Channel.send_progress(channel, 3, 3, "three")
        Process.send_after(self(), :some_info3, 1000)
        {:stream, state}
      end)
      |> expect(:handle_message, fn :some_info3, _channel, _state ->
        {:result, MCP.call_tool_result(text: "hello")}
      end)

      chunks =
        client(url: @mcp_url)
        |> post_message(
          %{
            jsonrpc: "2.0",
            id: 456,
            method: "tools/call",
            params: %{
              name: "SomeAsyncTool",
              arguments: %{some: :arg},
              _meta: request_meta(%{progressToken: token})
            }
          },
          into: :self
        )
        |> stream_chunks()
        |> parse_stream()
        |> Enum.map(fn %{event: "message", data: data} -> data end)

      assert [
               %{
                 "method" => "notifications/progress",
                 "params" => %{
                   "message" => "zero",
                   "progressToken" => ^token,
                   "progress" => 0,
                   "total" => 3
                 }
               },
               %{
                 "method" => "notifications/progress",
                 "params" => %{
                   "message" => "three",
                   "progressToken" => ^token,
                   "progress" => 3,
                   "total" => 3
                 }
               },
               %{
                 "id" => 456,
                 "jsonrpc" => "2.0",
                 "result" => %{"content" => [%{"text" => "hello", "type" => "text"}]}
               }
             ] = chunks
    end

    test "a real client disconnect mid-stream invokes handle_close server-side" do
      # End-to-end over real HTTP: the client opens an SSE stream, reads a
      # progress event (so the request is genuinely mid-flight), then closes the
      # connection. Bandit observes the dropped socket on the next chunk write,
      # the worker's relay monitor fires :CHAN_DOWN, and the server's
      # `handle_close/2` runs with the channel already `:closed`.
      #
      # The server keeps ticking ~every 50ms so the dropped socket is noticed
      # promptly — disconnect is detected on the next write, not by the 25s
      # keepalive. `ServerMock` implements handle_close, so the normal
      # /mcp/mock route is enough (no dedicated route/mock).
      test_pid = self()
      token = "disconnect-token"

      ServerMock
      |> expect(:init, fn _opts -> {:ok, :server_state} end)
      |> expect(:handle_request, fn _req, %Channel{progress_token: ^token}, state ->
        Process.send_after(self(), :tick, 50)
        {:stream, state}
      end)
      |> stub(:handle_message, fn :tick, channel, state ->
        :ok = Channel.send_progress(channel, 1, 2, "tick")
        Process.send_after(self(), :tick, 50)
        {:stream, state}
      end)
      |> expect(:handle_close, fn channel, :server_state ->
        send(test_pid, {:closed_for_real, channel.status})
        :ok
      end)

      resp =
        post_message(
          client(url: @mcp_url),
          %{
            jsonrpc: "2.0",
            id: 99,
            method: "tools/call",
            params: %{
              name: "StreamTool",
              arguments: %{},
              _meta: request_meta(%{progressToken: token})
            }
          },
          into: :self
        )

      # The stream is live: pull the first SSE event (a progress notification).
      assert [%{event: "message", data: %{"method" => "notifications/progress"}}] =
               resp |> stream_chunks() |> parse_stream() |> Enum.take(1)

      # Now drop the connection for real; the next tick's write fails, the relay
      # finalizes, and the worker observes :CHAN_DOWN.
      Req.cancel_async_response(resp)

      # The server runs cleanup with a closed channel.
      assert_receive {:closed_for_real, :closed}, 2000
    end

    test "a server-initiated Channel.close gracefully ends the stream and runs handle_close" do
      # The handler emits one progress event, then ends the stream itself via
      # `Channel.close/1` (server-initiated, no client disconnect). The transport
      # acknowledges the close and finalizes the response *gracefully*, so the
      # client reads the progress event and then a clean end-of-stream, while the
      # worker runs `handle_close` with the channel already `:closed`.
      test_pid = self()
      token = "server-close-token"

      ServerMock
      |> expect(:init, fn _opts -> {:ok, :server_state} end)
      |> expect(:handle_request, fn _req, %Channel{progress_token: ^token}, state ->
        send(self(), :tick)
        {:stream, state}
      end)
      |> expect(:handle_message, fn :tick, channel, state ->
        :ok = Channel.send_progress(channel, 1, 2, "tick")
        # The server decides to end the stream itself.
        {:ok, %Channel{status: :closed}} = Channel.close(channel)
        {:stream, state}
      end)
      |> expect(:handle_close, fn channel, :server_state ->
        send(test_pid, {:server_closed, channel.status})
        :ok
      end)

      resp =
        post_message(
          client(url: @mcp_url),
          %{
            jsonrpc: "2.0",
            id: 100,
            method: "tools/call",
            params: %{
              name: "StreamTool",
              arguments: %{},
              _meta: request_meta(%{progressToken: token})
            }
          },
          into: :self
        )

      # The client reads the whole stream to its end: the progress event, then a
      # graceful close (the consumer reaches `:done`). `read_chunk/1` only
      # consumes this response's `{ref, _}` messages, so the `{:server_closed,
      # _}` signal below is left untouched in the mailbox.
      assert [%{event: "message", data: %{"method" => "notifications/progress"}}] =
               resp
               |> stream_chunks()
               |> parse_stream()
               |> Enum.to_list()

      # The transport closed the connection on the server's behalf, so the worker
      # ran cleanup with a closed channel.
      assert_receive {:server_closed, :closed}, 5000
    end

    test "async tool that errors from a continuation terminates the stream" do
      ServerMock
      |> expect(:init, fn _opts -> {:ok, :server_state} end)
      |> expect(:handle_request, fn req, _channel, state ->
        assert %MCP.CallToolRequest{
                 id: 457,
                 params: %MCP.CallToolRequestParams{
                   arguments: %{"arg" => 123},
                   name: "AsyncToolWithError"
                 }
               } = req

        send(self(), :async_error)
        {:stream, state}
      end)
      |> expect(:handle_message, fn :async_error, _channel, _state ->
        {:error, "Something went wrong in async operation"}
      end)

      chunks =
        client(url: @mcp_url)
        |> post_message(
          %{
            jsonrpc: "2.0",
            id: 457,
            method: "tools/call",
            params: %{name: "AsyncToolWithError", arguments: %{arg: 123}}
          },
          into: :self
        )
        |> stream_chunks()
        |> parse_stream()
        |> Enum.map(fn %{event: "message", data: data} -> data end)

      assert [
               %{
                 "error" => %{
                   "code" => -32_603,
                   "message" => "Something went wrong in async operation"
                 },
                 "id" => 457,
                 "jsonrpc" => "2.0"
               }
             ] = chunks
    end
  end

  describe "worker lifecycle" do
    @tag capture_log: true
    test "a crashing handler yields a JSON-RPC internal error, not a generic 500" do
      # The relay monitors the worker and converts an abnormal exit into a
      # proper JSON-RPC error. Crash details stay in the logs, not in the body.
      expect_request(fn %MCP.ListToolsRequest{}, _channel, _state ->
        raise "boom"
      end)

      resp =
        client(url: @mcp_url)
        |> post_message(%{jsonrpc: "2.0", id: 9, method: "tools/list", params: %{}})
        |> expect_status(500)

      assert %{"error" => %{"code" => -32_603}, "id" => 9, "jsonrpc" => "2.0"} = resp.body
      refute resp.body["error"]["message"] =~ "boom"
    end

    @tag capture_log: true
    test "a crash from a streaming continuation emits the error on the SSE stream" do
      ServerMock
      |> expect(:init, fn _opts -> {:ok, :server_state} end)
      |> expect(:handle_request, fn _req, _channel, state ->
        send(self(), :boom)
        {:stream, state}
      end)
      |> expect(:handle_message, fn :boom, _channel, _state ->
        raise "boom"
      end)

      chunks =
        client(url: @mcp_url)
        |> post_message(
          %{jsonrpc: "2.0", id: 458, method: "tools/list", params: %{}},
          into: :self
        )
        |> stream_chunks()
        |> parse_stream()
        |> Enum.map(fn %{event: "message", data: data} -> data end)

      assert [%{"error" => %{"code" => -32_603}, "id" => 458}] = chunks
    end

    test "a {:stop, reason} continuation ends the stream with no final result" do
      # The listener exit path (spec 008's canonical consumer): the worker
      # stops cleanly, the relay just terminates the stream.
      ServerMock
      |> expect(:init, fn _opts -> {:ok, :server_state} end)
      |> expect(:handle_request, fn _req, _channel, state ->
        send(self(), :quit)
        {:stream, state}
      end)
      |> expect(:handle_message, fn :quit, _channel, _state ->
        {:stop, :normal}
      end)

      chunks =
        client(url: @mcp_url)
        |> post_message(
          %{jsonrpc: "2.0", id: 459, method: "tools/list", params: %{}},
          into: :self
        )
        |> stream_chunks()
        |> parse_stream()
        |> Enum.to_list()

      assert [] == chunks
    end
  end

  describe "notifications" do
    test "a notification the server cannot accept is rejected with an id-less error" do
      # Spec: a notification (no id) the server cannot accept yields an HTTP
      # error (e.g. 400); the optional JSON-RPC error body has no id. Here the
      # transport rejects malformed notification params before dispatch, so the
      # server behaviour is never invoked.

      resp =
        post_invalid_message(client(url: @mcp_url), %{
          jsonrpc: "2.0",
          method: "notifications/cancelled",
          # Add an invalid request ID to make the schema not validate
          params: %{requestId: true}
        })

      assert resp.status >= 400
      assert %{"jsonrpc" => "2.0", "id" => nil, "error" => %{}} = resp.body
      Mox.verify!(ServerMock)
    end

    test "cancelled notification is accepted with 202 and an empty body" do
      expect_notification(fn notif, _channel, _state ->
        assert %MCP.CancelledNotification{
                 params: %MCP.CancelledNotificationParams{
                   requestId: "request-to-cancel",
                   reason: "User cancelled"
                 }
               } = notif

        :ok
      end)

      assert "" =
               client(url: @mcp_url)
               |> post_message(%{
                 jsonrpc: "2.0",
                 method: "notifications/cancelled",
                 params: %{requestId: "request-to-cancel", reason: "User cancelled"}
               })
               |> expect_status(202)
               |> refute_session_header()
               |> body()
    end

    @tag capture_log: true
    test "a crashing notification handler yields an id-less error on an HTTP error status" do
      # Spec: a notification the server cannot accept gets an HTTP error
      # status; the optional JSON-RPC error body has no id. The worker crash is
      # converted by the transport, like for requests.
      expect_notification(fn %MCP.CancelledNotification{}, _channel, _state ->
        raise "boom"
      end)

      resp =
        post_message(client(url: @mcp_url), %{
          jsonrpc: "2.0",
          method: "notifications/cancelled",
          params: %{requestId: "x"}
        })

      assert resp.status >= 400
      assert %{"error" => %{"code" => -32_603}, "id" => nil} = resp.body
    end

    test "initialized notification is accepted as a no-op with 202, without invoking the server" do
      # `notifications/initialized` is an accept-and-ignore no-op for
      # transitional clients (SEP-1442). It does not exist in the 2026 schemas
      # (hence `post_invalid_message`): the transport short-circuits it before
      # validation and dispatch, so the server behaviour is never invoked — no
      # stubs, and any `init`/`handle_notification` call fails the test.
      assert "" =
               client(url: @mcp_url)
               |> post_invalid_message(%{
                 jsonrpc: "2.0",
                 method: "notifications/initialized",
                 params: %{}
               })
               |> expect_status(202)
               |> body()

      Mox.verify!(ServerMock)
    end
  end

  describe "resource operations" do
    test "list resources with pagination" do
      expect_request(fn %MCP.ListResourcesRequest{id: 200, params: %{}}, _channel, _state ->
        result =
          MCP.list_resources_result(
            [
              %{uri: "file:///page1.txt", name: "Page 1", description: "First page"},
              %{uri: "file:///page2.txt", name: "Page 2"}
            ],
            "next-page-token"
          )

        {:result, result}
      end)

      resp1 =
        post_message(client(url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 200,
          method: "resources/list",
          params: %{}
        })

      assert %{
               "id" => 200,
               "jsonrpc" => "2.0",
               "result" => %{
                 "resources" => [
                   %{
                     "uri" => "file:///page1.txt",
                     "name" => "Page 1",
                     "description" => "First page"
                   },
                   %{"uri" => "file:///page2.txt", "name" => "Page 2"}
                 ],
                 "nextCursor" => cursor
               }
             } = resp1.body

      assert cursor == "next-page-token"

      expect_request(fn req, _channel, _state ->
        assert %MCP.ListResourcesRequest{
                 id: 201,
                 params: %MCP.PaginatedRequestParams{cursor: ^cursor}
               } = req

        {:result, MCP.list_resources_result([%{uri: "file:///page3.txt", name: "Page 3"}], nil)}
      end)

      resp2 =
        post_message(client(url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 201,
          method: "resources/list",
          params: %{cursor: cursor}
        })

      assert %{
               "id" => 201,
               "jsonrpc" => "2.0",
               "result" => %{"resources" => [%{"uri" => "file:///page3.txt", "name" => "Page 3"}]}
             } = resp2.body

      assert nil == resp2.body["result"]["nextCursor"]
    end

    test "read resource" do
      expect_request(fn req, _channel, _state ->
        assert %MCP.ReadResourceRequest{
                 id: 204,
                 params: %MCP.ReadResourceRequestParams{uri: "file:///readme.txt"}
               } = req

        result =
          MCP.read_resource_result(
            uri: "file:///readme.txt",
            text: "# Welcome\n\nThis is the readme.",
            mime_type: "text/plain"
          )

        {:result, result}
      end)

      assert %{
               "id" => 204,
               "jsonrpc" => "2.0",
               "result" => %{
                 "contents" => [
                   %{
                     "uri" => "file:///readme.txt",
                     "mimeType" => "text/plain",
                     "text" => "# Welcome\n\nThis is the readme."
                   }
                 ]
               }
             } =
               post_message(client(url: @mcp_url), %{
                 jsonrpc: "2.0",
                 id: 204,
                 method: "resources/read",
                 params: %{uri: "file:///readme.txt"}
               }).body
    end

    test "read resource not found" do
      expect_request(fn req, _channel, _state ->
        assert %MCP.ReadResourceRequest{id: 205} = req
        {:error, {:resource_not_found, "file:///missing.txt"}}
      end)

      resp =
        client(url: @mcp_url)
        |> post_message(%{
          jsonrpc: "2.0",
          id: 205,
          method: "resources/read",
          params: %{uri: "file:///missing.txt"}
        })
        |> expect_status(200)

      # Missing-resource uses the standard -32602 (invalid params) under the
      # 2026 semantics; the old MCP-specific -32002 is retired (spec 005).
      assert %{
               "error" => %{
                 "code" => -32_602,
                 "message" => message,
                 "data" => %{"uri" => "file:///missing.txt"}
               },
               "id" => 205,
               "jsonrpc" => "2.0"
             } = resp.body

      assert message =~ "Resource not found"
    end

    test "list resource templates" do
      expect_request(fn %MCP.ListResourceTemplatesRequest{id: 207, params: %{}},
                        _channel,
                        _state ->
        result =
          MCP.list_resource_templates_result([
            %{
              uriTemplate: "file:///documents/{path}",
              name: "Documents",
              description: "Access documents by path",
              mimeType: "text/plain"
            },
            %{uriTemplate: "file:///images/{id}.png", name: "Images"}
          ])

        {:result, result}
      end)

      assert %{
               "id" => 207,
               "jsonrpc" => "2.0",
               "result" => %{
                 "resourceTemplates" => [
                   %{
                     "uriTemplate" => "file:///documents/{path}",
                     "name" => "Documents",
                     "description" => "Access documents by path",
                     "mimeType" => "text/plain"
                   },
                   %{"uriTemplate" => "file:///images/{id}.png", "name" => "Images"}
                 ]
               }
             } =
               post_message(client(url: @mcp_url), %{
                 jsonrpc: "2.0",
                 id: 207,
                 method: "resources/templates/list",
                 params: %{}
               }).body
    end
  end

  describe "prompt operations" do
    test "list prompts" do
      expect_request(fn %MCP.ListPromptsRequest{id: 300}, _channel, _state ->
        result =
          MCP.list_prompts_result(
            [
              %{name: "greeting", description: "A friendly greeting"},
              %{
                name: "analysis",
                description: "Data analysis",
                arguments: [%{name: "dataset", required: true, description: "Dataset to analyze"}]
              }
            ],
            nil
          )

        {:result, result}
      end)

      assert %{
               "id" => 300,
               "jsonrpc" => "2.0",
               "result" => %{
                 "prompts" => [
                   %{"name" => "greeting", "description" => "A friendly greeting"},
                   %{
                     "name" => "analysis",
                     "description" => "Data analysis",
                     "arguments" => [
                       %{
                         "name" => "dataset",
                         "required" => true,
                         "description" => "Dataset to analyze"
                       }
                     ]
                   }
                 ]
               }
             } =
               post_message(client(url: @mcp_url), %{
                 jsonrpc: "2.0",
                 id: 300,
                 method: "prompts/list",
                 params: %{}
               }).body
    end

    test "get prompt with arguments" do
      expect_request(fn req, _channel, _state ->
        assert %MCP.GetPromptRequest{
                 id: 303,
                 params: %{name: "analysis", arguments: %{"dataset" => "sales.csv"}}
               } = req

        result = %MCP.GetPromptResult{
          resultType: "complete",
          messages: [
            %MCP.PromptMessage{
              role: :user,
              content: %MCP.TextContent{text: "Analyze dataset: sales.csv"}
            }
          ]
        }

        {:result, result}
      end)

      assert %{
               "id" => 303,
               "jsonrpc" => "2.0",
               "result" => %{
                 "messages" => [
                   %{
                     "role" => "user",
                     "content" => %{"type" => "text", "text" => "Analyze dataset: sales.csv"}
                   }
                 ]
               }
             } =
               post_message(client(url: @mcp_url), %{
                 jsonrpc: "2.0",
                 id: 303,
                 method: "prompts/get",
                 params: %{name: "analysis", arguments: %{dataset: "sales.csv"}}
               }).body
    end

    test "prompt not found error" do
      expect_request(fn %MCP.GetPromptRequest{id: 304, params: %{name: "unknown"}},
                        _channel,
                        _state ->
        {:error, {:prompt_not_found, "unknown"}}
      end)

      assert %{
               "id" => 304,
               "jsonrpc" => "2.0",
               "error" => %{
                 "code" => -32_602,
                 "message" => "Prompt not found: unknown",
                 "data" => %{"name" => "unknown"}
               }
             } =
               post_message(client(url: @mcp_url), %{
                 jsonrpc: "2.0",
                 id: 304,
                 method: "prompts/get",
                 params: %{name: "unknown"}
               }).body
    end
  end

  describe "logging (deprecated, per-request level)" do
    # Logging is deprecated in 2026-07-28 (SEP-2577) and there is no
    # `logging/setLevel` request. The verbosity is declared per-request in `_meta`
    # `io.modelcontextprotocol/logLevel`; its absence disables logging entirely
    # (the server MUST NOT emit `notifications/message`). See spec 011.

    test "rejects a request with an unrecognized io.modelcontextprotocol/logLevel" do
      # The generic schema validation rejects the bad level before dispatch
      # (LoggingLevel is an enum), so the server behaviour is never invoked and
      # the channel can only ever hold a valid level or nil (spec 011).
      resp =
        post_invalid_message(client(url: @mcp_url), %{
          jsonrpc: "2.0",
          id: 788,
          method: "tools/call",
          params: %{
            name: "SomeTool",
            arguments: %{},
            _meta: request_meta(%{"io.modelcontextprotocol/logLevel" => "verbose"})
          }
        })

      assert 400 = resp.status
      assert %{"error" => %{"code" => -32_602}, "id" => 788, "jsonrpc" => "2.0"} = resp.body
      Mox.verify!(ServerMock)
    end

    test "emits notifications/message when the request declares a log level" do
      ServerMock
      |> expect(:init, fn _opts -> {:ok, :server_state} end)
      |> expect(:handle_request, fn %MCP.CallToolRequest{}, _channel, state ->
        send(self(), :send_log)
        {:stream, state}
      end)
      |> expect(:handle_message, fn :send_log, channel, _state ->
        # Channel built from a request carrying logLevel "warning"; an :error log
        # is at/above that, so it is emitted.
        :ok = Channel.send_log(channel, :error, "something broke", "db")
        {:result, MCP.call_tool_result(text: "done")}
      end)

      chunks =
        client(url: @mcp_url)
        |> post_message(
          %{
            jsonrpc: "2.0",
            id: 789,
            method: "tools/call",
            params: %{
              name: "SomeTool",
              arguments: %{},
              _meta: request_meta(%{"io.modelcontextprotocol/logLevel" => "warning"})
            }
          },
          into: :self
        )
        |> stream_chunks()
        |> parse_stream()
        |> Enum.map(fn %{event: "message", data: data} -> data end)

      assert [
               %{
                 "method" => "notifications/message",
                 "params" => %{
                   "level" => "error",
                   "data" => "something broke",
                   "logger" => "db"
                 }
               },
               %{
                 "id" => 789,
                 "jsonrpc" => "2.0",
                 "result" => %{"content" => [%{"text" => "done", "type" => "text"}]}
               }
             ] = chunks
    end

    test "send_log is a no-op when the request declares no log level" do
      # MUST NOT emit notifications/message for a request without
      # io.modelcontextprotocol/logLevel. The handler calls send_log anyway; the
      # channel's log_level is nil so it is dropped, and only the final result
      # reaches the client. (Fails if send_log is not gated on the per-request
      # level.)
      ServerMock
      |> expect(:init, fn _opts -> {:ok, :server_state} end)
      |> expect(:handle_request, fn %MCP.CallToolRequest{}, _channel, state ->
        send(self(), :send_log)
        {:stream, state}
      end)
      |> expect(:handle_message, fn :send_log, channel, _state ->
        :ok = Channel.send_log(channel, :error, "should be dropped", "db")
        {:result, MCP.call_tool_result(text: "done")}
      end)

      chunks =
        client(url: @mcp_url)
        |> post_message(
          %{
            jsonrpc: "2.0",
            id: 790,
            method: "tools/call",
            params: %{name: "SomeTool", arguments: %{}}
          },
          into: :self
        )
        |> stream_chunks()
        |> parse_stream()
        |> Enum.map(fn %{event: "message", data: data} -> data end)

      # Only the result — no notifications/message.
      assert [
               %{
                 "id" => 790,
                 "jsonrpc" => "2.0",
                 "result" => %{"content" => [%{"text" => "done", "type" => "text"}]}
               }
             ] = chunks

      refute Enum.any?(chunks, &match?(%{"method" => "notifications/message"}, &1))
    end
  end
end
