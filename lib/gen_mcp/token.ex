defmodule GenMCP.Token do
  @moduledoc """
  Encrypts and decrypts the opaque tokens the server hands out to MCP
  clients: pagination cursors, and the MRTR `requestState` blobs.

  This is a thin layer over `Phoenix.Token.encrypt/4` and
  `Phoenix.Token.decrypt/4`, which provide *authenticated encryption*
  (XChaCha20-Poly1305 via `Plug.Crypto.MessageEncryptor`): clients cannot
  read the payload, and any tampered or forged token is rejected as
  `:invalid` before the payload is ever decoded.

  ## Key source

  The first argument is anything `Phoenix.Token` accepts as context — a
  Phoenix endpoint module, a `secret_key_base` string (20+ bytes), a
  `Plug.Conn` — or a `GenMCP.Mux.Channel` carrying the endpoint copied from
  the conn by the transport. The encryption key is derived from the
  application's `secret_key_base`, so a token minted while serving one
  request is valid for any later request on any node sharing that
  configuration. No per-session or per-node key is involved.

  ## Purposes

  Every token is minted for a `t:purpose/0`, a `{kind, qualifier}` pair such
  as `{:cursor, "resources/list"}` or `{:reqstate, tool_name}`. The purpose
  participates in key derivation, so a token only decrypts under the exact
  purpose it was minted for: a `resources/list` cursor replayed on
  `prompts/list` is `:invalid`, and no cursor can ever pass as a request
  state. Cursors are qualified by the MCP method they paginate.

  ## Terminology warning

  `Phoenix.Token.encrypt(context, secret, data)` names its second argument
  `secret`, but it is **not** the encryption key. It is a *salt*:
  `Plug.Crypto` stretches it together with the context's `secret_key_base`
  (PBKDF2, see `Plug.Crypto.KeyGenerator`) to derive the actual key. The
  purpose lands there, prefixed with `gen_mcp` so it cannot collide with
  salts the host application uses for its own `Phoenix.Token` tokens on the
  same endpoint.
  """

  alias GenMCP.Mux.Channel

  @typedoc """
  The domain a token is minted for.

  - For `:cursor`, the qualifier is a string. `GenMCP.Suite` uses the MCP method
  name that uses pagination in reponses (`"resources/list"`, `"prompts/list"`,
  `"resources/templates/list"`)
  - For `:reqstate`, the qualifier is a map that should uniquely identify a
    request so the token is only valid if echoed by the client on the same
    request. By unique we mean "same tool and same parameters", the request
    remains repeatable during the token's time to live. `GenMCP.Suite` uses a
    map with the tool name and the whole parameters of the tool call. MCP
    clients MUST use request state tokens with the exact same request parameters
    when providing additional inputs.
  """
  @type purpose :: {:cursor, String.t()} | {:reqstate, map}

  @typedoc "A `Phoenix.Token` context or a channel carrying the endpoint."
  @type key_source :: Channel.t() | module | binary | Plug.Conn.t()

  # Embedded in the encrypted payload at mint time and enforced by decrypt,
  # so expiry is a tamper-proof mint-time policy no decrypt site can forget.
  @default_max_age_seconds 60 * 20

  @doc """
  Encrypts `term` into an opaque, URL-safe token for the given purpose.

  Accepts the `Phoenix.Token.encrypt/4` options (notably `:signed_at`, in
  **seconds**). Unless overridden, tokens expire after
  #{@default_max_age_seconds} seconds (20 minutes): the `:max_age` is stored
  inside the encrypted payload and applied by `decrypt/4`.
  """
  @spec encrypt(key_source, purpose, term, keyword) :: binary
  def encrypt(context, purpose, term, opts \\ [])

  def encrypt(%Channel{} = channel, purpose, term, opts) do
    encrypt(endpoint!(channel), purpose, term, opts)
  end

  def encrypt(context, purpose, term, opts) do
    opts = Keyword.put_new(opts, :max_age, @default_max_age_seconds)
    Phoenix.Token.encrypt(context, salt_for(purpose), term, opts)
  end

  @doc """
  Decrypts a token minted by `encrypt/4` with the same purpose.

  Returns `{:error, :invalid}` on forgery, tampering, a wrong key or a wrong
  purpose, `{:error, :expired}` past the max age (in **seconds**, the one
  embedded at encryption unless `:max_age` is given here) and
  `{:error, :missing}` when the token is `nil`.
  """
  @spec decrypt(key_source, purpose, binary | nil, keyword) ::
          {:ok, term} | {:error, :invalid | :expired | :missing}
  def decrypt(context, purpose, token, opts \\ [])

  def decrypt(%Channel{} = channel, purpose, token, opts) do
    decrypt(endpoint!(channel), purpose, token, opts)
  end

  def decrypt(context, purpose, token, opts) do
    Phoenix.Token.decrypt(context, salt_for(purpose), token, opts)
  end

  defp salt_for({:cursor, qualifier}) when is_binary(qualifier) do
    "gen_mcp cursor " <> qualifier
  end

  defp salt_for({:reqstate, qualifier}) when is_map(qualifier) do
    "gen_mcp reqstate " <> hash_qualifier(qualifier)
  end

  defp hash_qualifier(term) do
    bin = :erlang.term_to_binary(term, [:deterministic])
    :crypto.hash(:sha256, bin)
  end

  defp endpoint!(%Channel{endpoint: nil}) do
    raise ArgumentError,
          "the channel carries no endpoint: the transport found no Phoenix " <>
            "endpoint in the conn, so there is no key to encrypt or decrypt " <>
            "tokens with"
  end

  defp endpoint!(%Channel{endpoint: endpoint}) do
    endpoint
  end
end
