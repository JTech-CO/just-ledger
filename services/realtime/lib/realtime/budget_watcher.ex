defmodule Realtime.BudgetWatcher do
  @moduledoc """
  예산 임계 감시 (M7 DoD 4 — 동일 임계 알림 중복 발송 금지).

  `balance_changed` 를 받아 해당 계정에 걸린 예산의 소진 비율을 보고, 임계를
  넘는 순간 **한 번만** `budget_alert` 를 발행한다.

  중복 방지 규칙:
    · 발화 키는 `{owner_id, budget_id, period_key}` 다. 같은 기간에 같은 예산이
      여러 번 임계를 넘어도(잔액이 오르내려도) 재발화하지 않는다.
    · 기간이 바뀌면(다음 달) 키가 달라지므로 자연히 다시 감시한다.
    · **해제 후 재발화(플래핑)를 만들지 않는다.** 임계 아래로 내려갔다고 키를
      지우면 경계에서 잔액이 흔들릴 때 알림이 반복되기 때문이다.

  금액은 정수(최소 화폐 단위)로만 다룬다. 비율 비교도 부동소수점 없이
  `spent * den >= limit * num` 교차곱으로 한다 (INV-4).
  """
  use GenServer
  require Logger

  @type key :: {String.t(), String.t(), String.t()}

  # name: nil 이면 이름 없이 뜬다 — 테스트가 lookup 을 주입한 독립 인스턴스를
  # 여러 개 띄울 수 있어야 하기 때문이다(운영에서는 항상 모듈명 단일 인스턴스).
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

  @doc "테스트·운영 점검용 — 이미 발화한 키 집합"
  def fired, do: GenServer.call(__MODULE__, :fired)

  @doc "기간 키 — 예산 주기에 따라 달라진다(월간이면 YYYY-MM)"
  def period_key(period_kind, %Date{} = on) do
    case period_kind do
      "monthly" -> Calendar.strftime(on, "%Y-%m")
      "quarterly" -> "#{on.year}-Q#{div(on.month - 1, 3) + 1}"
      "yearly" -> Integer.to_string(on.year)
      _ -> Calendar.strftime(on, "%Y-%m")
    end
  end

  @doc """
  임계 도달 여부 — 부동소수점 없이 교차곱으로 비교한다.
  `spent/limit >= num/den` ⟺ `spent*den >= limit*num`
  """
  def threshold_reached?(spent, limit, {num, den})
      when is_integer(spent) and is_integer(limit) and limit > 0 do
    spent * den >= limit * num
  end

  def threshold_reached?(_, _, _), do: false

  @impl true
  def init(opts) do
    ratio = Keyword.get(opts, :ratio, Application.get_env(:realtime, :budget_alert_ratio, {8, 10}))
    pubsub = Keyword.get(opts, :pubsub, Realtime.PubSub)
    # 조회 함수를 주입 가능하게 둔다 — DB 없이 순수 로직을 테스트하기 위함
    lookup = Keyword.get(opts, :lookup, &__MODULE__.lookup_budgets/2)
    {:ok, %{ratio: ratio, pubsub: pubsub, lookup: lookup, fired: MapSet.new()}}
  end

  @impl true
  def handle_call(:fired, _from, state), do: {:reply, state.fired, state}

  @impl true
  def handle_cast({:observe, owner, %{"type" => "balance_changed", "row" => row}}, state) do
    {:noreply, evaluate(owner, row, state)}
  end

  def handle_cast({:observe, _owner, _event}, state), do: {:noreply, state}

  defp evaluate(owner, %{"account_id" => account_id}, state) do
    case state.lookup.(owner, account_id) do
      [] ->
        state

      budgets ->
        Enum.reduce(budgets, state, fn b, acc -> maybe_fire(owner, b, acc) end)
    end
  rescue
    # 감시는 부가 기능이다 — 조회가 실패해도 브리지를 죽이지 않는다
    e ->
      Logger.error("BudgetWatcher: 예산 조회 실패 #{inspect(e)}")
      state
  end

  defp maybe_fire(owner, budget, state) do
    key = {owner, budget.id, budget.period_key}

    cond do
      MapSet.member?(state.fired, key) ->
        state

      not threshold_reached?(budget.spent_minor, budget.limit_minor, state.ratio) ->
        state

      true ->
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

        %{state | fired: MapSet.put(state.fired, key)}
    end
  end

  @doc """
  계정에 걸린 예산과 현재 기간 소진액 조회 (기본 구현 — DB 필요).
  DB 가 없으면 빈 목록을 준다: 감시는 부가 기능이므로 브리지를 막지 않는다.
  """
  def lookup_budgets(owner_id, account_id) do
    case Process.whereis(Realtime.QueryConn) do
      nil ->
        []

      conn ->
        today = Date.utc_today()

        sql = """
        SELECT b.id::text, b.period_kind, b.limit_minor::text,
               COALESCE(SUM(CASE WHEN e.direction = 'debit'
                                 THEN e.amount_minor ELSE -e.amount_minor END), 0)::text
          FROM budget b
          LEFT JOIN entry e ON e.account_id = b.account_id
          LEFT JOIN txn t ON t.id = e.txn_id
                         AND t.status IN ('posted', 'settled')
                         AND t.occurred_on >= $3::date
         WHERE b.owner_id = $1::text::uuid AND b.account_id = $2::text::uuid
         GROUP BY b.id, b.period_kind, b.limit_minor
        """

        with {:ok, _} <-
               Postgrex.query(conn, "SELECT set_config('app.user_id', $1, true)", [owner_id]),
             {:ok, res} <-
               Postgrex.query(conn, sql, [owner_id, account_id, period_start(today)]) do
          Enum.map(res.rows, fn [id, kind, limit, spent] ->
            %{
              id: id,
              period_key: period_key(kind, today),
              limit_minor: String.to_integer(limit),
              spent_minor: String.to_integer(spent)
            }
          end)
        else
          _ -> []
        end
    end
  end

  defp period_start(%Date{} = d), do: %{d | day: 1}
end
