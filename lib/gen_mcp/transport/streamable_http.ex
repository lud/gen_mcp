plug_opts_schema =
  NimbleOptions.new!(
    assigns: [
      type: :map,
      default: %{},
      doc:
        "A map of assigns to define to the channel passed to" <>
          " tools, resources, etc."
    ],
    copy_assigns: [
      type: {:list, :atom},
      default: [],
      doc:
        "A list of assigns keys that will be copied from the conn to the channel." <>
          " Those will overwrite the assigns from the `:assigns` option above."
    ],
    allowed_origins: [
      type: {:or, [{:in, [:any]}, {:list, :string}]},
      default: [],
      doc:
        "Origin allowlist for DNS-rebinding protection. A request carrying an" <>
          " `Origin` header not in the list is rejected with 403 Forbidden." <>
          " Requests without an `Origin` header (non-browser clients) are always" <>
          " accepted. Use `:any` to disable the check (e.g. behind a gateway" <>
          " that already validates origins)."
    ]
  )

defmodule GenMCP.Transport.StreamableHTTP do
  @moduledoc """
  HTTP plug implementing the MCP Streamable HTTP transport for the `2026-07-28`
  protocol.

  This is the entry point of an MCP server over HTTP. It is a `Plug.Router`, so
  you mount it in a Plug or Phoenix router and it answers Model Context Protocol
  requests at that path. A client POSTs a JSON-RPC message, and the transport
  replies with either a single JSON response or a Server-Sent Events stream,
  depending on what the server returns.

  The transport is stateless: each request is validated, run by a fresh server
  process, and answered on its own. The server that handles the decoded request
  is `GenMCP.Suite` by default,
  so the smallest useful mount needs no `:server` option and just lists what to
  serve:

      forward "/mcp", GenMCP.Transport.StreamableHTTP,
        tools: [MyApp.AddTool]

  To run a custom `GenMCP` implementation instead of the Suite, pass it as
  `:server`:

      forward "/mcp", GenMCP.Transport.StreamableHTTP, server: MyApp.Server

  ### Options

  Options are read at three layers. The transport keeps the HTTP connection
  options for itself and passes everything else to the server, which takes its own
  wrapper options and forwards the rest to the server implementation.

  #### HTTP connection options

  #{NimbleOptions.docs(plug_opts_schema)}

  #### MCP server options

  `:server` selects the `GenMCP` implementation that handles the decoded request.
  See `GenMCP` for the `{module, arg}` form.

  #{NimbleOptions.docs(GenMCP.Server.init_opts_schema())}

  #### Server implementation options

  Every option not listed above is forwarded to the server implementation. The
  default server, `GenMCP.Suite`, accepts:

  #{NimbleOptions.docs(GenMCP.Suite.init_opts_schema())}

  ### Passing request data to handlers

  Handlers read per-request context from the `GenMCP.Mux.Channel` they are given.
  Use `:assigns` and `:copy_assigns` to put your own data there. `:assigns` holds
  static values set on every channel. `:copy_assigns` lists `conn` assign keys to
  copy from the connection onto the channel, which is how an upstream
  authentication plug hands the authenticated identity to your tools: the plug
  puts `:current_user` on the conn, and you copy it across.

      pipeline :mcp_auth do
        plug MyAppWeb.AuthPlug
      end

      scope "/mcp" do
        pipe_through :mcp_auth

        forward "/", GenMCP.Transport.StreamableHTTP,
          tools: [MyApp.AddTool],
          copy_assigns: [:current_user]
      end

  A copied conn assign overwrites a static `:assigns` entry of the same key.

  ### DNS-rebinding protection

  A browser-based client sends an `Origin` header. The transport rejects a
  request whose `Origin` is not in `:allowed_origins` with `403 Forbidden`, which
  stops a malicious page from rebinding DNS to reach a local MCP server. A request
  with no `Origin` header (a non-browser client) is always accepted. Set
  `allowed_origins: :any` to disable the check, for example behind a gateway that
  already validates the origin.

      forward "/mcp", GenMCP.Transport.StreamableHTTP,
        tools: [MyApp.AddTool],
        allowed_origins: ["https://app.example.com"]

  ### Multiple endpoints in one router

  On Phoenix 1.8 and later you can mount the transport directly as many times as
  you need. Each `forward` keeps its own options, so different endpoints can serve
  different tools, resources, or origins:

      scope "/mcp" do
        forward "/files", GenMCP.Transport.StreamableHTTP, tools: [MyApp.FileTool]
        forward "/admin", GenMCP.Transport.StreamableHTTP, tools: [MyApp.AdminTool]
      end

  Phoenix resolves a forwarded plug to a path by module, so reverse route lookup
  (path helpers and `~p` verified routes) for a module mounted at several paths
  returns only the first one. This affects URL generation, not request dispatch.
  If you generate URLs to these endpoints, give each its own module with
  `defplug/1` so each resolves to its own path.

  #### Phoenix before 1.8

  Older Phoenix routers refuse to forward the same module more than once and raise
  at compile time:

      ** (ArgumentError) GenMCP.Transport.StreamableHTTP has already been
      forwarded to. A module can only be forwarded a single time.

  Give each endpoint its own module with `defplug/1`, then forward to those
  modules instead of to the transport:

      require GenMCP.Transport.StreamableHTTP, as: StreamableHTTP

      StreamableHTTP.defplug(MyAppWeb.FilesMcp)
      StreamableHTTP.defplug(MyAppWeb.AdminMcp)

      scope "/mcp" do
        forward "/files", MyAppWeb.FilesMcp, tools: [MyApp.FileTools]
        forward "/admin", MyAppWeb.AdminMcp, tools: [MyApp.AdminTools]
      end
  """
  use Plug.Router, copy_opts_to_assign: :gen_mcp_streamable_http_opts

  import Plug.Conn

  alias GenMCP.Transport.StreamableHTTP.Impl
  alias GenMCP.Utils.OptsValidator

  @plug_opts_schema plug_opts_schema

  # -- Plug API ---------------------------------------------------------------
  @doc """
  Initializes the plug, returning the prepared transport configuration.

  This is the `c:Plug.init/1` callback. It validates the transport's own options
  (`:allowed_origins`, `:assigns`, `:copy_assigns`) and keeps every other option
  aside as the server options handed to the server on each request. The returned
  value is the opaque configuration later passed to `call/2`; you do not build or
  read it yourself.
  """
  def init(opts) do
    {self_opts, server_opts} = OptsValidator.validate_take_opts!(opts, @plug_opts_schema)
    _conf = Map.put(Map.new(self_opts), :server_opts, server_opts)
  end

  plug :validate_origin
  plug :match
  plug :dispatch

  post "/" do
    Impl.http_post(conn, conn.assigns.gen_mcp_streamable_http_opts)
  end

  # Origin validation guards every verb on the MCP endpoint (the spec requires
  # it on all incoming connections), before routing. An absent Origin is always
  # accepted (non-browser clients do not send it). A present Origin must be
  # allowlisted: a rebound browser request cannot forge the hostname the
  # browser actually used, so this check defeats DNS rebinding.
  defp validate_origin(conn, _opts) do
    %{allowed_origins: allowed_origins} = conn.assigns.gen_mcp_streamable_http_opts

    case get_req_header(conn, "origin") do
      [] -> conn
      [origin | _] -> check_allowed_origin(conn, origin, allowed_origins)
    end
  end

  defp check_allowed_origin(conn, _origin, :any) do
    conn
  end

  defp check_allowed_origin(conn, origin, allowed_origins) do
    if origin in allowed_origins do
      conn
    else
      conn
      |> Impl.send_error({:origin_forbidden, origin}, _msg_id = nil)
      |> halt()
    end
  end

  get "/" do
    send_resp(conn, 405, "Method Not Allowed")
  end

  delete "/" do
    send_resp(conn, 405, "Method Not Allowed")
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  # -- Plug Duplication -------------------------------------------------------

  @doc """
  Defines a named plug module that delegates to `GenMCP.Transport.StreamableHTTP`.

  Use this to mount more than one MCP endpoint on a router that allows a module to
  be forwarded only once. Phoenix before 1.8 is the common case: forwarding
  `GenMCP.Transport.StreamableHTTP` at two paths raises `ArgumentError` with the
  message "has already been forwarded to. A module can only be forwarded a single
  time". The generated module is a distinct plug that delegates both `init/1` and
  `call/2` to the transport, so you forward to it exactly like the transport
  itself and each endpoint is its own module. On Phoenix 1.8 and later you can
  forward to `GenMCP.Transport.StreamableHTTP` directly instead, even for several
  endpoints.

  This is a macro, so `require` (or alias and require) the transport before
  calling it, and give a literal module name:

      require GenMCP.Transport.StreamableHTTP, as: StreamableHTTP

      StreamableHTTP.defplug(MyAppWeb.McpPlug)

      # then, in the router, mount the generated module
      forward "/mcp", MyAppWeb.McpPlug, tools: [MyApp.AddTool]
  """
  defmacro defplug(module) do
    module = Macro.expand_literals(module, __CALLER__)

    {:module, mod, _, _} =
      defmodule module do
        alias GenMCP.Transport.StreamableHTTP

        defdelegate init(opts), to: StreamableHTTP
        defdelegate call(conn, opts), to: StreamableHTTP
      end

    mod
  end
end

# Separate modules so we do not get bad stacktraces because of Plug

defmodule GenMCP.Transport.StreamableHTTP.Impl do
  @moduledoc false

  import Plug.Conn

  alias GenMCP.Error
  alias GenMCP.MCP.V2607.JSONRPCResultResponse
  alias GenMCP.Mux.Channel
  alias GenMCP.Server
  alias GenMCP.Validator
  alias JSV.Codec

  @stream_keepalive_timeout to_timeout(second: 25)

  # Legacy support. Initialized notification does not exist in schemas
  def http_post(
        %{body_params: %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}} = conn,
        _conf
      ) do
    send_accepted(conn)
  end

  def http_post(%{body_params: %{"jsonrpc" => "2.0"} = body_params} = conn, conf) do
    with {:ok, kind, req} <- Validator.validate_request(body_params),
         :ok <- validate_headers(conn, kind, req) do
      dispatch(conn, kind, req, conf)
    else
      {:error, reason} -> send_error(conn, reason, msg_id_from_req(body_params))
    end
  end

  def http_post(%{body_params: %{"jsonrpc" => _}} = conn, _conf) do
    send_error(conn, :bad_rpc_version, _msg_id = nil)
  end

  def http_post(conn, _conf) do
    send_error(conn, :bad_rpc, _msg_id = nil)
  end

  defp msg_id_from_req(body) do
    case body do
      %{"id" => id} -> id
      _ -> nil
    end
  end

  @supported_vsn "2026-07-28"
  defp validate_headers(conn, _, req) do
    with :ok <- validate_version_header(conn, req),
         :ok <- validate_method_header(conn, req) do
      validate_name_header(conn, req)
    end
  end

  defp validate_version_header(conn, req) do
    case Plug.Conn.get_req_header(conn, "mcp-protocol-version") do
      [@supported_vsn | _] ->
        case req do
          %{params: %{_meta: %{"io.modelcontextprotocol/protocolVersion": vsn}}}
          when vsn != @supported_vsn ->
            {:error, {:header_mismatch, "MCP-Protocol-Version", @supported_vsn, vsn}}

          _ ->
            :ok
        end

      [unsupported | _] ->
        {:error, {:unsupported_protocol_version, unsupported}}

      _ ->
        {:error, {:header_missing, "MCP-Protocol-Version"}}
    end
  end

  # Mcp-Method mirrors the body `method` and is REQUIRED for all requests and
  # notifications. The headers are compared against the raw body (the cast
  # structs do not carry the method const). Header values are case-sensitive.
  defp validate_method_header(conn, _req) do
    %{"method" => method} = conn.body_params

    case Plug.Conn.get_req_header(conn, "mcp-method") do
      [^method | _] -> :ok
      [other | _] -> {:error, {:header_mismatch, "Mcp-Method", other, method}}
      [] -> {:error, {:header_missing, "Mcp-Method"}}
    end
  end

  # Mcp-Name mirrors `params.name` (tools/call, prompts/get) or `params.uri`
  # (resources/read) and is REQUIRED for those three methods only. A stray
  # Mcp-Name on any other method is ignored.
  defp validate_name_header(conn, _req) do
    case expected_name(conn.body_params) do
      nil ->
        :ok

      name ->
        case Plug.Conn.get_req_header(conn, "mcp-name") do
          [^name | _] -> :ok
          [other | _] -> {:error, {:header_mismatch, "Mcp-Name", other, name}}
          [] -> {:error, {:header_missing, "Mcp-Name"}}
        end
    end
  end

  defp expected_name(body_params) do
    case body_params do
      %{"method" => "tools/call", "params" => %{"name" => name}} -> name
      %{"method" => "resources/read", "params" => %{"uri" => uri}} -> uri
      %{"method" => "prompts/get", "params" => %{"name" => name}} -> name
      _ -> nil
    end
  end

  defp dispatch(conn, :request, %{id: msg_id} = req, conf) do
    dispatch_req(conn, msg_id, req, conf)
  end

  defp dispatch(conn, :notification, req, conf) do
    dispatch_notif(conn, req, conf)
  end

  defp dispatch_req(conn, msg_id, req, conf) do
    channel = make_channel(conn, req, conf)

    case Server.start_request(conf.server_opts, req, channel) do
      {:ok, pid} -> init_loop(conn, msg_id, pid)
      {:error, reason} -> send_error(conn, reason, msg_id)
    end
  end

  # Notifications run through the same receive loop as requests; theirs is the
  # degenerate conversation ending at {:"$gen_mcp", :accepted}, emitted by the
  # worker once handle_notification/3 returned — so the 202 goes out only after
  # the handler ran. A worker crash becomes an id-less JSON-RPC error on an
  # HTTP error status (spec: the server MUST return an HTTP error status for a
  # notification it cannot accept). A channel is built the same way as for a
  # request, so the handler gets the notification's read-only `_meta` context.
  defp dispatch_notif(conn, notif, conf) do
    channel = make_channel(conn, notif, conf)

    case Server.start_notification(conf.server_opts, notif, channel) do
      {:ok, pid} -> init_loop(conn, _msg_id = nil, pid)
      {:error, reason} -> send_error(conn, reason, _msg_id = nil)
    end
  end

  defp make_channel(conn, req, conf) do
    %{assigns: conn_assigns} = conn
    %{assigns: static_assigns, copy_assigns: copied_assign_keys} = conf

    assigns =
      Enum.reduce(copied_assign_keys, static_assigns, fn key, acc ->
        case Map.fetch(conn_assigns, key) do
          {:ok, value} -> Map.put(acc, key, value)
          :error -> acc
        end
      end)

    Channel.from_request(conn, req, assigns)
  end

  defp send_accepted(conn) do
    conn
    |> send_resp(202, "")
    |> finalize()
  end

  defp send_json(conn, status, payload) do
    body = json_encode(payload, true)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end

  defp init_loop(conn, msg_id, server_pid) do
    mref = :erlang.monitor(:process, server_pid, tag: :SERVER_DOWN)

    state = %{
      gen_mcp_msg_id: msg_id,
      gen_mcp_server: server_pid,
      gen_mcp_mref: mref,
      gen_mcp_status: :init
    }

    conn = Plug.Conn.merge_private(conn, state)
    stream_loop(conn)
  end

  defp stream_loop(conn) do
    receive do
      {:"$gen_mcp", :result, result} ->
        send_result(conn, result)

      {:"$gen_mcp", :accepted} ->
        send_accepted(conn)

      {:"$gen_mcp", :notification, notif} ->
        conn = init_stream(conn)
        send_notification(conn, notif, &reenter_stream_loop/1)

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
              {:error, :closed} -> conn
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

  defp init_stream(%{private: %{gen_mcp_status: :init}} = conn) do
    conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("x-accel-buffering", "no")
    |> send_chunked(200)
    |> start_keepalive()
    |> put_private(:gen_mcp_status, :streaming)
  end

  defp init_stream(%{private: %{gen_mcp_status: :streaming}} = conn) do
    conn
  end

  defp send_result(conn, result) do
    payload = %JSONRPCResultResponse{
      id: conn.private.gen_mcp_msg_id,
      jsonrpc: "2.0",
      result: result
    }

    case conn.private.gen_mcp_status do
      :init -> conn |> send_json(200, payload) |> finalize()
      :streaming -> send_stream_message(conn, json_encode(payload), &finalize/1)
    end
  end

  defp send_error(conn, reason) do
    msg_id = Map.get(conn.private, :gen_mcp_msg_id)
    send_error(conn, reason, msg_id)
  end

  # Public: also used by the router module (origin validation).
  def send_error(conn, reason, msg_id) do
    emit_rejection(reason)
    {status, error_payload} = Error.cast_error(reason)

    payload = %GenMCP.MCP.V2607.JSONRPCErrorResponse{
      error: error_payload,
      id: msg_id,
      jsonrpc: "2.0"
    }

    case conn.private[:gen_mcp_status] do
      :init -> conn |> send_json(status, payload) |> finalize()
      nil -> conn |> send_json(status, payload) |> finalize()
      :streaming -> send_stream_message(conn, json_encode(payload), &finalize/1)
    end
  end

  # Every rejection funnels through send_error/3, so this is the single place to
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

  defp send_notification(conn, notif, continuation) do
    :streaming = conn.private.gen_mcp_status
    send_stream_message(conn, json_encode(notif), continuation)
  end

  defp start_keepalive(conn) do
    tref = :erlang.start_timer(@stream_keepalive_timeout, self(), {__MODULE__, :keepalive})
    Plug.Conn.put_private(conn, :gen_mcp_keepalive, tref)
  end

  defp reset_keepalive(conn) do
    :ok = :erlang.cancel_timer(conn.private.gen_mcp_keepalive, async: true, info: false)
    _conn = start_keepalive(conn)
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

  # Terminal cleanup, called from every point where the response ends: result
  # or error sent (direct or streamed), 202 accepted, clean worker shutdown, or
  # the client closing the socket. Flushes the worker monitor and cancels the
  # keepalive timer — the conn process may serve further requests on a
  # keepalive connection, and a late :SERVER_DOWN or stale timeout would be
  # read by the next request's receive loop.
  defp finalize(conn) do
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

  defp send_stream_message(conn, data, continuation) do
    event = "event: message\ndata: #{data}\n\n"

    case chunk(conn, event) do
      {:ok, conn} -> continuation.(conn)
      {:error, :closed} -> finalize(conn)
    end
  end

  defp json_encode(payload, pretty? \\ false) do
    if pretty? do
      Codec.format_to_iodata!(payload)
    else
      Codec.encode_to_iodata!(payload)
    end
  end
end
