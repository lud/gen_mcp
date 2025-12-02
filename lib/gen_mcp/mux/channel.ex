defmodule GenMCP.Mux.Channel do
  alias GenMCP.MCP.ProgressNotification

  @enforce_keys [:client, :progress_token]
  defstruct @enforce_keys ++ [:assigns]

  @type t :: %__MODULE__{
          client: pid,
          progress_token: nil | binary | integer,
          assigns: map()
        }

  @doc """
  Returns a channel identifying the calling process.
  """
  def from_request(req, assigns \\ %{}) do
    progress_token =
      case req do
        %{params: %{_meta: %{"progressToken" => pt}}} -> pt
        _ -> nil
      end

    %__MODULE__{client: self(), progress_token: progress_token, assigns: assigns}
  end

  @doc false
  def for_pid(pid, assigns \\ %{}) do
    %__MODULE__{client: pid, progress_token: nil, assigns: assigns}
  end

  def with_default_assigns(%__MODULE__{assigns: assigns} = chan, default_assigns) do
    %{chan | assigns: Map.merge(default_assigns, assigns)}
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

  @spec assign(t, atom, term) :: t
  def assign(%__MODULE__{assigns: assigns} = channel, key, value) when is_atom(key) do
    %{channel | assigns: Map.put(assigns, key, value)}
  end
end
