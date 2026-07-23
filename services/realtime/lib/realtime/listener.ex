defmodule Realtime.Listener do
  @moduledoc """
  PostgreSQL `LISTEN ledger_events` → Phoenix PubSub 브리지.

  페이로드는 `contracts/notify-envelope.schema.json` 봉투(`{owner_id, event}`)다.
  단일 채널에 모든 소유자의 이벤트가 흐르므로 **owner_id 로 토픽을 좁혀** 해당
  소유자에게만 전달한다. 실시간 경로에는 DB 의 RLS 가 적용되지 않으므로 이
  라우팅이 테넌트 격리의 유일한 근거다 — 봉투가 깨졌거나 owner_id 가 없으면
  브로드캐스트하지 않고 버린다(모두에게 보내는 폴백은 두지 않는다).

  브라우저로 나가는 프레임은 `event` 부분만이다(자기 것만 받으므로 owner_id 를
  되돌려 보내지 않는다). 그 형태의 계약은 `notify-event.schema.json` 이다.

  감독 트리 아래에서 돌며, 연결이 끊기면 재연결한다(DoD 3).
  """
  use GenServer
  require Logger

  @uuid_re ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/

  # name: nil 이면 이름 없이 뜬다 — 통합 테스트가 스크래치 DB 를 향한 독립
  # 리스너를 띄울 수 있어야 하기 때문이다(운영에서는 모듈명 단일 인스턴스).
  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  실제 LISTEN 상태 — 프로세스 생존이 아니라 알림 커넥션이 실제로 붙어 있는지.
  health 체크가 이걸 봐야 브리지가 조용히 끊긴 상태를 감지한다.
  """
  def listening? do
    case Process.whereis(__MODULE__) do
      nil -> false
      pid -> match?(%{pid: p} when is_pid(p), :sys.get_state(pid))
    end
  catch
    _, _ -> false
  end

  # DB 가 발행하는 이벤트 유형(contracts/notify-event.schema.json). budget_alert·
  # sync 는 realtime 내부에서 생성되므로 봉투로 오지 않는다 — 봉투에 그 type 이
  # 오면 위조다. 알려진 유형만 통과시켜 임의 프레임이 채널로 새는 것을 막는다.
  @db_event_types ~w(balance_changed settlement_done ingest_progress)

  @doc "소유자별 PubSub 토픽 — 채널과 리스너가 같은 규칙을 쓴다."
  def topic(owner_id) when is_binary(owner_id), do: "user:" <> owner_id

  @doc """
  봉투 문자열을 파싱해 `{:ok, owner_id, event}` 또는 `{:error, reason}` 을 준다.
  라우팅 결정에 쓰이는 순수 함수라 DB 없이 단위 테스트한다. event.type 이
  DB 발행 유형 화이트리스트에 없으면 거절한다(위조 프레임 차단).
  """
  @spec parse_envelope(binary()) :: {:ok, binary(), map()} | {:error, atom()}
  def parse_envelope(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, %{"owner_id" => owner, "event" => %{"type" => type} = event}} when is_binary(owner) ->
        cond do
          not Regex.match?(@uuid_re, owner) -> {:error, :bad_owner_id}
          type not in @db_event_types -> {:error, :unknown_event_type}
          true -> {:ok, owner, event}
        end

      {:ok, _} ->
        {:error, :bad_envelope}

      {:error, _} ->
        {:error, :bad_json}
    end
  end

  @impl true
  def init(opts) do
    channel = Keyword.get(opts, :channel, Application.get_env(:realtime, :listen_channel))
    pubsub = Keyword.get(opts, :pubsub, Realtime.PubSub)
    conn_opts = Keyword.get(opts, :conn_opts) || Realtime.Repo.conn_opts()

    state = %{
      channel: channel,
      pubsub: pubsub,
      conn_opts: conn_opts,
      pid: nil,
      ref: nil,
      mref: nil,
      reconnected: false
    }

    case conn_opts do
      nil ->
        # DATABASE_URL 미설정 — 브리지 없이 기동(테스트·채널 단독 검증용)
        Logger.warning("Realtime.Listener: DATABASE_URL 미설정 — LISTEN 비활성")
        {:ok, state}

      _ ->
        {:ok, state, {:continue, :connect}}
    end
  end

  @impl true
  def handle_continue(:connect, state), do: {:noreply, connect(state)}

  defp connect(state) do
    case Postgrex.Notifications.start_link(state.conn_opts) do
      {:ok, pid} ->
        # start_link 가 만든 링크를 즉시 끊고 monitor 로만 감시한다. 링크를 두면
        # 알림 커넥션이 죽을 때 EXIT 가 이 리스너를 함께 죽인다(감독자 재시작 의존).
        # unlink + monitor 면 DOWN 하나만 받아 **스스로** 재연결한다 (DoD 3) — 늦은
        # EXIT 로 인한 오종료도 원천 차단된다.
        Process.unlink(pid)
        mref = Process.monitor(pid)
        ref = Postgrex.Notifications.listen!(pid, state.channel)
        Logger.info("Realtime.Listener: LISTEN #{state.channel} 시작")

        # 재연결이면(이전에 pid 가 있었다가 끊긴 경우) 접속 중이던 채널들에
        # 재동기화를 요청한다 — 끊긴 창에서 놓친 NOTIFY 를 현재 상태로 수렴시킨다.
        if state.reconnected, do: request_resync(state.pubsub)
        %{state | pid: pid, ref: ref, mref: mref, reconnected: true}

      {:error, reason} ->
        Logger.error("Realtime.Listener: 연결 실패 #{inspect(reason)} — 1s 후 재시도")
        Process.send_after(self(), :reconnect, 1_000)
        %{state | pid: nil, ref: nil, mref: nil}
    end
  end

  # 재연결 창에서 놓친 이벤트 보정: 접속 중인 모든 채널에 스냅샷 재발행을 알린다.
  # 채널은 자기 소유자의 현재 잔액을 다시 sync 로 밀어 수렴시킨다 (DoD 3).
  defp request_resync(pubsub) do
    Phoenix.PubSub.broadcast(pubsub, "realtime:resync", :resync)
  end

  @impl true
  def handle_info({:notification, _pid, _ref, _channel, payload}, state) do
    dispatch(payload, state.pubsub)
    {:noreply, state}
  end

  # 알림 연결이 죽으면 감독자를 기다리지 않고 스스로 복구한다 (DoD 3).
  # unlink 했으므로 DOWN 만 온다 — EXIT 로 인한 오종료 경로가 없다.
  def handle_info({:DOWN, mref, :process, pid, reason}, %{mref: mref, pid: pid} = state) do
    Logger.warning("Realtime.Listener: 알림 연결 종료 #{inspect(reason)} — 재연결")
    Process.send_after(self(), :reconnect, 200)
    {:noreply, %{state | pid: nil, ref: nil, mref: nil}}
  end

  def handle_info(:reconnect, state), do: {:noreply, connect(state)}
  def handle_info(_other, state), do: {:noreply, state}

  @doc "예산 감시자가 balance_changed 를 받는 내부 토픽 (owner 무관 단일 구독)"
  def watch_topic, do: "budget:watch"

  @doc false
  def dispatch(payload, pubsub) do
    case parse_envelope(payload) do
      {:ok, owner, event} ->
        # 소유자 토픽으로만 발행 — 전역 브로드캐스트 폴백은 두지 않는다.
        Phoenix.PubSub.broadcast(pubsub, topic(owner), {:ledger_event, event})

        # 예산 감시는 같은 pubsub 의 내부 토픽으로 넘긴다. 감시자를 직접 호출하지
        # 않으므로 이 pubsub 을 쓰는 인스턴스에만 닿아 테스트 격리가 유지된다.
        Phoenix.PubSub.broadcast(pubsub, watch_topic(), {:observe, owner, event})
        :ok

      {:error, reason} ->
        # 계약 위반 페이로드는 조용히 버리지 않고 남긴다(원인 추적 가능하게).
        # 라우팅 근거가 없으므로 전달하지 않는 것이 유일하게 안전한 처리다.
        Logger.error("Realtime.Listener: 페이로드 폐기 (#{reason})")
        {:error, reason}
    end
  end
end
