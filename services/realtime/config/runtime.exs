import Config

# 런타임 설정 — 릴리스·prod 기동 시 환경변수에서 읽는다. secret_key_base 를
# 컴파일 타임(prod.exs)에 두지 않는 이유: 없으면 토큰 검증이 항상 예외라 모든
# 소켓 접속이 거절된다(실시간 계층 전체 불가). web(Fastify)과 **같은 키**를
# 공유해야 web 이 서명한 Phoenix.Token 을 이 서비스가 검증할 수 있다.
if config_env() == :prod do
  secret =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      SECRET_KEY_BASE 환경변수가 필요합니다. web(Fastify)과 동일한 값을 설정하세요.
      생성: mix phx.gen.secret
      """

  port = String.to_integer(System.get_env("PORT") || "4000")
  origin = System.get_env("ORIGIN") || "https://localhost"

  config :realtime, RealtimeWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret,
    check_origin: [origin],
    server: true

  if url = System.get_env("DATABASE_URL") do
    config :realtime, database_url: url
  end

  config :realtime,
    pool_size: String.to_integer(System.get_env("REALTIME_POOL_SIZE") || "5")
end
