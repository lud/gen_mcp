import Config

config :gen_mcp, GenMcp.TestWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 5002],
  url: [host: "localhost", port: 5002, scheme: "http"],
  server: true,
  debug_errors: true,
  code_reloader: false,
  secret_key_base: "g2XBbCWHb+zANuLKxVwY9Tu3MDkf18lpNPLiCh/Wbib2/G2GSVgiF4NAq9t03UZU",
  adapter: Bandit.PhoenixAdapter

config :logger, level: :debug
# config :logger, level: :warning

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:node]

config :phoenix, :logger, true
