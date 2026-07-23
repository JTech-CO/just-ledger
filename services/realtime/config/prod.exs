import Config

# 컴파일 타임 prod 설정만. 비밀·포트·오리진 등 배포 환경값은 runtime.exs 에서
# 환경변수로 읽는다(secret_key_base 를 여기 두면 이미지에 박히거나 누락된다).
config :logger, level: :info

# 운영 오류 렌더링 — 포맷터가 비어 있으면 렌더링 자체가 크래시하므로 최소 1개.
config :realtime, RealtimeWeb.Endpoint,
  render_errors: [formats: [json: RealtimeWeb.ErrorJSON], layout: false]
