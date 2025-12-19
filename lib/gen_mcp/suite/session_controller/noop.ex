defmodule GenMCP.Suite.SessionController.Noop do
  @moduledoc false
  @behaviour GenMCP.Suite.SessionController

  @impl true
  def fetch(_session_id, _channel, _arg) do
    {:error, :not_found}
  end

  @impl true
  def create(_session_id, _client_info, channel, arg) do
    {:ok, channel, arg}
  end

  @impl true
  def update(_session_id, _client_info, channel, arg) do
    {:ok, channel, arg}
  end

  @impl true
  @spec restore(term, term, term) :: no_return
  def restore(_restore_data, _channel, _arg) do
    raise "#{inspect(__MODULE__)} does not support restoring sessions"
  end

  @impl true
  def handle_info(msg, _channel, session_state) do
    _ = GenMCP.Suite.log_unhandled_info(msg)
    {:noreply, session_state}
  end

  @impl true
  def delete(_session_id, _session_state) do
    :ok
  end

  @impl true
  def listener_change(channel, session_state) do
    {:ok, channel, session_state}
  end
end
