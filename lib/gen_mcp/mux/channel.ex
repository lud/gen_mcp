defmodule GenMCP.Mux.Channel do
  alias GenMCP.Entities.ProgressNotification

  @enforce_keys [:client, :progress_token]
  defstruct @enforce_keys ++ [:assigns]

  @type t :: %__MODULE__{
          client: pid,
          progress_token: nil | binary | integer,
          assigns: map()
        }
  @type chan_info :: {:channel, module, pid}

  def from_client({:channel, _module, pid, assigns}, req) when is_pid(pid) do
    progress_token =
      case req do
        %{params: %{_meta: %{"progressToken" => pt}}} -> pt
        _ -> nil
      end

    %__MODULE__{
      client: pid,
      progress_token: progress_token,
      assigns: assigns
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

  def send_error(channel, error) do
    send(channel.client, {:"$gen_mcp", :error, error})
    channel
  end
end
