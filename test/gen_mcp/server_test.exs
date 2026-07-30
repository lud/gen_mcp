defmodule GenMCP.ServerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox

  alias GenMCP.Mux.Channel
  alias GenMCP.Server
  alias GenMCP.Support.ServerMock
  alias GenMCP.Support.ServerMockNoClose

  setup [:set_mox_global, :verify_on_exit!]

  test "the worker stops immediately when the relay dies and handle_close is not implemented" do
    # The stateless-core cancellation story: there is no registry to find an
    # in-flight request, but the worker monitors the relay and its death is
    # observable and sufficient. ServerMockNoClose skips the optional
    # `handle_close/2`, so the worker stops immediately with no cleanup callback
    # (spec 005).
    ServerMockNoClose
    |> expect(:init, fn _opts -> {:ok, :server_state} end)
    |> expect(:handle_request, fn :fake_request, _channel, state -> {:stream, state} end)

    relay =
      spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

    channel = Channel.for_pid(relay)

    assert {:ok, worker} =
             Server.start_request([server: ServerMockNoClose], :fake_request, channel)

    wref = Process.monitor(worker)

    # The relay exits normally; the worker's monitor still fires :CHAN_DOWN.
    send(relay, :stop)

    assert_receive {:DOWN, ^wref, :process, ^worker, {:shutdown, :client_disconnected}}, 1000
  end

  test "the worker invokes handle_close with a closed channel before stopping, when implemented" do
    # When the server implements the optional `handle_close/2`, the worker calls
    # it on disconnect so the implementation can run explicit cleanup. The
    # channel is passed already `:closed` (nothing more can be sent), the return
    # value is ignored, and the worker still stops gracefully afterwards.
    test_pid = self()

    ServerMock
    |> expect(:init, fn _opts -> {:ok, :server_state} end)
    |> expect(:handle_request, fn :fake_request, _channel, state ->
      {:stream, state}
    end)
    |> expect(:handle_close, fn channel, :server_state ->
      send(test_pid, {:handle_close, channel.status})
      :ok
    end)

    relay =
      spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

    channel = Channel.for_pid(relay)

    assert {:ok, worker} = Server.start_request([server: ServerMock], :fake_request, channel)
    wref = Process.monitor(worker)

    # The relay exits normally; the worker's monitor still fires :CHAN_DOWN.
    send(relay, :stop)

    # The cleanup hook runs with the channel already marked closed...
    assert_receive {:handle_close, :closed}, 1000
    # ...and the worker still stops gracefully afterwards.
    assert_receive {:DOWN, ^wref, :process, ^worker, {:shutdown, :client_disconnected}}, 1000
  end

  test "the worker runs handle_close on a :closed ack (server-initiated Channel.close)" do
    # Server-initiated close does NOT go through :CHAN_DOWN: on a keep-alive
    # connection the relay (Bandit conn process) survives a finalize, so the
    # monitor never fires. Instead, when a handler calls `Channel.close/1`, the
    # relay finalizes the response and sends `{:"$gen_mcp", :closed}` back as an
    # acknowledgement; the worker runs `handle_close/2` with the channel
    # `:closed` and stops with `{:shutdown, :closed}`.
    #
    # The relay is kept ALIVE here precisely so this can't be mistaken for a
    # :CHAN_DOWN — the cleanup must come from the ack alone.
    test_pid = self()

    relay =
      spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

    channel = Channel.for_pid(relay)

    ServerMock
    |> expect(:init, fn _opts -> {:ok, :server_state} end)
    |> expect(:handle_request, fn :fake_request, _channel, state -> {:stream, state} end)
    |> expect(:handle_close, fn channel, :server_state ->
      send(test_pid, {:handle_close, channel.status})
      :ok
    end)

    assert {:ok, worker} = Server.start_request([server: ServerMock], :fake_request, channel)
    wref = Process.monitor(worker)

    # The transport's close acknowledgement, delivered after the handler called
    # `Channel.close/1` (the transport↔worker hop is covered end-to-end in the
    # StreamableHTTP test).
    send(worker, {:"$gen_mcp", :closed})

    assert_receive {:handle_close, :closed}, 1000
    assert_receive {:DOWN, ^wref, :process, ^worker, {:shutdown, :closed}}, 1000
  end

  test "handle_request {:result, result, stop_reason} replies, then stops the worker with the custom reason" do
    # The three-tuple result lets a handler answer the request normally AND
    # choose the worker's exit reason instead of the default `{:shutdown,
    # :reply}`. The client sees the same result; the custom reason is only
    # observable to whatever monitors/supervises the worker (and in telemetry).
    ServerMockNoClose
    |> expect(:init, fn _opts -> {:ok, :server_state} end)
    |> expect(:handle_request, fn :fake_request, _channel, _state ->
      {:result, :the_result, {:shutdown, :custom_reason}}
    end)

    # The owner (result recipient) is the channel's client — make it the test pid.
    channel = Channel.for_pid(self())

    assert {:ok, worker} =
             Server.start_request([server: ServerMockNoClose], :fake_request, channel)

    wref = Process.monitor(worker)

    # The result still reaches the owner...
    assert_receive {:"$gen_mcp", :result, :the_result}, 1000
    # ...and the worker stops with the handler's reason, not {:shutdown, :reply}.
    assert_receive {:DOWN, ^wref, :process, ^worker, {:shutdown, :custom_reason}}, 1000
  end

  test "handle_message {:result, result, stop_reason} ends the stream, then stops the worker with the custom reason" do
    # Same three-tuple on the streaming path: the final result ends the stream
    # and the custom reason becomes the worker's exit reason.
    ServerMockNoClose
    |> expect(:init, fn _opts -> {:ok, :server_state} end)
    |> expect(:handle_request, fn :fake_request, _channel, state -> {:stream, state} end)
    |> expect(:handle_message, fn :finish, _channel, _state ->
      {:result, :final, {:shutdown, :stream_done}}
    end)

    channel = Channel.for_pid(self())

    assert {:ok, worker} =
             Server.start_request([server: ServerMockNoClose], :fake_request, channel)

    wref = Process.monitor(worker)

    # The stream opens, then a process message drives the final result.
    assert_receive {:"$gen_mcp", :stream}, 1000
    send(worker, :finish)

    assert_receive {:"$gen_mcp", :result, :final}, 1000
    assert_receive {:DOWN, ^wref, :process, ^worker, {:shutdown, :stream_done}}, 1000
  end

  test "a linked Task.async crash kills the worker before its :DOWN message is handled" do
    # A streaming handler may be tempted to hold a `Task.async/1` in its stream
    # state and wait for the `:DOWN` on failure. That message never gets
    # handled: `Task.async/1` links the task to the worker, and the worker does
    # not trap exits, so the crash propagates through the link and kills the
    # worker first. This is why the v2 upgrade guide's porting example starts
    # its task with `Task.Supervisor.async_nolink/2` (test below).
    ServerMockNoClose
    |> expect(:init, fn _opts -> {:ok, :server_state} end)
    |> expect(:handle_request, fn :fake_request, _channel, _state ->
      {:stream, Task.async(fn -> raise "boom" end)}
    end)

    channel = Channel.for_pid(self())

    capture_log(fn ->
      assert {:ok, worker} =
               Server.start_request([server: ServerMockNoClose], :fake_request, channel)

      wref = Process.monitor(worker)

      assert_receive {:"$gen_mcp", :stream}, 1000

      # No handle_message expectation is set: the worker dies from the link,
      # carrying the task's own crash reason, without any callback running.
      assert_receive {:DOWN, ^wref, :process, ^worker, {%RuntimeError{message: "boom"}, _}},
                     1000
    end)
  end

  test "a Task.Supervisor.async_nolink crash reaches handle_message as a :DOWN message" do
    # The unlinked task is only monitored by the worker, so the worker outlives
    # the crash and the `:DOWN` message reaches the stream handler, which turns
    # it into a proper error. The `%Task{}` struct kept as the stream state is
    # what makes the `ref` match possible.
    sup = start_supervised!(Task.Supervisor)
    test_pid = self()

    ServerMockNoClose
    |> expect(:init, fn _opts -> {:ok, :server_state} end)
    |> expect(:handle_request, fn :fake_request, _channel, _state ->
      {:stream, Task.Supervisor.async_nolink(sup, fn -> raise "boom" end)}
    end)
    |> expect(:handle_message, fn message, _channel, %Task{ref: task_ref} ->
      assert {:DOWN, ^task_ref, :process, _pid, {%RuntimeError{message: "boom"}, _}} = message
      send(test_pid, :down_handled)
      {:error, "task failed"}
    end)

    channel = Channel.for_pid(self())

    capture_log(fn ->
      assert {:ok, worker} =
               Server.start_request([server: ServerMockNoClose], :fake_request, channel)

      wref = Process.monitor(worker)

      assert_receive {:"$gen_mcp", :stream}, 1000
      assert_receive :down_handled, 1000
      assert_receive {:DOWN, ^wref, :process, ^worker, _reason}, 1000
    end)
  end

  describe "a worker that cannot start" do
    # Spec 022. The client only ever sees `-32603 Internal Error`, which says
    # nothing about the cause, and the usual cause — a mount whose options do
    # not validate — fails identically on every request. The reason has to
    # reach the operator by some route that does not depend on having attached
    # `GenMCP.TelemetryLogger`.

    test "logs the option that failed validation" do
      # The Suite requires :server_name and :server_version. Omitting them is
      # exactly what a mount copied from an incomplete example does.
      log =
        capture_log(fn ->
          assert {:error, _} =
                   Server.start_request(
                     [server: GenMCP.Suite, tools: []],
                     :fake_request,
                     Channel.for_pid(self())
                   )
        end)

      assert log =~ "could not start a server worker"
      # The whole point: the missing option is named.
      assert log =~ "server_name"
      # And it says where to look, since the mount is what carries the options.
      assert log =~ "mounted"
    end

    test "logs a non-validation stop reason as-is" do
      expect(ServerMock, :init, fn _opts -> {:stop, :nope} end)

      log =
        capture_log(fn ->
          assert {:error, _} =
                   Server.start_request(
                     [server: ServerMock],
                     :fake_request,
                     Channel.for_pid(self())
                   )
        end)

      assert log =~ "could not start a server worker"
      assert log =~ ":nope"
    end
  end
end
