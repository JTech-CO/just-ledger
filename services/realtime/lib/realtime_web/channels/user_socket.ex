defmodule RealtimeWeb.UserSocket do
  @moduledoc """
  WebSocket 진입점. 연결 시 토큰을 검증해 `owner_id` 를 확정한다.

  토큰은 web(Fastify)이 발급한 `Phoenix.Token` 서명값이다 — 두 서비스가 같은
  `secret_key_base` 를 공유한다. 서명이 없거나 만료면 연결 자체를 거절한다:
  실시간 경로에는 RLS 가 없으므로 여기서 신원을 확정하지 못하면 이후 어떤
  격리도 근거가 없다.
  """
  use Phoenix.Socket
  require Logger

  # 토큰 유효기간(초) — 재연결 시 갱신 토큰을 다시 받는다
  @max_age 86_400

  channel("ledger:*", RealtimeWeb.LedgerChannel)

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(socket, "user socket", token, max_age: @max_age) do
      {:ok, owner_id} when is_binary(owner_id) ->
        {:ok, assign(socket, :owner_id, owner_id)}

      {:error, reason} ->
        Logger.info("UserSocket: 토큰 거절 (#{inspect(reason)})")
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:" <> (socket.assigns[:owner_id] || "anon")
end
