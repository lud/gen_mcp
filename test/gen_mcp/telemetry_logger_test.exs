defmodule GenMCP.TelemetryLoggerTest do
  # async: false — asserts on the process-global Logger and the app-wide
  # `GenMCP.TelemetryLogger` handler (already attached at boot in non-prod, see
  # `GenMCP.Application`). We only emit events here; we never (de)attach.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  # Drives the realigned event contract from spec 013: every event the stateless
  # core emits must map to a handled log line at the documented level. If an
  # event is not in the `events` map it is never subscribed, so emitting it logs
  # nothing and the matching assertion fails — which is the signal to wire it up.
  setup do
    prev_level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: prev_level) end)
    :ok
  end

  defp emit_log(event, meta) do
    capture_log(fn ->
      :telemetry.execute(event, %{}, meta)
      Logger.flush()
    end)
  end

  test "server init logs at :debug with the server module" do
    log =
      emit_log([:gen_mcp, :server, :init], %{
        server_mod: GenMCP.TelemetryLoggerTest.FakeServer,
        server_arg: :arg,
        owner: self()
      })

    assert log =~ "[debug]"
    assert log =~ "FakeServer"
  end

  test "server start_error logs at :error with the reason" do
    log = emit_log([:gen_mcp, :server, :start_error], %{reason: :max_children})

    assert log =~ "[error]"
    assert log =~ "max_children"
  end

  test "transport server_crashed logs at :error" do
    log = emit_log([:gen_mcp, :transport, :server_crashed], %{reason: :server_crashed})

    assert log =~ "[error]"
  end

  test "transport version_rejected logs at :debug with the rejected version" do
    log =
      emit_log([:gen_mcp, :transport, :version_rejected], %{
        reason: {:unsupported_protocol_version, "1999-01-01"}
      })

    assert log =~ "[debug]"
    assert log =~ "1999-01-01"
  end

  test "transport request_rejected logs at :debug" do
    log = emit_log([:gen_mcp, :transport, :request_rejected], %{reason: :bad_rpc})

    assert log =~ "[debug]"
  end
end
