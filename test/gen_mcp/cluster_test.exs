defmodule GenMCP.ClusterTest do
  use ExUnit.Case, async: false

  import Mox

  alias GenMCP.Mux
  alias GenMCP.Support.ServerMock
  alias GenMCP.Test.ClusterTestHelper
  alias GenMCP.TestWeb.Endpoint

  setup [:set_mox_global, :verify_on_exit!]

  defp start_session do
    expect(ServerMock, :init, fn _, _ -> {:ok, :some_state} end)
    {:ok, session_id} = Mux.start_session(server: ServerMock)
    session_id
  end

  test "session registered in syn on start" do
    session_id = start_session()

    assert {:ok, pid} = Mux.lookup_pid(session_id)
    assert is_pid(pid)
    assert node(pid) == node()
  end

  test "session ID is opaque base64url" do
    session_id = start_session()

    assert {:ok, decoded} = Base.url_decode64(session_id)
    assert byte_size(decoded) == 36
  end

  test "multiple sessions coexist" do
    expect(ServerMock, :init, 2, fn _, _ -> {:ok, :some_state} end)

    {:ok, id1} = Mux.start_session(server: ServerMock)
    {:ok, id2} = Mux.start_session(server: ServerMock)

    assert id1 != id2
    assert {:ok, pid1} = Mux.lookup_pid(id1)
    assert {:ok, pid2} = Mux.lookup_pid(id2)
    assert pid1 != pid2
  end

  test "session death auto-unregisters" do
    session_id = start_session()

    {:ok, pid} = Mux.lookup_pid(session_id)
    Process.exit(pid, :kill)
    Process.sleep(50)

    assert :error = Mux.lookup_pid(session_id)
  end

  test "session deletion unregisters" do
    session_id = start_session()

    expect(ServerMock, :session_delete, fn _ -> :ok end)

    assert {:ok, _pid} = Mux.lookup_pid(session_id)
    assert :ok = Mux.delete_session(session_id)
    Process.sleep(50)

    assert :error = Mux.lookup_pid(session_id)
  end

  test "session timeout unregisters" do
    expect(ServerMock, :init, fn _, _ -> {:ok, :some_state} end)

    {:ok, session_id} =
      Mux.start_session(server: ServerMock, session_timeout: 100)

    assert {:ok, _pid} = Mux.lookup_pid(session_id)
    Process.sleep(200)

    assert :error = Mux.lookup_pid(session_id)
  end

  describe "cross-node" do
    @describetag :cluster

    test "cross-node session access" do
      {:ok, cluster} =
        LocalCluster.start_link(1,
          applications: [:gen_mcp],
          environment: [
            gen_mcp: [
              {
                Endpoint,
                server: true,
                http: [port: 5003],
                url: [port: 5003],
                adapter: Bandit.PhoenixAdapter
              }
            ],
            logger: [
              level: :warning,
              default_formatter: [format: "$time $metadata[$level] $message\n", metadata: [:node]]
            ]
          ]
        )

      {:ok, [peer]} = LocalCluster.nodes(cluster)
      assert :pong = Node.ping(peer)

      # Start a session on the peer
      {:ok, session_id} =
        :rpc.call(peer, ClusterTestHelper, :start_session_on_peer, [])

      assert is_binary(session_id)

      # Wait for syn to sync, then verify lookup from local node
      assert {:ok, pid} =
               poll(fn -> Mux.lookup_pid(session_id) end, :ok_tuple)

      assert node(pid) == peer

      :ok = LocalCluster.stop(cluster, peer)
    end

    test "node failure unregisters session" do
      {:ok, cluster} =
        LocalCluster.start_link(1,
          applications: [:gen_mcp],
          environment: [
            gen_mcp: [
              {
                Endpoint,
                server: true,
                http: [port: 5004],
                url: [port: 5004],
                adapter: Bandit.PhoenixAdapter
              }
            ],
            logger: [
              level: :warning,
              default_formatter: [format: "$time $metadata[$level] $message\n", metadata: [:node]]
            ]
          ]
        )

      {:ok, [peer]} = LocalCluster.nodes(cluster)

      {:ok, session_id} =
        :rpc.call(peer, ClusterTestHelper, :start_session_on_peer, [])

      # Wait for syn sync
      assert {:ok, _pid} =
               poll(fn -> Mux.lookup_pid(session_id) end, :ok_tuple)

      # Stop the peer
      :ok = LocalCluster.stop(cluster, peer)

      # Session should become unreachable
      assert :error =
               poll(fn -> Mux.lookup_pid(session_id) end, :error)
    end
  end

  # Poll a function until the result matches the pattern or timeout
  defp poll(fun, expected_shape, attempts \\ 20) do
    result = fun.()

    if matches_shape?(result, expected_shape) do
      result
    else
      if attempts <= 1 do
        flunk("poll timed out, last result: #{inspect(result)}")
      else
        Process.sleep(100)
        poll(fun, expected_shape, attempts - 1)
      end
    end
  end

  defp matches_shape?({:ok, _}, :ok_tuple) do
    true
  end

  defp matches_shape?(:error, :error) do
    true
  end

  defp matches_shape?(_, _) do
    false
  end
end
