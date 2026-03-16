defmodule GenMCP.Test.ClusterTestHelper do
  @moduledoc false

  alias GenMCP.Support.ServerMock

  def start_session_on_peer do
    # Reset Mox ownership on the peer so we can set expectations locally
    Mox.set_mox_from_context(%{})
    Mox.stub(ServerMock, :init, fn _, _ -> {:ok, :peer_state} end)
    GenMCP.Mux.start_session(server: ServerMock)
  end
end
