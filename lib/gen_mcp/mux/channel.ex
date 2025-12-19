defmodule GenMCP.Mux.Channel do
  alias GenMCP.MCP.ProgressNotification

  @enforce_keys [:client, :progress_token, :status, :assigns]
  defstruct @enforce_keys

  @type status :: :request | :stream | :closed

  @type t :: %__MODULE__{
          client: pid | nil,
          status: status,
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

    %__MODULE__{
      client: self(),
      progress_token: progress_token,
      assigns: assigns,
      status: :request
    }
  end

  @doc false
  def for_pid(pid, assigns \\ %{}) do
    %__MODULE__{client: pid, progress_token: nil, assigns: assigns, status: :request}
  end

  def with_default_assigns(%__MODULE__{assigns: assigns} = channel, default_assigns) do
    %{channel | assigns: Map.merge(default_assigns, assigns)}
  end

  def send_progress(channel, progress, total \\ nil, message \\ nil)

  def send_progress(%{status: :closed}, _, _, _) do
    {:error, :closed}
  end

  def send_progress(%{progress_token: nil}, _, _, _) do
    {:error, :no_progress_token}
  end

  def send_progress(%{progress_token: token} = channel, progress, total, message) do
    payload =
      %ProgressNotification{
        method: "notifications/progress",
        params: %{progress: progress, progressToken: token, total: total, message: message}
      }

    send(channel.client, {:"$gen_mcp", :notification, payload})
    {:ok, channel}
  end

  def send_result(%{status: :closed}, _payload) do
    {:error, :closed}
  end

  def send_result(channel, payload) do
    send(channel.client, {:"$gen_mcp", :result, payload})
    {:ok, channel}
  end

  def send_error(%{status: :closed}, _error) do
    {:error, :closed}
  end

  def send_error(channel, error) do
    send(channel.client, {:"$gen_mcp", :error, error})
    {:ok, channel}
  end

  @doc """
  Sends a message event with the given `data`, a binary that will be sent as-is
  to the client.

  To be a valid SSE event, the data must not contain any newlines.
  """
  def send_message(%{status: :closed}, data) when is_binary(data) do
    {:error, :closed}
  end

  def send_message(channel, data) when is_binary(data) do
    send(channel.client, {:"$gen_mcp", :raw_message, data})
    {:ok, channel}
  end

  @doc """
  Sends a termination message to the open HTTP connection. When this function
  returns, the HTTP connection may not have terminated yet.
  """
  def close(%{status: :closed}) do
    {:error, :closed}
  end

  # If the status is request we send the message anyway because the channel can
  # be converted to a stream later, and it will receive the message
  def close(%{status: status} = channel) when status in [:stream, :request] do
    send(channel.client, {:"$gen_mcp", :close})
    {:ok, %{channel | status: :closed}}
  end

  @spec assign(t, atom, term) :: t
  def assign(%__MODULE__{assigns: assigns} = channel, key, value) when is_atom(key) do
    %{channel | assigns: Map.put(assigns, key, value)}
  end

  def set_streaming(%__MODULE__{status: :request} = t) do
    %{t | status: :stream}
  end

  def set_streaming(%__MODULE__{status: :stream} = t) do
    t
  end

  @doc """
  Used by server implementations when a channel process exits (generally
  observed by a monitor). Sets the channel status as closed and prevents sending
  messages.
  """
  def as_closed(t) do
    %{t | status: :closed, client: nil}
  end
end
