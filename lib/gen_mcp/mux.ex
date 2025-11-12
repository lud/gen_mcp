defmodule GenMCP.Mux do
  alias GenMCP.Mux.Session
  alias GenMCP.Mux.SessionSupervisor
  alias GenMCP.NodeSync
  require Logger

  # -- Session Initializing ---------------------------------------------------

  def start_session(opts) do
    session_id = NodeSync.gen_session_id()
    start_session(session_id, opts)
  end

  defp start_session(session_id, opts) do
    name = {:via, Registry, {registry(), session_id}}
    opts = Keyword.merge(opts, name: name, session_id: session_id)

    case DynamicSupervisor.start_child(SessionSupervisor.name(), {Session, opts}) do
      {:ok, _pid} ->
        {:ok, session_id}

      {:error, reason} ->
        Logger.error("Could not start MCP session: #{inspect(reason)}")
        {:error, {:session_start_failed, reason}}
    end
  end

  # -- Local Process Registry -------------------------------------------------

  def registry do
    :gen_mcp_mux_session_registry
  end

  # -- Calling Session --------------------------------------------------------

  def request(session_id, request, channel, timeout \\ 5000) do
    safe_call(session_id, {:"$gen_mcp", :request, request, channel}, timeout)
  end

  def notify(session_id, notification, timeout \\ 5000) do
    safe_call(session_id, {:"$gen_mcp", :notification, notification}, timeout)
  end

  def safe_call(session_id, callarg, timeout \\ 5000) do
    GenServer.call(via_session(session_id), callarg, timeout)
  end

  IO.warn("test with a peer node")

  def via_session(session_id) do
    case NodeSync.node_of(session_id) do
      {:ok, n} when n == node() -> {:via, Registry, {registry(), session_id}}
    end
  end
end
