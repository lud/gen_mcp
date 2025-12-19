defmodule GenMCP.Test.Helpers do
  @moduledoc false
  alias GenMCP.Cluster.NodeSync

  def check_error({:error, reason}) do
    check_error(reason)
  end

  def check_error(reason) do
    GenMCP.RpcError.cast_error(reason)
  end

  def build_channel(assigns \\ %{}) do
    GenMCP.Mux.Channel.for_pid(self(), assigns)
  end

  def random_session_id do
    NodeSync.gen_session_id()
  end
end
