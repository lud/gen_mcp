defmodule GenMCP.Mux.Session do
  # This layer is mostly a middleman without much additional value. The server
  # implementation could be the gen server receiving requests directly.
  #
  # The most useful thing is that the server being a behaviour, we can mock it,
  # and this Session module unwraps the $gen_mcp messages before entering our
  # mock.
  #
  # This also simplifies the API for user-defined servers.

  require Logger
  use GenServer, restart: :temporary

  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a

  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, @gen_opts)
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  defmodule State do
    @enforce_keys [:server_mod, :server_state]
    defstruct @enforce_keys
  end

  IO.warn("@todo test init failure")
  @impl true
  def init(opts) do
    {server, opts} = Keyword.pop(opts, :server, GenMCP.Suite)

    # pass all other options to the server if the server is not a tuple
    default_server_options = opts

    {server_mod, server_arg} = normalize_server(server, default_server_options)
    Logger.debug("GenMCP session #{opts[:session_id]} initializing with #{inspect(server_mod)}")

    case server_mod.init(server_arg) do
      {:ok, server_state} -> {:ok, %State{server_mod: server_mod, server_state: server_state}}
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
    case state.server_mod.handle_notification(notif, state.server_state) do
      {:noreply, server_state} ->
        {:reply, :ack, %{state | server_state: server_state}}

      other ->
        exit({:bad_return_value, other})
    end
  end

  @impl true
  def handle_info(info, state) do
    case state.server_mod.handle_info(info, state.server_state) do
      {:noreply, server_state} ->
        {:noreply, %{state | server_state: server_state}}

      other ->
        exit({:bad_return_value, other})
    end
  end
end
