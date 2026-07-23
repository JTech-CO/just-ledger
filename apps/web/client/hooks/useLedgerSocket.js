// 실시간 채널 클라이언트 (M7 realtime 연결). Phoenix WebSocket 프로토콜을
// 최소 구현으로 직접 말한다 — phoenix.js 의존 없이 계약 프레임만 소비한다.
//
// 격리·단일 진입점: 수신한 이벤트는 store.applyRealtime 으로만 병합한다
// (CLAUDE.md — 컴포넌트가 채널을 직접 구독하지 않는다). 채널 토픽은
// ledger:<owner_id>, 서버는 owner_id 일치 소켓만 가입시킨다(테넌트 격리).
//
// 프레임: 서버가 단일 "event" 메시지로 계약 객체(type 포함)를 보낸다
// (contracts/notify-event.schema.json). join 직후·재연결 시 sync 로 스냅샷.

import { useEffect, useRef } from 'react';
import { useLedgerStore } from '../store/ledgerStore.js';

/** Phoenix 채널 메시지 프레임: [join_ref, ref, topic, event, payload] */
function encode(joinRef, ref, topic, event, payload) {
  return JSON.stringify([joinRef, ref, topic, event, payload]);
}

/**
 * @param {object} opts
 * @param {string} opts.url  ws(s):// 소켓 엔드포인트 (예: ws://host/socket/websocket)
 * @param {string} opts.token  web(Fastify)이 발급한 Phoenix.Token
 * @param {string} opts.ownerId
 * @param {boolean} [opts.enabled=true]
 */
export function useLedgerSocket({ url, token, ownerId, enabled = true }) {
  const applyRealtime = useLedgerStore((s) => s.applyRealtime);
  const setConnected = useLedgerStore((s) => s.setSocketConnected);
  const ref = useRef({ ws: null, timer: null, hb: null, refCounter: 0, closed: false });

  useEffect(() => {
    if (!enabled || !url || !token || !ownerId) return undefined;
    const state = ref.current;
    state.closed = false;
    const topic = `ledger:${ownerId}`;

    function connect() {
      if (state.closed) return;
      const wsUrl = `${url}?token=${encodeURIComponent(token)}&vsn=2.0.0`;
      const ws = new WebSocket(wsUrl);
      state.ws = ws;
      const joinRef = String((state.refCounter += 1));

      ws.onopen = () => {
        ws.send(encode(joinRef, String((state.refCounter += 1)), topic, 'phx_join', {}));
        // 하트비트 — Phoenix 는 무응답 소켓을 끊는다
        state.hb = setInterval(() => {
          if (ws.readyState === WebSocket.OPEN) {
            ws.send(encode(null, String((state.refCounter += 1)), 'phoenix', 'heartbeat', {}));
          }
        }, 30_000);
      };

      ws.onmessage = (e) => {
        let frame;
        try {
          frame = JSON.parse(e.data);
        } catch {
          return;
        }
        const [, , msgTopic, event, payload] = frame;
        if (event === 'phx_reply' && msgTopic === topic) {
          // join 성공 응답
          if (payload?.status === 'ok') setConnected(true);
          return;
        }
        // 서버가 보내는 계약 프레임 — 단일 진입점으로만 병합
        if (event === 'event' && msgTopic === topic && payload && payload.type) {
          applyRealtime(payload);
        }
      };

      ws.onclose = () => {
        setConnected(false);
        if (state.hb) clearInterval(state.hb);
        if (!state.closed) {
          // 자동 재연결 — 서버 재시작·네트워크 흔들림에 견딘다.
          // 재연결 후 서버가 sync 를 다시 밀어 현재 상태로 수렴시킨다(M7 DoD 3).
          state.timer = setTimeout(connect, 1_000);
        }
      };

      ws.onerror = () => {
        // onclose 가 이어서 재연결을 처리한다
        try {
          ws.close();
        } catch {
          /* 이미 닫힘 */
        }
      };
    }

    connect();

    return () => {
      state.closed = true;
      if (state.timer) clearTimeout(state.timer);
      if (state.hb) clearInterval(state.hb);
      if (state.ws) {
        try {
          state.ws.close();
        } catch {
          /* 이미 닫힘 */
        }
      }
      setConnected(false);
    };
  }, [url, token, ownerId, enabled, applyRealtime, setConnected]);
}
