defmodule GenMCP.Transport.RelayTest do
  use ExUnit.Case, async: true

  alias GenMCP.Mux.Channel
  alias GenMCP.Transport.Relay
  alias Plug.Adapters.Test.Conn

  @codec {GenMCP.Transport.Relay.Codec.JSONRPC, nil}
  @msg_id 123

  @moduletag capture_log: true

  # The relay runs in the test process. Fake workers send their messages to the
  # channel's client alias before `Relay.respond_and_close/5` starts consuming
  # them, the way a real worker does.

  # A worker that is already gone when the relay monitors it: the monitor
  # reports `:noproc`, whatever the real exit reason was.
  defp dead_worker(channel, messages) do
    {pid, ref} = spawn_monitor(fn -> Enum.each(messages, &send(channel.client_alias, &1)) end)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    pid
  end

  # A worker that exits with `reason` only once the relay monitors it, so the
  # monitor reports the real reason.
  defp live_worker(channel, messages, reason) do
    owner = self()

    spawn(fn ->
      Enum.each(messages, &send(channel.client_alias, &1))
      await_monitored_by(owner)
      exit(reason)
    end)
  end

  defp await_monitored_by(pid) do
    {:monitored_by, monitors} = Process.info(self(), :monitored_by)

    if pid in monitors do
      :ok
    else
      Process.sleep(1)
      await_monitored_by(pid)
    end
  end

  defp respond(worker, channel) do
    Relay.respond_and_close(Plug.Test.conn(:post, "/mcp"), @codec, @msg_id, worker, channel)
  end

  defp chunks(conn) do
    {Conn, %{chunks: chunks}} = conn.adapter
    chunks
  end

  defp stream_events(conn) do
    conn
    |> chunks()
    |> String.split("\n\n", trim: true)
    |> Enum.map(fn event ->
      assert "event: message\ndata: " <> json = event
      JSV.Codec.decode!(json)
    end)
  end

  defp assert_stream(conn) do
    assert conn.halted
    assert conn.state == :chunked
    assert conn.status == 200
    assert ["text/event-stream"] = Plug.Conn.get_resp_header(conn, "content-type")
    conn
  end

  defp assert_error_response(conn) do
    assert conn.halted
    assert conn.state == :sent
    assert conn.status == 500

    assert %{"error" => %{"code" => -32_603} = error, "id" => @msg_id, "jsonrpc" => "2.0"} =
             JSV.Codec.decode!(conn.resp_body)

    error
  end

  defp assert_crash_response(conn) do
    assert %{"message" => "Internal server error"} = assert_error_response(conn)
  end

  defp assert_crash_event(conn) do
    assert_stream(conn)

    assert [
             %{
               "error" => %{"code" => -32_603, "message" => "Internal server error"},
               "id" => @msg_id,
               "jsonrpc" => "2.0"
             }
           ] = stream_events(conn)
  end

  defp refute_leftover_messages do
    refute_received {:SERVER_DOWN, _, _, _, _}
    refute_received {:"$gen_mcp", _}
    refute_received {:"$gen_mcp", _, _}
  end

  describe "{:end, reason} while streaming" do
    for reason <- [:normal, :shutdown, {:shutdown, :done}] do
      test "a clean #{inspect(reason)} ends the stream with no further event" do
        reason = unquote(Macro.escape(reason))
        channel = Channel.for_pid(self())
        worker = dead_worker(channel, [{:"$gen_mcp", :stream}, {:"$gen_mcp", :end, reason}])

        conn = respond(worker, channel)

        assert_stream(conn)
        assert [] == stream_events(conn)
        refute_leftover_messages()
      end
    end

    test "an unclean reason ends the stream with an internal error event" do
      channel = Channel.for_pid(self())
      worker = dead_worker(channel, [{:"$gen_mcp", :stream}, {:"$gen_mcp", :end, :boom}])

      conn = respond(worker, channel)

      assert_crash_event(conn)
      refute_leftover_messages()
    end

    test "the reason from {:end, reason} wins over the monitor reason" do
      channel = Channel.for_pid(self())

      worker =
        live_worker(channel, [{:"$gen_mcp", :stream}, {:"$gen_mcp", :end, :normal}], :boom)

      conn = respond(worker, channel)

      assert_stream(conn)
      assert [] == stream_events(conn)
    end
  end

  describe "{:end, reason} before any stream" do
    test "a clean reason is a no-result error response" do
      channel = Channel.for_pid(self())
      worker = dead_worker(channel, [{:"$gen_mcp", :end, :normal}])

      conn = respond(worker, channel)

      assert %{"message" => message} = assert_error_response(conn)
      assert message =~ ~r/no result/i
      refute_leftover_messages()
    end

    test "an unclean reason is an internal error response" do
      channel = Channel.for_pid(self())
      worker = dead_worker(channel, [{:"$gen_mcp", :end, :boom}])

      conn = respond(worker, channel)

      assert_crash_response(conn)
      refute_leftover_messages()
    end
  end

  describe "worker down with no {:end, reason}" do
    # A worker that goes through `terminate/2` always sends `{:end, reason}`.
    # Reaching the monitor alone means it was killed (`:kill`, a linked exit
    # signal, a supervisor shutdown), which is a crash whatever the reason says.
    # This is also why the `:noproc` race is harmless: a clean reason and
    # `:noproc` lead to the same outcome.

    for reason <- [:normal, :shutdown, {:shutdown, :done}, :boom] do
      test "a #{inspect(reason)} exit while streaming ends the stream with an internal error event" do
        reason = unquote(Macro.escape(reason))
        channel = Channel.for_pid(self())
        worker = live_worker(channel, [{:"$gen_mcp", :stream}], reason)

        conn = respond(worker, channel)

        assert_crash_event(conn)
        refute_leftover_messages()
      end

      test "a #{inspect(reason)} exit before any stream is an internal error response" do
        reason = unquote(Macro.escape(reason))
        channel = Channel.for_pid(self())
        worker = live_worker(channel, [], reason)

        conn = respond(worker, channel)

        assert_crash_response(conn)
        refute_leftover_messages()
      end
    end

    test "a worker already gone after opening a stream ends it with an internal error event" do
      channel = Channel.for_pid(self())
      worker = dead_worker(channel, [{:"$gen_mcp", :stream}])

      conn = respond(worker, channel)

      assert_crash_event(conn)
      refute_leftover_messages()
    end

    test "a worker already gone with no message is an internal error response" do
      channel = Channel.for_pid(self())
      worker = dead_worker(channel, [])

      conn = respond(worker, channel)

      assert_crash_response(conn)
      refute_leftover_messages()
    end
  end

  describe "messages arriving after the response ended" do
    # The connection process may serve the next request of a keep-alive
    # connection: nothing from this worker may reach that request's loop.

    test "an {:end, reason} already queued behind the result is drained" do
      channel = Channel.for_pid(self())

      worker =
        dead_worker(channel, [
          {:"$gen_mcp", :result, %{}},
          {:"$gen_mcp", :end, {:shutdown, :reply}}
        ])

      conn = respond(worker, channel)

      assert conn.status == 200
      refute_leftover_messages()
    end

    test "messages queued behind a streamed result are drained" do
      channel = Channel.for_pid(self())

      worker =
        dead_worker(channel, [
          {:"$gen_mcp", :stream},
          {:"$gen_mcp", :result, %{}},
          {:"$gen_mcp", :notification, %{method: "notifications/message"}},
          {:"$gen_mcp", :end, :normal}
        ])

      conn = respond(worker, channel)

      assert_stream(conn)
      assert [%{"id" => @msg_id, "result" => %{}}] = stream_events(conn)
      refute_leftover_messages()
    end

    test "messages sent to the client alias after the response ended are dropped" do
      channel = Channel.for_pid(self())
      worker = live_worker(channel, [{:"$gen_mcp", :result, %{}}], {:shutdown, :reply})

      conn = respond(worker, channel)
      assert conn.status == 200

      send(channel.client_alias, {:"$gen_mcp", :notification, %{method: "notifications/message"}})
      send(channel.client_alias, {:"$gen_mcp", :end, {:shutdown, :reply}})

      refute_leftover_messages()
    end

    test "a late message from a previous worker does not reach the next request" do
      first_channel = Channel.for_pid(self())

      first_worker =
        live_worker(first_channel, [{:"$gen_mcp", :result, %{}}], {:shutdown, :reply})

      first_conn = respond(first_worker, first_channel)
      assert first_conn.status == 200
      {Conn, %{ref: ref}} = first_conn.adapter
      assert_receive {^ref, {200, _, _}}

      send(first_channel.client_alias, {:"$gen_mcp", :result, %{"stale" => true}})

      channel = Channel.for_pid(self())
      worker = dead_worker(channel, [{:"$gen_mcp", :stream}, {:"$gen_mcp", :end, :normal}])

      conn = respond(worker, channel)

      assert_stream(conn)
      assert [] == stream_events(conn)
    end
  end

  describe "other endings" do
    test "an accepted notification is a 202 with an empty body" do
      channel = Channel.for_pid(self())
      worker = live_worker(channel, [{:"$gen_mcp", :accepted}], {:shutdown, :reply})

      conn = respond(worker, channel)

      assert conn.halted
      assert conn.status == 202
      assert conn.resp_body == ""
      refute_leftover_messages()
    end

    test "a server-initiated close ends the stream and acknowledges it to the worker" do
      test_pid = self()
      channel = Channel.for_pid(self())

      worker =
        spawn(fn ->
          send(channel.client_alias, {:"$gen_mcp", :stream})
          send(channel.client_alias, {:"$gen_mcp", :close})

          receive do
            {:"$gen_mcp", :closed} -> send(test_pid, :worker_got_closed)
          end
        end)

      conn = respond(worker, channel)

      assert_stream(conn)
      assert [] == stream_events(conn)
      assert_receive :worker_got_closed, 1000
    end

    test "an error message is an error response" do
      channel = Channel.for_pid(self())
      worker = live_worker(channel, [{:"$gen_mcp", :error, :bad_rpc}], {:shutdown, :reply})

      conn = respond(worker, channel)

      assert conn.halted
      assert conn.status == 400

      assert %{"error" => %{"code" => -32_600}, "id" => @msg_id} =
               JSV.Codec.decode!(conn.resp_body)

      refute_leftover_messages()
    end
  end

  describe "send_error/4" do
    test "writes and halts an error response outside of any relay loop" do
      conn = Relay.send_error(Plug.Test.conn(:post, "/mcp"), :bad_rpc, @msg_id, @codec)

      assert conn.halted
      assert conn.state == :sent
      assert conn.status == 400

      assert %{"error" => %{"code" => -32_600}, "id" => @msg_id} =
               JSV.Codec.decode!(conn.resp_body)
    end
  end
end
