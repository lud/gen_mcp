defmodule GenMCP.Token do
  @moduledoc """
  Authenticated encryption for the opaque tokens the library hands back to
  clients and later verifies.

  Some values the server produces have to make a round trip through an
  untrusted client and come back intact: a pagination cursor returned by
  `resources/list` and replayed on the next page, or the `requestState` blob a
  tool returns when it needs another round trip (see the MRTR pattern). The
  server is stateless, so it cannot remember what it issued. Instead it seals
  the value into a token that any per-request state, on any node, can verify
  using the application's `secret_key_base`.

  This module is a thin wrapper over `Phoenix.Token`, which provides the
  authenticated encryption (XChaCha20-Poly1305 via `Plug.Crypto`). It is not a
  general key/value store: it encrypts a term, hands the caller an opaque
  string, and decrypts that string back to the original term while rejecting
  anything forged, tampered, expired, or minted for a different purpose.

  The simplest round trip uses a `secret_key_base` string as the key source:

      iex> key = "Iy0gLZpcS5ENbZS0jJ0mIVOZD7aOu4Pn7D8BiNUyrJVzlAevQUCFGDQDmprQyevy"
      iex> token = GenMCP.Token.encrypt(key, {:cursor, "resources/list"}, "page-2")
      iex> GenMCP.Token.decrypt(key, {:cursor, "resources/list"}, token)
      {:ok, "page-2"}

  ### Key source

  The first argument is a key source, of type `t:key_source/0`. It may be a
  `GenMCP.Mux.Channel`, which carries the Phoenix endpoint the transport copied
  from the connection, or anything `Phoenix.Token` itself accepts: an endpoint
  module, a `secret_key_base` string, or a `Plug.Conn`. Inside request handling
  you usually pass the `channel` you already hold:

      token = GenMCP.Token.encrypt(channel, {:cursor, "resources/list"}, next_cursor)

      case GenMCP.Token.decrypt(channel, {:cursor, "resources/list"}, token) do
        {:ok, cursor} -> # resume listing from this cursor
        {:error, :invalid} -> # not a cursor we issued for this method
        {:error, :expired} -> # cursor too old
      end

  A channel whose `endpoint` is `nil` raises `ArgumentError`: there is no key to
  work with. In practice the transport always sets it.

  Because the key is the application's own `secret_key_base`, a token minted on
  one node verifies on any other node sharing that configuration. The key is
  never embedded in the token: `Plug.Crypto` stretches it with PBKDF2.

  ### Purposes

  The second argument is a purpose of type `t:purpose/0`, a `{kind, qualifier}`
  pair that frames what the token is for:

    * `{:cursor, method}` - a pagination cursor, qualified by the MCP method it
      paginates (for example `"resources/list"` or `"prompts/list"`).
    * `{:reqstate, unicity}` - an MRTR `requestState` blob, qualified by a map
      that binds it to the exact call that produced it (the tool name and its
      arguments).

  The purpose participates in key derivation, so a token only ever decrypts
  under the exact purpose it was minted for. A `resources/list` cursor replayed
  on `prompts/list` is rejected, and a cursor can never pass as a request state.
  For a `{:reqstate, unicity}` purpose the map is hashed deterministically, so
  the qualifier verifies regardless of key order, which is what lets a retry on
  another node rebuild the same purpose without coordinating map construction.

  All `gen_mcp` tokens carry a salt namespace that keeps them distinct from any
  `Phoenix.Token` the host application mints from the same endpoint, even if the
  application happens to use a bare method name as its own salt.

  ### Expiry

  Tokens carry a default `:max_age` of 20 minutes, set at encrypt time.
  `Plug.Crypto` embeds the mint-time `:max_age` inside the encrypted payload, so
  `decrypt/4` enforces it without the call site having to remember. Pass an
  explicit `:max_age` (in seconds) to either function to override it.
  """

  alias GenMCP.Mux.Channel

  @type purpose :: {:cursor, String.t()} | {:reqstate, map}

  @type key_source :: Channel.t() | module | binary | Plug.Conn.t()

  # Embedded in the encrypted payload at mint time and enforced by decrypt,
  # so expiry is a tamper-proof mint-time policy no decrypt site can forget.
  @default_max_age_seconds 60 * 20

  @doc """
  Seals `term` into an opaque token bound to `purpose`.

  Returns an encrypted, authenticated string. The token can be carried by an
  untrusted client and read back later with `decrypt/4`, as long as the same key
  source and purpose are used. The `term` can be any Erlang term.

  ### Arguments

    * `context` - the key source (`t:key_source/0`). A `GenMCP.Mux.Channel`
      supplies the Phoenix endpoint it carries, whose `secret_key_base` becomes
      the encryption key; you may also pass an endpoint module, a
      `secret_key_base` string, or a `Plug.Conn`.
    * `purpose` - the `t:purpose/0` the token is for. It is folded into key
      derivation, so the token only decrypts under this same purpose.
    * `term` - the value to seal.
    * `opts` - forwarded to `Phoenix.Token.encrypt/4`. A `:max_age` of 20
      minutes is added when you do not pass one, and is embedded in the payload
      so `decrypt/4` enforces it.

  ### Examples

      iex> key = "Iy0gLZpcS5ENbZS0jJ0mIVOZD7aOu4Pn7D8BiNUyrJVzlAevQUCFGDQDmprQyevy"
      iex> token = GenMCP.Token.encrypt(key, {:cursor, "resources/list"}, "page-2")
      iex> is_binary(token)
      true
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
  Reads a token minted by `encrypt/4` back to its original term.

  Returns `{:ok, term}` when the token is genuine, unexpired, and was minted for
  the same `context` and `purpose`. Otherwise it returns one of:

    * `{:error, :invalid}` - the token is forged, tampered, minted under a
      different key, or minted for a different purpose (a wrong method, a wrong
      `{tool, args}` binding, or the other kind).
    * `{:error, :expired}` - the token is past its `:max_age`.
    * `{:error, :missing}` - the token is `nil`.

  ### Arguments

    * `context` - the key source (`t:key_source/0`), the same as the one passed
      to `encrypt/4`. A `GenMCP.Mux.Channel` supplies the Phoenix endpoint and
      thus the application's `secret_key_base`.
    * `purpose` - the `t:purpose/0` the token must have been minted for.
    * `token` - the token string, or `nil`.
    * `opts` - forwarded to `Phoenix.Token.decrypt/4`. Without a `:max_age` the
      mint-time value embedded in the token is enforced; pass `:max_age` (in
      seconds) to override it.

  ### Examples

  A token decrypts only under the purpose it was minted for, and a `nil` token
  reports `:missing`:

      iex> key = "Iy0gLZpcS5ENbZS0jJ0mIVOZD7aOu4Pn7D8BiNUyrJVzlAevQUCFGDQDmprQyevy"
      iex> token = GenMCP.Token.encrypt(key, {:cursor, "resources/list"}, "page-2")
      iex> GenMCP.Token.decrypt(key, {:cursor, "resources/list"}, token)
      {:ok, "page-2"}
      iex> GenMCP.Token.decrypt(key, {:cursor, "prompts/list"}, token)
      {:error, :invalid}
      iex> GenMCP.Token.decrypt(key, {:cursor, "resources/list"}, nil)
      {:error, :missing}
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
