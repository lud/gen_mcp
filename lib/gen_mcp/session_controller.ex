defmodule GenMCP.SessionController do
  @moduledoc """
  Behaviour for the session store of the 2025 compatibility transport.

  The `2026-07-28` core is stateless and has no sessions. The 2025 protocol
  requires one: the client handshakes with `initialize`, the server answers with
  an `Mcp-Session-Id`, and every later request carries that id back. A session
  controller is what bridges the two — it is asked to `c:create/3` a session id
  at the end of the handshake, and to `c:fetch/3` the session data back on each
  subsequent request.

  The session is deliberately tiny. It holds only what the server actually reads
  later: the negotiated protocol version and the client's name and version,
  which the transport writes into the `_meta` of the `V2607` request it builds,
  so `GenMCP.Mux.Channel` carries them to handlers exactly as it would for a
  2026 request. It is written once at `initialize` and only read afterwards.

  The default controller is `GenMCP.SessionController.Token`, which stores
  nothing server-side. Configure another one on the compat transport with the
  `:session_controller` option, as a module or a `{module, arg}` tuple:

      forward "/mcp-2025", GenMCP.Transport.StreamableHTTP.V2511,
        server_name: "My App",
        server_version: "1.0.0",
        tools: [MyApp.AddTool],
        session_controller: {MyApp.RedisSessions, pool: :sessions}

  Implement one when the deployment needs the full `clientInfo` and capabilities
  kept server-side, or needs real revocation, which a self-contained session id
  cannot offer.
  """

  @typedoc """
  The client data a session carries across requests.
  """
  @type session :: %{
          protocol_version: binary,
          client_name: binary | nil,
          client_version: binary | nil
        }

  @type session_id :: binary

  @typedoc """
  The value configured alongside the module as `{module, arg}`.
  """
  @type arg :: term

  @type controller :: module | {module, arg} | %{mod: module, arg: arg}

  @doc """
  Creates a session and returns the id the client will send back.

  Called once, while answering `initialize`, with the `session` built from the
  handshake. The returned id becomes the response's `Mcp-Session-Id` header. It
  must be usable as an HTTP header value, and small enough to travel on every
  later request.

  Returning `{:error, reason}` fails the handshake with that reason.
  """
  @callback create(session, Plug.Conn.t(), arg) :: {:ok, session_id} | {:error, term}

  @doc """
  Reads back the session named by `session_id`.

  Called on every request after the handshake. Return `{:error, :invalid}` for
  an id this server did not issue or can no longer honor, and
  `{:error, :expired}` for one that has aged out; both are answered to the
  client as a `404 Not Found`, which the 2025 spec defines as the signal for the
  client to start a new session.
  """
  @callback fetch(session_id, Plug.Conn.t(), arg) :: {:ok, session} | {:error, term}

  @doc """
  Drops the session, on a client `DELETE`. Optional.

  A controller that keeps no server-side state has nothing to do here, so the
  callback is optional and the `DELETE` is accepted either way.
  """
  @callback delete(session_id, Plug.Conn.t(), arg) :: term

  @optional_callbacks delete: 3

  @doc """
  Normalizes the `:session_controller` option into a `%{mod: _, arg: _}` descriptor.
  """
  @spec expand(controller) :: %{mod: module, arg: arg}
  def expand(%{mod: _, arg: _} = controller) do
    controller
  end

  def expand(mod) when is_atom(mod) do
    expand({mod, []})
  end

  def expand({mod, arg}) when is_atom(mod) do
    Code.ensure_loaded!(mod)
    %{mod: mod, arg: arg}
  end

  @doc false
  def create(%{mod: mod, arg: arg}, session, conn) do
    mod.create(session, conn, arg)
  end

  @doc false
  def fetch(%{mod: mod, arg: arg}, session_id, conn) do
    mod.fetch(session_id, conn, arg)
  end

  @doc false
  def delete(%{mod: mod, arg: arg}, session_id, conn) do
    if function_exported?(mod, :delete, 3) do
      mod.delete(session_id, conn, arg)
    else
      :ok
    end
  end
end

defmodule GenMCP.SessionController.Token do
  @moduledoc """
  The default `GenMCP.SessionController`: the session id *is* the session.

  Nothing is stored server-side. The client data is sealed into the id itself
  with `GenMCP.Token`, using the application's `secret_key_base`, so
  `c:GenMCP.SessionController.create/3` is an encrypt and
  `c:GenMCP.SessionController.fetch/3` is a decrypt. There is no table, no
  process, and no coordination: a session minted on one node is readable on any
  other node sharing the configuration.

  The trade-off is that a session cannot be revoked. It stops being accepted
  when it expires, and a client whose session expired mid-conversation gets a
  `404`, the 2025 signal to handshake again.

  ## Session lifetime

  A session lasts one day. Expiry is the token's `:max_age`, and this
  controller sets its own default rather than taking the 20 minutes
  `GenMCP.Token` uses for pagination cursors, which is sized for a value
  replayed within a single listing rather than one a client holds across a
  whole conversation.

  To choose another lifetime, pass `:max_age` in the controller's `arg`, which
  is handed through as the `GenMCP.Token` options:

      forward "/mcp-2025", GenMCP.Transport.StreamableHTTP.V2511,
        server_name: "My App",
        server_version: "1.0.0",
        tools: [MyApp.AddTool],
        session_controller: {GenMCP.SessionController.Token, max_age: 3600}

  The value is in seconds and is embedded in the token at mint time, so every
  session is read back under the lifetime it was issued with — changing this
  setting does not retroactively extend or shorten sessions already handed out.

  Deployments that need revocation, or that need the full `clientInfo` and
  client capabilities server-side, implement their own controller instead.

  To keep the `Mcp-Session-Id` header small the sealed payload is a pruned
  tuple, not the whole `initialize` params — `clientInfo` is unbounded, since it
  may carry descriptions and icon data URIs.
  """

  @behaviour GenMCP.SessionController

  alias GenMCP.Token

  # Qualifies the token purpose, so a session id can never decrypt as a cursor
  # or a request state. The leading integer in the payload tags the tuple
  # layout; later gen_mcp releases have no session ids at all, so this is the
  # whole versioning story.
  @purpose {:session, "v2511"}
  @layout 1

  # A session spans a whole client conversation, so `GenMCP.Token`'s 20 minute
  # default — sized for a pagination cursor replayed within one listing — would
  # drop clients mid-work. A day covers the ordinary case without keeping a
  # forever-valid credential in circulation, and a deployment that wants
  # another number passes `max_age:` in the controller arg.
  @default_max_age_seconds 60 * 60 * 24

  # Only minting applies the default: `Plug.Crypto` embeds the max age in the
  # payload, so `fetch/3` enforces what the token was issued with rather than
  # whatever this release happens to default to today.
  @impl true
  def create(session, conn, opts) do
    %{
      protocol_version: protocol_version,
      client_name: client_name,
      client_version: client_version
    } = session

    payload = {@layout, protocol_version, client_name, client_version}
    opts = Keyword.put_new(opts, :max_age, @default_max_age_seconds)

    {:ok, Token.encrypt(conn, @purpose, payload, opts)}
  end

  @impl true
  def fetch(session_id, conn, opts) do
    case Token.decrypt(conn, @purpose, session_id, opts) do
      {:ok, {@layout, protocol_version, client_name, client_version}} ->
        {:ok,
         %{
           protocol_version: protocol_version,
           client_name: client_name,
           client_version: client_version
         }}

      # A well-formed token whose payload is not the layout this release mints.
      {:ok, _} ->
        {:error, :invalid}

      {:error, _} = err ->
        err
    end
  end
end
