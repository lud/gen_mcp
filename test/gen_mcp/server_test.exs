defmodule GenMCP.ServerTest do
  use ExUnit.Case, async: false

  import Mox

  alias GenMCP.Mux.Channel
  alias GenMCP.Server
  alias GenMCP.Support.ServerMock

  setup [:set_mox_global, :verify_on_exit!]

  test "the worker stops when the transport relay dies (client disconnect)" do
    # The stateless-core cancellation story: there is no registry to find an
    # in-flight request, but the worker monitors the relay and its death is
    # observable and sufficient.
    ServerMock
    |> expect(:init, fn _opts -> {:ok, :server_state} end)
    |> expect(:handle_request, fn :fake_request, _channel, state -> {:stream, state} end)

    relay =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    channel = Channel.for_pid(relay)

    assert {:ok, worker} = Server.start_request([server: ServerMock], :fake_request, channel)
    wref = Process.monitor(worker)

    Process.exit(relay, :kill)

    assert_receive {:DOWN, ^wref, :process, ^worker, {:shutdown, :client_disconnected}}, 1000
  end
end
