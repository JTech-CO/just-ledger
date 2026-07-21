// Go 워커 어댑터 (M3 에서 Unix socket + JSON 으로 구현). 지금은 스텁이지만
// 시그니처는 확정본이다 — 워커는 이 계약에 맞춰 붙는다 (HARNESS M2 주의).
//
// RLS 모델(PROGRESS 미결질문 #7): 모든 호출은 ownerId 를 명시로 받는다.
// 워커는 작업 단위로 set_config('app.user_id', ownerId) 를 수행한다 — (a)안 확정.

/** @typedef {import('../../types/contracts.gen.js')} _types */

export class WorkerNotConnectedError extends Error {
  constructor(op) {
    super(`worker 어댑터 미연결 (M3): ${op}`);
    this.statusCode = 503;
  }
}

/**
 * @typedef {Object} WorkerAdapter
 * @property {(p: {ownerId: string, batchId: string}) => Promise<{jobId: string}>} enqueueIngestBatch
 *   암호화 명세서 배치 파싱·draft 생성 잡 큐잉. 진행률은 DB(ingest_batch.state)+NOTIFY 로 전파.
 * @property {(p: {ownerId: string, period: {start: string, end: string}}) => Promise<{jobId: string}>} enqueueSettlement
 *   COBOL 마감 배치 실행 요청 (M5). 결과는 settlement_run 행 + settlement_done NOTIFY.
 * @property {() => Promise<{polledAt: string}>} requestFxPoll
 *   환율 폴링 즉시 1회 트리거 (fx_rate 는 전역 — owner 불필요).
 * @property {() => Promise<{ok: boolean}>} ping
 */

/** @returns {WorkerAdapter} */
export function createWorkerAdapter(_opts = {}) {
  return {
    async enqueueIngestBatch({ ownerId, batchId }) {
      void ownerId; void batchId;
      throw new WorkerNotConnectedError('enqueueIngestBatch');
    },
    async enqueueSettlement({ ownerId, period }) {
      void ownerId; void period;
      throw new WorkerNotConnectedError('enqueueSettlement');
    },
    async requestFxPoll() {
      throw new WorkerNotConnectedError('requestFxPoll');
    },
    async ping() {
      return { ok: false };
    },
  };
}
