defmodule GenMCPTest do
  use ExUnit.Case

  doctest GenMCP

  test "the GenMCP behaviour exposes only the stateless callbacks" do
    # No session_fetch/session_restore/session_delete/session_timeout: the
    # 2026-07-28 core is stateless and a module implementing GenMCP defines
    # exactly the per-request lifecycle (spec 004).
    assert [handle_message: 3, handle_notification: 3, handle_request: 3, init: 1] ==
             Enum.sort(GenMCP.behaviour_info(:callbacks))
  end
end
