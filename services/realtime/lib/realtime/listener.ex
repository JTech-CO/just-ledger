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

  @doc "소유자별 PubSub 토픽 — 채널과 리스너가 같은 규칙을 쓴다."
  def topic(owner_id) when is_binary(owner_id), do: "user:" <> owner_id

  @doc """
  봉투 문자열을 파싱해 `{:ok, owner_id, event}` 또는 `{:error, reason}` 을 준다.
  라우팅 결정에 쓰이는 순수 함수라 DB 없이 단위 테스트한다.
  """
  @spec parse_envelope(binary()) :: {:ok, binary(), map()} | {:error, atom()}
  def parse_envelope(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, %{"owner_id" => owner, "event" => %{"type" => _} = event}} when is_binary(owner) ->
        if Regex.match?(@uuid_re, owner) do
          {:ok, owner, event}
        else
          {:error, :bad_owner_id}
        end

      {:ok, _} ->
        {:error, :bad_envelope}

      {:error, _} ->
        {:error, :bad_json}
    end
  end

  @impl true
  def init(opts) do
    # Postgrex.Notifications.start_link 는 호출자와 링크를 만든다. 링크를 그대로
    # 두면 알림 커넥션이 죽을 때 이 리스너도 함께 죽어 감독자 재시작에 의존하게
    # 된다. EXIT 를 메시지로 받아 **스스로** 재연결한다 (DoD 3).
    Process.flag(:trap_exit, true)
    channel = Keyword.get(opts, :channel, Application.get_env(:realtime, :listen_channel))
    pubsub = Keyword.get(opts, :pubsub, Realtime.PubSub)
    conn_opts = Keyword.get(opts, :conn_opts) || Realtime.Repo.conn_opts()

    state = %{channel: channel, pubsub: pubsub, conn_opts: conn_opts, pid: nil, ref: nil}

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
        ref = Postgrex.Notifications.listen!(pid, state.channel)
        Process.monitor(pid)
        Logger.info("Realtime.Listener: LISTEN #{state.channel} 시작")
        %{state | pid: pid, ref: ref}

      {:error, reason} ->
        Logger.error("Realtime.Listener: 연결 실패 #{inspect(reason)} — 1s 후 재시도")
        Process.send_after(self(), :reconnect, 1_000)
        %{state | pid: nil, ref: nil}
    end
  end

  @impl true
  def handle_info({:notification, _pid, _ref, _channel, payload}, state) do
    dispatch(payload, state.pubsub)
    {:noreply, state}
  end

  # 알림 연결이 죽으면 감독자를 기다리지 않고 스스로 복구한다 (DoD 3).
  # trap_exit 때문에 {:EXIT, ...} 로 오고, monitor 때문에 {:DOWN, ...} 로도 온다.
  # 먼저 온 쪽이 pid 를 nil 로 만들므로 나중 것은 아래 패턴에 걸리지 않는다.
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{pid: pid} = state) do
    {:noreply, schedule_reconnect(state, reason)}
  end

  def handle_info({:EXIT, pid, reason}, %{pid: pid} = state) do
    {:noreply, schedule_reconnect(state, reason)}
  end

  # 부모(감독자)로부터의 EXIT — trap_exit 을 켰으므로 직접 종료해야 한다
  def handle_info({:EXIT, _other, reason}, state), do: {:stop, reason, state}

  def handle_info(:reconnect, state), do: {:noreply, connect(state)}
  def handle_info(_other, state), do: {:noreply, state}

  defp schedule_reconnect(state, reason) do
    Logger.warning("Realtime.Listener: 알림 연결 종료 #{inspect(reason)} — 재연결")
    Process.send_after(self(), :reconnect, 200)
    %{state | pid: nil, ref: nil}
  end

  @doc false
  def dispatch(payload, pubsub) do
    case parse_envelope(payload) do
      {:ok, owner, event} ->
        # 소유자 토픽으로만 발행 — 전역 브로드캐스트 폴백은 두지 않는다
        Phoenix.PubSub.broadcast(pubsub, topic(owner), {:ledger_event, event})
        Realtime.BudgetWatcher.observe(owner, event)
        :ok

      {:error, reason} ->
        # 계약 위반 페이로드는 조용히 버리지 않고 남긴다(원인 추적 가능하게).
        # 라우팅 근거가 없으므로 전달하지 않는 것이 유일하게 안전한 처리다.
        Logger.error("Realtime.Listener: 페이로드 폐기 (#{reason})")
        {:error, reason}
    end
  end
end
