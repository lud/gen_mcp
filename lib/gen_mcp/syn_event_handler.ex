defmodule GenMCP.SynEventHandler do
  @moduledoc false

  @behaviour :syn_event_handler

  @impl true
  def resolve_registry_conflict(
        :gen_mcp_sessions,
        session_id,
        {pid1, _meta1, time1},
        {pid2, _meta2, time2}
      ) do
    {surviving, killed} =
      if time1 <= time2 do
        {pid1, pid2}
      else
        {pid2, pid1}
      end

    :telemetry.execute([:gen_mcp, :cluster, :conflict], %{}, %{
      session_id: session_id,
      killed_pid: killed,
      surviving_pid: surviving
    })

    surviving
  end
end
