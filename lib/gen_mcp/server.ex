defmodule GenMCP.Server do
  @moduledoc false
  use GenServer, restart: :temporary

  import GenMCP.Utils.CallbackExt

  alias GenMCP.Mux.Channel
  alias GenMCP.Utils.OptsValidator

  @enforce_keys [:server_mod, :server_state, :owner, :mref, :channel]
  defstruct @enforce_keys

  @init_opts_schema NimbleOptions.new!(
                      owner: [
                        type: :pid,
                        required: true,
                        # The transport process identifier
                        doc: false
                      ],
                      server: [
                        type: {:or, [:atom, :mod_arg]},
                        default: GenMCP.Suite,
                        doc:
                          "The `GenMCP` behaviour server implemetation that will handle MCP messages." <>
                            " If a simple atom, it will receive all other options given to the session."
                      ]
                    )

  def init_opts_schema do
    @init_opts_schema
  end

  # -- Starting workers --------------------------------------------------------

  # Every validated JSON-RPC message is dispatched to a fresh worker carrying
  # an initiator: `{:request, req, channel}` or `{:notification, notif}`. The
  # worker runs `init/1` then the matching handler from a continue — no call
  # round-trip. The caller (the transport relay) monitors the returned pid and
  # consumes the `{:"$gen_mcp", ...}` messages the worker emits.

  def start_request(opts, req, channel) do
    start_worker(Keyword.put(opts, :owner, channel.client), {:request, req, channel})
  end

  def start_notification(opts, notif, channel) do
    start_worker(Keyword.put(opts, :owner, channel.client), {:notification, notif, channel})
  end

  defp start_worker(opts, initiator) do
    child_spec = {__MODULE__, {opts, initiator}}

    case DynamicSupervisor.start_child(GenMCP.ServerSupervisor, child_spec) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, reason} ->
        :telemetry.execute([:gen_mcp, :server, :start_error], %{}, %{reason: reason})

        {:error, reason}
    end
  end

  # -- Worker ------------------------------------------------------------------

  def start_link({opts, initiator}) do
    case OptsValidator.validate_take_opts(opts, @init_opts_schema) do
      {:ok, wrapper_opts, server_opts} ->
        server = Keyword.fetch!(wrapper_opts, :server)
        owner = Keyword.fetch!(wrapper_opts, :owner)
        true = is_pid(owner)
        {server_mod, server_arg} = normalize_server(server, server_opts)
        GenServer.start_link(__MODULE__, {server_mod, server_arg, owner, initiator})

      {:error, _} = err ->
        err
    end
  end

  defp normalize_server({module, arg}, _) when is_atom(module) do
    {module, arg}
  end

  defp normalize_server(module, default_arg) when is_atom(module) do
    {module, default_arg}
  end

  def init({server_mod, server_arg, owner, initiator}) do
    :telemetry.execute([:gen_mcp, :server, :init], %{}, %{
      server_mod: server_mod,
      server_arg: server_arg,
      owner: owner
    })

    mref = :erlang.monitor(:process, owner, tag: :CHAN_DOWN)

    callback GenMCP, server_mod.init(server_arg) do
      {:ok, server_state} ->
        state = %__MODULE__{
          server_mod: server_mod,
          server_state: server_state,
          owner: owner,
          mref: mref,
          channel: initiator_channel(initiator)
        }

        {:ok, state, {:continue, initiator}}

      {:stop, reason} ->
        {:error, reason}
    end
  end

  defp initiator_channel({:request, _req, channel}) do
    channel
  end

  defp initiator_channel({:notification, _notif, channel}) do
    channel
  end

  def handle_continue({:request, req, _channel}, state) do
    %__MODULE__{
      server_mod: server_mod,
      server_state: server_state,
      owner: owner,
      channel: channel
    } = state

    callback GenMCP, server_mod.handle_request(req, channel, server_state) do
      {:result, result} ->
        send(owner, {:"$gen_mcp", :result, result})
        {:stop, {:shutdown, :reply}, state}

      {:error, reason} ->
        send(owner, {:"$gen_mcp", :error, reason})
        {:stop, {:shutdown, :reply}, state}

      {:stream, server_state} ->
        send(owner, {:"$gen_mcp", :stream})
        {:noreply, %{state | server_state: server_state}}
    end
  end

  def handle_continue({:notification, notif, _channel}, state) do
    callback GenMCP,
             state.server_mod.handle_notification(notif, state.channel, state.server_state) do
      :ok ->
        send(state.owner, {:"$gen_mcp", :accepted})
        {:stop, {:shutdown, :reply}, state}
    end
  end

  def handle_info({:CHAN_DOWN, mref, :process, _pid, _reason}, %__MODULE__{mref: mref} = state) do
    {:stop, {:shutdown, :client_disconnected}, terminate_server(state)}
  end

  # received as an acknowledgement of server-initiated close
  def handle_info({:"$gen_mcp", :closed}, state) do
    {:stop, {:shutdown, :closed}, terminate_server(state)}
  end

  def handle_info(msg, state) do
    %__MODULE__{
      server_mod: server_mod,
      server_state: server_state,
      owner: owner,
      channel: channel
    } = state

    callback GenMCP, server_mod.handle_message(msg, channel, server_state) do
      {:result, result} ->
        send(owner, {:"$gen_mcp", :result, result})
        {:stop, {:shutdown, :reply}, state}

      {:error, reason} ->
        send(owner, {:"$gen_mcp", :error, reason})
        {:stop, {:shutdown, :reply}, state}

      {:stream, server_state} ->
        send(owner, {:"$gen_mcp", :stream})
        {:noreply, %{state | server_state: server_state}}

      # End the stream with no final result (a listener's exit). Implementations
      # should return :normal, :shutdown or {:shutdown, term} for a clean exit.
      {:stop, reason} ->
        {:stop, reason, state}
    end
  end

  defp terminate_server(state) do
    channel = Channel.set_closed(state.channel)

    if function_exported?(state.server_mod, :handle_close, 2) do
      _ = state.server_mod.handle_close(channel, state.server_state)
    end

    %{state | channel: channel}
  end
end
