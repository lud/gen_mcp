defmodule GenMCP.Transport.StreamableHTTP.V2511.RpcCodec do
  @moduledoc false

  # The POST response codec. The JSON-RPC envelope and the notification shapes
  # are the same in 2025 and 2026; only the result payloads carry 2026-only
  # fields, so that is the single thing this codec does differently from
  # `GenMCP.Transport.Relay.Codec.JSONRPC`.

  @behaviour GenMCP.Transport.Relay

  alias GenMCP.Error
  alias GenMCP.Transport.StreamableHTTP.V2511.Translate

  @impl true
  def render_result(result, msg_id, _ctx) do
    {:send,
     %{
       "jsonrpc" => "2.0",
       "id" => msg_id,
       "result" => Translate.downgrade_result(result)
     }}
  end

  @impl true
  def render_notification(notif, _ctx) do
    {:send, Translate.strip_subscription_id(notif)}
  end

  @impl true
  def render_error(reason, msg_id, _ctx) do
    {status, payload} = Error.cast_error(reason)

    {:send, status, %{"jsonrpc" => "2.0", "id" => msg_id, "error" => payload}}
  end

  @impl true
  def render_stream_error(reason, msg_id, _ctx) do
    {_status, payload} = Error.cast_error(reason)

    {:send, %{"jsonrpc" => "2.0", "id" => msg_id, "error" => payload}}
  end
end

defmodule GenMCP.Transport.StreamableHTTP.V2511.InitializeCodec do
  @moduledoc false

  # Renders the `initialize` response. The worker that produced the result ran
  # an ordinary `server/discover`, so the 2025-specific part — the negotiated
  # protocol version — travels in the codec `ctx` instead.

  @behaviour GenMCP.Transport.Relay

  alias GenMCP.Error
  alias GenMCP.Transport.StreamableHTTP.V2511.Translate

  @impl true
  def render_result(discover_result, msg_id, %{protocol_version: protocol_version}) do
    {:send,
     %{
       "jsonrpc" => "2.0",
       "id" => msg_id,
       "result" => Translate.initialize_result(discover_result, protocol_version)
     }}
  end

  # A handshake emits nothing before its result.
  @impl true
  def render_notification(_notif, _ctx) do
    :drop
  end

  @impl true
  def render_error(reason, msg_id, _ctx) do
    {status, payload} = Error.cast_error(reason)

    {:send, status, %{"jsonrpc" => "2.0", "id" => msg_id, "error" => payload}}
  end

  # A handshake never opens a stream: it drops the notifications that would.
  @impl true
  def render_stream_error(_reason, _msg_id, _ctx) do
    :end
  end
end

defmodule GenMCP.Transport.StreamableHTTP.V2511.GetStreamCodec do
  @moduledoc false

  # The GET stream codec. A 2025 GET carries only server-initiated
  # notifications — it answers no request, so there is no JSON-RPC envelope and
  # no id. What arrives on it is a 2026 `subscriptions/listen` conversation,
  # whose framing has to be translated away:
  #
  #   * the `subscriptions/acknowledged` notification has no 2025 equivalent
  #     and is dropped;
  #   * the terminal `SubscriptionsListenResult` ends the stream instead of
  #     being written, since there is no request to answer;
  #   * everything else (the `list_changed` family, `resources/updated`) shares
  #     its method name and params with 2025 and is forwarded once the
  #     subscription id is stripped.

  @behaviour GenMCP.Transport.Relay

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Transport.StreamableHTTP.V2511.Translate

  @ack_method "notifications/subscriptions/acknowledged"

  @impl true
  def render_result(%MCP.SubscriptionsListenResult{}, _msg_id, _ctx) do
    :end
  end

  def render_result(_result, _msg_id, _ctx) do
    :end
  end

  @impl true
  def render_notification(notif, _ctx) do
    if method(notif) == @ack_method do
      :drop
    else
      {:send, Translate.strip_subscription_id(notif)}
    end
  end

  # Before anything is written, an error means the subscription never started:
  # `405 Method Not Allowed` is what the 2025 spec defines for a server that
  # offers no server-initiated stream, which is exactly the case when no
  # subscription handler is configured and the Suite answers
  # `{:unsupported_method, _}`.
  @impl true
  def render_error(_reason, _msg_id, _ctx) do
    {:send, 405, %{"error" => "Method Not Allowed"}}
  end

  # Once the stream is open there is nothing to report on it: a 2025 client
  # reads bare notifications here, so any payload would be parsed as one. The
  # only honest signal left is closing the stream, which is also what the
  # client sees if the connection simply drops.
  @impl true
  def render_stream_error(_reason, _msg_id, _ctx) do
    :end
  end

  defp method(%mod{}) do
    mod.method()
  rescue
    UndefinedFunctionError -> nil
  end

  defp method(%{"method" => method}) do
    method
  end

  defp method(%{method: method}) do
    method
  end

  defp method(_) do
    nil
  end
end
