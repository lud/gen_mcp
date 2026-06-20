defmodule GenMCP.ChannelTest do
  use ExUnit.Case, async: true

  import GenMCP.Test.Helpers

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.MCP.V2607.LoggingMessageNotification
  alias GenMCP.Mux.Channel

  # The reverse-DNS `_meta` key that demultiplexes a subscription stream. Its
  # value is the JSON-RPC id of the `subscriptions/listen` request (= the
  # channel's `request_id`). See spec 008.
  @sub_id_key :"io.modelcontextprotocol/subscriptionId"
  @sub_id_key_str "io.modelcontextprotocol/subscriptionId"

  describe "send_log/4" do
    test "sends log when level is at or above channel log level" do
      channel = %{build_channel() | log_level: :warning}

      assert :ok = Channel.send_log(channel, :error, "an error occurred")
      assert_receive {:"$gen_mcp", :notification, notification}

      assert %LoggingMessageNotification{
               params: %{level: :error, data: "an error occurred", logger: nil}
             } = notification
    end

    test "sends log at exact level match" do
      channel = %{build_channel() | log_level: :warning}

      assert :ok = Channel.send_log(channel, :warning, "a warning")
      assert_receive {:"$gen_mcp", :notification, _}
    end

    test "filters log below channel log level" do
      channel = %{build_channel() | log_level: :warning}

      assert :ok = Channel.send_log(channel, :info, "just info")
      refute_receive {:"$gen_mcp", :notification, _}
    end

    test "includes logger name when provided" do
      channel = %{build_channel() | log_level: :warning}

      assert :ok = Channel.send_log(channel, :error, "db error", "database")
      assert_receive {:"$gen_mcp", :notification, notification}

      assert %LoggingMessageNotification{
               params: %{level: :error, data: "db error", logger: "database"}
             } = notification
    end

    test "returns error when channel is closed" do
      channel = Channel.as_closed(build_channel())

      assert {:error, :closed} = Channel.send_log(channel, :error, "won't send")
      refute_receive {:"$gen_mcp", :notification, _}
    end

    test "supports structured data" do
      channel = %{build_channel() | log_level: :warning}

      data = %{"error" => "Connection failed", "host" => "localhost"}
      assert :ok = Channel.send_log(channel, :error, data)
      assert_receive {:"$gen_mcp", :notification, notification}

      assert %LoggingMessageNotification{params: %{data: ^data}} = notification
    end

    # The primary MUST of spec 011: a request that did not declare
    # `io.modelcontextprotocol/logLevel` has `log_level: nil` and logging is
    # disabled — `send_log` must emit nothing (no library default level). It must
    # still be safe to call unconditionally from a handler, so it returns `:ok`.
    test "is a no-op when logging is disabled (channel log_level is nil)" do
      channel = build_channel()
      assert channel.log_level == nil

      assert :ok = Channel.send_log(channel, :error, "should be dropped")
      assert :ok = Channel.send_log(channel, :emergency, "even the most severe")
      refute_receive {:"$gen_mcp", :notification, _}
    end

    test "returns {:error, :invalid_level} for an unrecognized level" do
      channel = %{build_channel() | log_level: :warning}

      assert {:error, :invalid_level} = Channel.send_log(channel, :verbose, "nope")
      refute_receive {:"$gen_mcp", :notification, _}
    end
  end

  # The verbosity is declared per-request in the request `_meta`
  # `io.modelcontextprotocol/logLevel`; there is no stateful `logging/setLevel`
  # and no library default. `from_request/2` lifts the level into the channel,
  # defaulting to `nil` (disabled) whenever it is absent or unrecognized. The
  # transport rejects an unrecognized level upstream with `-32602` (see the
  # streamable_http logging tests), so in practice the channel only holds a valid
  # level or `nil`. See spec 011.
  describe "from_request/2 — per-request log level (spec 011)" do
    test "reads io.modelcontextprotocol/logLevel from _meta into log_level" do
      req = %MCP.CallToolRequest{
        id: 1,
        params: %{_meta: %{"io.modelcontextprotocol/logLevel": :warning}}
      }

      channel = Channel.from_request(nil, req, %{})

      assert channel.log_level == :warning
    end

    test "log_level is nil when the request omits the level (logging disabled)" do
      req = %MCP.CallToolRequest{id: 1, params: %{_meta: %{}}}

      channel = Channel.from_request(nil, req, %{})

      assert channel.log_level == nil
    end

    test "log_level is nil when params carry no _meta" do
      req = %MCP.CallToolRequest{id: 1, params: %{}}

      channel = Channel.from_request(nil, req, %{})

      assert channel.log_level == nil
    end

    test "an unrecognized level falls back to nil" do
      req = %MCP.CallToolRequest{
        id: 1,
        params: %{_meta: %{"io.modelcontextprotocol/logLevel": :verbose}}
      }

      channel = Channel.from_request(nil, req, %{})

      assert channel.log_level == nil
    end
  end

  describe "request_id" do
    test "is set from the JSON-RPC id for a request" do
      req = %MCP.CallToolRequest{id: 42, params: nil}
      channel = Channel.from_request(nil, req, %{})

      assert channel.request_id == 42
    end

    test "preserves a string JSON-RPC id" do
      req = %MCP.CallToolRequest{id: "req-7", params: nil}
      channel = Channel.from_request(nil, req, %{})

      assert channel.request_id == "req-7"
    end

    test "is nil for a notification-built channel (notifications have no id)" do
      notif = %MCP.ToolListChangedNotification{}
      channel = Channel.from_request(nil, notif, %{})

      assert channel.request_id == nil
    end

    test "is nil for for_pid/2" do
      channel = Channel.for_pid(self())

      assert channel.request_id == nil
    end
  end

  describe "send_notification/2 — subscriptionId stamping" do
    test "stamps a schema struct payload (atom key form)" do
      channel = %{build_channel() | request_id: 99}

      assert :ok = Channel.send_notification(channel, %MCP.ToolListChangedNotification{})
      assert_receive {:"$gen_mcp", :notification, payload}

      assert %MCP.ToolListChangedNotification{} = payload
      meta = payload.params._meta
      assert Map.get(meta, @sub_id_key) == 99
    end

    test "stamps an atom-keyed raw map, keeping the atom key form" do
      channel = %{build_channel() | request_id: 99}
      input = %{method: "notifications/tools/list_changed", params: %{}}

      assert :ok = Channel.send_notification(channel, input)
      assert_receive {:"$gen_mcp", :notification, payload}

      assert %{params: %{_meta: meta}} = payload
      assert Map.get(meta, @sub_id_key) == 99
      assert Map.has_key?(meta, @sub_id_key)
      refute Map.has_key?(meta, @sub_id_key_str)
    end

    test "stamps a string-keyed raw map, keeping the string key form" do
      channel = %{build_channel() | request_id: 99}
      input = %{"method" => "notifications/tools/list_changed", "params" => %{}}

      assert :ok = Channel.send_notification(channel, input)
      assert_receive {:"$gen_mcp", :notification, payload}

      assert %{"params" => %{"_meta" => meta}} = payload
      assert Map.get(meta, @sub_id_key_str) == 99
      assert Map.has_key?(meta, @sub_id_key_str)
      refute Map.has_key?(meta, @sub_id_key)
    end

    test "creates params and _meta containers when absent (atom-keyed payload)" do
      channel = %{build_channel() | request_id: 7}
      input = %{method: "notifications/resources/list_changed"}

      assert :ok = Channel.send_notification(channel, input)
      assert_receive {:"$gen_mcp", :notification, payload}

      assert %{params: %{_meta: meta}} = payload
      assert Map.get(meta, @sub_id_key) == 7
    end

    test "does not overwrite a pre-existing subscriptionId" do
      channel = %{build_channel() | request_id: 99}

      input = %{
        method: "notifications/tools/list_changed",
        params: %{_meta: %{@sub_id_key => "PRESET"}}
      }

      assert :ok = Channel.send_notification(channel, input)
      assert_receive {:"$gen_mcp", :notification, payload}

      assert %{params: %{_meta: meta}} = payload
      assert Map.get(meta, @sub_id_key) == "PRESET"
    end

    test "preserves other _meta keys while adding subscriptionId" do
      channel = %{build_channel() | request_id: 99}

      input = %{
        method: "notifications/tools/list_changed",
        params: %{_meta: %{progressToken: "abc"}}
      }

      assert :ok = Channel.send_notification(channel, input)
      assert_receive {:"$gen_mcp", :notification, payload}

      assert %{params: %{_meta: meta}} = payload
      assert Map.get(meta, :progressToken) == "abc"
      assert Map.get(meta, @sub_id_key) == 99
    end

    test "is a no-op stamp when request_id is nil (payload sent unchanged)" do
      channel = build_channel()
      assert channel.request_id == nil

      input = %{method: "notifications/tools/list_changed", params: %{}}

      assert :ok = Channel.send_notification(channel, input)
      assert_receive {:"$gen_mcp", :notification, payload}

      assert payload == input
    end

    test "returns error when channel is closed" do
      channel = %{Channel.as_closed(build_channel()) | request_id: 99}

      assert {:error, :closed} =
               Channel.send_notification(channel, %MCP.ToolListChangedNotification{})

      refute_receive {:"$gen_mcp", :notification, _}
    end
  end

  # The schema (`NotificationMetaObject`) is explicit that `subscriptionId` is
  # ABSENT on notifications not delivered via a subscription stream — it cites
  # progress notifications for an in-flight request as the example. So even with
  # `request_id` set, `send_notification/2` must stamp ONLY payloads whose method
  # is in the watched subscription set
  # (`GenMCP.MCP.V2607.Info.subscription_notification_method?/1`). Request-scoped
  # notifications (`notifications/progress`, `notifications/message`) must pass
  # through untouched. See spec 008.
  describe "send_notification/2 — gating to subscription notifications (spec 008)" do
    test "does not stamp a non-subscription struct (notifications/progress)" do
      channel = %{build_channel() | request_id: 99}
      input = %MCP.ProgressNotification{params: nil}

      assert :ok = Channel.send_notification(channel, input)
      assert_receive {:"$gen_mcp", :notification, payload}

      assert payload == input
    end

    test "does not stamp a non-subscription atom-keyed map (notifications/message)" do
      channel = %{build_channel() | request_id: 99}
      input = %{method: "notifications/message", params: %{}}

      assert :ok = Channel.send_notification(channel, input)
      assert_receive {:"$gen_mcp", :notification, payload}

      assert payload == input
      refute payload |> Map.get(:params) |> Map.has_key?(:_meta)
    end

    test "does not stamp a non-subscription string-keyed map (notifications/progress)" do
      channel = %{build_channel() | request_id: 99}
      input = %{"method" => "notifications/progress", "params" => %{}}

      assert :ok = Channel.send_notification(channel, input)
      assert_receive {:"$gen_mcp", :notification, payload}

      assert payload == input
      refute payload |> Map.get("params") |> Map.has_key?("_meta")
    end

    test "still stamps the mandatory acknowledged notification (watched method)" do
      channel = %{build_channel() | request_id: 99}
      input = %{method: "notifications/subscriptions/acknowledged", params: %{}}

      assert :ok = Channel.send_notification(channel, input)
      assert_receive {:"$gen_mcp", :notification, payload}

      assert %{params: %{_meta: meta}} = payload
      assert Map.get(meta, @sub_id_key) == 99
    end
  end
end
