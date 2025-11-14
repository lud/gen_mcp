defmodule GenMCP.Mux.Session do
  @moduledoc false

  require Logger
  use GenServer, restart: :temporary

  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a

  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, @gen_opts)
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  defmodule State do
    @enforce_keys [:server_mod, :server_state, :session_id, :session_timeout_ref, :opts]
    defstruct @enforce_keys
  end

  IO.warn("@todo document session timeout default to 1 minute and also refreshed on handle info")
  IO.warn("@todo test init failure")
  @impl true
  def init(opts) do
    {server, opts} = Keyword.pop(opts, :server, GenMCP.Suite)
    session_id = Keyword.fetch!(opts, :session_id)
    session_timeout = Keyword.get(opts, :session_timeout, :timer.minutes(1))

    self_opts = [session_timeout: session_timeout]

    # pass all other options to the server if the server is not a tuple
    default_server_options = opts

    {server_mod, server_arg} = normalize_server(server, default_server_options)
    Logger.debug("GenMCP session #{opts[:session_id]} initializing with #{inspect(server_mod)}")

    case server_mod.init(session_id, server_arg) do
      {:ok, server_state} ->
        {:ok,
         %State{
           server_mod: server_mod,
           server_state: server_state,
           session_id: session_id,
           session_timeout_ref: start_session_timeout(session_timeout),
           opts: self_opts
         }}
    end
  end

  defp normalize_server({module, arg}, _) when is_atom(module) do
    {module, arg}
  end

  defp normalize_server(module, default_arg) when is_atom(module) do
    {module, default_arg}
  end

  @impl true
  def handle_call({:"$gen_mcp", :request, req, chan_info}, _from, state) do
    state = refresh_session_timeout(state)

    case state.server_mod.handle_request(req, chan_info, state.server_state) do
      {:reply, reply, server_state} ->
        {:reply, reply, %{state | server_state: server_state}}

      {:stop, reason, reply, server_state} ->
        {:stop, reason, reply, %{state | server_state: server_state}}

      other ->
        exit({:bad_return_value, other})
    end
  end

  def handle_call({:"$gen_mcp", :notification, notif}, _from, state) do
    # TODO Handle error/noreply return ?
    state = refresh_session_timeout(state)

    case state.server_mod.handle_notification(notif, state.server_state) do
      {:noreply, server_state} ->
        {:reply, :ack, %{state | server_state: server_state}}

      other ->
        exit({:bad_return_value, other})
    end
  end

  def handle_call({:"$gen_mcp", :stop}, _from, state) do
    Logger.info("session #{state.session_id} terminating (client delete)")
    {:stop, {:shutdown, :mcp_stop}, :ok, state}
  end

  @impl true
  def handle_info({:timeout, tref, :session_timeout} = msg, state) do
    msg |> dbg()

    case state.session_timeout_ref do
      ^tref ->
        Logger.info("session #{state.session_id} terminating (client timeout)")
        {:stop, {:shutdown, :session_timeout}, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(info, state) do
    state = refresh_session_timeout(state)

    case state.server_mod.handle_info(info, state.server_state) do
      {:noreply, server_state} ->
        {:noreply, %{state | server_state: server_state}}

      other ->
        exit({:bad_return_value, other})
    end
  end

  defp start_session_timeout(ms) do
    :erlang.start_timer(ms, self(), :session_timeout)
  end

  defp refresh_session_timeout(state) do
    Process.cancel_timer(state.session_timeout_ref, async: true, info: false)
    %{state | session_timeout_ref: start_session_timeout(state.opts[:session_timeout])}
  end
end
