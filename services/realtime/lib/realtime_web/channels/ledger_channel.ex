defmodule RealtimeWeb.LedgerChannel do
  @moduledoc """
  원장 실시간 채널. 토픽은 `ledger:<owner_id>` 한 가지다.

  격리: 소켓이 인증에서 확정한 `owner_id` 와 토픽의 owner_id 가 **정확히
  일치할 때만** 가입을 허용한다. 실시간 경로에는 RLS 가 없으므로 여기서
  막지 못하면 남의 잔액이 그대로 흘러간다.

  재접속 보정(DoD 3): join 직후 현재 잔액 스냅샷을 `sync` 로 밀어 넣는다.
  끊긴 동안 놓친 변경이 무엇이든 스냅샷으로 수렴하므로 이벤트 로그 재생이
  필요 없다. 클라이언트는 `sync` 를 받으면 해당 소유자의 잔액을 통째로 교체한다.
  """
  use Phoenix.Channel
  require Logger

  @impl true
  def join("ledger:" <> owner_id, _params, socket) do
    if socket.assigns[:owner_id] == owner_id do
      # 이 소유자 토픽만 구독한다 (리스너와 동일 규칙)
      Phoenix.PubSub.subscribe(socket.pubsub_server, Realtime.Listener.topic(owner_id))
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "forbidden"}}
    end
  end

  def join(_topic, _params, _socket), do: {:error, %{reason: "unknown_topic"}}

  @impl true
  def handle_info(:after_join, socket) do
    push(socket, "sync", %{"balances" => snapshot(socket.assigns.owner_id)})
    {:noreply, socket}
  end

  # 리스너·감시자가 PubSub 으로 흘려 보낸 계약 프레임을 그대로 전달한다.
  # 프레임 형태는 contracts/notify-event.schema.json — 여기서 재구성하지 않는다.
  def handle_info({:ledger_event, %{"type" => type} = event}, socket) do
    push(socket, type, Map.delete(event, "type"))
    {:noreply, socket}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  defp snapshot(owner_id) do
    case Process.whereis(Realtime.QueryConn) do
      nil ->
        []

      conn ->
        case Realtime.Repo.balance_snapshot(conn, owner_id) do
          {:ok, rows} ->
            rows

          other ->
            Logger.error("LedgerChannel: 스냅샷 실패 #{inspect(other)}")
            []
        end
    end
  end
end
