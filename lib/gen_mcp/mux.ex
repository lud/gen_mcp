defmodule GenMCP.Mux do
  @moduledoc false

  alias GenMCP.Mux.Session
  alias GenMCP.Mux.SessionSupervisor
  alias GenMCP.Utils.CallbackExt

  @syn_scope :gen_mcp_sessions

  # -- Session Initializing ---------------------------------------------------

  def start_session(opts) do
    session_id = gen_session_id()

    with {:ok, _pid} <- start_as(session_id, opts) do
      {:ok, session_id}
    end
  end

  @doc false
  def start_as(session_id, opts) do
    name = {:via, :syn, {@syn_scope, session_id}}
    opts = Keyword.merge(opts, name: name, session_id: session_id)

    case DynamicSupervisor.start_child(SessionSupervisor, {Session, opts}) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, reason} ->
        :telemetry.execute([:gen_mcp, :session, :start_error], %{}, %{
          session_id: session_id,
          reason: reason
        })

        {:error, reason}
    end
  end

  def ensure_started(session_id, channel, opts) when is_binary(session_id) do
    case syn_lookup(session_id) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        case start_existing_session(session_id, channel, opts) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:session_not_found, _}} = err -> err
          {:error, _} = err -> CallbackExt.wrap_result(err, :mcp_session_restore_failure)
        end
    end
  end

  defp start_existing_session(session_id, channel, opts) do
    with {:ok, session_data} <- Session.fetch_restore_data(session_id, channel, opts),
         {:ok, pid} <- start_as(session_id, opts),
         :ok <- restore_session(pid, session_data, channel) do
      {:ok, pid}
    else
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, :not_found} -> {:error, {:session_not_found, session_id}}
      {:error, _} = err -> err
    end
  end

  # -- Calling Session --------------------------------------------------------

  def request(session, request, channel, timeout \\ 5000)

  def request(session_id, request, channel, timeout) when is_binary(session_id) do
    case lookup_pid(session_id) do
      {:ok, pid} -> request(pid, request, channel, timeout)
      :error -> {:error, {:session_not_found, session_id}}
    end
  end

  def request(session_pid, request, channel, timeout) when is_pid(session_pid) do
    GenServer.call(session_pid, {:"$gen_mcp", :request, request, channel}, timeout)
  end

  def notify(session, notification, timeout \\ 5000)

  def notify(session_id, notification, timeout) when is_binary(session_id) do
    case lookup_pid(session_id) do
      {:ok, pid} -> notify(pid, notification, timeout)
      :error -> {:error, {:session_not_found, session_id}}
    end
  end

  def notify(session_pid, notification, timeout) when is_pid(session_pid) do
    GenServer.call(session_pid, {:"$gen_mcp", :notification, notification}, timeout)
  end

  defp restore_session(session_pid, data, channel) do
    GenServer.call(session_pid, {:"$gen_mcp", :restore_session, data, channel})
  end

  # -- Deleting Session -------------------------------------------------------

  def delete_session(session_id, timeout \\ to_timeout(minute: 1))

  def delete_session(session_id, timeout) when is_binary(session_id) do
    case lookup_pid(session_id) do
      {:ok, pid} -> delete_session(pid, timeout)
      :error -> {:error, {:session_not_found, session_id}}
    end
  end

  def delete_session(session_pid, timeout) when is_pid(session_pid) do
    GenServer.call(session_pid, {:"$gen_mcp", :delete_session}, timeout)
  end

  # -- OTP Plumbing ---------------------------------------------------------

  def call_session(session_id, callarg, timeout \\ 5000) do
    case lookup_pid(session_id) do
      {:ok, pid} -> GenServer.call(pid, callarg, timeout)
      :error -> {:error, {:session_not_found, session_id}}
    end
  end

  @doc """
  Retrieves the pid of a session in the cluster
  """
  @spec lookup_pid(binary) :: {:ok, pid} | :error
  def lookup_pid(session_id) when is_binary(session_id) do
    syn_lookup(session_id)
  end

  @doc false
  # Retrieves pids locally only, exported for tests and debug
  def whereis(session_id) when is_binary(session_id) do
    case :syn.lookup(@syn_scope, session_id) do
      {pid, _meta} -> pid
      :undefined -> nil
    end
  end

  # -- Private ----------------------------------------------------------------

  defp gen_session_id do
    Base.url_encode64(:crypto.strong_rand_bytes(36))
  end

  defp syn_lookup(session_id) do
    case :syn.lookup(@syn_scope, session_id) do
      {pid, _meta} -> {:ok, pid}
      :undefined -> :error
    end
  end
end
