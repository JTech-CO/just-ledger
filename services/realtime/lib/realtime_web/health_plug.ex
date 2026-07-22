defmodule RealtimeWeb.HealthPlug do
  @moduledoc """
  최소 HTTP 표면 — `/health` 만 응답한다.
  이 서비스는 WebSocket 전용이므로 REST 라우터를 두지 않는다(원장 조회는 web 담당).
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["health"]} = conn, _opts) do
    listening = Process.whereis(Realtime.Listener) != nil

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{"ok" => true, "listener" => listening}))
    |> halt()
  end

  def call(conn, _opts), do: conn |> send_resp(404, "") |> halt()
end
