defmodule GenMCP.Transport.Relay do
  @moduledoc false

  # The version-agnostic half of the HTTP transport: the receive loop that
  # relays one worker's `{:"$gen_mcp", _}` messages onto the response, plus the
  # SSE chunking, keepalive and finalization around it.
  #
  # What differs between protocol versions is only how each worker message is
  # rendered on the wire, so that part is delegated to a codec module. The
  # 2026-07-28 transport uses `GenMCP.Transport.Relay.Codec.JSONRPC`; the 2025
  # compatibility transport uses the same codec for its POST responses and a
  # different one for the GET stream, which carries bare notifications instead
  # of a JSON-RPC conversation.

  import Plug.Conn

  alias JSV.Codec

  @stream_keepalive_timeout to_timeout(second: 25)

  # A codec returns the JSON-encodable payload to write, not encoded bytes: the
  # relay owns the encoding because the same payload is formatted differently
  # depending on where it lands (pretty in a direct response, compact in an SSE
  # event). `:drop` skips the message but keeps the response open; `:end`
  # terminates the response without writing anything more.
  @type render :: {:send, term} | :drop | :end

  # A codec is given as `{module, ctx}`. The `ctx` is per-request data the codec
  # needs but that the worker's messages do not carry — the 2025 `initialize`
  # response, for instance, is rendered from a `server/discover` result plus the
  # negotiated version, which only the plug knows.
  @type codec :: {module, ctx :: term}

  @callback render_result(result :: term, msg_id :: term, ctx :: term) :: render
  @callback render_notification(notification :: term, ctx :: term) :: render

  # Errors get two callbacks because the two situations are genuinely
  # different, and a codec cannot tell them apart on its own: before anything is
  # written there is still an HTTP status to choose, but once the response is an
  # open SSE stream the status is long gone and whatever comes back is chunked
  # as an event. A codec whose stream carries no error vocabulary (the 2025 GET
  # stream carries bare notifications) answers `:end` to the second and just
  # closes.
  @callback render_error(reason :: term, msg_id :: term, ctx :: term) ::
              {:send, pos_integer, term} | :end

  @callback render_stream_error(reason :: term, msg_id :: term, ctx :: term) ::
              {:send, term} | :end

  @doc """
  Writes the whole response for one request by relaying a worker's messages.

  Monitors `server_pid`, then blocks in the calling (connection) process
  consuming its `{:"$gen_mcp", _}` messages and writing each one onto `conn`
  through `codec`, until the response ends. Returns the halted conn. It spawns
  nothing: the worker is already running when this is called.
  """
  def respond(conn, codec, msg_id, server_pid) do
    mref = :erlang.monitor(:process, server_pid, tag: :SERVER_DOWN)

    conn
    |> merge_private(%{
      gen_mcp_msg_id: msg_id,
      gen_mcp_server: server_pid,
      gen_mcp_mref: mref,
      gen_mcp_status: :init,
      gen_mcp_codec: codec
    })
    |> stream_loop()
  end

  defp stream_loop(conn) do
    receive do
      {:"$gen_mcp", :result, result} ->
        send_result(conn, result)

      {:"$gen_mcp", :accepted} ->
        send_accepted(conn)

      {:"$gen_mcp", :notification, notif} ->
        conn = init_stream(conn)
        send_notification(conn, notif)

      {:"$gen_mcp", :stream} ->
        conn = init_stream(conn)
        stream_loop(conn)

      {:"$gen_mcp", :error, reason} ->
        send_error(conn, reason)

      {:"$gen_mcp", :close} ->
        send(conn.private.gen_mcp_server, {:"$gen_mcp", :closed})
        finalize(conn)

      {:SERVER_DOWN, _mref, :process, _pid, reason} ->
        handle_server_down(conn, reason)

      {:timeout, tref, {__MODULE__, :keepalive}} ->
        # Bracket access: a stale timeout from a previous request on the same
        # keepalive connection may arrive before any stream was initialized.
        case conn.private[:gen_mcp_keepalive] do
          ^tref ->
            case chunk(conn, ":keepalive\n") do
              {:ok, conn} -> reenter_stream_loop(conn)
              {:error, :closed} -> client_gone(conn)
            end

          _ ->
            stream_loop(conn)
        end

      other
      when other != {:plug_conn, :sent} and not (is_tuple(other) and elem(other, 0) == :bandit) ->
        unexpected_message(other)
        stream_loop(conn)
    end
  end

  # The worker died before delivering a result or error. A reply-exit
  # (`{:shutdown, :reply}`) is never seen here: the reply message is enqueued
  # before the exit, so the loop sends the response and returns first.
  #
  # * Clean exit while streaming — a `{:stop, reason}` continuation (listener
  #   exit with no final result): terminate the stream.
  # * Clean exit with no output at all, or a crash — convert to a proper
  #   JSON-RPC internal error instead of a generic Bandit 500.
  defp handle_server_down(conn, reason) do
    clean? =
      case reason do
        :normal -> true
        :shutdown -> true
        {:shutdown, _} -> true
        _ -> false
      end

    case {clean?, conn.private.gen_mcp_status} do
      {true, :streaming} -> finalize(conn)
      {_, _} -> send_error(conn, :server_crashed)
    end
  end

  defp reenter_stream_loop(conn) do
    conn
    |> reset_keepalive()
    |> stream_loop()
  end

  # -- Writing the response ---------------------------------------------------

  defp send_result(conn, result) do
    {mod, ctx} = conn.private.gen_mcp_codec

    case mod.render_result(result, conn.private.gen_mcp_msg_id, ctx) do
      {:send, payload} -> write(conn, 200, payload)
      :drop -> stream_loop(conn)
      :end -> finalize(conn)
    end
  end

  defp send_notification(conn, notif) do
    :streaming = conn.private.gen_mcp_status
    {mod, ctx} = conn.private.gen_mcp_codec

    case mod.render_notification(notif, ctx) do
      {:send, payload} -> send_stream_message(conn, payload, &reenter_stream_loop/1)
      :drop -> reenter_stream_loop(conn)
      :end -> finalize(conn)
    end
  end

  defp send_error(conn, reason) do
    send_error(conn, reason, Map.get(conn.private, :gen_mcp_msg_id), conn.private.gen_mcp_codec)
  end

  @doc """
  Writes an error response outside of any relay loop.

  Used by the plugs to reject a request before a worker is ever started (origin
  check, header validation, an unknown method).
  """
  def send_error(conn, reason, msg_id, {mod, ctx}) do
    emit_rejection(reason)

    case conn.private[:gen_mcp_status] do
      :streaming ->
        case mod.render_stream_error(reason, msg_id, ctx) do
          {:send, payload} -> send_stream_message(conn, payload, &finalize/1)
          :end -> finalize(conn)
        end

      _ ->
        case mod.render_error(reason, msg_id, ctx) do
          {:send, status, payload} -> write(conn, status, payload)
          :end -> finalize(conn)
        end
    end
  end

  # Writes a terminal payload, as a plain response when nothing was sent yet or
  # as a last SSE event when the response is already a stream.
  defp write(conn, status, payload) do
    case conn.private[:gen_mcp_status] do
      :streaming ->
        send_stream_message(conn, payload, &finalize/1)

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(status, Codec.format_to_iodata!(payload))
        |> finalize()
    end
  end

  defp send_accepted(conn) do
    conn
    |> send_resp(202, "")
    |> finalize()
  end

  defp send_stream_message(conn, payload, continuation) do
    event = ["event: message\ndata: ", Codec.encode_to_iodata!(payload), "\n\n"]

    case chunk(conn, event) do
      {:ok, conn} -> continuation.(conn)
      {:error, :closed} -> client_gone(conn)
    end
  end

  # The socket is dead, discovered on a write. Tell the worker so it runs its
  # `handle_close` cleanup now. The worker takes `{:"$gen_mcp", :closed}` as
  # "the channel is gone, stop", the same thing it means after a
  # server-initiated `Channel.close/1`, and it cannot be invoked twice: the
  # worker stops on this message, so the `:CHAN_DOWN` that follows is delivered
  # to a dead process and dropped.
  #
  # This is belt and braces rather than a fix for a leak. The worker already
  # learns of the disconnect through its `:CHAN_DOWN` monitor once this process
  # exits, and under Bandit it does exit promptly — so no test distinguishes
  # the two routes. What the explicit message buys is not depending on that:
  # cleanup is tied to the write failing rather than to the connection process
  # dying afterwards.
  #
  # Finalizing here matters as much as the notification: `halt/1` is a pure
  # struct update so it is safe on a dead socket, and skipping it would hand
  # the connection process back with the worker monitor un-flushed and the
  # keepalive timer live, for the next request on this keep-alive connection to
  # trip over.
  defp client_gone(conn) do
    send(conn.private.gen_mcp_server, {:"$gen_mcp", :closed})
    finalize(conn)
  end

  @doc """
  Opens the SSE response if it is not open yet.

  Public because a transport may need the stream open before any worker message
  arrives — the 2025 GET stream does, since a client holds it open waiting.
  """
  def init_stream(%{private: %{gen_mcp_status: :init}} = conn) do
    conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("x-accel-buffering", "no")
    |> send_chunked(200)
    |> start_keepalive()
    |> put_private(:gen_mcp_status, :streaming)
  end

  def init_stream(%{private: %{gen_mcp_status: :streaming}} = conn) do
    conn
  end

  # -- Telemetry --------------------------------------------------------------

  # Every rejection funnels through send_error/4, so this is the single place to
  # trace them. server_crashed is a fault (:error); the rest are client-induced
  # rejections (:debug). Protocol-version negotiation gets its own event so its
  # level can be tuned independently.
  defp emit_rejection(:server_crashed = reason) do
    :telemetry.execute([:gen_mcp, :transport, :server_crashed], %{}, %{reason: reason})
  end

  defp emit_rejection({:unsupported_protocol_version, _} = reason) do
    :telemetry.execute([:gen_mcp, :transport, :version_rejected], %{}, %{reason: reason})
  end

  defp emit_rejection(reason) do
    :telemetry.execute([:gen_mcp, :transport, :request_rejected], %{}, %{reason: reason})
  end

  # -- Keepalive and cleanup --------------------------------------------------

  defp start_keepalive(conn) do
    tref = :erlang.start_timer(keepalive_timeout(), self(), {__MODULE__, :keepalive})
    put_private(conn, :gen_mcp_keepalive, tref)
  end

  # Read at each timer start rather than inlined, so tests can shorten the
  # interval — 25s is longer than any test can wait on. Not a documented option.
  defp keepalive_timeout do
    Application.get_env(:gen_mcp, :stream_keepalive_timeout, @stream_keepalive_timeout)
  end

  defp reset_keepalive(conn) do
    :ok = :erlang.cancel_timer(conn.private.gen_mcp_keepalive, async: true, info: false)
    _conn = start_keepalive(conn)
  end

  # Terminal cleanup, called from every point where the response ends: result
  # or error sent (direct or streamed), 202 accepted, clean worker shutdown, or
  # the client closing the socket. Flushes the worker monitor and cancels the
  # keepalive timer — the conn process may serve further requests on a
  # keepalive connection, and a late :SERVER_DOWN or stale timeout would be
  # read by the next request's receive loop.
  def finalize(conn) do
    case conn.private[:gen_mcp_mref] do
      nil -> :ok
      mref -> :erlang.demonitor(mref, [:flush])
    end

    case conn.private[:gen_mcp_keepalive] do
      nil -> :ok
      tref -> :ok = :erlang.cancel_timer(tref, async: true, info: false)
    end

    halt(conn)
  end

  if Mix.env() == :test do
    @spec unexpected_message(term) :: no_return
    defp unexpected_message(msg) do
      raise "unexpected message in #{inspect(__MODULE__)}: #{inspect(msg)}"
    end
  else
    defp unexpected_message(_msg) do
      :ok
    end
  end
end

defmodule GenMCP.Transport.Relay.Codec.JSONRPC do
  @moduledoc false

  # Renders worker messages as a JSON-RPC conversation: results and errors are
  # responses carrying the request id, notifications are sent as-is. This is
  # what both the 2026-07-28 transport and the 2025 compatibility transport use
  # for POST responses — the JSON-RPC envelope is identical across the two
  # protocol versions.

  @behaviour GenMCP.Transport.Relay

  alias GenMCP.Error
  alias GenMCP.MCP.V2607.JSONRPCErrorResponse
  alias GenMCP.MCP.V2607.JSONRPCResultResponse

  @impl true
  def render_result(result, msg_id, _ctx) do
    {:send, %JSONRPCResultResponse{id: msg_id, jsonrpc: "2.0", result: result}}
  end

  @impl true
  def render_notification(notif, _ctx) do
    {:send, notif}
  end

  @impl true
  def render_error(reason, msg_id, _ctx) do
    {status, error_payload} = Error.cast_error(reason)

    {:send, status, %JSONRPCErrorResponse{error: error_payload, id: msg_id, jsonrpc: "2.0"}}
  end

  # A JSON-RPC stream can carry its own error response as a final event, so the
  # status is simply dropped.
  @impl true
  def render_stream_error(reason, msg_id, _ctx) do
    {_status, error_payload} = Error.cast_error(reason)

    {:send, %JSONRPCErrorResponse{error: error_payload, id: msg_id, jsonrpc: "2.0"}}
  end
end
