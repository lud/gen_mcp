defmodule GenMCP.ServerTest do
  use ExUnit.Case, async: false

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
end
