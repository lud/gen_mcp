defmodule GenMCP.Test.Helpers do
  @moduledoc false

  def check_error({:error, reason}) do
    check_error(reason)
  end

  def check_error(reason) do
    GenMCP.RpcError.cast_error(reason)
  end

  def build_channel(assigns \\ %{}) do
    GenMCP.Mux.Channel.for_pid(self(), assigns)
  end
end
