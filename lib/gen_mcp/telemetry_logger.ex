# quokka:skip-module-directive-reordering

defmodule GenMCP.TelemetryLogger do
  events = %{
    # Cluster
    [:gen_mcp, :cluster, :joined] => :info,
    [:gen_mcp, :cluster, :left] => :info,
    [:gen_mcp, :cluster, :conflict] => :warning,
    [:gen_mcp, :cluster, :error] => :error,
    [:gen_mcp, :cluster, :status] => :debug,

    # Session.
    [:gen_mcp, :session, :init] => :debug,
    [:gen_mcp, :session, :restore] => :debug,
    [:gen_mcp, :session, :delete] => :debug,
    [:gen_mcp, :session, :start_error] => :error,
    [:gen_mcp, :session, :restore_error] => :error,

    # Suite
    [:gen_mcp, :suite, :error, :unknown_request] => :error
  }

  @moduledoc """
  A `:telemetry` event listener that produces logs for events emitted by the
  `:gen_mcp` application.

  ## Events

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

  def handle_event(
        [:gen_mcp, :suite, :error, :unknown_request] = p,
        _,
        %{request: request, session_id: session_id},
        _
      ) do
    log(p, fn ->
      {"gen_mcp suite received an unknown request: #{inspect(request)}",
       %{gen_mcp_session_id: session_id}}
    end)
  end

  def handle_event(
        [:gen_mcp, :session, :init] = p,
        _,
        %{server: server, session_id: session_id},
        _
      ) do
    log(p, "gen_mcp session initializing with #{inspect(server)}", %{
      gen_mcp_session_id: session_id
    })
  end

  def handle_event(
        [:gen_mcp, :session, :restore] = p,
        _,
        %{server: server, session_id: session_id},
        _
      ) do
    log(p, "gen_mcp restoring session with #{inspect(server)}", %{gen_mcp_session_id: session_id})
  end

  def handle_event(
        [:gen_mcp, :session, :restore_error] = p,
        _,
        %{reason: reason, server: server, session_id: session_id},
        _
      ) do
    log(p, "gen_mcp session restore error from server #{inspect(server)}: #{inspect(reason)}", %{
      gen_mcp_session_id: session_id
    })
  end

  def handle_event(
        [:gen_mcp, :session, :delete] = p,
        _,
        %{reason: reason, session_id: session_id},
        _
      ) do
    log(p, "gen_mcp delete session for: #{inspect(reason)}", %{gen_mcp_session_id: session_id})
  end

  def handle_event(
        [:gen_mcp, :session, :start_error] = p,
        _,
        %{reason: reason, session_id: session_id},
        _
      ) do
    log(p, "gen_mcp session start error: #{inspect(reason)}", %{gen_mcp_session_id: session_id})
  end

  def handle_event([:gen_mcp, :cluster, :joined] = p, _, %{node: node, node_id: node_id}, _) do
    log(p, "gen_mcp node #{node} joined as #{node_id}")
  end

  def handle_event([:gen_mcp, :cluster, :left] = p, _, %{node: node, node_id: node_id}, _) do
    log(p, "gen_mcp node #{node}  as #{node_id}")
  end

  def handle_event([:gen_mcp, :cluster, :conflict] = p, _, %{node: node, node_id: node_id}, _) do
    log(p, "gen_mcp peer #{node} shutting down, duplicated node id #{node_id}")
  end

  def handle_event([:gen_mcp, :cluster, :error] = p, _, %{message: message}, _) do
    log(p, message)
  end

  def handle_event([:gen_mcp, :cluster, :status] = p, _, %{peers: peers}, _) do
    log(p, fn ->
      as_text =
        Enum.map_intersperse(peers, ?\s, fn %{node_id: node_id, node: node} ->
          [node_id, "/", Atom.to_string(node)]
        end)

      "gen_mcp cluster map #{as_text}"
    end)
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
