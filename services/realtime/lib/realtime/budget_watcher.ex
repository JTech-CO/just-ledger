defmodule Realtime.BudgetWatcher do
  @moduledoc """
  예산 임계 감시 (M7 DoD 4 — 동일 임계 알림 중복 발송 금지).

  `balance_changed` 를 받아 해당 계정에 걸린 예산의 소진 비율을 보고, 임계를
  넘는 순간 **한 번만** `budget_alert` 를 발행한다.

  중복 방지는 DB 의 `budget_alert_log`(PRIMARY KEY (budget_id, period_key))로
  한다 — INSERT ON CONFLICT DO NOTHING 이 1행을 넣을 때만 발화한다. 발화 기록이
  DB 에 남으므로 **감시자가 재시작해도** 같은 (예산, 기간) 알림이 다시 나가지
  않는다(프로세스 메모리 상태에 기대면 재시작 경계에서 DoD 4 가 깨진다).
  기간이 바뀌면 period_key 가 달라져 자연히 다시 감시한다.

  금액은 정수(최소 화폐 단위)로만 다룬다. 비율 비교도 부동소수점 없이
  `spent * den >= limit * num` 교차곱으로 한다 (INV-4).

  위조 방어: 계약 밖 페이로드(row·account_id 누락 등)는 함수 절에서 걸러
  무시한다 — rescue 로는 함수 절 불일치(FunctionClauseError)를 막을 수 없어
  감시자가 죽고 그 사이 상태가 날아갈 수 있다.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "리스너가 이벤트를 흘려 보낸다 (비동기 — 브로드캐스트 지연에 영향 없음)"
  def observe(owner_id, event), do: observe(__MODULE__, owner_id, event)

  @doc false
  def observe(server, owner_id, event) do
    case resolve(server) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:observe, owner_id, event})
    end
  end

  defp resolve(pid) when is_pid(pid), do: pid
  defp resolve(name), do: Process.whereis(name)

  @doc """
  임계 도달 여부 — 부동소수점 없이 교차곱으로 비교한다.
  `spent/limit >= num/den` ⟺ `spent*den >= limit*num`. spent 가 음수면
  (환불 우세) 도달하지 않은 것으로 본다.
  """
  def threshold_reached?(spent, limit, {num, den})
      when is_integer(spent) and is_integer(limit) and limit > 0 and spent >= 0 do
    spent * den >= limit * num
  end

  def threshold_reached?(_, _, _), do: false

  @impl true
  def init(opts) do
    ratio =
      validate_ratio(
        Keyword.get(opts, :ratio, Application.get_env(:realtime, :budget_alert_ratio, {8, 10}))
      )

    pubsub = Keyword.get(opts, :pubsub, Realtime.PubSub)

    # 조회·발화 함수를 주입 가능하게 둔다 — DB 없이 순수 로직을 테스트하기 위함.
    # 기본은 QueryConn 을 쓰는 실제 구현.
    status_fn = Keyword.get(opts, :status_fn, &default_status/2)
    claim_fn = Keyword.get(opts, :claim_fn, &default_claim/3)

    # 리스너가 내부 토픽으로 흘려 보내는 balance_changed 를 구독한다. 감시자를
    # 직접 호출하지 않으므로(pubsub 경유) 이 pubsub 을 쓰는 인스턴스에만 닿는다.
    Phoenix.PubSub.subscribe(pubsub, Realtime.Listener.watch_topic())
    {:ok, %{ratio: ratio, pubsub: pubsub, status_fn: status_fn, claim_fn: claim_fn}}
  end

  # 비율은 0 < num < den 이어야 한다 — num=0 이면 소진 0 예산도 즉시 발화하고,
  # num>=den 이면 100% 초과에서만 발화해 사실상 무의미해진다.
  defp validate_ratio({num, den})
       when is_integer(num) and is_integer(den) and num > 0 and den > 0 and num < den do
    {num, den}
  end

  defp validate_ratio(bad) do
    raise ArgumentError, "budget_alert_ratio 는 0 < num < den 이어야 합니다: #{inspect(bad)}"
  end

  @impl true
  # 계약(balance_changed + row.account_id)에 맞는 이벤트만 평가한다.
  # 직접 cast(테스트) 와 pubsub 브로드캐스트(운영) 둘 다 같은 형태로 받는다.
  def handle_cast({:observe, owner, event}, state), do: {:noreply, on_observe(owner, event, state)}

  @impl true
  def handle_info({:observe, owner, event}, state), do: {:noreply, on_observe(owner, event, state)}
  def handle_info(_other, state), do: {:noreply, state}

  defp on_observe(owner, %{"type" => "balance_changed", "row" => %{"account_id" => acc}}, state)
       when is_binary(owner) and is_binary(acc) do
    evaluate(owner, acc, state)
  end

  # 그 외(다른 이벤트 유형·위조 페이로드)는 조용히 무시 — 크래시 금지
  defp on_observe(_owner, _event, state), do: state

  defp evaluate(owner, account_id, state) do
    for b <- state.status_fn.(owner, account_id) do
      if threshold_reached?(b.spent_minor, b.limit_minor, state.ratio) and
           state.claim_fn.(owner, b.id, b.period_key) do
        broadcast(owner, b, state)
      end
    end

    state
  rescue
    e ->
      # 조회/발화가 터져도 브리지·감시자를 죽이지 않는다 (부가 기능)
      Logger.error("BudgetWatcher: 평가 실패 #{inspect(e)}")
      state
  end

  defp broadcast(owner, budget, state) do
    {num, den} = state.ratio

    Phoenix.PubSub.broadcast(
      state.pubsub,
      Realtime.Listener.topic(owner),
      {:ledger_event,
       %{
         "type" => "budget_alert",
         "budget_id" => budget.id,
         "period" => budget.period_key,
         "limit_minor" => Integer.to_string(budget.limit_minor),
         "spent_minor" => Integer.to_string(budget.spent_minor),
         "ratio" => "#{num}/#{den}"
       }}
    )
  end

  # ── 기본(운영) 구현 — Realtime.QueryConn 을 쓴다. 없으면 비활성(빈/실패) ──
  defp default_status(owner_id, account_id) do
    case Process.whereis(Realtime.QueryConn) do
      nil -> []
      conn -> Realtime.Repo.budget_status(conn, owner_id, account_id)
    end
  end

  defp default_claim(owner_id, budget_id, period_key) do
    case Process.whereis(Realtime.QueryConn) do
      nil -> false
      conn -> Realtime.Repo.claim_alert(conn, owner_id, budget_id, period_key)
    end
  end
end
