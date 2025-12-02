defmodule GenMCP.Mux.Session do
  @moduledoc """
  A GenServer based module used for processes representing an ongoing MCP
  session.

  Delegates all requests to the `GenMCP` behaviour implementations.
  """

  # All session and mcp opts are given in the child spec from the transport
  # plug. It is not kept in memory by the supervisor as long as the session has
  # restart: :temporary. If we want to use another restart strategy we must
  # change the boot setup to avoid keeping to much in memory.
  use GenServer, restart: :temporary

  alias GenMCP.Utils.OptsValidator

  require Logger

  @gen_opts ~w(name timeout debug spawn_opt hibernate_after)a
  @default_session_timeout_minutes to_timeout(minute: 2)

  @init_opts_schema NimbleOptions.new!(
                      session_id: [
                        required: true,
                        type: :string,
                        doc: "The session identifier, prefixed with the node ID and a dash"
                      ],
                      server: [
                        type: {:or, [:atom, :mod_arg]},
                        default: GenMCP.Suite,
                        doc:
                          "The `GenMCP` behaviour server implemetation that will handle MCP messages." <>
                            " If a simple atom, it will receive all other options given to the session."
                      ],
                      session_timeout: [
                        type: :integer,
                        default: @default_session_timeout_minutes,
                        doc:
                          "Session will automatically terminate when not receiving any request" <>
                            " or notification for that number of milliseconds."
                      ]
                    )

  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, @gen_opts)
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc false
  def init_opts_schema do
    @init_opts_schema
  end

  defmodule State do
    @moduledoc false
    @enforce_keys [:server_mod, :server_state, :session_id, :session_timeout_ref, :conf]
    defstruct @enforce_keys
  end

  @impl true
  def init(opts) do
    with {:ok, conf} <- init_self(opts),
         {:ok, server_state} <- init_server(conf) do
      {:ok,
       %State{
         server_mod: conf.server_mod,
         server_state: server_state,
         session_id: conf.session_id,
         session_timeout_ref: start_session_timeout(conf.session_timeout),
         conf: conf
       }}
    else
      {:stop, _} = stop -> stop
    end
  end

  defp init_self(opts) do
    case OptsValidator.validate_take_opts(opts, @init_opts_schema) do
      {:ok, self_opts, server_opts} ->
        server = Keyword.fetch!(self_opts, :server)
        session_timeout = Keyword.fetch!(self_opts, :session_timeout)
        session_id = Keyword.fetch!(opts, :session_id)
        {server_mod, server_arg} = normalize_server(server, server_opts)

        :telemetry.execute([:gen_mcp, :session, :init], %{}, %{
          session_id: session_id,
          server: server_mod,
          pid: self()
        })

        {:ok,
         %{
           session_id: session_id,
           server_mod: server_mod,
           server_arg: server_arg,
           session_timeout: session_timeout
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp init_server(conf) do
    case conf.server_mod.init(conf.session_id, conf.server_arg) do
      {:ok, server_state} -> {:ok, server_state}
      {:stop, reason} -> {:stop, {:mcp_server_init_failure, reason}}
      other -> exit({:bad_return_value, other})
    end
  end

  defp normalize_server({module, arg}, _) when is_atom(module) do
    {module, arg}
  end

  defp normalize_server(module, default_arg) when is_atom(module) do
    {module, default_arg}
  end

  @impl true
  def handle_call({:"$gen_mcp", :request, req, channel}, _from, state) do
    state = refresh_session_timeout(state)

    case state.server_mod.handle_request(req, channel, state.server_state) do
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
    :telemetry.execute([:gen_mcp, :session, :terminate], %{}, %{
      session_id: state.session_id,
      server: state.server_mod,
      reason: :client_delete,
      pid: self()
    })

    {:stop, {:shutdown, :mcp_stop}, :ok, state}
  end

  @impl true
  def handle_info({:timeout, tref, :session_timeout}, state) do
    case state.session_timeout_ref do
      ^tref ->
        :telemetry.execute([:gen_mcp, :session, :terminate], %{}, %{
          session_id: state.session_id,
          server: state.server_mod,
          reason: :timeout,
          pid: self()
        })

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
    _ = Process.cancel_timer(state.session_timeout_ref, async: true, info: false)
    %{state | session_timeout_ref: start_session_timeout(state.conf.session_timeout)}
  end
end
