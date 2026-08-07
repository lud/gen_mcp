defmodule GenMCP.V2511CompatTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.SessionController
  alias GenMCP.Support.ResourceRepoMock
  alias GenMCP.Support.SubscriptionHandlerFullMock
  alias GenMCP.Support.SubscriptionHandlerMock
  alias GenMCP.Support.ToolMock
  alias GenMCP.TestWeb.Endpoint

  setup [:set_mox_global, :verify_on_exit!]

  @url "/mcp/v2511"
  @res_url "/mcp/v2511-res"
  @sub_url "/mcp/v2511-sub"

  @latest "2025-11-25"

  @endpoint Endpoint

  # -- A 2025 client ----------------------------------------------------------
  #
  # Deliberately not `GenMCP.Test.Client`: that one validates every outgoing
  # message against the V2607 schemas and defaults a 2026 `_meta` into the
  # params. A 2025 client sends neither, and the point of these tests is that
  # the transport copes with exactly what a 2025 client puts on the wire.

  defp req(headers \\ %{}) do
    Req.new(
      base_url: Endpoint.url(),
      headers: headers,
      retry: false,
      receive_timeout: to_timeout(second: 30)
    )
  end

  defp post(body, opts \\ []) do
    url = Keyword.get(opts, :url, @url)

    headers =
      case Keyword.get(opts, :session) do
        nil -> %{}
        session_id -> %{"mcp-session-id" => session_id}
      end

    Req.post!(req(headers), [url: url, json: body] ++ Keyword.take(opts, [:into]))
  end

  defp initialize(opts \\ []) do
    resp =
      post(
        %{
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: %{
            protocolVersion: Keyword.get(opts, :version, @latest),
            capabilities: %{},
            clientInfo: %{name: "legacy-client", version: "0.4.2"}
          }
        },
        opts
      )

    assert resp.status == 200
    resp
  end

  defp session_id(resp) do
    assert %{"mcp-session-id" => [session_id]} = resp.headers
    session_id
  end

  # Opens a session and returns just its id, for the many tests that only need
  # to get past the handshake.
  defp open_session(opts \\ []) do
    opts |> initialize() |> session_id()
  end

  # A tool that answers `text` and does nothing else.
  defp stub_tool(name, call_fun) do
    ToolMock
    |> stub(:info, fn
      :name, _ -> name
      _, _ -> nil
    end)
    |> stub(:input_schema, fn _ -> %{type: :object} end)
    |> stub(:output_schema, fn _ -> nil end)
    |> stub(:call, call_fun)
  end

  defp sse_events(resp) do
    resp.body
    |> String.split("\n\n", trim: true)
    |> Enum.reject(&(&1 == ":keepalive"))
    |> Enum.map(fn chunk ->
      assert ["event: message", "data: " <> data] = String.split(chunk, "\n", trim: true)
      JSV.Codec.decode!(data)
    end)
  end

  # The `io.modelcontextprotocol/` namespace is the 2026 spec's own reserved
  # `_meta` prefix. A 2025 client knows none of those keys, so none of them
  # belong in a downgraded payload — whether the shim drops the offending keys
  # or the whole `_meta` is up to the fix.
  defp reserved_meta_keys(payload) do
    payload
    |> Map.get("_meta", %{})
    |> Map.keys()
    |> Enum.filter(&String.starts_with?(&1, "io.modelcontextprotocol/"))
  end

  # -- Handshake --------------------------------------------------------------

  describe "initialize" do
    test "answers a 2025 initialize result and mints a session id" do
      resp = initialize()

      assert %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "result" => %{
                 "protocolVersion" => @latest,
                 "serverInfo" => %{"name" => "Compat Server", "version" => "9.9.9"},
                 "capabilities" => capabilities
               }
             } = resp.body

      # 2025 capability values are objects, never booleans, and `logging` is
      # always advertised because the Suite emits log notifications.
      assert %{"logging" => %{}, "tools" => %{}} = capabilities

      assert is_binary(session_id(resp))
    end

    test "the initialize result carries no 2026-only discover fields" do
      # `server/discover` is what actually ran behind this response, so the
      # translation has to strip everything a 2025 client never saw.
      %{"result" => result} = initialize().body

      refute Map.has_key?(result, "resultType")
      refute Map.has_key?(result, "cacheScope")
      refute Map.has_key?(result, "ttlMs")
      refute Map.has_key?(result, "supportedVersions")
    end

    test "accepts the older 2025-06-18 protocol version and echoes it back" do
      assert %{"result" => %{"protocolVersion" => "2025-06-18"}} =
               initialize(version: "2025-06-18").body
    end

    test "answers an unknown protocol version with the newest supported one" do
      # 2025 spec: the server responds with a version it does support and lets
      # the client decide whether to carry on.
      assert %{"result" => %{"protocolVersion" => @latest}} =
               initialize(version: "1999-01-01").body
    end

    test "accepts notifications/initialized with 202 and no body" do
      resp = post(%{jsonrpc: "2.0", method: "notifications/initialized"})

      assert resp.status == 202
      assert resp.body == ""
    end
  end

  # -- Sessions ---------------------------------------------------------------

  describe "sessions" do
    test "a session id round-trips through a later request" do
      stub_tool("Add", fn _req, _channel, _arg -> {:result, MCP.call_tool_result(text: "ok")} end)

      session = open_session()

      assert %{"result" => %{"tools" => [%{"name" => "Add"}]}} =
               post(%{jsonrpc: "2.0", id: 2, method: "tools/list"}, session: session).body
    end

    test "rejects a request with no session id" do
      resp = post(%{jsonrpc: "2.0", id: 2, method: "tools/list"})

      assert resp.status == 400
      assert %{"error" => %{"message" => "Mcp-Session-Id header is required"}} = resp.body
    end

    test "answers 404 for a forged session id, telling the client to start over" do
      resp = post(%{jsonrpc: "2.0", id: 2, method: "tools/list"}, session: "not-a-real-token")

      assert resp.status == 404
      assert %{"error" => %{"message" => "Session not found or expired"}} = resp.body
    end

    test "answers 404 for a tampered session id" do
      session = open_session()

      # Tamper in the middle, not at the end. The token is unpadded base64url,
      # so its final character carries spare bits and two different final
      # characters can decode to the same bytes — an "edit" there sometimes
      # leaves a perfectly valid session and the test passes for the wrong
      # reason. A middle character always contributes six real bits.
      {head, <<char::utf8, tail::binary>>} =
        String.split_at(session, div(String.length(session), 2))

      replacement =
        if <<char::utf8>> == "X" do
          "Y"
        else
          "X"
        end

      tampered = head <> replacement <> tail

      refute tampered == session

      assert post(%{jsonrpc: "2.0", id: 2, method: "tools/list"}, session: tampered).status == 404
    end

    test "session lifetime is configurable through the controller arg" do
      # Sessions default to a day, but the controller's `arg` is handed through
      # as the token options, so a deployment picks its own without writing a
      # controller.
      conn = Plug.Conn.put_private(Plug.Test.conn(:post, "/"), :phoenix_endpoint, @endpoint)
      session = %{protocol_version: @latest, client_name: "c", client_version: "1"}

      hour = SessionController.expand({SessionController.Token, max_age: 3600})
      assert {:ok, id} = SessionController.create(hour, session, conn)
      assert {:ok, ^session} = SessionController.fetch(hour, id, conn)

      # Reading the same id under an already-elapsed max age reports expiry
      # rather than forgery, which is what drives the 404 back to the client.
      elapsed = SessionController.expand({SessionController.Token, max_age: -1})
      assert {:error, :expired} = SessionController.fetch(elapsed, id, conn)
    end

    test "a session minted with the default lifetime reads back" do
      # The exact default (a day) is not assertable here: the mint-time max age
      # is sealed inside the token, and passing `:max_age` to fetch overrides it
      # rather than revealing it, so any such assertion would pass for a 20
      # minute token too. What this pins is that minting with no options works
      # and round-trips; the value itself is pinned by the constant.
      conn = Plug.Conn.put_private(Plug.Test.conn(:post, "/"), :phoenix_endpoint, @endpoint)
      session = %{protocol_version: @latest, client_name: "c", client_version: "1"}

      default = SessionController.expand(SessionController.Token)

      assert {:ok, id} = SessionController.create(default, session, conn)
      assert {:ok, ^session} = SessionController.fetch(default, id, conn)
    end

    test "accepts DELETE as a no-op" do
      session = open_session()

      resp = Req.delete!(req(%{"mcp-session-id" => session}), url: @url)

      assert resp.status == 200
    end
  end

  # -- The point of the whole exercise ----------------------------------------

  describe "translation into the 2026 core" do
    test "a tool sees a 2026 request and the client info sealed in the session" do
      # Nothing 2025-shaped reaches the tool: it is handed a V2607
      # CallToolRequest, and `channel.meta` carries the client identity that
      # only the session knows, exactly as it would for a 2026 request.
      test_pid = self()

      stub_tool("Echo", fn req, channel, _arg ->
        send(test_pid, {:tool_called, req, channel})
        {:result, MCP.call_tool_result(text: "echoed")}
      end)

      session = open_session()

      post(
        %{
          jsonrpc: "2.0",
          id: 3,
          method: "tools/call",
          params: %{name: "Echo", arguments: %{"value" => 42}}
        },
        session: session
      )

      assert_receive {:tool_called, req, channel}

      assert %MCP.CallToolRequest{id: 3, params: %MCP.CallToolRequestParams{}} = req
      assert req.params.name == "Echo"
      assert req.params.arguments == %{"value" => 42}

      assert %Channel{meta: meta} = channel
      assert %MCP.Implementation{name: "legacy-client", version: "0.4.2"} = meta.client_info

      # The negotiated 2025 version, not 2026-07-28: a handler inspecting it
      # should see what the client actually speaks.
      assert meta.protocol_version == @latest
    end

    test "a 2025-06-18 session round-trips and the tool sees that version" do
      # Both supported 2025 versions have to work end to end, not just through
      # the handshake: the negotiated version is sealed into the session id, so
      # a client that handshook as 2025-06-18 must still be seen as 2025-06-18
      # by the tool on a later request.
      test_pid = self()

      stub_tool("Echo", fn req, channel, _arg ->
        send(test_pid, {:tool_called, req, channel})
        {:result, MCP.call_tool_result(text: "echoed")}
      end)

      session = open_session(version: "2025-06-18")

      resp =
        post(
          %{
            jsonrpc: "2.0",
            id: 3,
            method: "tools/call",
            params: %{name: "Echo", arguments: %{"value" => 42}}
          },
          session: session
        )

      assert %{"result" => %{"content" => [%{"text" => "echoed"}]}} = resp.body

      assert_receive {:tool_called, req, channel}

      assert req.params.name == "Echo"
      assert %Channel{meta: meta} = channel
      assert %MCP.Implementation{name: "legacy-client", version: "0.4.2"} = meta.client_info
      assert meta.protocol_version == "2025-06-18"
    end

    test "a 2025 progressToken reaches the channel and drives progress notifications" do
      stub_tool("Slow", fn _req, channel, _arg ->
        :ok = Channel.send_progress(channel, 1, 2, "halfway")
        {:result, MCP.call_tool_result(text: "done")}
      end)

      session = open_session()

      resp =
        post(
          %{
            jsonrpc: "2.0",
            id: 4,
            method: "tools/call",
            params: %{
              name: "Slow",
              arguments: %{},
              _meta: %{progressToken: "tok-1"}
            }
          },
          session: session
        )

      assert [progress, result] = sse_events(resp)

      assert %{
               "method" => "notifications/progress",
               "params" => %{"progressToken" => "tok-1", "progress" => 1, "total" => 2}
             } = progress

      assert %{"id" => 4, "result" => %{"content" => [%{"text" => "done"}]}} = result
    end

    test "a tool's log notifications arrive on the POST's own SSE response" do
      # `initialize` advertises the `logging` capability unconditionally, and
      # `logging/setLevel` is not part of this slice, so the level a 2025 client
      # gets is whatever the transport puts in the synthesized request `_meta`.
      # Whatever that default is, an `:info` record has to reach the client —
      # otherwise the advertised capability is a promise the server never keeps.
      stub_tool("Chatty", fn _req, channel, _arg ->
        :ok = Channel.send_log(channel, :info, "hello")
        {:result, MCP.call_tool_result(text: "done")}
      end)

      session = open_session()

      resp =
        post(
          %{
            jsonrpc: "2.0",
            id: 15,
            method: "tools/call",
            params: %{name: "Chatty", arguments: %{}}
          },
          session: session
        )

      assert is_binary(resp.body),
             "expected an SSE response carrying the log record, got a plain body: " <>
               inspect(resp.body)

      assert [log, result] = sse_events(resp)

      assert %{
               "method" => "notifications/message",
               "params" => %{"level" => "info", "data" => "hello"}
             } = log

      assert %{"id" => 15, "result" => %{"content" => [%{"text" => "done"}]}} = result
    end

    test "tools/list results are stripped of 2026-only fields" do
      stub_tool("Add", fn _req, _channel, _arg -> {:result, MCP.call_tool_result(text: "ok")} end)

      session = open_session()

      %{"result" => result} =
        post(%{jsonrpc: "2.0", id: 5, method: "tools/list"}, session: session).body

      assert %{"tools" => [%{"name" => "Add", "inputSchema" => %{"type" => "object"}}]} = result

      refute Map.has_key?(result, "resultType")
      refute Map.has_key?(result, "cacheScope")
      refute Map.has_key?(result, "ttlMs")
    end

    test "tools/call results are stripped of 2026-only fields" do
      stub_tool("Add", fn _req, _channel, _arg -> {:result, MCP.call_tool_result(text: "3")} end)

      session = open_session()

      %{"result" => result} =
        post(
          %{jsonrpc: "2.0", id: 6, method: "tools/call", params: %{name: "Add", arguments: %{}}},
          session: session
        ).body

      assert %{"content" => [%{"type" => "text", "text" => "3"}]} = result
      refute Map.has_key?(result, "resultType")
    end

    test "no 2026 reserved _meta keys ride along on a tools/call result" do
      stub_tool("Add", fn _req, _channel, _arg -> {:result, MCP.call_tool_result(text: "3")} end)

      session = open_session()

      %{"result" => result} =
        post(
          %{jsonrpc: "2.0", id: 16, method: "tools/call", params: %{name: "Add", arguments: %{}}},
          session: session
        ).body

      assert reserved_meta_keys(result) == []
    end

    test "no 2026 reserved _meta keys ride along on a tools/list result" do
      stub_tool("Add", fn _req, _channel, _arg -> {:result, MCP.call_tool_result(text: "ok")} end)

      session = open_session()

      %{"result" => result} =
        post(%{jsonrpc: "2.0", id: 17, method: "tools/list"}, session: session).body

      assert reserved_meta_keys(result) == []
    end

    test "a tool error is reported as a 2025 isError result" do
      stub_tool("Boom", fn _req, _channel, _arg ->
        {:result, MCP.call_tool_result(error: "it broke")}
      end)

      session = open_session()

      assert %{"result" => %{"isError" => true, "content" => [%{"text" => "it broke"}]}} =
               post(
                 %{
                   jsonrpc: "2.0",
                   id: 7,
                   method: "tools/call",
                   params: %{name: "Boom", arguments: %{}}
                 },
                 session: session
               ).body
    end
  end

  # -- Subscription ids -------------------------------------------------------

  describe "subscription ids are stripped from notifications" do
    # `GenMCP.Mux.Channel` stamps `io.modelcontextprotocol/subscriptionId` into
    # the `params._meta` of every subscription-family notification, keyed to the
    # channel's request id. On a POST that id is the JSON-RPC id, so a tool that
    # emits a `list_changed` notification gets one stamped — and a 2025 client
    # has no subscription to route it to.

    test "from a notification that carries its own struct _meta" do
      stub_tool("Notifier", fn _req, channel, _arg ->
        :ok =
          Channel.send_notification(channel, %MCP.ToolListChangedNotification{
            params: %MCP.NotificationParams{_meta: %MCP.NotificationMetaObject{}}
          })

        {:result, MCP.call_tool_result(text: "done")}
      end)

      session = open_session()

      resp =
        post(
          %{
            jsonrpc: "2.0",
            id: 18,
            method: "tools/call",
            params: %{name: "Notifier", arguments: %{}}
          },
          session: session
        )

      assert [notif, _result] = sse_events(resp)
      assert notif["method"] == "notifications/tools/list_changed"

      # The subscription id was the only thing in that `_meta`, so nothing is
      # left to send: the key goes away rather than travelling as an empty
      # object a 2025 client would have to ignore.
      refute Map.has_key?(Map.get(notif, "params") || %{}, "_meta")
    end

    test "from a plain string-keyed notification" do
      # `Channel.send_notification/2` accepts a plain map carrying a `method`,
      # and stamps the id under string keys for one. That shape has to be
      # stripped too.
      stub_tool("Notifier", fn _req, channel, _arg ->
        :ok =
          Channel.send_notification(channel, %{
            "jsonrpc" => "2.0",
            "method" => "notifications/tools/list_changed"
          })

        {:result, MCP.call_tool_result(text: "done")}
      end)

      session = open_session()

      resp =
        post(
          %{
            jsonrpc: "2.0",
            id: 19,
            method: "tools/call",
            params: %{name: "Notifier", arguments: %{}}
          },
          session: session
        )

      assert [notif, _result] = sse_events(resp)
      assert notif["method"] == "notifications/tools/list_changed"

      refute get_in(notif, ["params", "_meta", "io.modelcontextprotocol/subscriptionId"])
    end
  end

  # -- Resources --------------------------------------------------------------

  describe "resources" do
    setup do
      stub(ResourceRepoMock, :prefix, fn :compat_repo -> "ui://" end)
      :ok
    end

    test "the handshake advertises the resources capability" do
      resp = initialize(url: @res_url)

      assert %{"result" => %{"capabilities" => capabilities}} = resp.body
      assert Map.has_key?(capabilities, "resources")
    end

    test "the handshake does not advertise resources/subscribe" do
      stub(SubscriptionHandlerFullMock, :subscription_capabilities, fn _channel, _arg ->
        %{resources_updated: true}
      end)

      resp = initialize(url: "/mcp/v2511-sub-full")

      assert %{"result" => %{"capabilities" => %{"resources" => resources}}} = resp.body

      # On 2025 the flag promises `resources/subscribe`, which the shim answers
      # with -32601. Its update notifications ride the GET stream instead.
      refute Map.has_key?(resources, "subscribe")
    end

    test "resources/list downgrades the 2026 result" do
      expect(ResourceRepoMock, :list, fn nil, _channel, :compat_repo ->
        {[%{uri: "ui://app/main", name: "main", mimeType: "text/html"}], nil}
      end)

      session = open_session(url: @res_url)

      resp =
        post(%{jsonrpc: "2.0", id: 30, method: "resources/list"},
          session: session,
          url: @res_url
        )

      assert resp.status == 200

      assert %{"result" => result} = resp.body
      assert [%{"uri" => "ui://app/main", "name" => "main"}] = result["resources"]

      # 2026-only fields must not reach a 2025 client.
      refute Map.has_key?(result, "resultType")
      refute Map.has_key?(result, "cacheScope")
      refute Map.has_key?(result, "ttlMs")
    end

    test "a resources/list cursor round-trips to the next page" do
      ResourceRepoMock
      |> expect(:list, fn nil, _channel, :compat_repo ->
        {[%{uri: "ui://app/one", name: "one"}], "page-2"}
      end)
      |> expect(:list, fn "page-2", _channel, :compat_repo ->
        {[%{uri: "ui://app/two", name: "two"}], nil}
      end)

      session = open_session(url: @res_url)

      first =
        post(%{jsonrpc: "2.0", id: 31, method: "resources/list"},
          session: session,
          url: @res_url
        )

      assert %{"result" => %{"nextCursor" => cursor}} = first.body
      assert is_binary(cursor)

      second =
        post(
          %{jsonrpc: "2.0", id: 32, method: "resources/list", params: %{cursor: cursor}},
          session: session,
          url: @res_url
        )

      assert second.status == 200
      assert %{"result" => result} = second.body
      assert [%{"uri" => "ui://app/two"}] = result["resources"]
      refute Map.has_key?(result, "nextCursor")
    end

    test "resources/list rejects a non-string cursor" do
      session = open_session(url: @res_url)

      resp =
        post(
          %{jsonrpc: "2.0", id: 32, method: "resources/list", params: %{cursor: 12}},
          session: session,
          url: @res_url
        )

      assert resp.status == 400
      assert %{"error" => %{"code" => -32_602}} = resp.body
    end

    test "resources/read returns the contents" do
      expect(ResourceRepoMock, :read, fn "ui://app/main", _channel, :compat_repo ->
        {:ok, MCP.read_resource_result(uri: "ui://app/main", text: "<h1>Hi</h1>")}
      end)

      session = open_session(url: @res_url)

      resp =
        post(
          %{jsonrpc: "2.0", id: 33, method: "resources/read", params: %{uri: "ui://app/main"}},
          session: session,
          url: @res_url
        )

      assert resp.status == 200
      assert %{"result" => result} = resp.body
      assert [%{"uri" => "ui://app/main", "text" => "<h1>Hi</h1>"}] = result["contents"]
      refute Map.has_key?(result, "resultType")
    end

    test "resources/read answers a missing resource with the 2025 error code" do
      expect(ResourceRepoMock, :read, fn "ui://app/missing", _channel, :compat_repo ->
        {:error, :not_found}
      end)

      session = open_session(url: @res_url)

      resp =
        post(
          %{jsonrpc: "2.0", id: 36, method: "resources/read", params: %{uri: "ui://app/missing"}},
          session: session,
          url: @res_url
        )

      assert resp.status == 200

      # 2026 retired -32002 for the standard -32602; a 2025 client still gets
      # the code its own spec defines.
      assert %{"error" => %{"code" => -32_002, "data" => %{"uri" => "ui://app/missing"}}} =
               resp.body
    end

    test "resources/read requires a uri" do
      session = open_session(url: @res_url)

      resp =
        post(%{jsonrpc: "2.0", id: 34, method: "resources/read"},
          session: session,
          url: @res_url
        )

      assert resp.status == 400
      assert %{"error" => %{"code" => -32_602}} = resp.body
    end

    test "resources/templates/list is served" do
      session = open_session(url: @res_url)

      resp =
        post(%{jsonrpc: "2.0", id: 35, method: "resources/templates/list"},
          session: session,
          url: @res_url
        )

      assert resp.status == 200
      assert %{"result" => %{"resourceTemplates" => []}} = resp.body
    end
  end

  # -- Rejections -------------------------------------------------------------

  describe "unsupported surface" do
    test "answers -32601 for a method outside the compat surface" do
      session = open_session()

      resp = post(%{jsonrpc: "2.0", id: 8, method: "prompts/list"}, session: session)

      # 200, not the 404 the 2026 transport answers for an unknown method: a
      # 2025 client reads 404 as "session gone, run initialize again", so a
      # refused method must not borrow that status.
      assert resp.status == 200

      assert %{"error" => %{"code" => -32_601, "data" => %{"method" => "prompts/list"}}} =
               resp.body
    end

    test "answers -32601 for a method outside the protocol entirely" do
      session = open_session()

      resp = post(%{jsonrpc: "2.0", id: 21, method: "not/a/method"}, session: session)

      assert resp.status == 200
      assert %{"error" => %{"code" => -32_601}} = resp.body
    end

    test "a dead session is still the only thing answered 404" do
      # The counterpart to the two tests above: 404 keeps meaning what the 2025
      # spec says it means, so the client can still tell the cases apart.
      resp = post(%{jsonrpc: "2.0", id: 22, method: "prompts/list"}, session: "not-a-session")

      assert resp.status == 404
      assert %{"error" => %{"message" => "Session not found or expired"}} = resp.body
    end

    test "answers ping without touching the session" do
      assert %{"id" => 9, "result" => %{}} = post(%{jsonrpc: "2.0", id: 9, method: "ping"}).body
    end

    test "accepts logging/setLevel instead of failing the client" do
      # A client sets its level during setup and has no reason to expect a
      # failure, so this is accepted and ignored rather than answered -32601.
      # The level cannot be honored — the token session is immutable — so what
      # the client actually gets is the transport's default level.
      assert %{"id" => 20, "result" => %{}} =
               post(
                 %{
                   jsonrpc: "2.0",
                   id: 20,
                   method: "logging/setLevel",
                   params: %{level: "debug"}
                 },
                 session: open_session()
               ).body
    end

    test "rejects a tools/call with no tool name" do
      session = open_session()

      resp =
        post(%{jsonrpc: "2.0", id: 10, method: "tools/call", params: %{}}, session: session)

      assert resp.status == 400
      assert %{"error" => %{"code" => -32_602}} = resp.body
    end

    # There is no 2025 schema to validate a body against, so the envelope is
    # checked by hand. These pin that a malformed body is rejected as a
    # JSON-RPC error rather than crashing the connection process.
    test "rejects a non-object params" do
      session = open_session()

      resp =
        post(%{jsonrpc: "2.0", id: 12, method: "tools/call", params: "oops"}, session: session)

      assert resp.status == 400
      assert %{"error" => %{"code" => -32_602, "message" => message}} = resp.body
      assert message =~ "params must be an object"
    end

    test "rejects a non-scalar JSON-RPC id" do
      session = open_session()

      resp =
        post(%{jsonrpc: "2.0", id: %{"nope" => 1}, method: "tools/list"}, session: session)

      assert resp.status == 400
      assert %{"error" => %{"code" => -32_600}} = resp.body
    end

    test "rejects non-object tools/call arguments" do
      session = open_session()

      resp =
        post(
          %{
            jsonrpc: "2.0",
            id: 13,
            method: "tools/call",
            params: %{name: "Add", arguments: "oops"}
          },
          session: session
        )

      assert resp.status == 400
      assert %{"error" => %{"code" => -32_602, "message" => message}} = resp.body
      assert message =~ "params.arguments must be an object"
    end

    test "ignores a malformed _meta instead of failing the request" do
      # `_meta` carries only optional hints, and 2025 clients are known to put
      # odd things there, so a bad one costs the client its progress reports
      # and nothing else.
      stub_tool("Add", fn _req, _channel, _arg -> {:result, MCP.call_tool_result(text: "ok")} end)

      session = open_session()

      assert %{"result" => %{"tools" => [_]}} =
               post(
                 %{jsonrpc: "2.0", id: 14, method: "tools/list", params: %{_meta: "nope"}},
                 session: session
               ).body
    end

    @tag :capture_log
    test "an input_required return becomes an internal error, not a client fault" do
      # MRTR has no 2025 equivalent. Per feature 017 this is a server-side
      # contract violation: the worker crashes and the client is told the
      # server failed, never that its request was faulty.
      stub_tool("Wizard", fn _req, _channel, _arg ->
        {:input_required, %{}, "state"}
      end)

      session = open_session()

      resp =
        post(
          %{
            jsonrpc: "2.0",
            id: 11,
            method: "tools/call",
            params: %{name: "Wizard", arguments: %{}}
          },
          session: session
        )

      assert resp.status == 500
      assert %{"error" => %{"code" => -32_603, "message" => "Internal server error"}} = resp.body
    end
  end

  # -- The GET stream ---------------------------------------------------------

  describe "GET stream" do
    test "answers 405 when no subscription handler is configured" do
      session = open_session()

      resp = Req.get!(req(%{"mcp-session-id" => session}), url: @url)

      assert resp.status == 405
    end

    test "serves notifications from the subscription handler with no 2026 vocabulary" do
      test_pid = self()

      SubscriptionHandlerMock
      |> expect(:subscribe, fn %MCP.SubscriptionFilter{} = filter, _channel, _arg ->
        # The GET stream asks for everything and lets the handler narrow it.
        assert filter.toolsListChanged
        send(test_pid, {:subscribed, self()})
        {:stream, %{}}
      end)
      |> expect(:handle_message, fn :tools_changed, channel, _state, _arg ->
        :ok = Channel.send_notification(channel, %MCP.ToolListChangedNotification{})
        {:stop, :normal}
      end)

      session = open_session(url: @sub_url)

      task =
        Task.async(fn ->
          Req.get!(req(%{"mcp-session-id" => session}), url: @sub_url)
        end)

      assert_receive {:subscribed, worker}
      send(worker, :tools_changed)

      resp = Task.await(task, to_timeout(second: 10))

      assert resp.status == 200
      assert [notification] = sse_events(resp)

      # The 2025 client gets a bare notification: no JSON-RPC envelope wrapping
      # it, and no subscription id it could not route.
      assert %{"jsonrpc" => "2.0", "method" => "notifications/tools/list_changed"} = notification
      refute get_in(notification, ["params", "_meta", "io.modelcontextprotocol/subscriptionId"])

      # The acknowledgment that opened the 2026 subscription is not on the wire.
      refute notification["method"] == "notifications/subscriptions/acknowledged"
    end

    test "a handler crash after the stream is open just ends the stream" do
      # 405 is the right answer while nothing has been written — it is what a
      # GET gets when no subscription handler is configured. Once the stream is
      # open the status is gone and the payload would be chunked as an SSE
      # event, so a 2025 client reading bare notifications there would parse
      # `{"error": "Method Not Allowed"}` as one.
      test_pid = self()

      SubscriptionHandlerMock
      |> expect(:subscribe, fn %MCP.SubscriptionFilter{}, _channel, _arg ->
        send(test_pid, {:subscribed, self()})
        {:stream, %{}}
      end)
      |> expect(:handle_message, fn :tools_changed, channel, state, _arg ->
        # Opens the stream, so the crash below happens mid-stream.
        :ok = Channel.send_notification(channel, %MCP.ToolListChangedNotification{})
        {:stream, state}
      end)
      |> expect(:handle_message, fn :boom, _channel, _state, _arg ->
        raise "handler blew up"
      end)

      session = open_session(url: @sub_url)

      {resp, _log} =
        with_log(fn ->
          task =
            Task.async(fn ->
              Req.get!(req(%{"mcp-session-id" => session}), url: @sub_url)
            end)

          assert_receive {:subscribed, worker}
          send(worker, :tools_changed)
          send(worker, :boom)

          Task.await(task, to_timeout(second: 10))
        end)

      assert resp.status == 200

      assert [notification] = sse_events(resp)
      assert notification["method"] == "notifications/tools/list_changed"
    end

    test "a client dropping the GET stream tears the subscription down" do
      # A 2025 client holds this stream open for the whole conversation and then
      # simply goes away. The relay notices on its next write, and the handler's
      # `handle_close/3` runs its cleanup.
      #
      # This does not distinguish the relay's explicit `{:"$gen_mcp", :closed}`
      # from the `:CHAN_DOWN` monitor that fires when this connection process
      # exits — both reach `handle_close/3`, and the test passes either way
      # (checked by reverting the message). What it does pin is that dropping
      # the GET stream tears the subscription down at all, which is the part a
      # 2025 client depends on for its server-side resources to be released.
      test_pid = self()

      SubscriptionHandlerFullMock
      |> stub(:subscription_capabilities, fn _channel, _arg -> %{tools_list_changed: true} end)
      |> expect(:subscribe, fn %MCP.SubscriptionFilter{}, _channel, _arg ->
        send(test_pid, {:subscribed, self()})
        {:stream, %{}}
      end)
      # Keeps writing so the dropped socket is noticed promptly: a disconnect is
      # detected on the next write, not by the 25s keepalive.
      |> stub(:handle_message, fn :tick, channel, state, _arg ->
        :ok = Channel.send_notification(channel, %MCP.ToolListChangedNotification{})
        Process.send_after(self(), :tick, 50)
        {:stream, state}
      end)
      |> expect(:handle_close, fn channel, _state, _arg ->
        send(test_pid, {:torn_down, channel.status})
        :ok
      end)

      session = open_session(url: "/mcp/v2511-sub-full")

      # `:into` streams the body, so the task can read one event and then drop
      # the connection mid-stream instead of waiting for the response to end.
      task =
        Task.async(fn ->
          Req.get!(req(%{"mcp-session-id" => session}),
            url: "/mcp/v2511-sub-full",
            into: fn {:data, _data}, acc -> {:halt, acc} end
          )
        end)

      assert_receive {:subscribed, worker}
      send(worker, :tick)

      # The client is gone once the task returns; the handler sees it on the
      # next push.
      Task.await(task, to_timeout(second: 10))

      assert_receive {:torn_down, :closed}, 2000
    end

    test "rejects a GET with no session id" do
      assert Req.get!(req(), url: @sub_url).status == 400
    end
  end
end
