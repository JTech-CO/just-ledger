import Config

config :realtime, RealtimeWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: {:system, "PORT"}],
  check_origin: [System.get_env("ORIGIN") || "https://localhost"]

config :logger, level: :info
