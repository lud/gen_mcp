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

  import GenMCP.Utils.CallbackExt

  alias GenMCP.Utils.OptsValidator

  require GenMCP
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

    case OptsValidator.validate_take_opts(opts, @init_opts_schema) do
      {:ok, self_opts, server_opts} ->
        GenServer.start_link(__MODULE__, {self_opts, server_opts}, gen_opts)

      {:error, _} = err ->
        err
    end
  end

  def fetch_restore_data(session_id, channel, opts) do
    opts = Keyword.put(opts, :session_id, session_id)

    case OptsValidator.validate_take_opts(opts, @init_opts_schema) do
      {:ok, self_opts, server_opts} ->
        server = Keyword.fetch!(self_opts, :server)
        {server_mod, server_arg} = normalize_server(server, server_opts)

        callback GenMCP, server_mod.session_fetch(session_id, channel, server_arg) do
          {:ok, session_data} -> {:ok, session_data}
          {:error, :not_found} = err -> err
        end

      {:error, _} = err ->
        err
    end
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
  def init({self_opts, server_opts}) do
    conf = init_self({self_opts, server_opts})

    case init_server(conf) do
      {:ok, server_state} ->
        state = %State{
          server_mod: conf.server_mod,
          server_state: server_state,
          session_id: conf.session_id,
          session_timeout_ref: start_session_timeout(conf.session_timeout),
          conf: conf
        }

        {:ok, state}

      {:stop, _} = stop ->
        stop
    end
  end

  defp init_self({self_opts, server_opts}) do
    session_timeout = Keyword.fetch!(self_opts, :session_timeout)
    session_id = Keyword.fetch!(self_opts, :session_id)
    server = Keyword.fetch!(self_opts, :server)
    {server_mod, server_arg} = normalize_server(server, server_opts)

    :telemetry.execute([:gen_mcp, :session, :init], %{}, %{
      session_id: session_id,
      server: server_mod
    })

    %{
      session_id: session_id,
      server_mod: server_mod,
      server_arg: server_arg,
      session_timeout: session_timeout
    }
  end

  defp init_server(conf) do
    require GenMCP

    callback GenMCP, conf.server_mod.init(conf.session_id, conf.server_arg) do
      {:ok, server_state} -> {:ok, server_state}
      {:stop, reason} -> {:stop, {:mcp_server_init_failure, reason}}
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

    callback GenMCP, state.server_mod.handle_request(req, channel, state.server_state) do
      {:reply, reply, server_state}
      when elem(reply, 0) == :result
      when reply == :stream
      when elem(reply, 0) == :error ->
        {:reply, reply, %{state | server_state: server_state}}

      {:stop, reason, reply, server_state}
      when elem(reply, 0) == :result
      when elem(reply, 0) == :error ->
        {:stop, reason, reply, %{state | server_state: server_state}}
    end
  end

  def handle_call({:"$gen_mcp", :notification, notif}, _from, state) do
    # TODO Handle error/noreply return ?
    state = refresh_session_timeout(state)

    callback GenMCP, state.server_mod.handle_notification(notif, state.server_state) do
      {:noreply, server_state} ->
        {:reply, :ack, %{state | server_state: server_state}}
    end
  end

  def handle_call({:"$gen_mcp", :restore_session, session_data, channel}, _from, state) do
    state = refresh_session_timeout(state)

    :telemetry.execute([:gen_mcp, :session, :restore], %{}, %{
      session_id: state.session_id,
      server: state.server_mod,
      session_data: session_data
    })

    callback GenMCP,
             state.server_mod.session_restore(session_data, channel, state.server_state) do
      {:noreply, server_state} ->
        {:reply, :ok, %{state | server_state: server_state}}

      {:stop, reason, server_state} ->
        :telemetry.execute([:gen_mcp, :session, :restore_error], %{}, %{
          session_id: state.session_id,
          server: state.server_mod,
          session_data: session_data,
          reason: reason
        })

        {:stop, {:shutdown, {:session_restore_error, reason}}, {:error, reason},
         %{state | server_state: server_state}}
    end
  end

  def handle_call({:"$gen_mcp", :delete_session}, _from, state) do
    :telemetry.execute([:gen_mcp, :session, :delete], %{}, %{
      session_id: state.session_id,
      server: state.server_mod,
      reason: :client_delete
    })

    _ = state.server_mod.session_delete(state.server_state)
    {:stop, {:shutdown, :session_deleted}, :ok, state}
  end

  # TODO session timeout should be handled by the server, so if there is any
  # async tool in progress or GET stream it could return {:snooze, ms} | :stop

  @impl true
  def handle_info({:timeout, tref, :session_timeout}, state) do
    case state.session_timeout_ref do
      ^tref ->
        :telemetry.execute([:gen_mcp, :session, :terminate], %{}, %{
          session_id: state.session_id,
          server: state.server_mod,
          reason: :timeout
        })

        {:stop, {:shutdown, :session_timeout}, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(info, state) do
    state = refresh_session_timeout(state)

    callback GenMCP, state.server_mod.handle_info(info, state.server_state) do
      {:noreply, server_state} ->
        {:noreply, %{state | server_state: server_state}}

      {:stop, reason, server_state} ->
        {:stop, reason, %{state | server_state: server_state}}
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
