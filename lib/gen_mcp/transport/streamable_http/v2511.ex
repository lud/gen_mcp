v2511_plug_opts_schema =
  NimbleOptions.new!(
    assigns: [
      type: :map,
      default: %{},
      doc: "A map of assigns to define to the channel passed to tools."
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
          " accepted. Use `:any` to disable the check."
    ],
    session_controller: [
      type: {:or, [:atom, :mod_arg]},
      default: GenMCP.SessionController.Token,
      doc:
        "The `GenMCP.SessionController` implementation that mints and reads back" <>
          " session ids. The default seals the session into the id itself and" <>
          " stores nothing server-side."
    ]
  )

defmodule GenMCP.Transport.StreamableHTTP.V2511 do
  @moduledoc """
  HTTP plug serving MCP clients that speak the `2025-06-18` or `2025-11-25`
  protocol, on top of the stateless `2026-07-28` core.

  This is a migration shim, not a second implementation. A 2025 request is
  translated at this boundary into the same per-request contract
  `GenMCP.Transport.StreamableHTTP` drives, so `GenMCP.Suite`, your tools, and
  every other provider stay written once against the `2026-07-28` vocabulary and
  never learn that a 2025 client exists.

  Mount it alongside the 2026 transport, on its own path:

      scope "/mcp" do
        forward "/", GenMCP.Transport.StreamableHTTP,
          server_name: "My App",
          server_version: "1.0.0",
          tools: [MyApp.AddTool]

        forward "/2025", GenMCP.Transport.StreamableHTTP.V2511,
          server_name: "My App",
          server_version: "1.0.0",
          tools: [MyApp.AddTool]
      end

  ### Served methods

  The surface is what a migrating client needs to keep using the server, not
  feature parity with the 2025 spec:

  * `initialize` and `notifications/initialized` — the handshake.
  * `ping`.
  * `tools/list` and `tools/call`, including progress and log notifications on
    the POST's own SSE response.
  * `resources/list`, `resources/templates/list` and `resources/read`. A mount
    with no `:resources` answers an empty listing. The handshake advertises the
    downgraded resources capability carrying `listChanged`, the flag whose
    notifications the `GET` stream below delivers. These methods are also what
    carries the MCP Apps extension: a tool's `_meta.ui.resourceUri` points at a
    `ui://` resource the host fetches with `resources/read`.
  * `GET` — the server-to-client notification stream, served by the Suite's
    subscription handler (see below).

  Any other method is answered with a JSON-RPC `-32601` in a `200` response. The
  `404` that a 2026 client gets for an unknown method is not used here: in 2025
  that status means the session is gone, so a client would answer it by starting
  a new one instead of reading the error.

  ### Sessions

  The 2025 protocol is stateful: `initialize` returns an `Mcp-Session-Id` that
  every later request must carry. The default `GenMCP.SessionController.Token`
  seals the session into the id itself, so no server-side state is introduced.
  Pass `:session_controller` to store sessions yourself — see
  `GenMCP.SessionController`.

  A request with no `Mcp-Session-Id` after the handshake is answered `400`, and
  one whose id is unknown or expired is answered `404`, which is the 2025
  signal for the client to start a new session.

  ### The GET stream

  A 2025 client opens a long-lived `GET` to receive server-initiated
  notifications. That maps onto the 2026 `subscriptions/listen` request, so the
  stream is served by the Suite's configured `:subscription_handler` and the
  2026 subscription vocabulary is translated away on the wire.

      forward "/2025", GenMCP.Transport.StreamableHTTP.V2511,
        server_name: "My App",
        server_version: "1.0.0",
        tools: [MyApp.AddTool],
        subscription_handler: MyApp.ToolChanges

  Without a subscription handler, `GET` is answered `405 Method Not Allowed`,
  which the 2025 spec permits for a server that offers no server-initiated
  stream.

  ### Options

  #{NimbleOptions.docs(v2511_plug_opts_schema)}

  Every other option is forwarded to the server implementation, exactly as for
  `GenMCP.Transport.StreamableHTTP`.
  """

  use Plug.Router, copy_opts_to_assign: :gen_mcp_v2511_opts

  import Plug.Conn

  alias GenMCP.SessionController
  alias GenMCP.Transport.StreamableHTTP.V2511.Impl
  alias GenMCP.Utils.OptsValidator

  @plug_opts_schema v2511_plug_opts_schema

  @doc """
  Initializes the plug, returning the prepared transport configuration.
  """
  def init(opts) do
    {self_opts, server_opts} = OptsValidator.validate_take_opts!(opts, @plug_opts_schema)

    self_opts
    |> Map.new()
    |> Map.update!(:session_controller, &SessionController.expand/1)
    |> Map.put(:server_opts, server_opts)
  end

  plug :validate_origin
  plug :match
  plug :dispatch

  post "/" do
    Impl.http_post(conn, conn.assigns.gen_mcp_v2511_opts)
  end

  get "/" do
    Impl.http_get(conn, conn.assigns.gen_mcp_v2511_opts)
  end

  delete "/" do
    Impl.http_delete(conn, conn.assigns.gen_mcp_v2511_opts)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp validate_origin(conn, _opts) do
    %{allowed_origins: allowed_origins} = conn.assigns.gen_mcp_v2511_opts

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

  @doc """
  Defines a named plug module delegating to this transport.

  The 2025 counterpart of `GenMCP.Transport.StreamableHTTP.defplug/1`, for
  routers that allow a module to be forwarded only once.
  """
  defmacro defplug(module) do
    module = Macro.expand_literals(module, __CALLER__)

    {:module, mod, _, _} =
      defmodule module do
        @moduledoc """
        A plug copy of `GenMCP.Transport.StreamableHTTP.V2511`.
        See `GenMCP.Transport.StreamableHTTP.V2511.defplug/1`.
        """

        @behaviour Plug

        alias GenMCP.Transport.StreamableHTTP.V2511

        defdelegate init(opts), to: V2511
        defdelegate call(conn, opts), to: V2511
      end

    mod
  end
end

defmodule GenMCP.Transport.StreamableHTTP.V2511.Impl do
  @moduledoc false

  import Plug.Conn

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.Server
  alias GenMCP.SessionController
  alias GenMCP.Transport.Relay
  alias GenMCP.Transport.StreamableHTTP.V2511.GetStreamCodec
  alias GenMCP.Transport.StreamableHTTP.V2511.InitializeCodec
  alias GenMCP.Transport.StreamableHTTP.V2511.RpcCodec
  alias GenMCP.Transport.StreamableHTTP.V2511.Translate

  # Newest first: the version a client gets when it asks for one we do not know.
  @supported_versions ["2025-11-25", "2025-06-18"]

  @session_header "mcp-session-id"

  # `{:mcp_error, rpc_code, http_status, message}` is the escape hatch
  # `GenMCP.Error` offers for reasons that need no dedicated clause.
  @rpc_invalid_request -32_600

  @rpc_codec {RpcCodec, nil}

  @doc false
  def supported_versions do
    @supported_versions
  end

  # -- POST -------------------------------------------------------------------

  def http_post(%{body_params: %{"jsonrpc" => "2.0", "method" => method} = body} = conn, conf) do
    case normalize(body) do
      {:ok, msg} -> route(conn, method, msg, conf)
      {:error, reason} -> send_error(conn, reason, _msg_id = nil)
    end
  end

  def http_post(%{body_params: %{"jsonrpc" => _}} = conn, _conf) do
    send_error(conn, :bad_rpc_version, _msg_id = nil)
  end

  def http_post(conn, _conf) do
    send_error(conn, :bad_rpc, _msg_id = nil)
  end

  # There is no 2025 vocabulary to validate a body against, so the JSON-RPC
  # envelope is checked here by hand, once, before anything reads it. Past this
  # point `id` is a scalar and `params` and `params._meta` are maps, which is
  # what lets the translation read fields without guarding every access. It
  # stops at the envelope: the tool `arguments` are validated against the
  # tool's own input schema by `GenMCP.Suite`, which is version-independent and
  # where the real risk lives.
  defp normalize(body) do
    with {:ok, id} <- normalize_id(body),
         {:ok, params} <- normalize_params(body) do
      {:ok, %{id: id, params: params, meta: normalize_meta(params)}}
    end
  end

  defp normalize_id(%{"id" => id}) when is_binary(id) when is_integer(id) do
    {:ok, id}
  end

  defp normalize_id(%{"id" => id}) when not is_nil(id) do
    {:error, {:mcp_error, @rpc_invalid_request, 400, "id must be a string or a number"}}
  end

  # No id, or a null one: a notification.
  defp normalize_id(_body) do
    {:ok, nil}
  end

  defp normalize_params(%{"params" => params}) when is_map(params) do
    {:ok, params}
  end

  defp normalize_params(%{"params" => params}) when not is_nil(params) do
    {:error, Translate.invalid_params("params must be an object")}
  end

  defp normalize_params(_body) do
    {:ok, %{}}
  end

  # A malformed `_meta` is ignored rather than rejected: it carries only
  # optional hints, and 2025 clients are known to put odd things there.
  defp normalize_meta(%{"_meta" => meta}) when is_map(meta) do
    meta
  end

  defp normalize_meta(_params) do
    %{}
  end

  defp route(conn, "initialize", msg, conf) do
    initialize(conn, msg, conf)
  end

  # Every 2025 client-to-server notification is accept-and-ignore, the same
  # stance `GenMCP.Suite` takes under the stateless core. They are answered
  # without starting a worker at all: none of them carries an action, and
  # `notifications/initialized` in particular arrives before any session
  # lookup would make sense.
  defp route(conn, "notifications/" <> _, _msg, _conf) do
    conn
    |> send_resp(202, "")
    |> Relay.finalize()
  end

  defp route(conn, "ping", msg, _conf) do
    send_result(conn, %{}, msg.id)
  end

  # Accept-and-ignore, the first of the two options feature 017 left open. A
  # client calls `logging/setLevel` during setup and has no reason to expect it
  # to fail, so answering the JSON-RPC error would break sessions over a
  # setting rather than over anything the client did wrong. The level cannot be
  # honored — the token session is immutable and carries no room for it — so
  # what the client gets is the default level the transport synthesizes into
  # every request (see `Translate`). No session lookup: the call is a no-op, so
  # a lookup would only add ways for it to fail.
  defp route(conn, "logging/setLevel", msg, _conf) do
    send_result(conn, %{}, msg.id)
  end

  defp route(conn, "tools/list", msg, conf) do
    with_session(conn, msg, conf, fn session ->
      dispatch(conn, Translate.list_tools_request(msg, session), msg.id, @rpc_codec, conf)
    end)
  end

  defp route(conn, "tools/call", msg, conf) do
    with_session(conn, msg, conf, fn session ->
      dispatch(conn, Translate.call_tool_request(msg, session), msg.id, @rpc_codec, conf)
    end)
  end

  # The resource methods carry the same names and param shapes in both
  # versions, so they need no more translation than the tool methods do. They
  # are routed for every mount, and the Suite answers from whatever `:resources`
  # holds — an empty listing when it holds nothing. The MCP Apps extension
  # fetches its `ui://` bundles through `resources/read`.
  defp route(conn, "resources/list", msg, conf) do
    with_session(conn, msg, conf, fn session ->
      dispatch(conn, Translate.list_resources_request(msg, session), msg.id, @rpc_codec, conf)
    end)
  end

  defp route(conn, "resources/templates/list", msg, conf) do
    with_session(conn, msg, conf, fn session ->
      request = Translate.list_resource_templates_request(msg, session)
      dispatch(conn, request, msg.id, @rpc_codec, conf)
    end)
  end

  defp route(conn, "resources/read", msg, conf) do
    with_session(conn, msg, conf, fn session ->
      dispatch(conn, Translate.read_resource_request(msg, session), msg.id, @rpc_codec, conf)
    end)
  end

  # `-32601` in a `200`, never the `404` the 2026 transport answers for a method
  # outside the protocol. On this transport `404` is the 2025 signal that the
  # session is gone and the client must run `initialize` again, so answering a
  # refused method with it turns a capability probe into a dropped connection —
  # the client cannot tell the two apart.
  #
  # The session is still looked up first, unlike for `ping` and
  # `logging/setLevel`: it is what keeps `404` meaning exactly one thing, so a
  # client whose session died while probing a method learns to start a new one
  # rather than reading the refusal and carrying on.
  defp route(conn, method, msg, conf) do
    with_session(conn, msg, conf, fn _session ->
      send_error(conn, {:unsupported_method, method}, msg.id)
    end)
  end

  # -- initialize -------------------------------------------------------------

  # The handshake is the one place where the 2025 and 2026 shapes do not line
  # up: 2026 has no handshake, only `server/discover`. So `initialize` runs a
  # DiscoverRequest through the ordinary worker path and the response is
  # rendered from its result by InitializeCodec, which also knows the negotiated
  # version. The session is created first, because its id must be on the
  # response headers before the relay writes anything.
  defp initialize(conn, msg, conf) do
    client_info = client_info(msg.params)
    negotiated = negotiate_version(Map.get(msg.params, "protocolVersion"))

    session = %{
      protocol_version: negotiated,
      client_name: string_or_nil(Map.get(client_info, "name")),
      client_version: string_or_nil(Map.get(client_info, "version"))
    }

    case SessionController.create(conf.session_controller, session, conn) do
      {:ok, session_id} ->
        req = Translate.discover_request(msg, session)
        codec = {InitializeCodec, %{protocol_version: negotiated}}

        conn
        |> put_resp_header(@session_header, session_id)
        |> run(req, msg.id, codec, conf)

      {:error, reason} ->
        send_error(conn, reason, msg.id)
    end
  end

  defp client_info(%{"clientInfo" => info}) when is_map(info) do
    info
  end

  defp client_info(_params) do
    %{}
  end

  defp string_or_nil(value) when is_binary(value) do
    value
  end

  defp string_or_nil(_value) do
    nil
  end

  # The 2025 spec: when the server does not support the version the client
  # asked for, it answers with one it does support and lets the client decide
  # whether to continue.
  defp negotiate_version(requested) when requested in @supported_versions do
    requested
  end

  defp negotiate_version(_requested) do
    hd(@supported_versions)
  end

  # -- GET --------------------------------------------------------------------

  # The 2025 server-to-client stream, expressed as a 2026 subscription. The
  # filter asks for everything; the handler narrows it to what it actually
  # serves through its honored filter. With no handler configured the Suite
  # answers `{:unsupported_method, _}`, which GetStreamCodec turns into the 405
  # the 2025 spec allows.
  def http_get(conn, conf) do
    with_session(conn, empty_message(), conf, fn session ->
      req = Translate.subscriptions_listen_request(session)
      dispatch(conn, req, _msg_id = nil, {GetStreamCodec, nil}, conf)
    end)
  end

  # A GET carries no JSON-RPC body at all.
  defp empty_message do
    %{id: nil, params: %{}, meta: %{}}
  end

  # -- DELETE -----------------------------------------------------------------

  def http_delete(conn, conf) do
    case get_req_header(conn, @session_header) do
      [session_id | _] ->
        _ = SessionController.delete(conf.session_controller, session_id, conn)
        conn |> send_resp(200, "") |> Relay.finalize()

      [] ->
        send_error(conn, session_required_error(), _msg_id = nil)
    end
  end

  # -- Session ----------------------------------------------------------------

  defp with_session(conn, msg, conf, fun) do
    case get_req_header(conn, @session_header) do
      [session_id | _] ->
        case SessionController.fetch(conf.session_controller, session_id, conn) do
          {:ok, session} -> fun.(session)
          {:error, _} -> send_error(conn, session_not_found_error(), msg.id)
        end

      [] ->
        send_error(conn, session_required_error(), msg.id)
    end
  end

  defp session_required_error do
    {:mcp_error, @rpc_invalid_request, 400, "Mcp-Session-Id header is required"}
  end

  # 404 is what the 2025 spec defines as "start a new session".
  defp session_not_found_error do
    {:mcp_error, @rpc_invalid_request, 404, "Session not found or expired"}
  end

  # -- Dispatch ---------------------------------------------------------------

  defp dispatch(conn, {:ok, req}, msg_id, codec, conf) do
    run(conn, req, msg_id, codec, conf)
  end

  defp dispatch(conn, {:error, reason}, msg_id, codec, _conf) do
    Relay.send_error(conn, reason, msg_id, codec)
  end

  defp run(conn, req, msg_id, codec, conf) do
    channel = make_channel(conn, req, conf)

    case Server.start_request(conf.server_opts, req, channel) do
      {:ok, pid} -> Relay.respond(conn, codec, msg_id, pid)
      {:error, reason} -> Relay.send_error(conn, reason, msg_id, codec)
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

  defp send_result(conn, result, msg_id) do
    payload = %MCP.JSONRPCResultResponse{id: msg_id, jsonrpc: "2.0", result: result}

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, JSV.Codec.format_to_iodata!(payload))
    |> Relay.finalize()
  end

  # Public: also used by the router module (origin validation).
  def send_error(conn, reason, msg_id) do
    Relay.send_error(conn, reason, msg_id, @rpc_codec)
  end
end
