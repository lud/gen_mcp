defmodule GenMCP.Mux.Channel do
  @log_levels Enum.map(GenMCP.MCP.V2607.LoggingLevel.json_schema().enum, &String.to_atom/1)

  alias GenMCP.MCP.V2607, as: MCP

  @enforce_keys [:client, :progress_token, :status, :log_level, :meta, :endpoint, :request_id]
  defstruct @enforce_keys

  @type status :: :request | :stream | :closed

  @type log_level ::
          :debug | :info | :notice | :warning | :error | :critical | :alert | :emergency

  @type meta :: %{
          client_info: GenMCP.MCP.V2607.Implementation.t() | nil,
          client_capabilities: GenMCP.MCP.V2607.ClientCapabilities.t() | nil,
          protocol_version: binary | nil
        }

  @type t :: %__MODULE__{
          client: pid | nil,
          status: status,
          progress_token: nil | binary | integer,
          log_level: log_level() | nil,
          meta: meta,
          endpoint: nil | module,
          request_id: binary | integer | nil
        }

  @empty_meta %{client_info: nil, client_capabilities: nil, protocol_version: nil}

  @doc """
  Returns a channel identifying the calling process.

  The progress token and the per-request log level are read from the request
  `_meta`. The log level comes from `io.modelcontextprotocol/logLevel`; when it is
  absent the channel's `log_level` is `nil` and logging is **disabled** (the
  server MUST NOT emit `notifications/message` — see `send_log/4`). The transport
  is expected to have already rejected an unrecognized level with `-32602`, so
  only a valid level or `nil` reaches here.

  The other `io.modelcontextprotocol/*` request `_meta` fields are extracted into
  the write-once `meta` field: `client_info`, `client_capabilities` and
  `protocol_version`. They are read-only request context, not handler state.
  """
  def from_request(conn, req, meta_assigns \\ %{}) do
    endpoint =
      case conn do
        %{private: %{phoenix_endpoint: endpoint}} -> endpoint
        _ -> nil
      end

    %__MODULE__{
      client: self(),
      request_id: request_id_from_request(req),
      endpoint: endpoint,
      progress_token: progress_token_from_request(req),
      status: :request,
      log_level: log_level_from_request(req),
      meta: Map.merge(meta_assigns, meta_from_request(req))
    }
  end

  defp progress_token_from_request(req) do
    case req do
      %{params: %{_meta: %{progressToken: pt}}} -> pt
      _ -> nil
    end
  end

  defp log_level_from_request(req) do
    case req do
      %{params: %{_meta: %{"io.modelcontextprotocol/logLevel": lvl}}} when lvl in @log_levels ->
        lvl

      _ ->
        nil
    end
  end

  defp meta_from_request(req) do
    case req do
      %{params: %{_meta: %{} = meta}} ->
        %{
          client_info: Map.get(meta, :"io.modelcontextprotocol/clientInfo"),
          client_capabilities: Map.get(meta, :"io.modelcontextprotocol/clientCapabilities"),
          protocol_version: Map.get(meta, :"io.modelcontextprotocol/protocolVersion")
        }

      _ ->
        @empty_meta
    end
  end

  defp request_id_from_request(req) do
    case req do
      %{id: id} -> id
      _ -> nil
    end
  end

  @doc false
  def for_pid(pid, meta_assigns \\ %{}) do
    %__MODULE__{
      client: pid,
      request_id: nil,
      endpoint: nil,
      progress_token: nil,
      status: :request,
      log_level: nil,
      meta: meta_assigns
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
      %GenMCP.MCP.V2607.ProgressNotification{
        params: %{progress: progress, progressToken: token, total: total, message: message}
      }

    send(channel.client, {:"$gen_mcp", :notification, payload})
    :ok
  end

  @doc """
  Sends a log message notification to the client if the message level is at or
  above the channel's configured log level.

  Logging is **per-request and deprecated** (SEP-2577). When the request did not
  declare `io.modelcontextprotocol/logLevel`, the channel's `log_level` is `nil`
  and this is a **no-op**: the server MUST NOT emit `notifications/message` for
  such a request. So `send_log/4` is safe to call unconditionally — it simply does
  nothing when the client did not opt in.

  Returns `:ok` if the message was sent, filtered out, or suppressed (disabled);
  `{:error, :closed}` if the channel is closed.
  """
  def send_log(channel, level, data, logger \\ nil)

  def send_log(%{status: :closed}, _level, _data, _logger) do
    {:error, :closed}
  end

  # Logging disabled: the request omitted io.modelcontextprotocol/logLevel.
  def send_log(%{log_level: nil}, _level, _data, _logger) do
    :ok
  end

  def send_log(%{log_level: _}, level, _data, _logger) when level not in @log_levels do
    {:error, :invalid_level}
  end

  def send_log(%{log_level: min_level} = channel, level, data, logger)
      when min_level in @log_levels and level in @log_levels do
    if :logger.compare_levels(level, min_level) in [:gt, :eq] do
      payload = %GenMCP.MCP.V2607.LoggingMessageNotification{
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

  def send_notification(%__MODULE__{status: :closed}, notification) when is_map(notification) do
    {:error, :closed}
  end

  def send_notification(%__MODULE__{} = channel, notification) when is_map(notification) do
    notification =
      if requires_subscription_id?(notification) do
        copy_subscription_id(channel, notification)
      else
        notification
      end

    send(channel.client, {:"$gen_mcp", :notification, notification})
    :ok
  end

  def requires_subscription_id?(%{"method" => method}) do
    MCP.Info.subscription_notification_method?(method)
  end

  def requires_subscription_id?(%{method: method}) do
    MCP.Info.subscription_notification_method?(method)
  end

  def requires_subscription_id?(%mod{}) do
    MCP.Info.subscription_notification_method?(mod.method())
  rescue
    UndefinedFunctionError ->
      e = %ArgumentError{
        message:
          "could not figure out subscription id requirement for notification" <>
            "%#{inspect(mod)}{}, " <>
            ~s(missing "method" or :method key on the notification payload, ) <>
            "or exported function #{inspect(mod)}.method/0"
      }

      reraise e, __STACKTRACE__
  end

  def requires_subscription_id?(_) do
    false
  end

  def copy_subscription_id(%__MODULE__{request_id: nil}, notification) do
    notification
  end

  @sid_atom_key :"io.modelcontextprotocol/subscriptionId"
  @sid_bin_key "io.modelcontextprotocol/subscriptionId"

  def copy_subscription_id(%__MODULE__{request_id: id}, notification) do
    # Default key is derived from the top map keys type only
    default_key =
      case notification do
        %_s{} -> @sid_atom_key
        %{method: _} -> @sid_atom_key
        _ -> @sid_bin_key
      end

    {params_key, params} = map_get_lax(notification, :params, %{})
    {meta_key, meta} = map_get_lax(params, :_meta, %{}, default_key == @sid_bin_key)

    meta =
      case meta do
        %{@sid_atom_key => v} when v != nil -> meta
        %{@sid_bin_key => v} when v != nil -> meta
        %{@sid_atom_key => _} -> Map.put(meta, @sid_atom_key, id)
        %{@sid_bin_key => _} -> Map.put(meta, @sid_bin_key, id)
        _ -> Map.put(meta, default_key, id)
      end

    params = Map.put(params, meta_key, meta)
    Map.put(notification, params_key, params)
  end

  # returns the key and value from a map. If the map has the string version of
  # the key we use it. The default value is returned if no key is found but the
  # map is not updated. The default value is also returned is the key maps to
  # `nil`.
  #
  # If nothing is found, the atom key is returned
  defp map_get_lax(map, atom_key, default, default_to_bin? \\ false) do
    case map do
      %{^atom_key => nil} ->
        {atom_key, default}

      %{^atom_key => v} ->
        {atom_key, v}

      _ ->
        bin_key = Atom.to_string(atom_key)

        case map do
          %{^bin_key => nil} -> {bin_key, default}
          %{^bin_key => v} -> {bin_key, v}
          _ when default_to_bin? -> {bin_key, default}
          _ -> {atom_key, default}
        end
    end
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
    {:ok, set_closed(channel)}
  end

  def set_closed(channel) do
    %{channel | status: :closed}
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
