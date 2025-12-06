defmodule GenMCP.Cluster.NodeSync do
  @moduledoc false
  use GenServer

  require Logger
  require Record

  # TODO(doc) document configuration for static node id
  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a
  @scope GenMCP.Cluster.scope()
  @glob :gen_mcp_node_sync_glob
  @group :gen_mcp_node_sync_group
  @tag __MODULE__
  @name __MODULE__
  @persistent_key __MODULE__
  @random_node_id_chars 4
  @default_register_max_attempts 10

  Record.defrecordp(:peer, node_id: nil, node: nil, pid: nil)

  def node_id do
    case :persistent_term.get(@persistent_key, nil) do
      nil -> raise "#{inspect(__MODULE__)} is not initialized"
      id -> id
    end
  end

  def gen_session_id do
    node_id() <> "-" <> Base.url_encode64(:crypto.strong_rand_bytes(36))
  end

  def node_of(session_id)

  def node_of(session_id) when is_binary(session_id) do
    case String.split(session_id, "-", parts: 2) do
      [node_id | _] -> GenServer.call(@name, {:get_node, node_id})
      _ -> :error
    end
  end

  def node_known?(node) do
    GenServer.call(@name, {:node_known?, node})
  end

  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, @gen_opts)
    gen_opts = Keyword.put_new(gen_opts, :name, @name)
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def global_name(node_id) do
    {@glob, node_id}
  end

  @impl true
  def init(_opts) do
    :ok = :net_kernel.monitor_nodes(true)

    {node_id_gen, max_attempts} =
      case Application.fetch_env(:gen_mcp, :node_id) do
        {:ok, <<_, _::binary>> = id} when is_binary(id) ->
          case Regex.match?(~r{^[a-zA-Z0-9_]+$}, id) do
            true ->
              {fn -> id end, 1}

            _ ->
              raise ArgumentError,
                    "expected config :gen_mcp/:node_id to be an alphanumeric string or '_', got: #{inspect(id)}"
          end

        {:ok, :random} ->
          {&random_node_id/0, @default_register_max_attempts}

        :error ->
          {&random_node_id/0, @default_register_max_attempts}

        {:ok, other} ->
          raise ArgumentError,
                "expected config :gen_mcp/:node_id to be a string or :random, got: #{inspect(other)}"
      end

    case register_random_node_id(node_id_gen, max_attempts) do
      {:ok, node_id} ->
        {mref, group_members} = :pg.monitor(@scope, @group)
        :ok = :pg.join(@scope, @group, self())
        publish(group_members, node_id)
        :persistent_term.put(@persistent_key, node_id)

        state =
          %{
            mref: mref,
            node_id: node_id,
            # It is possible that multiple peers have the same node id when a
            # cluster is formed and two nodes share the same ID. In that case
            # they will both publish their ID and we need to keep both until one
            # of the node process is shut down by global uniqueness.
            cluster: [peer(node_id: node_id, node: node(), pid: self())]
          }

        {:ok, state}

      {:error, :max_attempts} ->
        {:stop, :max_attempts}
    end
  end

  @impl true
  def handle_info({mref, :join, @group, pids}, %{mref: mref} = state) do
    publish(pids, state.node_id)

    dump({:noreply, state})
  end

  def handle_info({mref, :leave, @group, pids}, %{mref: mref} = state) do
    state =
      Enum.reduce(pids, state, fn pid, state ->
        update_in(state.cluster, &cleanup_pid(&1, pid))
      end)

    dump({:noreply, state})
  end

  def handle_info({@tag, node_id, node, pid}, state) when node == node() do
    %{node_id: ^node_id} = state
    ^pid = self()
    {:noreply, state}
  end

  def handle_info({@tag, node_id, node, pid}, state) when node != node() do
    peer = peer(node_id: node_id, node: node, pid: pid)
    cluster = [peer | state.cluster]
    state = %{state | cluster: cluster}

    :telemetry.execute([:gen_mcp, :cluster, :joined], %{}, peer_to_map(peer))

    dump({:noreply, state})
  end

  def handle_info({:nodeup, _}, state) do
    {:noreply, state}
  end

  def handle_info({:nodedown, node}, state) do
    state = update_in(state.cluster, &cleanup_node(&1, node))
    dump({:noreply, state})
  end

  def handle_info({:global_name_conflict, {@glob, node_id}}, state) do
    peer(node_id: ^node_id) = self_peer = List.keyfind!(state.cluster, self(), peer(:pid))
    :telemetry.execute([:gen_mcp, :cluster, :conflict], %{}, peer_to_map(self_peer))

    # This may impact performances, hopefully duplicate node ids only happen
    # during boot or when rolling nodes.
    :persistent_term.erase(@persistent_key)

    {:stop, :shutdown, state}
  end

  def handle_info(other, state) do
    :telemetry.execute([:gen_mcp, :cluster, :error], %{}, %{
      node: node(),
      message: "unexpected message #{inspect(other)} in #{inspect(__MODULE__)}"
    })

    dump({:noreply, state})
  end

  @impl true
  def handle_call(:node_id, _from, state) do
    {:reply, state.node_id, state}
  end

  def handle_call({:get_node, node_id}, _from, state) do
    reply =
      case List.keyfind(state.cluster, node_id, peer(:node_id)) do
        peer(node: node) -> {:ok, node}
        _ -> :error
      end

    {:reply, reply, state}
  end

  def handle_call({:node_known?, node}, _from, state) do
    known? =
      case List.keyfind(state.cluster, node, peer(:node)) do
        nil -> false
        peer() -> true
      end

    {:reply, known?, state}
  end

  defp register_random_node_id(id_generator, max_attempts, attempt \\ 1)

  defp register_random_node_id(_id_generator, max_attempts, attempt)
       when attempt > max_attempts do
    :telemetry.execute([:gen_mcp, :cluster, :error], %{}, %{
      node: node(),
      message: "Could not register node_id from #{inspect(node())}"
    })

    {:error, :max_attempts}
  end

  defp register_random_node_id(id_generator, max_attempts, attempt) do
    node_id = id_generator.()

    case :global.register_name(global_name(node_id), self(), &:global.random_notify_name/3) do
      :yes -> {:ok, node_id}
      :no -> register_random_node_id(id_generator, max_attempts, attempt + 1)
    end
  end

  @doc false
  @random_chars Enum.concat([?a..?z, ?0..?9, ?A..?Z])
  def random_node_id do
    for _ <- 1..@random_node_id_chars,
        reduce: <<>>,
        do: (acc -> <<acc::binary, Enum.random(@random_chars)>>)
  end

  defp cleanup_pid(cluster, pid) do
    case List.keytake(cluster, pid, peer(:pid)) do
      nil ->
        cluster

      {peer, cluster} ->
        :telemetry.execute([:gen_mcp, :cluster, :left], %{}, peer_to_map(peer))
        cluster
    end
  end

  defp cleanup_node(cluster, node) do
    Enum.filter(cluster, fn
      peer(node: ^node) -> false
      _ -> true
    end)
  end

  defp dump({:noreply, state}) do
    value = state.cluster

    case Process.get(:prev_dump_value, nil) do
      ^value ->
        :ok

      _ ->
        Process.put(:prev_dump_value, value)

        :telemetry.execute([:gen_mcp, :cluster, :status], %{}, %{
          peers: Enum.map(value, &peer_to_map/1)
        })
    end

    {:noreply, state}
  end

  defp publish(pids, node_id) do
    Enum.each(pids, fn pid ->
      send(pid, {@tag, node_id, node(), self()})
    end)
  end

  defp peer_to_map(peer) do
    peer(node_id: node_id, node: node, pid: pid) = peer
    %{node_id: node_id, node: node, pid: pid}
  end
end
