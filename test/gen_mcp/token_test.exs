defmodule GenMCP.TokenTest do
  use ExUnit.Case, async: true

  alias GenMCP.Mux.Channel
  alias GenMCP.Token

  # Spec 004 / task 012 — server-wide encryption for pagination cursors and,
  # later, the MRTR `requestState` blob (spec 007).
  #
  # `GenMCP.Token` is a thin wrapper over `Phoenix.Token` (authenticated
  # encryption — XChaCha20-Poly1305 via Plug.Crypto). There is no user-defined
  # token module and no transport option: the transport copies the Phoenix
  # endpoint from `conn.private.phoenix_endpoint` into the channel's
  # `endpoint` field, and `Phoenix.Token` accepts that endpoint as its key
  # source. The wrapper adds over calling `Phoenix.Token` directly:
  #
  #   * framed purposes `{:cursor, method}` / `{:reqstate, tool_name}` that
  #     participate in key derivation, so a token only ever decrypts under
  #     the exact purpose it was minted for;
  #   * a `gen_mcp` salt namespace, so our tokens can never collide with the
  #     host app's own Phoenix.Token usage of the same endpoint;
  #   * a `%GenMCP.Mux.Channel{}` head, so callers pass the channel they
  #     already hold.
  #
  # First argument is a key source: anything `Phoenix.Token` accepts as
  # context (endpoint module, secret-key-base string, conn) or a channel.

  @key_base "Iy0gLZpcS5ENbZS0jJ0mIVOZD7aOu4Pn7D8BiNUyrJVzlAevQUCFGDQDmprQyevy"
  @other_key_base "tJ2eXh0v1V5n3v8mY4qK7wL9sD2fG6hJ1kP5rT8uW0xZ3cB6nM9aQ4eS7gV0yI2o"

  defmodule FakeEndpoint do
    # The only part of the Phoenix endpoint contract that Phoenix.Token uses.
    def config(:secret_key_base) do
      "FmZ0sLJtmcfttHGNW8eU9o4lXgxLbXUkOGyiZQpYdGV3aDhxYkZzcW1wQXNkZmc0"
    end
  end

  defp channel_with_endpoint(endpoint \\ FakeEndpoint) do
    channel = Channel.for_pid(self())
    %{channel | endpoint: endpoint}
  end

  describe "encrypt/decrypt round-trip" do
    test "round-trips an arbitrary term with a key base string" do
      pagination = {_repo_index = 3, _repo_cursor = "page-2-marker"}

      token = Token.encrypt(@key_base, {:cursor, "resources/list"}, pagination)

      assert is_binary(token)
      assert {:ok, ^pagination} = Token.decrypt(@key_base, {:cursor, "resources/list"}, token)
    end

    test "round-trips with an endpoint module as key source" do
      token = Token.encrypt(FakeEndpoint, {:cursor, "prompts/list"}, %{some: ["term", 1]})

      assert {:ok, %{some: ["term", 1]}} =
               Token.decrypt(FakeEndpoint, {:cursor, "prompts/list"}, token)
    end

    test "round-trips through a channel carrying the endpoint" do
      channel = channel_with_endpoint()

      token = Token.encrypt(channel, {:cursor, "resources/list"}, {0, nil})

      assert {:ok, {0, nil}} = Token.decrypt(channel, {:cursor, "resources/list"}, token)
    end

    test "channel and raw endpoint key sources are interchangeable" do
      # The channel head only unwraps the endpoint; a token minted on one
      # request must verify on another node holding nothing but the same
      # endpoint configuration.
      channel = channel_with_endpoint()

      token = Token.encrypt(channel, {:cursor, "resources/list"}, "self-contained")

      assert {:ok, "self-contained"} =
               Token.decrypt(FakeEndpoint, {:cursor, "resources/list"}, token)
    end

    test "the reqstate purpose round-trips state blobs" do
      # Spec 007 will store tool continuation state here. MRTR requirement 4:
      # requestState is attacker-controlled, integrity MUST be protected —
      # authenticated encryption covers it, no extra AAD needed.
      kept = %{step: 2, args: %{"amount" => 100}}

      token = Token.encrypt(@key_base, {:reqstate, "transfer"}, kept)

      assert {:ok, ^kept} = Token.decrypt(@key_base, {:reqstate, "transfer"}, token)
    end
  end

  describe "token opacity" do
    test "the payload is encrypted, not merely signed" do
      # Repo cursors are repo-author-controlled; encrypting means we never
      # have to warn authors against putting secrets in them. A signed-only
      # token would expose the term_to_binary payload in a base64 segment.
      secret = "do-not-leak-repo-cursor"

      token = Token.encrypt(@key_base, {:cursor, "resources/list"}, {3, secret})

      refute token =~ secret

      for part <- String.split(token, "."),
          {:ok, decoded} <- [Base.url_decode64(part, padding: false)] do
        refute decoded =~ secret
      end
    end
  end

  describe "rejection" do
    test "rejects a forged token" do
      assert {:error, :invalid} =
               Token.decrypt(@key_base, {:cursor, "resources/list"}, "made-up-token")
    end

    test "rejects a tampered token" do
      token = Token.encrypt(@key_base, {:cursor, "resources/list"}, {0, "data"})

      assert {:error, :invalid} =
               Token.decrypt(@key_base, {:cursor, "resources/list"}, token <> "x")
    end

    test "rejects a token minted under another key" do
      token = Token.encrypt(@other_key_base, {:cursor, "resources/list"}, {0, "data"})

      assert {:error, :invalid} = Token.decrypt(@key_base, {:cursor, "resources/list"}, token)
    end

    test "cursors are bound to the method that minted them" do
      # Without the qualifier in key derivation, an authenticated
      # resources/list cursor would be a valid prompts/list cursor: some
      # PromptRepo would receive a repo cursor it never issued, carried by
      # the framework's "this is yours" stamp.
      token = Token.encrypt(@key_base, {:cursor, "resources/list"}, {0, "repo-data"})

      assert {:error, :invalid} = Token.decrypt(@key_base, {:cursor, "prompts/list"}, token)

      assert {:error, :invalid} =
               Token.decrypt(@key_base, {:cursor, "resources/templates/list"}, token)
    end

    test "purpose kinds are not interchangeable, even with the same qualifier" do
      cursor_token = Token.encrypt(@key_base, {:cursor, "transfer"}, {0, nil})
      state_token = Token.encrypt(@key_base, {:reqstate, "transfer"}, %{step: 1})

      assert {:error, :invalid} = Token.decrypt(@key_base, {:reqstate, "transfer"}, cursor_token)
      assert {:error, :invalid} = Token.decrypt(@key_base, {:cursor, "transfer"}, state_token)
    end

    test "does not accept tokens from the host app's own Phoenix.Token usage" do
      # The host app shares the endpoint (and thus secret_key_base) with us
      # for its own tokens. The gen_mcp salt namespace keeps both worlds
      # apart even if the app happens to use a bare method name as salt.
      app_token = Phoenix.Token.encrypt(FakeEndpoint, "resources/list", {0, nil})

      assert {:error, :invalid} =
               Token.decrypt(FakeEndpoint, {:cursor, "resources/list"}, app_token)
    end

    test "returns :missing for a nil token" do
      assert {:error, :missing} = Token.decrypt(@key_base, {:cursor, "resources/list"}, nil)
    end

    test "tokens expire after 20 minutes by default" do
      # The default :max_age is embedded in the encrypted payload at mint
      # time (Plug.Crypto stores {data, signed_at, max_age}), so decrypt
      # enforces it without any option at the call site.
      purpose = {:cursor, "resources/list"}
      now = System.system_time(:second)

      fresh = Token.encrypt(@key_base, purpose, {0, nil}, signed_at: now - 19 * 60)
      stale = Token.encrypt(@key_base, purpose, {0, nil}, signed_at: now - 21 * 60)

      assert {:ok, {0, nil}} = Token.decrypt(@key_base, purpose, fresh)
      assert {:error, :expired} = Token.decrypt(@key_base, purpose, stale)
    end

    test "expires tokens past max_age" do
      # :max_age and :signed_at are in SECONDS (Plug.Crypto convention). Note
      # the old suite passed `to_timeout(hour: 2)` — milliseconds — as
      # max_age, which made the 2h cursor expiry effectively ~83 days. The
      # suite rewrite must pass plain seconds.
      purpose = {:cursor, "resources/list"}

      token =
        Token.encrypt(@key_base, purpose, {0, nil}, signed_at: System.system_time(:second) - 61)

      assert {:error, :expired} = Token.decrypt(@key_base, purpose, token, max_age: 60)
      assert {:ok, {0, nil}} = Token.decrypt(@key_base, purpose, token, max_age: 3600)
    end
  end
end
