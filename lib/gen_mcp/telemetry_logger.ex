defmodule GenMCP.TelemetryLogger do
  events = %{
    # Server worker
    [:gen_mcp, :server, :init] => :debug,
    [:gen_mcp, :server, :start_error] => :error,

    # Transport
    [:gen_mcp, :transport, :server_crashed] => :error,
    [:gen_mcp, :transport, :version_rejected] => :debug,
    [:gen_mcp, :transport, :request_rejected] => :debug
  }

  @moduledoc """
  A `:telemetry` handler that logs the events emitted by the `:gen_mcp`
  application.

  Attaching it gives you ready-made `Logger` output for the lifecycle and
  transport events the library emits, each at a fixed log level. It is the
  quickest way to see what the server is doing without writing your own
  `:telemetry` handler.

  ### Attaching the logger

  Attach the handler once when your application boots, from your
  `Application.start/2` callback:

      defmodule MyApp.Application do
        use Application

        @impl true
        def start(_type, _args) do
          :ok = GenMCP.TelemetryLogger.attach()

          children = [
            # your supervision tree
          ]

          Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
        end
      end

  `GenMCP.attach_default_logger/1` is a thin wrapper over `attach/1`, so calling
  either one has the same effect. Pass filters to narrow what is logged, for
  example to keep only the more severe events:

      :ok = GenMCP.TelemetryLogger.attach(min_log_level: :error)

  See `attach/1` for the full list of filters.

  ### Events

  Here are the emitted events for the library, and the corresponding log level
  used for each one.

  #{events |> Enum.sort() |> Enum.map(fn {evt, log_level} -> """
    * `#{inspect(evt)}` with a log level of `#{inspect(log_level)}`
    """ end)}
  """

  require Logger

  @events events

  defp events do
    @events
  end

  @doc """
  Attaches the telemetry handler that logs `:gen_mcp` events.

  Call this once at startup (see the module doc for placement in
  `Application.start/2`). It subscribes a single `:telemetry` handler, named
  after this module, to the events listed in the module doc, and returns `:ok`
  on success.

  By default every event is logged at its mapped level. Pass `filters` to
  subscribe to a subset:

    * `:min_log_level` - keep only events whose mapped level is at least this
      severe. For example `min_log_level: :error` drops the `:debug` events and
      keeps the `:error` ones.
    * `:prefixes` - a list of event-name prefixes; keep only events whose name
      starts with one of them. For example `prefixes: [[:gen_mcp, :transport]]`
      keeps only the transport events.

  ### Examples

  Attach every event at its default level:

      :ok = GenMCP.TelemetryLogger.attach()

  Attach only transport events logged at `:error` or above:

      :ok =
        GenMCP.TelemetryLogger.attach(
          min_log_level: :error,
          prefixes: [[:gen_mcp, :transport]]
        )
  """
  def attach(filters \\ []) do
    :telemetry.attach_many(
      __MODULE__,
      filter_events(events(), filters),
      &__MODULE__.handle_event/4,
      []
    )
  end

  defp filter_events(events_map, []) do
    Map.keys(events_map)
  end

  defp filter_events(events_map, filters) do
    events_map =
      case filters[:min_log_level] do
        nil ->
          events_map

        min_level ->
          Map.filter(events_map, fn {_, level} ->
            :logger.compare_levels(level, min_level) in [:gt, :eq]
          end)
      end

    events_map =
      case filters[:prefixes] do
        prefixes when is_list(prefixes) ->
          Map.filter(events_map, fn {k, _} -> Enum.any?(prefixes, &List.starts_with?(k, &1)) end)

        nil ->
          events_map
      end

    Map.keys(events_map)
  end

  @doc false

  def handle_event([:gen_mcp, :server, :init] = p, _, %{server_mod: server_mod, server_arg: _}, _) do
    log(p, "gen_mcp server initializing with #{inspect(server_mod)}", %{
      gen_mcp_server_mod: server_mod
    })
  end

  def handle_event([:gen_mcp, :server, :start_error] = p, _, %{reason: reason}, _) do
    log(p, "gen_mcp server failed to start: #{inspect(reason)}")
  end

  def handle_event([:gen_mcp, :transport, :server_crashed] = p, _, %{reason: reason}, _) do
    log(p, "gen_mcp request worker crashed before replying: #{inspect(reason)}")
  end

  def handle_event([:gen_mcp, :transport, :version_rejected] = p, _, %{reason: reason}, _) do
    log(p, "gen_mcp rejected request protocol version: #{inspect(reason)}")
  end

  def handle_event([:gen_mcp, :transport, :request_rejected] = p, _, %{reason: reason}, _) do
    log(p, "gen_mcp rejected request: #{inspect(reason)}")
  end

  # -- event catchall ---------------------------------------------------------

  if Mix.env() == :test do
    def handle_event(other, _, meta, _) do
      keymap = ["%{", Enum.map_intersperse(meta, ", ", fn {k, _} -> "#{k}: #{k}" end), "}"]

      Logger.error("""
      unhandled telemetry event #{inspect(other)} with #{inspect(meta)}

      Add the following code
      in #{__ENV__.file}:#{__ENV__.line - 11}

          def handle_event(#{inspect(other)} = p, _, #{keymap},_) do
            log(p, "...")
          end

      """)

      Logger.flush()
      System.halt(1)
    end
  else
    def handle_event(_other, _, _meta, _) do
      :ok
    end
  end

  defp log(prefix, message, metadata \\ []) do
    level = Map.fetch!(events(), prefix)
    Logger.log(level, message, metadata)
  end
end
