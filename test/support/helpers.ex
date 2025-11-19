defmodule GenMCP.Test.Helpers do
  @moduledoc false

  def chan_info(assigns \\ %{}) do
    {:channel, __MODULE__, self(), assigns}
  end

  def check_error({:error, reason}) do
    check_error(reason)
  end

  def check_error(reason) do
    GenMCP.RpcError.cast_error(reason)
  end

  def build_channel(assigns \\ %{}) do
    %GenMCP.Mux.Channel{client: self(), progress_token: nil, assigns: assigns}
  end
end
