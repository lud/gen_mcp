import Config

port = String.to_integer(System.get_env("PORT", "5000"))

config :gen_mcp, GenMCP.TestWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: port],
  url: [host: "localhost", port: port, scheme: "http"],
  server: true,
  debug_errors: true,
  code_reloader: false,
  secret_key_base: "g2XBbCWHb+zANuLKxVwY9Tu3MDkf18lpNPLiCh/Wbib2/G2GSVgiF4NAq9t03UZU",
  adapter: Bandit.PhoenixAdapter

log_level =
  if config_env() == :test do
    :warning
  else
    :debug
  end

config :logger, level: log_level

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:node]

config :phoenix, :logger, true

config :phoenix, :plug_init_mode, :runtime
