import Config

config :realtime, RealtimeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("test-only-not-a-secret", 4),
  check_origin: false,
  server: false

# 테스트는 DB 연결 없이도 도는 부분(채널·감시 GenServer 순수 로직)과
# DB 가 필요한 부분(LISTEN 브리지 통합)을 나눈다. DATABASE_URL 이 있으면 후자도 돈다.
config :realtime,
  database_url: System.get_env("DATABASE_URL"),
  pool_size: 2

config :logger, level: :warning
