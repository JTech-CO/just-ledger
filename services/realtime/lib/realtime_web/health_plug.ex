defmodule RealtimeWeb.HealthPlug do
  @moduledoc """
  최소 HTTP 표면 — `/health` 만 응답한다.
  이 서비스는 WebSocket 전용이므로 REST 라우터를 두지 않는다(원장 조회는 web 담당).
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["health"]} = conn, _opts) do
    # 프로세스 생존이 아니라 실제 LISTEN 연결 상태를 본다. DATABASE_URL 미설정
    # 환경(채널 단독)에서는 브리지가 없는 게 정상이므로 degraded 로 구분한다.
    bridge_expected = Realtime.Repo.conn_opts() != nil
    listening = Realtime.Listener.listening?()
    ok = not bridge_expected or listening
    status = if ok, do: 200, else: 503

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{"ok" => ok, "listening" => listening}))
    |> halt()
  end

  def call(conn, _opts), do: conn |> send_resp(404, "") |> halt()
end
