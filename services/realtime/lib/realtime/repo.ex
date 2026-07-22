defmodule Realtime.Repo do
  @moduledoc """
  Postgrex 연결 설정과 스냅샷 조회.

  Ecto 를 쓰지 않는다 — 이 서비스가 필요한 것은 LISTEN 커넥션 1개와 재접속
  보정용 잔액 스냅샷 조회뿐이다. 원장 읽기/쓰기는 web(Fastify)이 담당한다.

  커넥션 풀 규율(DoD 5): 풀 크기를 config 에 명시하고, LISTEN 은 풀 밖의
  전용 커넥션 1개를 쓴다. 총합은 `PostgreSQL max_connections` 아래로 관리한다.
  """
  require Logger

  @doc "DATABASE_URL → Postgrex 옵션. 미설정이면 nil."
  def conn_opts do
    case System.get_env("DATABASE_URL") || Application.get_env(:realtime, :database_url) do
      nil -> nil
      url -> parse_url(url)
    end
  end

  @doc "풀을 쓰는 조회용 옵션 (pool_size 명시)"
  def pool_opts do
    case conn_opts() do
      nil -> nil
      opts -> Keyword.merge(opts, pool_size: Application.get_env(:realtime, :pool_size, 5))
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
  재접속 보정용 잔액 스냅샷 (DoD 3).

  채널 join 시점의 현재 잔액 전체를 돌려준다. 이벤트 로그를 재생하는 대신
  현재 상태를 한 번 밀어 넣는 방식이라, 연결이 끊긴 동안 놓친 변경이 무엇이든
  결과적으로 일치하게 된다(수렴). 금액은 계약대로 **문자열**로 넘긴다.

  RLS 는 이 커넥션의 세션 GUC 로 강제한다 — owner 를 SQL 파라미터로만 넘기고
  문자열로 이어 붙이지 않는다.
  """
  def balance_snapshot(conn, owner_id) do
    with {:ok, _} <- Postgrex.query(conn, "SELECT set_config('app.user_id', $1, true)", [owner_id]),
         {:ok, res} <-
           Postgrex.query(
             conn,
             # $1::text::uuid — Postgrex 는 $1::uuid 를 uuid 파라미터로 추론해
             # 16바이트 바이너리를 요구한다. text 로 받아 서버에서 캐스트한다.
             """
             SELECT b.account_id::text, b.currency, b.balance_minor::text
               FROM account_balance b
               JOIN account a ON a.id = b.account_id
              WHERE a.owner_id = $1::text::uuid
              ORDER BY b.account_id, b.currency
             """,
             [owner_id]
           ) do
      rows =
        Enum.map(res.rows, fn [account_id, currency, balance] ->
          %{"account_id" => account_id, "currency" => currency, "balance_minor" => balance}
        end)

      {:ok, rows}
    end
  end
end
