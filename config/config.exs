import Config

port = String.to_integer(System.get_env("PORT", "5000"))

log_level =
  if config_env() == :test do
    :warning
    # :debug
  else
    :debug
  end

config :gen_mcp, GenMCP.TestWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: port],
  url: [host: "localhost", port: port, scheme: "http"],
  server: true,
  debug_errors: true,
  code_reloader: false,
  secret_key_base: "g2XBbCWHb+zANuLKxVwY9Tu3MDkf18lpNPLiCh/Wbib2/G2GSVgiF4NAq9t03UZU",
  adapter: Bandit.PhoenixAdapter

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:node, :gen_mcp_session_id]

config :logger, level: log_level

config :phoenix, :logger, false

config :phoenix,
       :plug_init_mode,
       (case config_env() do
          :test -> :runtime
          _ -> :compile
        end)
