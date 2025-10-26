defmodule GenMcp.Mux.Channel do
  alias GenMcp.Mcp.Entities.ProgressNotification

  defstruct [:client, :progress_token]

  @type t :: %__MODULE__{client: pid, progress_token: nil | binary | integer}
  @type chan_info :: {:channel, GenMcp.Plug.StreamableHttp, pid}

  def from_client({:channel, GenMcp.Plug.StreamableHttp, pid}, req) do
    progress_token =
      case req do
        %{params: %{_meta: %{"progressToken" => pt}}} -> pt
        _ -> nil
      end

    %__MODULE__{
      client: pid,
      progress_token: progress_token
    }
  end

  def send_progress(channel, progress, total \\ nil, message \\ nil)

  def send_progress(%{progress_token: nil} = channel, _, _, _) do
    channel
  end

  def send_progress(%{progress_token: token} = channel, progress, total, message) do
    payload =
      %ProgressNotification{
        method: "notifications/progress",
        params: %{progress: progress, progressToken: token, total: total, message: message}
      }

    send(channel.client, {:"$gen_mcp", :notification, payload})
    channel
  end

  def send_result(channel, payload) do
    send(channel.client, {:"$gen_mcp", :result, payload})
    channel
  end
end
