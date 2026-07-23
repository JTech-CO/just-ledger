defmodule Realtime.ListenerTest do
  @moduledoc """
  봉투 파싱과 소유자 라우팅 — 실시간 경로의 테넌트 격리 근거를 직접 검증한다.
  RLS 가 없는 경로이므로 "라우팅이 틀리면 남의 잔액이 간다"가 그대로 성립한다.
  """
  use ExUnit.Case, async: true

  alias Realtime.Listener

  @owner1 "11111111-1111-4111-8111-111111111111"
  @owner2 "22222222-2222-4222-8222-222222222222"

  defp envelope(owner, event), do: Jason.encode!(%{"owner_id" => owner, "event" => event})

  defp balance_event(account \\ "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", amount \\ "42000") do
    %{
      "type" => "balance_changed",
      "row" => %{"account_id" => account, "currency" => "KRW", "balance_minor" => amount}
    }
  end

  describe "parse_envelope/1" do
    test "정상 봉투를 소유자와 이벤트로 분해한다" do
      assert {:ok, @owner1, event} = Listener.parse_envelope(envelope(@owner1, balance_event()))
      assert event["type"] == "balance_changed"
      assert event["row"]["balance_minor"] == "42000"
    end

    test "owner_id 가 없으면 거절한다 (브로드캐스트 폴백 없음)" do
      raw = Jason.encode!(%{"event" => balance_event()})
      assert {:error, :bad_envelope} = Listener.parse_envelope(raw)
    end

    test "owner_id 가 UUID 형식이 아니면 거절한다" do
      assert {:error, :bad_owner_id} =
               Listener.parse_envelope(envelope("not-a-uuid", balance_event()))

      assert {:error, :bad_owner_id} = Listener.parse_envelope(envelope("", balance_event()))
    end

    test "event 가 없거나 type 이 없으면 거절한다" do
      assert {:error, :bad_envelope} =
               Listener.parse_envelope(Jason.encode!(%{"owner_id" => @owner1}))

      assert {:error, :bad_envelope} =
               Listener.parse_envelope(Jason.encode!(%{"owner_id" => @owner1, "event" => %{}}))
    end

    test "JSON 이 아니면 거절한다" do
      assert {:error, :bad_json} = Listener.parse_envelope("not json")
      assert {:error, :bad_json} = Listener.parse_envelope("")
    end

    test "봉투 이전 형식(평면 이벤트)은 거절한다 — 소유자 근거가 없다" do
      legacy = Jason.encode!(balance_event())
      assert {:error, :bad_envelope} = Listener.parse_envelope(legacy)
    end

    test "DB 발행 유형 화이트리스트 밖 type 은 거절한다 (위조 프레임 차단)" do
      # budget_alert·sync 는 realtime 내부 생성 — 봉투로 오면 위조다
      for t <- ["budget_alert", "sync", "arbitrary", "delete_everything"] do
        ev = %{"type" => t}
        assert {:error, :unknown_event_type} = Listener.parse_envelope(envelope(@owner1, ev))
      end
    end
  end

  describe "dispatch/2 — 소유자 격리" do
    setup do
      pubsub = :"pubsub_#{System.unique_integer([:positive])}"
      start_supervised!({Phoenix.PubSub, name: pubsub})
      %{pubsub: pubsub}
    end

    test "이벤트는 그 소유자 토픽으로만 간다", %{pubsub: pubsub} do
      Phoenix.PubSub.subscribe(pubsub, Listener.topic(@owner1))
      Phoenix.PubSub.subscribe(pubsub, Listener.topic(@owner2))

      Listener.dispatch(envelope(@owner1, balance_event("acc-1", "1000")), pubsub)

      assert_receive {:ledger_event, %{"row" => %{"balance_minor" => "1000"}}}

      # owner2 토픽으로도 왔다면 같은 프로세스가 두 번 받는다 — 한 번만 와야 한다
      refute_receive {:ledger_event, _}, 50
    end

    test "다른 소유자의 구독자에게는 가지 않는다", %{pubsub: pubsub} do
      parent = self()

      task =
        Task.async(fn ->
          Phoenix.PubSub.subscribe(pubsub, Listener.topic(@owner2))
          send(parent, :subscribed)

          receive do
            {:ledger_event, e} -> {:got, e}
          after
            200 -> :nothing
          end
        end)

      assert_receive :subscribed
      Listener.dispatch(envelope(@owner1, balance_event()), pubsub)
      assert Task.await(task) == :nothing
    end

    test "계약 위반 페이로드는 어디로도 발행하지 않는다", %{pubsub: pubsub} do
      Phoenix.PubSub.subscribe(pubsub, Listener.topic(@owner1))

      assert {:error, :bad_envelope} = Listener.dispatch(Jason.encode!(balance_event()), pubsub)
      assert {:error, :bad_json} = Listener.dispatch("garbage", pubsub)
      refute_receive {:ledger_event, _}, 50
    end

    test "세 이벤트 유형이 모두 전달된다", %{pubsub: pubsub} do
      Phoenix.PubSub.subscribe(pubsub, Listener.topic(@owner1))

      for event <- [
            balance_event(),
            %{"type" => "ingest_progress", "batch_id" => @owner2, "state" => "done"},
            %{
              "type" => "settlement_done",
              "period" => %{"start" => "2026-05-01", "end" => "2026-05-31"}
            }
          ] do
        Listener.dispatch(envelope(@owner1, event), pubsub)
      end

      assert_receive {:ledger_event, %{"type" => "balance_changed"}}
      assert_receive {:ledger_event, %{"type" => "ingest_progress"}}
      assert_receive {:ledger_event, %{"type" => "settlement_done"}}
    end
  end

  describe "topic/1" do
    test "소유자별로 다른 토픽" do
      assert Listener.topic(@owner1) != Listener.topic(@owner2)
      assert Listener.topic(@owner1) == "user:" <> @owner1
    end
  end
end
