defmodule GenMCP.ChannelTest do
  use ExUnit.Case, async: true

  import GenMCP.Test.Helpers

  alias GenMCP.MCP
  alias GenMCP.Mux.Channel

  describe "send_log/4" do
    test "sends log when level is at or above channel log level" do
      channel = %{build_channel() | log_level: :warning}

      assert :ok = Channel.send_log(channel, :error, "an error occurred")
      assert_receive {:"$gen_mcp", :notification, notification}

      assert %MCP.LoggingMessageNotification{
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

      assert %MCP.LoggingMessageNotification{
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

      assert %MCP.LoggingMessageNotification{params: %{data: ^data}} = notification
    end
  end
end
