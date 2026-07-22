defmodule RealtimeWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :realtime

  socket("/socket", RealtimeWeb.UserSocket,
    websocket: [connect_info: [:peer_data]],
    longpoll: false
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(RealtimeWeb.HealthPlug)
end
