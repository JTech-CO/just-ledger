defmodule Realtime.Repo do
  @moduledoc """
  Postgrex 연결 설정과 조회.

  Ecto 를 쓰지 않는다 — 이 서비스가 필요한 것은 LISTEN 커넥션 1개와 재접속
  보정용 스냅샷·예산 감시 조회뿐이다. 원장 읽기/쓰기는 web(Fastify)이 담당한다.

  최소 권한(DoD 격리): 조회 커넥션은 접속 직후 `SET ROLE ledger_realtime` 으로
  강등한다(after_connect). 이 롤은 BYPASSRLS 가 없으므로 RLS 정책을 통과해야
  자기 소유 행만 본다. RLS 컨텍스트(app.user_id)는 각 조회를 **트랜잭션으로
  묶어** 그 안에서 set_config(local) 로 설정한다 — 트랜잭션 밖 set_config(local)
  은 바로 다음 문장에도 남지 않아, 그대로 두면 RLS 가 항상 0행을 준다.

  커넥션 예산(DoD 5): LISTEN 전용 1 + 조회 풀 pool_size(기본 5). web(Fastify)
  풀과의 총합이 PostgreSQL max_connections 아래가 되도록 배포 설정에서 관리한다.
  """
  require Logger

  @role "ledger_realtime"

  @doc "DATABASE_URL → Postgrex 옵션. 미설정이면 nil."
  def conn_opts do
    case System.get_env("DATABASE_URL") || Application.get_env(:realtime, :database_url) do
      nil -> nil
      url -> parse_url(url)
    end
  end

  @doc "풀을 쓰는 조회용 옵션 — 접속 직후 최소권한 롤로 강등한다"
  def pool_opts do
    case conn_opts() do
      nil ->
        nil

      opts ->
        Keyword.merge(opts,
          pool_size: Application.get_env(:realtime, :pool_size, 5),
          after_connect: {__MODULE__, :set_role, []}
        )
    end
  end

  @doc false
  def set_role(conn) do
    # 롤이 없거나 멤버십이 없는 환경(단위 테스트용 임시 DB)에서는 조용히 넘어간다.
    case Postgrex.query(conn, "SET ROLE #{@role}", []) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp parse_url(url) do
    uri = URI.parse(url)

    {user, pass} =
      case uri.userinfo do
        nil ->
          {nil, nil}

        info ->
          case String.split(info, ":", parts: 2) do
            [u, p] -> {u, p}
            [u] -> {u, nil}
          end
      end

    [
      hostname: uri.host,
      port: uri.port || 5432,
      database: String.trim_leading(uri.path || "", "/"),
      username: user,
      password: pass
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  @doc """
  RLS 컨텍스트 안에서 함수를 실행하고 그 결과를 벗겨 돌려준다. set_config(local)
  이 유효하려면 같은 트랜잭션이어야 하므로 Postgrex.transaction 으로 감싼다.
  fun 은 (conn) 을 받는다. 트랜잭션 실패는 예외로 올린다(호출측 rescue 가 잡음).
  """
  def with_owner(conn, owner_id, fun) do
    case Postgrex.transaction(conn, fn c ->
           Postgrex.query!(c, "SELECT set_config('app.user_id', $1, true)", [owner_id])
           fun.(c)
         end) do
      {:ok, result} -> result
      {:error, reason} -> raise "with_owner 트랜잭션 실패: #{inspect(reason)}"
    end
  end

  @doc """
  재접속 보정용 잔액 스냅샷 (DoD 3). 금액은 계약대로 문자열.
  RLS + WHERE owner 이중 필터 — 어느 하나가 뚫려도 남의 잔액이 새지 않는다.
  """
  def balance_snapshot(conn, owner_id) do
    with_owner(conn, owner_id, fn c ->
      res =
        Postgrex.query!(
          c,
          """
          SELECT b.account_id::text, b.currency, b.balance_minor::text
            FROM account_balance b
            JOIN account a ON a.id = b.account_id
           WHERE a.owner_id = $1::text::uuid
           ORDER BY b.account_id, b.currency
          """,
          [owner_id]
        )

      Enum.map(res.rows, fn [account_id, currency, balance] ->
        %{"account_id" => account_id, "currency" => currency, "balance_minor" => balance}
      end)
    end)
  end

  @doc """
  한 계정에 걸린 예산의 현재 기간 소진액 (DoD 4 감시용).

  소진액은 **해당 예산 기간·확정 상태·계정 통화**에 한정해 정확히 계산한다:
    · 기간: period_kind 별 date_trunc(월/분기/연) ≤ occurred_on < 다음 기간 시작.
      (LEFT JOIN 의 ON 절에 조건을 두고 t.id IS NULL 을 0 으로 처리 — WHERE 에
       두면 매칭 없는 예산이 통째로 사라지고, ON 밖에 두면 status·기간 필터가
       LEFT JOIN 때문에 무력화된다.)
    · 상태: posted·settled 만 (draft 제외).
    · 통화: 계정 통화와 같은 entry 만 (통화 혼합 합산 금지).
  period_key 도 SQL 에서 만들어 감시자·계약과 형식을 일치시킨다.
  """
  def budget_status(conn, owner_id, account_id) do
    # period_kind('monthly'/'quarterly'/'yearly') → date_trunc unit·interval 매핑.
    # 기간 시작 ≤ occurred_on < 다음 기간 시작 으로 정확히 자른다(CASE 를 JOIN ON
    # 절의 각 budget 행 기준으로 평가 — LEFT JOIN 이라 b 컬럼 참조 가능).
    unit =
      "CASE b.period_kind WHEN 'monthly' THEN 'month' WHEN 'quarterly' THEN 'quarter' ELSE 'year' END"

    step =
      "CASE b.period_kind WHEN 'monthly' THEN interval '1 month' WHEN 'quarterly' THEN interval '3 months' ELSE interval '1 year' END"

    sql = """
    SELECT b.id::text,
           CASE b.period_kind
             WHEN 'monthly' THEN to_char(now(), 'YYYY-MM')
             WHEN 'quarterly' THEN to_char(now(), 'YYYY') || '-Q' ||
                                   to_char(extract(quarter FROM now())::int, 'FM0')
             ELSE to_char(now(), 'YYYY')
           END AS period_key,
           b.limit_minor::text,
           COALESCE(SUM(CASE
             WHEN t.id IS NULL THEN 0
             WHEN e.direction = 'debit' THEN e.amount_minor
             ELSE -e.amount_minor END), 0)::text AS spent
      FROM budget b
      JOIN account acc ON acc.id = b.account_id
      LEFT JOIN entry e ON e.account_id = b.account_id AND e.currency = acc.currency
      LEFT JOIN txn t ON t.id = e.txn_id
                     AND t.status IN ('posted', 'settled')
                     AND t.occurred_on >= date_trunc(#{unit}, now())::date
                     AND t.occurred_on <  (date_trunc(#{unit}, now()) + #{step})::date
     WHERE b.owner_id = $1::text::uuid AND b.account_id = $2::text::uuid
     GROUP BY b.id, b.period_kind, b.limit_minor
    """

    with_owner(conn, owner_id, fn c ->
      res = Postgrex.query!(c, sql, [owner_id, account_id])

      Enum.map(res.rows, fn [id, period_key, limit, spent] ->
        %{
          id: id,
          period_key: period_key,
          limit_minor: String.to_integer(limit),
          spent_minor: String.to_integer(spent)
        }
      end)
    end)
  end

  @doc """
  예산 알림을 멱등하게 발화한다 (DoD 4 — 재시작 견고). INSERT ON CONFLICT
  DO NOTHING 이 1행을 넣으면 이번이 처음이라 true, 이미 있으면 false.
  발화 기록이 DB 에 남으므로 감시자가 재시작해도 같은 (예산, 기간) 알림이
  다시 나가지 않는다.
  """
  def claim_alert(conn, owner_id, budget_id, period_key) do
    with_owner(conn, owner_id, fn c ->
      res =
        Postgrex.query!(
          c,
          """
          INSERT INTO budget_alert_log (owner_id, budget_id, period_key)
          VALUES ($1::text::uuid, $2::text::uuid, $3)
          ON CONFLICT (budget_id, period_key) DO NOTHING
          RETURNING 1
          """,
          [owner_id, budget_id, period_key]
        )

      res.num_rows == 1
    end)
  end
end
