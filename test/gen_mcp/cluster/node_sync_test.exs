defmodule GenMCP.Cluster.NodeSyncTest do
  use ExUnit.Case, async: true

  alias GenMCP.Cluster.NodeSync

  require Logger

  doctest NodeSync

  test "returns unique session ids" do
    ids =
      for _ <- 1..1000 do
        NodeSync.gen_session_id()
      end

    assert Enum.uniq(ids) == ids
  end

  test "returns the node from a session id" do
    session_id = NodeSync.gen_session_id()
    assert {:ok, node()} == NodeSync.node_of(session_id)
  end

  test "is registered as global" do
    node_id = NodeSync.node_id()
    assert Process.whereis(NodeSync) == :global.whereis_name(NodeSync.global_name(node_id))
  end

  test "returns another node name from session id" do
    # Start a remote node
    {:ok, cluster} =
      LocalCluster.start_link(1,
        applications: [:gen_mcp],
        environment: [
          gen_mcp: [
            {GenMCP.TestWeb.Endpoint, server: true, http: [port: 5003], url: [port: 5003]}
          ],
          logger: [
            level: :warning,
            default_formatter: [format: "$time $metadata[$level] $message\n", metadata: [:node]]
          ]
        ]
      )

    {:ok, [peer]} = LocalCluster.nodes(cluster)

    assert :pong = Node.ping(peer)

    # We can ask a session id on this node
    session_id = :rpc.call(peer, NodeSync, :gen_session_id, [])

    # When known
    await_node_id_sync(peer)
    assert {:ok, peer} == NodeSync.node_of(session_id)

    # Not known anymore
    :ok = LocalCluster.stop(cluster, peer)
    assert :error == NodeSync.node_of(session_id)
  end

  defp await_node_id_sync(peer) do
    case NodeSync.node_known?(peer) do
      true ->
        :ok

      false ->
        Logger.warning("nodes not in sync yet")
        Process.sleep(100)
        await_node_id_sync(peer)
    end
  end
end
