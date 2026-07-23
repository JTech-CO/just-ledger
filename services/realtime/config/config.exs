import Config

# 커넥션 풀 총합 규율(M7 DoD 5): PostgreSQL max_connections 를 넘지 않도록
# 서비스별 상한을 여기서 명시한다. 이 서비스는 LISTEN 전용 커넥션 1개 +
# 스냅샷 조회 풀(기본 5)만 쓴다. web(Fastify) 풀과의 총합은
# docs 의 배포 노트와 infra/compose.yaml 에서 함께 관리한다.
config :realtime,
  listen_channel: "ledger_events",
  pool_size: 5,
  # 예산 임계 비율 — 초과 시 budget_alert 를 1회만 발행한다(중복 금지, DoD 4)
  budget_alert_ratio: {8, 10}

config :realtime, RealtimeWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [json: RealtimeWeb.ErrorJSON], layout: false],
  pubsub_server: Realtime.PubSub,
  # 채널 프레임은 계약 JSON — Jason 직렬화만 쓴다
  http: [ip: {0, 0, 0, 0}, port: 4000],
  server: true

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
