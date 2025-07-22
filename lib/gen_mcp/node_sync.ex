defmodule GenMcp.NodeSync do
  require Logger
  use GenServer

  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a
  @scope :gen_mcp_pg_scope
  @group :node_sync
  @tag __MODULE__

  def pg_child_spec do
    %{
      id: :pg,
      module: :pg,
      start: {:pg, :start_link, [@scope]},
      type: :supervisor
    }
  end

  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, @gen_opts)
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @impl true
  def init(_opts) do
    :net_kernel.monitor_nodes(true)

    case register_random_node_id() do
      {:ok, node_id} ->
        {mref, group_members} = :pg.monitor(@scope, @group)
        :ok = :pg.join(@scope, @group, self())
        publish(group_members, node_id)

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
        update_in(state.cluster, &cleanup_member(&1, {node(pid), pid}))
      end)

    dump({:noreply, state})
  end

  def handle_info({@tag, node_id, node, pid}, state) do
    state =
      update_in(state.cluster[node_id], fn
        nil -> [{node, pid}]
        [_ | _] = list -> append_member(list, {node, pid})
      end)

    dump({:noreply, state})
  end

  def handle_info({:nodeup, _}, state) do
    {:noreply, state}
  end

  def handle_info({:nodedown, node}, state) do
    state = update_in(state.cluster, &cleanup_node(&1, node))
    dump({:noreply, state})
  end

  def handle_info({:global_name_conflict, {@scope, name}}, state) do
    Logger.warning("duplicated node id #{name}, shutting down")
    {:stop, :shutdown, state}
  end

  def handle_info(other, state) do
    Logger.error("unexpected message #{inspect(other)}")

    dump({:noreply, state})
  end

  defp register_random_node_id(attempt \\ 0)

  defp register_random_node_id(attempt) when attempt < 10 do
    node_id = random_node_id()
    case :global.register_name({@scope, node_id}, self(), &:global.random_notify_name/3) do
      :yes -> {:ok, node_id}
      :no -> register_random_node_id(attempt + 1)
    end
  end

  defp register_random_node_id(_) do
    Logger.error("could not find available node_id from #{inspect(node())}")
    {:error, :max_attempts}
  end

  defp random_node_id do
    Enum.random(0..65535)
  end

  defp append_member([member | rest], member), do: [member | rest]
  defp append_member([h | rest], member), do: [h | append_member(rest, member)]
  defp append_member([], member), do: [member]

  defp cleanup_member(cluster, member) do
    cluster
    |> Enum.flat_map(fn {id, members} ->
      case members -- [member] do
        [] -> []
        rest -> [{id, rest}]
      end
    end)
    |> Map.new()
  end

  defp cleanup_node(cluster, node) do
    cluster
    |> Enum.flat_map(fn {id, members} ->
      case Enum.filter(members, fn {n, _} -> n != node end) do
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
        Process.put(:prev_dump_value,value)
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
