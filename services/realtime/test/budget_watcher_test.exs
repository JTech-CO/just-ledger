defmodule Realtime.BudgetWatcherTest do
  @moduledoc "M7 DoD 4 — 동일 예산 임계 알림이 중복 발송되지 않는다."
  use ExUnit.Case, async: false

  alias Realtime.BudgetWatcher

  @owner "11111111-1111-4111-8111-111111111111"
  @account "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

  defp balance_event(account \\ @account) do
    %{
      "type" => "balance_changed",
      "row" => %{"account_id" => account, "currency" => "KRW", "balance_minor" => "1"}
    }
  end

  # 이름 없는 독립 인스턴스 — 운영에서는 모듈명 단일 인스턴스지만
  # 테스트는 lookup 을 주입한 감시자를 여러 개 띄워야 한다.
  defp start_watcher(lookup, pubsub) do
    start_supervised!({BudgetWatcher, [name: nil, lookup: lookup, pubsub: pubsub, ratio: {8, 10}]})
  end

  defp watcher_for(budgets, pubsub), do: start_watcher(fn _o, _a -> budgets end, pubsub)

  setup do
    pubsub = :"pubsub_#{System.unique_integer([:positive])}"
    start_supervised!({Phoenix.PubSub, name: pubsub})
    Phoenix.PubSub.subscribe(pubsub, Realtime.Listener.topic(@owner))
    %{pubsub: pubsub}
  end

  describe "threshold_reached?/3 — 부동소수점 없는 교차곱" do
    test "0.8 경계는 정확히 판정된다" do
      # 400000 의 80% = 320000 — 경계값은 '도달'로 본다
      assert BudgetWatcher.threshold_reached?(320_000, 400_000, {8, 10})
      refute BudgetWatcher.threshold_reached?(319_999, 400_000, {8, 10})
      assert BudgetWatcher.threshold_reached?(320_001, 400_000, {8, 10})
    end

    test "나누어떨어지지 않는 한도에서도 반올림 오차가 없다" do
      # 333333 의 80% = 266666.4 → 266667 부터 도달
      refute BudgetWatcher.threshold_reached?(266_666, 333_333, {8, 10})
      assert BudgetWatcher.threshold_reached?(266_667, 333_333, {8, 10})
    end

    test "한도 0 이하는 발화하지 않는다" do
      refute BudgetWatcher.threshold_reached?(100, 0, {8, 10})
    end

    test "큰 금액에서도 정수 그대로" do
      assert BudgetWatcher.threshold_reached?(
               800_000_000_000_000_000,
               1_000_000_000_000_000_000,
               {8, 10}
             )

      refute BudgetWatcher.threshold_reached?(
               799_999_999_999_999_999,
               1_000_000_000_000_000_000,
               {8, 10}
             )
    end
  end

  describe "period_key/2" do
    test "주기별로 키가 다르다" do
      d = ~D[2026-05-15]
      assert BudgetWatcher.period_key("monthly", d) == "2026-05"
      assert BudgetWatcher.period_key("quarterly", d) == "2026-Q2"
      assert BudgetWatcher.period_key("yearly", d) == "2026"
    end

    test "다음 달은 다른 키 — 기간이 바뀌면 다시 감시한다" do
      assert BudgetWatcher.period_key("monthly", ~D[2026-05-31]) !=
               BudgetWatcher.period_key("monthly", ~D[2026-06-01])
    end
  end

  describe "중복 발송 금지 (DoD 4)" do
    test "임계를 여러 번 넘어도 한 번만 발화한다", %{pubsub: pubsub} do
      budget = %{id: "b1", period_key: "2026-05", limit_minor: 400_000, spent_minor: 350_000}
      w = watcher_for([budget], pubsub)

      for _ <- 1..5, do: BudgetWatcher.observe(w, @owner, balance_event())

      assert_receive {:ledger_event, %{"type" => "budget_alert", "budget_id" => "b1"}}, 500
      refute_receive {:ledger_event, %{"type" => "budget_alert"}}, 200
    end

    test "임계 미만이면 발화하지 않는다", %{pubsub: pubsub} do
      budget = %{id: "b1", period_key: "2026-05", limit_minor: 400_000, spent_minor: 319_999}
      w = watcher_for([budget], pubsub)

      BudgetWatcher.observe(w, @owner, balance_event())
      refute_receive {:ledger_event, %{"type" => "budget_alert"}}, 200
    end

    test "기간이 다르면 다시 발화한다", %{pubsub: pubsub} do
      # 같은 예산이지만 기간 키가 다르면 별개 — 다음 달에는 다시 알린다
      b_may = %{id: "b1", period_key: "2026-05", limit_minor: 400_000, spent_minor: 350_000}
      b_jun = %{id: "b1", period_key: "2026-06", limit_minor: 400_000, spent_minor: 350_000}
      w = watcher_for([b_may, b_jun], pubsub)

      BudgetWatcher.observe(w, @owner, balance_event())

      assert_receive {:ledger_event, %{"type" => "budget_alert", "period" => p1}}, 500
      assert_receive {:ledger_event, %{"type" => "budget_alert", "period" => p2}}, 500
      assert Enum.sort([p1, p2]) == ["2026-05", "2026-06"]
    end

    test "발화 프레임은 금액을 문자열로 싣는다", %{pubsub: pubsub} do
      budget = %{id: "b1", period_key: "2026-05", limit_minor: 400_000, spent_minor: 350_000}
      w = watcher_for([budget], pubsub)

      BudgetWatcher.observe(w, @owner, balance_event())

      assert_receive {:ledger_event, frame}, 500
      assert frame["limit_minor"] == "400000"
      assert frame["spent_minor"] == "350000"
      assert frame["ratio"] == "8/10"
      assert is_binary(frame["limit_minor"])
    end

    test "balance_changed 외의 이벤트는 무시한다", %{pubsub: pubsub} do
      budget = %{id: "b1", period_key: "2026-05", limit_minor: 400_000, spent_minor: 350_000}
      w = watcher_for([budget], pubsub)

      BudgetWatcher.observe(w, @owner, %{"type" => "settlement_done", "period" => %{}})
      refute_receive {:ledger_event, %{"type" => "budget_alert"}}, 200
    end

    test "조회가 터져도 감시자는 죽지 않는다", %{pubsub: pubsub} do
      w = start_watcher(fn _o, _a -> raise "boom" end, pubsub)

      BudgetWatcher.observe(w, @owner, balance_event())
      Process.sleep(100)
      assert Process.alive?(w)
    end
  end
end
