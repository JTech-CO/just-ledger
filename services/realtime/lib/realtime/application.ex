defmodule Realtime.Application do
  @moduledoc """
  감독 트리 (M7 DoD 3 — 프로세스 강제 종료 후 자동 복구).

  전략은 `:one_for_one` 이다. 리스너가 죽어도 채널 연결과 PubSub 은 살아 있고,
  리스너만 재시작해 LISTEN 을 다시 건다. 반대로 조회 커넥션이 끊겨도 브리지는
  계속 돈다 — 스냅샷은 부가 기능이므로 이벤트 전달을 막지 않는다.

  커넥션 예산(DoD 5): LISTEN 전용 1 + 조회 풀 `pool_size`(기본 5) = 최대 6.
  web(Fastify) 풀과의 총합이 PostgreSQL `max_connections` 아래가 되도록
  배포 설정에서 함께 관리한다.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Realtime.PubSub},
        RealtimeWeb.Endpoint,
        Realtime.BudgetWatcher
      ] ++ query_conn() ++ [Realtime.Listener]

    Supervisor.start_link(children, strategy: :one_for_one, name: Realtime.Supervisor)
  end

  # 조회 커넥션은 DATABASE_URL 이 있을 때만 띄운다.
  # 없으면 채널·브리지는 그대로 돌고 스냅샷만 비활성된다.
  defp query_conn do
    case Realtime.Repo.pool_opts() do
      nil -> []
      opts -> [{Postgrex, Keyword.put(opts, :name, Realtime.QueryConn)}]
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    RealtimeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
