defmodule GenMCP.Suite.SubscriptionsTest do
  use ExUnit.Case, async: true

  # Spec 008 — `subscriptions/listen` wiring in `GenMCP.Suite`.
  #
  # The Suite is driven exactly as the per-request worker drives any `GenMCP`
  # implementation (see `GenMCP.SuiteTest`):
  #
  #     {:ok, state} = Suite.init(server_opts)
  #     Suite.handle_request(req, channel, state)  # {:stream, state} | {:error, _}
  #     Suite.handle_message(msg, channel, state)  # only after {:stream, _}
  #     Suite.handle_close(channel, state)         # on client disconnect
  #
  # A configured `subscription_handler` receives the listen request through the
  # Suite-internal `GenMCP.Suite.SubscriptionHandler` behaviour. The Suite always
  # sends `notifications/subscriptions/acknowledged` as the first stream message
  # (the handler never does), stamped with the listen request's id as
  # `io.modelcontextprotocol/subscriptionId` (via `Channel.send_notification/2`).

  import Mox

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.Suite
  alias GenMCP.Support.SubscriptionHandlerFullMock
  alias GenMCP.Support.SubscriptionHandlerMock

  setup :verify_on_exit!

  # The reverse-DNS `_meta` key every stream message must carry, equal to the
  # JSON-RPC id of the `subscriptions/listen` request.
  @sub_id_key :"io.modelcontextprotocol/subscriptionId"

  @server_info [server_name: "Test Server", server_version: "0"]

  defp init_suite(server_opts \\ []) do
    assert {:ok, state} = Suite.init(Keyword.merge(@server_info, server_opts))
    state
  end

  defp subscription_filter(fields) do
    struct(MCP.SubscriptionFilter, fields)
  end

  defp listen_req(notifications, id) do
    %MCP.SubscriptionsListenRequest{
      id: id,
      params: %MCP.SubscriptionsListenRequestParams{_meta: nil, notifications: notifications}
    }
  end

  # The channel is built from the request so `request_id` carries the listen id;
  # the test process plays the transport relay role and receives the messages.
  defp listen_channel(req) do
    Channel.from_request(nil, req, %{})
  end

  describe "subscriptions/listen — handle_request" do
    test "accepts, sends acknowledged first reporting the requested filter, then streams" do
      requested = subscription_filter(toolsListChanged: true, resourcesListChanged: true)

      expect(SubscriptionHandlerMock, :subscribe, fn ^requested, _channel, :arg ->
        {:stream, :handler_state_0}
      end)

      state = init_suite(subscription_handler: {SubscriptionHandlerMock, :arg})
      req = listen_req(requested, 7)
      channel = listen_channel(req)

      assert {:stream, _state} = Suite.handle_request(req, channel, state)

      assert_receive {:"$gen_mcp", :notification, ack}
      assert %MCP.SubscriptionsAcknowledgedNotification{params: params} = ack
      # full requested filter reported
      assert params.notifications.toolsListChanged == true
      assert params.notifications.resourcesListChanged == true
      # stamped with the listen request id
      assert Map.get(params._meta, @sub_id_key) == 7
    end

    test "{:stream, honored, state} reports the honored (downgraded) filter in the ack" do
      requested = subscription_filter(toolsListChanged: true, resourcesListChanged: true)
      honored = subscription_filter(toolsListChanged: true)

      expect(SubscriptionHandlerMock, :subscribe, fn ^requested, _channel, :arg ->
        {:stream, honored, :handler_state_0}
      end)

      state = init_suite(subscription_handler: {SubscriptionHandlerMock, :arg})
      req = listen_req(requested, 1)
      channel = listen_channel(req)

      assert {:stream, _state} = Suite.handle_request(req, channel, state)

      assert_receive {:"$gen_mcp", :notification, ack}
      assert %MCP.SubscriptionsAcknowledgedNotification{params: params} = ack
      assert params.notifications.toolsListChanged == true
      # downgraded: the un-honored type is not reported as subscribed
      refute params.notifications.resourcesListChanged == true
    end

    test "{:stop, reason} rejects: error response, no ack, no stream" do
      requested = subscription_filter(toolsListChanged: true)

      expect(SubscriptionHandlerMock, :subscribe, fn ^requested, _channel, :arg ->
        {:stop, :unauthorized}
      end)

      state = init_suite(subscription_handler: {SubscriptionHandlerMock, :arg})
      req = listen_req(requested, 1)
      channel = listen_channel(req)

      assert {:error, :unauthorized} = Suite.handle_request(req, channel, state)
      refute_receive {:"$gen_mcp", :notification, _}
    end

    test "a listen request with no configured handler is method-not-found, no ack" do
      state = init_suite()
      req = listen_req(subscription_filter(toolsListChanged: true), 1)
      channel = listen_channel(req)

      # No handler configured ⇒ the Suite does not support subscriptions: same
      # -32601 method-not-found the catch-all returns for any unhandled method.
      assert {:error, {:unsupported_method, "subscriptions/listen"}} =
               Suite.handle_request(req, channel, state)

      refute_receive {:"$gen_mcp", :notification, _}
    end
  end

  describe "subscriptions/listen — streaming" do
    test "forwards stream messages to the handler's handle_message/4, stamping subscriptionId" do
      requested = subscription_filter(toolsListChanged: true)

      SubscriptionHandlerMock
      |> expect(:subscribe, fn _filter, _channel, :arg -> {:stream, :s0} end)
      |> expect(:handle_message, fn :some_tools_changed, channel, :s0, :arg ->
        :ok = Channel.send_notification(channel, %MCP.ToolListChangedNotification{})
        {:stream, :s1}
      end)
      |> expect(:handle_message, fn :bye, _channel, :s1, :arg -> {:stop, :done} end)

      state = init_suite(subscription_handler: {SubscriptionHandlerMock, :arg})
      req = listen_req(requested, 9)
      channel = listen_channel(req)

      assert {:stream, state} = Suite.handle_request(req, channel, state)
      assert_receive {:"$gen_mcp", :notification, %MCP.SubscriptionsAcknowledgedNotification{}}

      assert {:stream, state} = Suite.handle_message(:some_tools_changed, channel, state)

      assert_receive {:"$gen_mcp", :notification, notif}
      assert %MCP.ToolListChangedNotification{} = notif
      assert Map.get(notif.params._meta, @sub_id_key) == 9

      # {:stop, reason} ends the stream with no final result
      assert {:stop, :done} = Suite.handle_message(:bye, channel, state)
    end

    test "forwards client disconnect to the handler's handle_close/3" do
      test_pid = self()
      requested = subscription_filter(toolsListChanged: true)

      SubscriptionHandlerFullMock
      |> expect(:subscribe, fn _filter, _channel, :arg -> {:stream, :s0} end)
      |> expect(:handle_close, fn channel, :s0, :arg ->
        send(test_pid, {:subscription_closed, channel.status})
        :ok
      end)

      state = init_suite(subscription_handler: {SubscriptionHandlerFullMock, :arg})
      req = listen_req(requested, 1)
      channel = listen_channel(req)

      assert {:stream, state} = Suite.handle_request(req, channel, state)
      assert_receive {:"$gen_mcp", :notification, %MCP.SubscriptionsAcknowledgedNotification{}}

      # The worker passes the channel already marked closed.
      closed = %{channel | status: :closed}
      Suite.handle_close(closed, state)

      assert_receive {:subscription_closed, :closed}
    end
  end
end
