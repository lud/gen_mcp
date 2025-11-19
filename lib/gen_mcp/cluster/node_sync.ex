defmodule GenMCP.Cluster.NodeSync do
  use GenServer

  require Logger

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

  def node_id do
    case :persistent_term.get(@persistent_key, nil) do
      nil -> raise "#{inspect(__MODULE__)} is not initialized"
      id -> id
    end
  end

  def gen_session_id do
    node_id() <> "-" <> Base.url_encode64(:crypto.strong_rand_bytes(18))
  end

  def node_of(session_id)

  def node_of(session_id) when is_binary(session_id) do
    case String.split(session_id, "-", parts: 2) do
      [node_id | _] -> GenServer.call(@name, {:get_node, node_id})
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
    :ok = :net_kernel.monitor_nodes(true)

    {node_id_gen, max_attempts} =
      case Application.fetch_env(:gen_mcp, :node_id) do
        {:ok, <<_, _::binary>> = id} when is_binary(id) ->
          {fn -> id end, 1}

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

    # This may impact performances, hopefully duplicate node ids only happen
    # during boot or when rolling nodes.
    :persistent_term.erase(@persistent_key)

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

  defp register_random_node_id(id_generator, max_attempts, attempt \\ 1)

  defp register_random_node_id(_id_generator, max_attempts, attempt)
       when attempt > max_attempts do
    Logger.error("Could not register node_id from #{inspect(node())}")

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

  defp append_member([same | rest], same) do
    [same | rest]
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
