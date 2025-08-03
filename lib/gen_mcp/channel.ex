defmodule GenMcp.Channel do
  alias GenMcp.Entities.ProgressNotification

  defstruct [:kind, :session, :client, :progress_token]

  def send_progress(channel, progress, total \\ nil, message \\ nil)

  def send_progress(%{progress_token: nil}, _, _, _) do
    :ok
  end

  def send_progress(%{progress_token: token} = channel, progress, total, message) do
    payload =
      %ProgressNotification{
        method: "notifications/progress",
        params: %{progress: progress, progressToken: token, total: total, message: message}
      }

    case channel do
      %{client: [:alias | ref]} -> send(ref, {:"$gen_mcp", :progress, payload})
    end
  end
end
