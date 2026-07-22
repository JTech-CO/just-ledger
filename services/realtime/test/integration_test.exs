defmodule Realtime.IntegrationTest do
  @moduledoc """
  DB 통합 — M7 DoD 1·2·3 를 실제 NOTIFY 경로로 측정한다.
  DATABASE_URL 이 있을 때만 돈다(`@tag :db`).

    DoD 1  DB 변경 → 수신 p95 300ms 이내
    DoD 2  동시 100 연결에서 유실 0
    DoD 3  리스너 강제 종료 후 자동 복구
    DoD 5  커넥션 총합이 설정 상한 안
  """
  use ExUnit.Case, async: false
  require Logger

  @moduletag :db
  @channel "ledger_events"

  setup_all do
    opts = Realtime.Repo.conn_opts()
    {:ok, conn} = Postgrex.start_link(opts)
    owner = seed_owner(conn)
    %{conn: conn, owner: owner}
  end

  setup %{conn: conn} do
    # 테스트마다 고유 PubSub 로 격리 — 앱의 것과 섞이지 않게
    pubsub = :"pubsub_#{System.unique_integer([:positive])}"
    start_supervised!({Phoenix.PubSub, name: pubsub})

    # 스크래치 DB 를 향한 독립(익명) 리스너 — 앱의 단일 인스턴스와 충돌하지 않게
    listener =
      start_supervised!(
        {Realtime.Listener,
         [name: nil, channel: @channel, pubsub: pubsub, conn_opts: Realtime.Repo.conn_opts()]},
        id: :"listener_#{System.unique_integer([:positive])}"
      )

    # LISTEN 이 실제로 걸릴 때까지 대기 (건너뛰면 첫 이벤트를 놓친다)
    wait_until(fn -> :sys.get_state(listener).pid != nil end)
    %{pubsub: pubsub, listener: listener, conn: conn}
  end

  defp seed_owner(conn) do
    name = "rt_owner_#{System.unique_integer([:positive])}"

    {:ok, res} =
      Postgrex.query(conn, "INSERT INTO app_user (username) VALUES ($1) RETURNING id::text", [name])

    [[owner]] = res.rows

    for {code, type} <- [{"RT.A", "asset"}, {"RT.B", "expense"}] do
      Postgrex.query!(
        conn,
        "INSERT INTO account (owner_id, code, name, type, currency) VALUES ($1::text::uuid, $2, $2, $3::account_type, 'KRW')",
        [owner, code, type]
      )
    end

    owner
  end

  defp post_txn(conn, owner, amount) do
    {:ok, res} =
      Postgrex.query(
        conn,
        "INSERT INTO txn (owner_id, occurred_on) VALUES ($1::text::uuid, CURRENT_DATE) RETURNING id::text",
        [owner]
      )

    [[txn]] = res.rows

    {:ok, accs} =
      Postgrex.query(
        conn,
        "SELECT id::text, code FROM account WHERE owner_id = $1::text::uuid ORDER BY code",
        [owner]
      )

    [[a, _], [b, _]] = accs.rows

    Postgrex.query!(
      conn,
      "INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency) VALUES ($1::text::uuid,$2::text::uuid,'debit',$3,'KRW'), ($1::text::uuid,$4::text::uuid,'credit',$3,'KRW')",
      [txn, b, amount, a]
    )

    Postgrex.query!(conn, "UPDATE txn SET status='posted', posted_at=now() WHERE id=$1::text::uuid", [txn])
    txn
  end

  defp wait_until(fun, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(fun, deadline)
  end

  defp do_wait(fun, deadline) do
    cond do
      fun.() -> :ok
      System.monotonic_time(:millisecond) > deadline -> flunk("조건 대기 시간 초과")
      true -> Process.sleep(20); do_wait(fun, deadline)
    end
  end

  @tag timeout: 120_000
  test "DoD 1 — DB 변경 → 수신 p95 300ms 이내", %{conn: conn, owner: owner, pubsub: pubsub} do
    Phoenix.PubSub.subscribe(pubsub, Realtime.Listener.topic(owner))
    n = 30

    latencies =
      for i <- 1..n do
        # 이전 이벤트 잔여를 비운다
        flush_events()
        t0 = System.monotonic_time(:microsecond)
        post_txn(conn, owner, 1000 + i)

        receive do
          {:ledger_event, %{"type" => "balance_changed"}} ->
            (System.monotonic_time(:microsecond) - t0) / 1000
        after
          5_000 -> flunk("이벤트 미수신 (#{i}번째)")
        end
      end

    sorted = Enum.sort(latencies)
    p95 = Enum.at(sorted, min(round(0.95 * n) - 1, n - 1))
    p50 = Enum.at(sorted, div(n, 2))
    # 게이트 수치는 로그 레벨과 무관하게 항상 남긴다(PROGRESS 기록 근거)
    IO.puts("\n  [DoD 1] 전파 지연 p50=#{Float.round(p50, 1)}ms p95=#{Float.round(p95, 1)}ms (n=#{n})")
    assert p95 <= 300, "p95 #{p95}ms > 300ms"
  end

  defp flush_events do
    receive do
      {:ledger_event, _} -> flush_events()
    after
      0 -> :ok
    end
  end

  @tag timeout: 180_000
  test "DoD 2 — 동시 100 구독자에서 유실 0", %{conn: conn, owner: owner, pubsub: pubsub} do
    n_subs = 100
    parent = self()
    topic = Realtime.Listener.topic(owner)

    tasks =
      for _ <- 1..n_subs do
        Task.async(fn ->
          Phoenix.PubSub.subscribe(pubsub, topic)
          send(parent, :ready)

          receive do
            {:ledger_event, %{"type" => "balance_changed"}} -> :got
          after
            10_000 -> :missed
          end
        end)
      end

    for _ <- 1..n_subs, do: assert_receive(:ready, 5_000)
    post_txn(conn, owner, 7777)

    results = Task.await_many(tasks, 15_000)
    got = Enum.count(results, &(&1 == :got))
    IO.puts("  [DoD 2] 동시 #{n_subs} 구독자 수신 #{got}/#{n_subs} (유실 #{n_subs - got})")
    assert got == n_subs, "유실 #{n_subs - got}건 (수신 #{got}/#{n_subs})"
  end

  @tag timeout: 120_000
  test "DoD 3 — 알림 커넥션을 죽여도 복구되고 이후 이벤트를 받는다", %{
    conn: conn,
    owner: owner,
    pubsub: pubsub,
    listener: listener
  } do
    Phoenix.PubSub.subscribe(pubsub, Realtime.Listener.topic(owner))

    # 리스너가 물고 있는 Postgrex 알림 커넥션을 강제 종료한다.
    # 리스너는 :DOWN 을 받아 스스로 재연결해야 한다(감독자 재시작에 기대지 않음).
    old = :sys.get_state(listener).pid
    assert is_pid(old) and Process.alive?(old)
    Process.exit(old, :kill)

    wait_until(fn ->
      s = :sys.get_state(listener)
      is_pid(s.pid) and s.pid != old and Process.alive?(s.pid)
    end)

    # 리스너 프로세스 자체는 죽지 않았고, LISTEN 이 다시 걸려 이벤트가 온다
    assert Process.alive?(listener)
    flush_events()
    post_txn(conn, owner, 4242)
    assert_receive {:ledger_event, %{"type" => "balance_changed"}}, 10_000
  end

  test "DoD 5 — 커넥션 사용량이 설정 상한 안", %{conn: conn} do
    pool = Application.get_env(:realtime, :pool_size, 5)

    {:ok, res} =
      Postgrex.query(conn, "SELECT count(*)::int FROM pg_stat_activity WHERE datname = current_database()", [])

    [[active]] = res.rows
    IO.puts("  [DoD 5] 활성 커넥션 #{active} (풀 설정 #{pool} + LISTEN 1)")
    # LISTEN 1 + 조회 풀 + 테스트 커넥션 — 상한(풀+여유)을 넘지 않아야 한다
    assert active <= pool + 20, "활성 커넥션 #{active} 과다 (풀 설정 #{pool})"
  end

  test "봉투 소유자 격리 — 남의 이벤트는 오지 않는다", %{conn: conn, owner: owner, pubsub: pubsub} do
    other = seed_owner(conn)
    Phoenix.PubSub.subscribe(pubsub, Realtime.Listener.topic(owner))

    flush_events()
    post_txn(conn, other, 999)

    refute_receive {:ledger_event, _}, 1_000
  end
end
