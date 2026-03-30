defmodule GenMCP.Mux.Channel do
  alias GenMCP.MCP.LoggingMessageNotification
  alias GenMCP.MCP.ProgressNotification

  @log_levels Enum.map(GenMCP.MCP.LoggingLevel.json_schema().enum, &String.to_atom/1)

  @enforce_keys [:client, :progress_token, :status, :assigns, :log_level]
  defstruct @enforce_keys

  @type status :: :request | :stream | :closed

  @type log_level ::
          :debug | :info | :notice | :warning | :error | :critical | :alert | :emergency

  @type t :: %__MODULE__{
          client: pid | nil,
          status: status,
          progress_token: nil | binary | integer,
          assigns: map(),
          log_level: log_level() | nil
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

    create_new(self(), progress_token, assigns)
  end

  @doc false
  def for_pid(pid, assigns \\ %{}) do
    create_new(pid, nil, assigns)
  end

  defp create_new(owner_pid, progress_token, assigns) do
    %__MODULE__{
      client: owner_pid,
      progress_token: progress_token,
      assigns: assigns,
      status: :request,
      log_level: GenMCP.default_channel_log_level()
    }
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
        params: %{progress: progress, progressToken: token, total: total, message: message}
      }

    send(channel.client, {:"$gen_mcp", :notification, payload})
    :ok
  end

  @doc """
  Sends a log message notification to the client if the message level is at or
  above the channel's configured log level.

  Returns `:ok` if the message was sent or filtered out, `{:error, :closed}` if
  the channel is closed.
  """
  def send_log(channel, level, data, logger \\ nil)

  def send_log(%{status: :closed}, _level, _data, _logger) do
    {:error, :closed}
  end

  def send_log(%{log_level: min_level}, _level, _data, _logger)
      when min_level not in @log_levels do
    {:error, :invalid_min_level}
  end

  def send_log(%{log_level: _}, level, _data, _logger) when level not in @log_levels do
    {:error, :invalid_level}
  end

  def send_log(%{log_level: min_level} = channel, level, data, logger)
      when min_level in @log_levels and level in @log_levels do
    if :logger.compare_levels(level, min_level) in [:gt, :eq] do
      payload = %LoggingMessageNotification{
        params: %{level: level, data: data, logger: logger}
      }

      send(channel.client, {:"$gen_mcp", :notification, payload})
    end

    :ok
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
