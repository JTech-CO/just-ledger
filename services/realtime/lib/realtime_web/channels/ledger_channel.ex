defmodule RealtimeWeb.LedgerChannel do
  @moduledoc """
  원장 실시간 채널. 토픽은 `ledger:<owner_id>` 한 가지다.

  격리: 소켓이 인증에서 확정한 `owner_id` 와 토픽의 owner_id 가 **정확히
  일치할 때만** 가입을 허용한다. 실시간 경로에는 RLS 가 없으므로 여기서
  막지 못하면 남의 잔액이 그대로 흘러간다.

  프레임: 모든 이벤트를 단일 `"event"` 메시지로 내보내고, 페이로드는
  contracts/notify-event.schema.json 계약 객체 그대로다(type 포함). 브라우저
  store 의 applyRealtime(evt) 은 evt.type 으로 분기하므로 type 을 페이로드에
  유지해야 한다 — 이벤트명으로 빼면 web 이 전부 무시한다.

  재접속 보정(DoD 3): join 직후, 그리고 리스너 재연결 시(realtime:resync)
  현재 잔액 스냅샷을 sync 이벤트로 밀어 넣는다. 끊긴 동안 놓친 변경이
  무엇이든 스냅샷으로 수렴하므로 이벤트 로그 재생이 필요 없다.
  """
  use Phoenix.Channel
  require Logger

  @impl true
  def join("ledger:" <> owner_id, _params, socket) do
    if socket.assigns[:owner_id] == owner_id and owner_id != "" do
      # 이 소유자 토픽 + 리스너 재연결 보정 신호를 구독한다
      Phoenix.PubSub.subscribe(socket.pubsub_server, Realtime.Listener.topic(owner_id))
      Phoenix.PubSub.subscribe(socket.pubsub_server, "realtime:resync")
      send(self(), :sync)
      {:ok, socket}
    else
      {:error, %{reason: "forbidden"}}
    end
  end

  def join(_topic, _params, _socket), do: {:error, %{reason: "unknown_topic"}}

  @impl true
  def handle_info(:sync, socket) do
    push(socket, "event", %{"type" => "sync", "balances" => snapshot(socket.assigns.owner_id)})
    {:noreply, socket}
  end

  # 리스너 재연결 — 놓친 창을 현재 상태로 수렴시킨다 (모든 접속 채널에 온다)
  def handle_info(:resync, socket) do
    push(socket, "event", %{"type" => "sync", "balances" => snapshot(socket.assigns.owner_id)})
    {:noreply, socket}
  end

  # 리스너·감시자가 PubSub 으로 흘려 보낸 계약 프레임을 그대로 전달한다.
  def handle_info({:ledger_event, %{"type" => _} = event}, socket) do
    push(socket, "event", event)
    {:noreply, socket}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp snapshot(owner_id) do
    case Process.whereis(Realtime.QueryConn) do
      nil ->
        []

      conn ->
        Realtime.Repo.balance_snapshot(conn, owner_id)
    end
  rescue
    e ->
      Logger.error("LedgerChannel: 스냅샷 실패 #{inspect(e)}")
      []
  end
end
