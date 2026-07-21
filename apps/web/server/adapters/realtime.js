// Elixir 실시간 브리지 어댑터 (M7). 이벤트 버스 자체는 DB NOTIFY → Phoenix 이므로
// 서버가 이벤트를 '보내는' 경로는 없다. 서버의 역할은 클라이언트 채널 접속 정보 발급뿐.
// 스텁이지만 시그니처 확정본.

/**
 * @typedef {Object} ChannelTicket
 * @property {string} url    WebSocket 엔드포인트 (예: ws://host:4000/socket)
 * @property {string} topic  구독 토픽 (소유자 스코프, 예: ledger:<ownerId>)
 * @property {string} token  단기 서명 토큰 (M7 에서 서명 방식 확정)
 *
 * @typedef {Object} RealtimeAdapter
 * @property {(p: {ownerId: string}) => Promise<ChannelTicket>} issueChannelTicket
 * @property {() => Promise<{ok: boolean}>} ping
 */

export class RealtimeNotConnectedError extends Error {
  constructor(op) {
    super(`realtime 어댑터 미연결 (M7): ${op}`);
    this.statusCode = 503;
  }
}

/** @returns {RealtimeAdapter} */
export function createRealtimeAdapter(_opts = {}) {
  return {
    async issueChannelTicket({ ownerId }) {
      void ownerId;
      throw new RealtimeNotConnectedError('issueChannelTicket');
    },
    async ping() {
      return { ok: false };
    },
  };
}
