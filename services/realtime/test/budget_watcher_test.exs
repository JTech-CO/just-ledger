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

  # DB budget_alert_log 를 흉내 내는 Agent — (budget_id, period) 최초 1회만 true.
  defp new_claim_store do
    {:ok, claimed} = Agent.start_link(fn -> MapSet.new() end)
    claimed
  end

  defp claim_once(claimed, budget_id, period) do
    key = {budget_id, period}
    Agent.get_and_update(claimed, &claim_step(&1, key))
  end

  defp claim_step(set, key) do
    if MapSet.member?(set, key), do: {false, set}, else: {true, MapSet.put(set, key)}
  end

  # status_fn/claim_fn 을 주입한 독립 인스턴스.
  defp start_watcher(budgets, pubsub) do
    claimed = new_claim_store()
    claim_fn = fn _owner, bid, per -> claim_once(claimed, bid, per) end

    w =
      start_supervised!(
        {BudgetWatcher,
         [
           name: nil,
           pubsub: pubsub,
           ratio: {8, 10},
           status_fn: fn _o, _a -> budgets end,
           claim_fn: claim_fn
         ]}
      )

    {w, claimed}
  end

  setup do
    pubsub = :"pubsub_#{System.unique_integer([:positive])}"
    start_supervised!({Phoenix.PubSub, name: pubsub})
    Phoenix.PubSub.subscribe(pubsub, Realtime.Listener.topic(@owner))
    %{pubsub: pubsub}
  end

  describe "threshold_reached?/3 — 부동소수점 없는 교차곱" do
    test "0.8 경계는 정확히 판정된다" do
      assert BudgetWatcher.threshold_reached?(320_000, 400_000, {8, 10})
      refute BudgetWatcher.threshold_reached?(319_999, 400_000, {8, 10})
      assert BudgetWatcher.threshold_reached?(320_001, 400_000, {8, 10})
    end

    test "나누어떨어지지 않는 한도에서도 반올림 오차가 없다" do
      refute BudgetWatcher.threshold_reached?(266_666, 333_333, {8, 10})
      assert BudgetWatcher.threshold_reached?(266_667, 333_333, {8, 10})
    end

    test "한도 0 이하·소진 음수는 발화하지 않는다" do
      refute BudgetWatcher.threshold_reached?(100, 0, {8, 10})
      refute BudgetWatcher.threshold_reached?(-50, 400_000, {8, 10})
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

  describe "ratio 검증" do
    test "num >= den 또는 num=0 은 기동 거부" do
      for bad <- [{0, 10}, {10, 10}, {11, 10}] do
        assert_raise ArgumentError, fn ->
          BudgetWatcher.init(
            ratio: bad,
            pubsub: :x,
            status_fn: fn _, _ -> [] end,
            claim_fn: fn _, _, _ -> false end
          )
        end
      end
    end
  end

  describe "중복 발송 금지 (DoD 4)" do
    test "임계를 여러 번 넘어도 한 번만 발화한다 (claim 멱등)", %{pubsub: pubsub} do
      budget = %{id: "b1", period_key: "2026-05", limit_minor: 400_000, spent_minor: 350_000}
      {w, _} = start_watcher([budget], pubsub)

      for _ <- 1..5, do: BudgetWatcher.observe(w, @owner, balance_event())

      assert_receive {:ledger_event, %{"type" => "budget_alert", "budget_id" => "b1"}}, 500
      refute_receive {:ledger_event, %{"type" => "budget_alert"}}, 200
    end

    test "재시작해도 재발화하지 않는다 — claim 상태는 DB(여기선 Agent)에 있다", %{pubsub: pubsub} do
      budget = %{id: "b1", period_key: "2026-05", limit_minor: 400_000, spent_minor: 350_000}
      claimed = new_claim_store()
      claim_fn = fn _o, bid, per -> claim_once(claimed, bid, per) end

      opts = [
        name: nil,
        pubsub: pubsub,
        ratio: {8, 10},
        status_fn: fn _, _ -> [budget] end,
        claim_fn: claim_fn
      ]

      w1 = start_supervised!({BudgetWatcher, opts}, id: :w1)
      BudgetWatcher.observe(w1, @owner, balance_event())
      assert_receive {:ledger_event, %{"type" => "budget_alert"}}, 500
      stop_supervised!(:w1)

      # 감시자 재시작 — claim 상태(Agent=DB)는 살아 있으므로 다시 발화하지 않는다
      w2 = start_supervised!({BudgetWatcher, opts}, id: :w2)
      BudgetWatcher.observe(w2, @owner, balance_event())
      refute_receive {:ledger_event, %{"type" => "budget_alert"}}, 300
    end

    test "임계 미만이면 발화하지 않는다", %{pubsub: pubsub} do
      budget = %{id: "b1", period_key: "2026-05", limit_minor: 400_000, spent_minor: 319_999}
      {w, _} = start_watcher([budget], pubsub)

      BudgetWatcher.observe(w, @owner, balance_event())
      refute_receive {:ledger_event, %{"type" => "budget_alert"}}, 200
    end

    test "기간이 다르면 다시 발화한다", %{pubsub: pubsub} do
      b_may = %{id: "b1", period_key: "2026-05", limit_minor: 400_000, spent_minor: 350_000}
      b_jun = %{id: "b1", period_key: "2026-06", limit_minor: 400_000, spent_minor: 350_000}
      {w, _} = start_watcher([b_may, b_jun], pubsub)

      BudgetWatcher.observe(w, @owner, balance_event())

      assert_receive {:ledger_event, %{"type" => "budget_alert", "period" => p1}}, 500
      assert_receive {:ledger_event, %{"type" => "budget_alert", "period" => p2}}, 500
      assert Enum.sort([p1, p2]) == ["2026-05", "2026-06"]
    end

    test "발화 프레임은 금액을 문자열로 싣는다", %{pubsub: pubsub} do
      budget = %{id: "b1", period_key: "2026-05", limit_minor: 400_000, spent_minor: 350_000}
      {w, _} = start_watcher([budget], pubsub)

      BudgetWatcher.observe(w, @owner, balance_event())

      assert_receive {:ledger_event, frame}, 500
      assert frame["limit_minor"] == "400000"
      assert frame["spent_minor"] == "350000"
      assert frame["ratio"] == "8/10"
      assert is_binary(frame["limit_minor"])
    end
  end

  describe "위조·비계약 방어" do
    test "balance_changed 외 이벤트는 무시한다", %{pubsub: pubsub} do
      budget = %{id: "b1", period_key: "2026-05", limit_minor: 400_000, spent_minor: 350_000}
      {w, _} = start_watcher([budget], pubsub)

      BudgetWatcher.observe(w, @owner, %{"type" => "settlement_done", "period" => %{}})
      refute_receive {:ledger_event, %{"type" => "budget_alert"}}, 200
    end

    test "account_id 없는 위조 페이로드로 죽지 않는다", %{pubsub: pubsub} do
      budget = %{id: "b1", period_key: "2026-05", limit_minor: 400_000, spent_minor: 350_000}
      {w, _} = start_watcher([budget], pubsub)

      # row 에 account_id 가 없다 — 함수 절에서 걸러 무시되어야(크래시 금지)
      BudgetWatcher.observe(w, @owner, %{"type" => "balance_changed", "row" => %{"x" => 1}})
      BudgetWatcher.observe(w, @owner, %{"type" => "balance_changed"})
      Process.sleep(80)
      assert Process.alive?(w)
    end

    test "status_fn 이 터져도 감시자는 죽지 않는다", %{pubsub: pubsub} do
      w =
        start_supervised!(
          {BudgetWatcher,
           [
             name: nil,
             pubsub: pubsub,
             ratio: {8, 10},
             status_fn: fn _, _ -> raise "boom" end,
             claim_fn: fn _, _, _ -> true end
           ]}
        )

      BudgetWatcher.observe(w, @owner, balance_event())
      Process.sleep(100)
      assert Process.alive?(w)
    end
  end
end
