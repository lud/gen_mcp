defmodule GenMcp.NodeSync do
  require Logger
  use GenServer

  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a
  @scope :gen_mcp_pg_scope
  @glob :gen_mcp_global
  @group :node_sync
  @tag __MODULE__
  @name __MODULE__
  @node_id_bits 16
  @max_node_id 2 ** @node_id_bits - 1

  def pg_child_spec do
    %{
      id: :pg,
      module: :pg,
      start: {:pg, :start_link, [@scope]},
      type: :supervisor
    }
  end

  def node_id do
    case :persistent_term.get(__MODULE__, nil) do
      nil -> raise "NodeSync is not initialized"
      id -> id
    end
  end

  def gen_session_id do
    Base.encode16(<<node_id()::@node_id_bits>>) <>
      "-" <> Base.url_encode64(:crypto.strong_rand_bytes(18))
  end

  def node_of(session_id)

  def node_of(session_id) when is_binary(session_id) do
    with [node_b16 | _] <- String.split(session_id, "-", parts: 2),
         {:ok, <<node_id::@node_id_bits>>} <- Base.decode16(node_b16) do
      GenServer.call(@name, {:get_node, node_id})
    else
      _ -> :error
    end
  end

  def node_known?(name \\ @name, node) do
    GenServer.call(name, {:node_known?, node})
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
    Logger.metadata(node: node())
    :net_kernel.monitor_nodes(true)

    case register_random_node_id() do
      {:ok, node_id} ->
        {mref, group_members} = :pg.monitor(@scope, @group)
        :ok = :pg.join(@scope, @group, self())
        publish(group_members, node_id)
        :persistent_term.put(__MODULE__, node_id)

        state =
          %{
            mref: mref,
            node_id: node_id,
            # Nodes are stored as a list for the rare case where a cluster rejoins
            # itself and two nodes share the same ID. In that case they will both
            # publish their ID and we need to keep both until one of the node
            # process is shut down by global uniqueness.
            cluster: %{node_id => [{node(), self()}]}
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
        Logger.debug("Node #{node(pid)} left")
        update_in(state.cluster, &cleanup_member(&1, {node(pid), pid}))
      end)

    dump({:noreply, state})
  end

  def handle_info({@tag, node_id, node, pid}, state) when node == node() do
    %{node_id: ^node_id} = state
    ^pid = self()
    {:noreply, state}
  end

  def handle_info({@tag, node_id, node, pid}, state) when node != node() do
    state =
      update_in(state.cluster[node_id], fn
        nil -> [{node, pid}]
        [_ | _] = list -> append_member(list, {node, pid})
      end)

    Logger.debug("Node #{node} joined as #{node_id}")

    dump({:noreply, state})
  end

  def handle_info({:nodeup, _}, state) do
    {:noreply, state}
  end

  def handle_info({:nodedown, node}, state) do
    state = update_in(state.cluster, &cleanup_node(&1, node))
    dump({:noreply, state})
  end

  def handle_info({:global_name_conflict, {@glob, name}}, state) do
    Logger.warning("duplicated node id #{name}, shutting down")
    {:stop, :shutdown, state}
  end

  def handle_info(other, state) do
    Logger.error("unexpected message #{inspect(other)}")

    dump({:noreply, state})
  end

  @impl true
  def handle_call(:node_id, _from, state) do
    {:reply, state.node_id, state}
  end

  def handle_call({:get_node, node_id}, _from, state) do
    reply =
      case state.cluster do
        %{^node_id => [{node, _} | _]} -> {:ok, node}
        _ -> :error
      end

    {:reply, reply, state}
  end

  def handle_call({:node_known?, node}, _from, state) do
    known? =
      Enum.any?(state.cluster, fn {_id, members} ->
        Enum.any?(members, fn {n, _} -> n == node end)
      end)

    {:reply, known?, state}
  end

  defp register_random_node_id(attempt \\ 0)

  defp register_random_node_id(attempt) when attempt < 10 do
    node_id = random_node_id()

    case :global.register_name(global_name(node_id), self(), &:global.random_notify_name/3) do
      :yes -> {:ok, node_id}
      :no -> register_random_node_id(attempt + 1)
    end
  end

  defp register_random_node_id(_) do
    Logger.error("could not find available node_id from #{inspect(node())}")
    {:error, :max_attempts}
  end

  defp random_node_id do
    # Enum.random(1..3)
    Enum.random(0..@max_node_id)
  end

  defp append_member([member | rest], member) do
    [member | rest]
  end

  defp append_member([h | rest], member) do
    [h | append_member(rest, member)]
  end

  defp append_member([], member) do
    [member]
  end

  defp cleanup_member(cluster, member) do
    filter_members(cluster, &(&1 != member))
  end

  defp cleanup_node(cluster, node) do
    filter_members(cluster, fn {n, _} -> n != node end)
  end

  defp filter_members(cluster, f) do
    cluster
    |> Enum.flat_map(fn {id, members} ->
      case Enum.filter(members, f) do
        [] -> []
        rest -> [{id, rest}]
      end
    end)
    |> Map.new()
  end

  defp dump({:noreply, state}) do
    value = state.cluster

    case Process.get(:prev_dump_value, nil) do
      ^value ->
        :ok

      _ ->
        Process.put(:prev_dump_value, value)
        Logger.debug(inspect(state.cluster, pretty: true), ansi_color: :green)
    end

    {:noreply, state}
  end

  defp publish(pids, node_id) do
    Enum.each(pids, fn pid ->
      send(pid, {@tag, node_id, node(), self()})
    end)
  end
end
