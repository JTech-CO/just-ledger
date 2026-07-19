# services/realtime — Elixir (Phoenix)

WebSocket 채널, PostgreSQL `LISTEN/NOTIFY` 브리지, 예산 임계 감시 GenServer, 알림 감독 트리.

## 소유 범위
`services/realtime/`. M1·M2 게이트만 통과하면 M3~M6 과 병렬 착수 가능.

## 명령
```
cd services/realtime && mix deps.get && MIX_ENV=prod mix compile   # make build-realtime
cd services/realtime && mix format        # make fmt (일부)
cd services/realtime && mix credo          # make lint (일부)
cd services/realtime && mix test           # make test-realtime
```

## 규율
- NOTIFY 페이로드는 `contracts/notify-event.schema.json` 을 준수한다. 브라우저 store 는 이 프레임을 단일 진입점에서 병합한다.
- DB 변경 → 브라우저 수신 p95 300ms 이내. 동시 100 연결에서 메시지 유실 0.
- 프로세스 강제 종료 후 자동 복구, 재접속 시 미수신 이벤트 보정.
- 동일 예산 임계 알림 중복 발송 금지.
- **커넥션 풀 크기를 명시 설정.** Elixir·Fastify 풀 총합이 `max_connections` 를 초과하지 않게 한다.

## 참조
기술 백서 §4.1, §4.2 / 담당 phase: M7.
