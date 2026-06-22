defmodule GenMCP.Mux.Channel do
  @moduledoc """
  Per-request channel for pushing notifications, logs, and the final reply back
  to an MCP client.

  A channel is the server side of one request. The transport builds it from the
  incoming HTTP request and hands it to your `GenMCP` (or `GenMCP.Suite`)
  callbacks as the `channel` argument. You never construct one yourself: you
  receive it and call functions on it to send messages over the open response
  stream.

  Because the `2026-07-28` core is stateless, a channel lives only for the
  request that created it. It carries everything the server needs to talk back
  to the client without a session: the client process to deliver messages to,
  the request id, the progress token the client supplied, the negotiated minimum
  log level, and the client metadata (info, capabilities, protocol version) read
  from the request `_meta`.

  The common case is a request handler that reports progress and logs while it
  works, then returns its result:

      defmodule MyApp.Server do
        @behaviour GenMCP

        alias GenMCP.Mux.Channel
        alias GenMCP.MCP.V2607, as: MCP

        @impl true
        def init(arg), do: {:ok, arg}

        @impl true
        def handle_request(_request, channel, state) do
          Channel.send_log(channel, :info, "starting work")
          Channel.send_progress(channel, 50, 100)
          Channel.send_progress(channel, 100, 100)
          {:result, MCP.call_tool_result(text: "done")}
        end
      end

  ### Sending messages

  Each send function delivers one message to the client and returns `:ok` (or
  `{:ok, channel}` for the reply functions). They all short-circuit with
  `{:error, :closed}` once the channel has been closed.

  * `send_progress/4` reports progress for the request, but only when the client
    supplied a progress token.
  * `send_log/4` emits a log record, filtered against the client's minimum log
    level.
  * `send_notification/2` sends an arbitrary notification struct, stamping the
    subscription id when the notification's method requires it.
  * `send_result/2` and `send_error/2` deliver the final reply for the request.

  ### Streaming and lifecycle

  A channel's `status` moves from `:request` to `:stream` to `:closed`. The
  transport flips a channel to streaming with `set_streaming/1` once the handler
  asks to keep the response open, and a handler ends a long-lived stream itself
  with `close/1`. `set_closed/1` and `as_closed/1` mark a channel closed so any
  further send returns `{:error, :closed}` instead of delivering.
  """

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
  Builds a channel for an incoming request, targeting the calling process.

  The transport calls this while handling a request. The returned channel
  delivers its messages to `self()`, the process that builds it, which owns the
  HTTP response stream.

  Values are read from the parsed `req`:

  * the progress token from `req.params._meta.progressToken`,
  * the minimum log level from the `io.modelcontextprotocol/logLevel` `_meta`
    key (ignored unless it names a valid level),
  * the client info, capabilities, and protocol version from the matching
    `io.modelcontextprotocol/*` `_meta` keys,
  * the request id from `req.id`.

  The endpoint is taken from a `Phoenix.Endpoint` on the `conn` when present.
  `meta_assigns` is a map merged into the channel `meta`, used to carry
  application assigns (such as the authorization context copied from the
  connection) alongside the protocol metadata.
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

  @doc """
  Sends a progress notification for the request.

  Progress is reported only when the client supplied a progress token with the
  request. Without one there is nothing to correlate the update against, so the
  call returns `{:error, :no_progress_token}` and nothing is sent.

  The arguments are:

  * `channel` - the request's channel.
  * `progress` - the amount of progress so far, as a number.
  * `total` - the optional total amount of work, when known.
  * `message` - an optional human-readable status string.

  Returns `:ok` on delivery, `{:error, :no_progress_token}` when the client did
  not request progress, and `{:error, :closed}` once the channel is closed.

  ### Examples

  Report progress from the `channel` your callback was handed, as the work
  advances:

      def handle_request(_request, channel, state) do
        Channel.send_progress(channel, 25, 100, "indexing")
        # ... more work ...
        Channel.send_progress(channel, 100, 100)
        {:result, result}
      end
  """
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
  Sends a log record to the client, filtered by the client's minimum level.

  The client sets a minimum level on the request. A record is delivered only
  when its `level` is at or above that minimum, using the standard syslog
  severity order (`:debug` through `:emergency`). A record below the minimum is
  dropped silently and the call still returns `:ok`. When the request did not
  enable logging at all, every record is dropped the same way.

  The arguments are:

  * `channel` - the request's channel.
  * `level` - the severity, one of `:debug`, `:info`, `:notice`, `:warning`,
    `:error`, `:critical`, `:alert`, `:emergency`.
  * `data` - the payload to log, any JSON-encodable term.
  * `logger` - an optional logger name string attached to the record.

  Returns `:ok` when the record is delivered or intentionally filtered,
  `{:error, :invalid_level}` for an unknown level, and `{:error, :closed}` once
  the channel is closed.

  ### Examples

  Log from the `channel` your callback was handed. Records below the client's
  minimum level are dropped for you, so you can log freely:

      def handle_request(_request, channel, state) do
        Channel.send_log(channel, :info, "starting work")
        Channel.send_log(channel, :error, "database unreachable", "MyApp.Repo")
        {:result, result}
      end
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

  @doc """
  Sends the final successful reply for the request.

  Returns `{:ok, channel}` once the payload is delivered, or `{:error, :closed}`
  when the channel is already closed. See `send_error/2` for the failure reply.
  """
  def send_result(%{status: :closed}, _payload) do
    {:error, :closed}
  end

  def send_result(channel, payload) do
    send(channel.client, {:"$gen_mcp", :result, payload})
    {:ok, channel}
  end

  @doc """
  Sends the final error reply for the request.

  The error counterpart of `send_result/2`. Returns `{:ok, channel}` once the
  error is delivered, or `{:error, :closed}` when the channel is already closed.
  """
  def send_error(%{status: :closed}, _error) do
    {:error, :closed}
  end

  def send_error(channel, error) do
    send(channel.client, {:"$gen_mcp", :error, error})
    {:ok, channel}
  end

  @doc """
  Sends a notification to the client.

  Pass any notification struct from the `GenMCP.MCP.V2607` vocabulary (or a plain
  map carrying a `method`). When the notification's method is one delivered on a
  subscription stream, the channel stamps the subscription id into its
  `_meta` before sending, so the client can route it to the right
  `subscriptions/listen` stream. See `requires_subscription_id?/1` and
  `copy_subscription_id/2` for that mechanism.

  Returns `:ok` on delivery, or `{:error, :closed}` once the channel is closed.

  ### Examples

  Send a notification from the `channel` your callback was handed. For a
  list-changed method, the channel stamps the subscription id for you before
  delivering:

      def handle_message({:tools_changed, _}, channel, state) do
        Channel.send_notification(channel, %MCP.ToolListChangedNotification{})
        {:stream, state}
      end
  """
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

  @doc """
  Returns whether a notification must be stamped with a subscription id.

  This is `true` for the notification methods that are delivered on a
  `subscriptions/listen` stream (the various `list_changed`, `resources/updated`,
  and `subscriptions/acknowledged` methods), and `false` for anything else. The
  method is read from a `"method"` or `:method` key, or from the `method/0`
  function of a notification struct.

  `send_notification/2` uses this to decide whether to call
  `copy_subscription_id/2`.

  ### Examples

      iex> GenMCP.Mux.Channel.requires_subscription_id?(%{method: "notifications/resources/updated"})
      true

      iex> GenMCP.Mux.Channel.requires_subscription_id?(%{method: "notifications/message"})
      false
  """
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

  @doc """
  Stamps the channel's request id into a notification's subscription id.

  The id is written under the `io.modelcontextprotocol/subscriptionId` key inside
  the notification's `params._meta`, which lets the client demultiplex the
  notification onto the matching `subscriptions/listen` stream. The key already
  present (string or atom form) is respected, otherwise the form is chosen from
  the notification's own shape. A notification that already carries a non-nil
  subscription id is left unchanged, as is a channel with no request id.

  `send_notification/2` calls this for you when the notification's method
  requires it, so you rarely call it directly.
  """
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
  Ends the request's stream from the server side.

  A handler calls this to close a long-lived stream itself, for example to stop
  a `subscriptions/listen` stream it owns. The client is told to end the
  response, and the returned channel is marked closed so any later send returns
  `{:error, :closed}`.

  Returns `{:ok, channel}` with the closed channel, or `{:error, :closed}` when
  it was already closed.

  ### Examples

  End a `subscriptions/listen` stream from the `channel` your handler was given,
  for example when the app signals there is nothing left to watch:

      def handle_message({:source_drained, _}, channel, state) do
        {:ok, _closed} = Channel.close(channel)
        {:stop, :normal}
      end
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

  @doc """
  Marks the channel closed without telling the client.

  Returns the channel with its status set to `:closed`, so any later send returns
  `{:error, :closed}`. Unlike `close/1`, this sends nothing to the client. The
  transport uses it after the client has already disconnected.
  """
  def set_closed(channel) do
    %{channel | status: :closed}
  end

  @doc """
  Marks the channel as streaming.

  Moves a `:request` channel to `:stream`, the state in which the response stays
  open for further notifications. Already-streaming channels are returned
  unchanged. The transport calls this when a handler asks to keep the response
  open.
  """
  def set_streaming(%__MODULE__{status: :request} = t) do
    %{t | status: :stream}
  end

  def set_streaming(%__MODULE__{status: :stream} = t) do
    t
  end

  @doc """
  Returns a closed copy of the channel with no client attached.

  The status is set to `:closed` and the client process is cleared, so the
  channel can be carried in state to satisfy a callback signature while silently
  dropping any send.
  """
  def as_closed(t) do
    %{t | status: :closed, client: nil}
  end
end
