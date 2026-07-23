defmodule RealtimeWeb.LedgerChannelTest do
  @moduledoc """
  채널 가입 격리와 전달 — 토픽의 owner_id 가 소켓 신원과 다르면 거절한다.
  실시간 경로에는 RLS 가 없으므로 이 검사가 통과하면 그대로 데이터가 흐른다.
  """
  use ExUnit.Case, async: false
  import Phoenix.ChannelTest

  @endpoint RealtimeWeb.Endpoint

  @owner1 "11111111-1111-4111-8111-111111111111"
  @owner2 "22222222-2222-4222-8222-222222222222"

  # PubSub·Endpoint 는 애플리케이션 감독 트리가 이미 띄운 것을 그대로 쓴다.

  defp socket_for(owner) do
    socket(RealtimeWeb.UserSocket, "sock:#{owner}", %{owner_id: owner})
  end

  test "자기 토픽에는 가입할 수 있다" do
    assert {:ok, _, _socket} =
             socket_for(@owner1)
             |> subscribe_and_join(RealtimeWeb.LedgerChannel, "ledger:#{@owner1}")
  end

  test "남의 토픽 가입은 거절된다" do
    assert {:error, %{reason: "forbidden"}} =
             socket_for(@owner1)
             |> subscribe_and_join(RealtimeWeb.LedgerChannel, "ledger:#{@owner2}")
  end

  test "알 수 없는 토픽은 거절된다" do
    assert {:error, %{reason: "unknown_topic"}} =
             socket_for(@owner1) |> subscribe_and_join(RealtimeWeb.LedgerChannel, "other:x")
  end

  test "가입 직후 sync 스냅샷을 받는다 (재접속 보정 — DoD 3)" do
    {:ok, _, _socket} =
      socket_for(@owner1) |> subscribe_and_join(RealtimeWeb.LedgerChannel, "ledger:#{@owner1}")

    # 모든 프레임은 "event" 이벤트명 + 계약 객체(type 포함). DB 미연결이면 빈 목록.
    assert_push("event", %{"type" => "sync", "balances" => balances})
    assert is_list(balances)
  end

  test "내 소유자 이벤트만 푸시되고, 프레임에 type 이 유지된다" do
    {:ok, _, _socket} =
      socket_for(@owner1) |> subscribe_and_join(RealtimeWeb.LedgerChannel, "ledger:#{@owner1}")

    assert_push("event", %{"type" => "sync"})

    event = %{
      "type" => "balance_changed",
      "row" => %{"account_id" => "a", "currency" => "KRW", "balance_minor" => "5000"}
    }

    # 내 토픽 — 받아야 한다. web applyRealtime 이 evt.type 으로 분기하므로 type 유지.
    Phoenix.PubSub.broadcast(
      Realtime.PubSub,
      Realtime.Listener.topic(@owner1),
      {:ledger_event, event}
    )

    assert_push("event", %{"type" => "balance_changed", "row" => %{"balance_minor" => "5000"}})

    # 남의 토픽 — 오면 안 된다
    Phoenix.PubSub.broadcast(
      Realtime.PubSub,
      Realtime.Listener.topic(@owner2),
      {:ledger_event, event}
    )

    refute_push("event", %{"type" => "balance_changed"}, 100)
  end

  test "리스너 재연결(resync)에 현재 스냅샷을 다시 밀어 넣는다 (DoD 3)" do
    {:ok, _, _socket} =
      socket_for(@owner1) |> subscribe_and_join(RealtimeWeb.LedgerChannel, "ledger:#{@owner1}")

    assert_push("event", %{"type" => "sync"})

    Phoenix.PubSub.broadcast(Realtime.PubSub, "realtime:resync", :resync)
    assert_push("event", %{"type" => "sync", "balances" => _})
  end
end
