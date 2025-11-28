defmodule GenMCP.Mux do
  @moduledoc false

  alias GenMCP.Cluster.NodeSync
  alias GenMCP.Mux.Session
  alias GenMCP.Mux.SessionSupervisor

  # -- Session Initializing ---------------------------------------------------

  def start_session(opts) do
    session_id = NodeSync.gen_session_id()
    name = {:via, Registry, {registry(), session_id}}
    opts = Keyword.merge(opts, name: name, session_id: session_id)

    case DynamicSupervisor.start_child(SessionSupervisor.name(), {Session, opts}) do
      {:ok, _pid} ->
        {:ok, session_id}

      {:error, reason} ->
        :telemetry.execute([:gen_mcp, :session, :start_error], %{}, %{
          session_id: session_id,
          reason: reason
        })

        {:error, reason}
    end
  end

  # -- Local Process Registry -------------------------------------------------

  def registry do
    :gen_mcp_mux_session_registry
  end

  # -- Calling Session --------------------------------------------------------

  def request(session_id, request, chan_info, timeout \\ 5000) do
    call_session(session_id, {:"$gen_mcp", :request, request, chan_info}, timeout)
  end

  def notify(session_id, notification, timeout \\ 5000) do
    call_session(session_id, {:"$gen_mcp", :notification, notification}, timeout)
  end

  # -- Stopping Session -------------------------------------------------------

  def stop_session(session_id, timeout \\ to_timeout(minute: 1)) do
    call_session(session_id, {:"$gen_mcp", :stop}, timeout)
  end

  # -- OTP Plumbing ---------------------------------------------------------

  def call_session(session_id, callarg, timeout \\ 5000) do
    case lookup_pid(session_id) do
      {:ok, pid} -> GenServer.call(pid, callarg, timeout)
      :error -> {:error, {:session_not_found, session_id}}
    end
  end

  def lookup_pid(session_id) when is_binary(session_id) do
    case NodeSync.node_of(session_id) do
      {:ok, n} when n == node() ->
        pid_result(whereis(session_id))

      {:ok, remote_node} ->
        rpc = :rpc.call(remote_node, GenMCP.Mux, :whereis, [session_id])
        pid_result(rpc)

      :error ->
        :error
    end
  end

  @doc false
  # Retrieves pids locally only, exported for tests and debug
  def whereis(session_id) do
    case Registry.lookup(registry(), session_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp pid_result(pid_or_nil) do
    case pid_or_nil do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> :error
    end
  end
end
