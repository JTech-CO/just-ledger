defmodule RealtimeWeb.ErrorJSON do
  @moduledoc "최소 JSON 오류 렌더러 — 이 서비스는 WebSocket 전용이라 표면이 작다."

  def render(template, _assigns) do
    %{error: Phoenix.Controller.status_message_from_template(template)}
  end
end
