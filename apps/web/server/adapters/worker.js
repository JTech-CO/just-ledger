// Go 워커 어댑터 — Unix socket + JSON (백서 §3.3). 프로토콜은 services/worker/queue/socket.go
// 와 1:1: 한 연결 = 한 요청/응답, 개행 종료 JSON.
//
// RLS 모델(미결질문 #7 (a)안 확정): 모든 호출은 ownerId 를 명시로 받고, 워커가 작업
// 단위로 set_config('app.user_id', ownerId) 를 수행한다.
//
// 큐의 진실원천은 DB 상태 기계다 — 어댑터의 nudge 는 '즉시 처리 힌트'일 뿐이라
// 소켓이 없거나 실패해도 워커 스캔이 배치를 집는다. 호출부는 실패를 무시해도 안전하다.

import net from 'node:net';

export class WorkerUnavailableError extends Error {
  constructor(op, cause) {
    super(`worker 소켓 통신 실패 (${op}): ${cause}`);
    this.statusCode = 503;
  }
}

/**
 * 한 요청/응답. 소켓이 없으면(워커 미기동) 즉시 실패한다.
 * @param {string} socketPath
 * @param {object} command
 * @param {number} timeoutMs
 * @returns {Promise<{ok: boolean, error?: string}>}
 */
function sendCommand(socketPath, command, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const conn = net.createConnection(socketPath);
    let buf = '';
    const done = (fn, arg) => {
      conn.destroy();
      fn(arg);
    };
    conn.setTimeout(timeoutMs);
    conn.on('connect', () => conn.write(JSON.stringify(command) + '\n'));
    conn.on('data', (d) => {
      buf += d;
      const nl = buf.indexOf('\n');
      if (nl !== -1) {
        try {
          done(resolve, JSON.parse(buf.slice(0, nl)));
        } catch (e) {
          done(reject, e);
        }
      }
    });
    conn.on('timeout', () => done(reject, new Error('timeout')));
    conn.on('error', (e) => done(reject, e));
  });
}

/**
 * @param {{ socketPath?: string }} [opts]
 */
export function createWorkerAdapter(opts = {}) {
  const socketPath = opts.socketPath ?? process.env.WORKER_SOCKET ?? '/tmp/just-ledger-worker.sock';

  return {
    async enqueueIngestBatch({ ownerId, batchId }) {
      try {
        const r = await sendCommand(socketPath, { op: 'enqueue_ingest', owner_id: ownerId, batch_id: batchId });
        return { ok: r.ok === true };
      } catch (e) {
        throw new WorkerUnavailableError('enqueueIngestBatch', e.message);
      }
    },
    async enqueueSettlement({ ownerId, period }) {
      void ownerId; void period;
      throw new WorkerUnavailableError('enqueueSettlement', '미구현 (M5)');
    },
    async requestFxPoll() {
      try {
        const r = await sendCommand(socketPath, { op: 'poll_fx' });
        return { ok: r.ok === true };
      } catch (e) {
        throw new WorkerUnavailableError('requestFxPoll', e.message);
      }
    },
    async ping() {
      try {
        const r = await sendCommand(socketPath, { op: 'ping' });
        return { ok: r.ok === true };
      } catch {
        return { ok: false };
      }
    },
  };
}
