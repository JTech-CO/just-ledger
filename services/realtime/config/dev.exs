import Config

config :realtime, RealtimeWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  debug_errors: true,
  secret_key_base: String.duplicate("dev-only-not-a-secret", 4),
  check_origin: false

config :logger, level: :debug
