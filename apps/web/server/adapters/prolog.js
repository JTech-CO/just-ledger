// Prolog 추론 서비스 어댑터 (M4 에서 HTTP + JSON 으로 구현). 스텁이지만 시그니처 확정본.
// 분류 결과에는 근거 규칙명(rule_name)이 반드시 동반된다 (M4 DoD 6 — Inspector 표시용).
// 이체 페어 매칭은 금액 '정확 일치'만 — 근사 매칭 금지 (INV-8).

export class PrologNotConnectedError extends Error {
  constructor(op) {
    super(`prolog 어댑터 미연결 (M4): ${op}`);
    this.statusCode = 503;
  }
}

/**
 * @typedef {Object} Classification
 * @property {string} txn_id
 * @property {string} account_id  제안 계정
 * @property {string} rule_name   근거 규칙명 (필수 — 근거 없는 분류는 반환하지 않는다)
 * @property {number} confidence  0..100
 *
 * @typedef {Object} TransferPair
 * @property {string} txn_a       uuid (txn_a < txn_b 정규화)
 * @property {string} txn_b
 * @property {number} confidence  0..100
 * @property {string} matched_by  매칭 규칙명
 *
 * @typedef {Object} PrologAdapter
 * @property {(p: {ownerId: string, txnIds: string[]}) => Promise<Classification[]>} classify
 * @property {(p: {ownerId: string, from: string, to: string}) => Promise<TransferPair[]>} matchTransfers
 * @property {(p: {ownerId: string}) => Promise<Array<{account_id: string, period_kind: string, rule_name: string}>>} detectRecurring
 * @property {() => Promise<{ok: boolean}>} ping
 */

/** @returns {PrologAdapter} */
export function createPrologAdapter(_opts = {}) {
  return {
    async classify({ ownerId, txnIds }) {
      void ownerId; void txnIds;
      throw new PrologNotConnectedError('classify');
    },
    async matchTransfers({ ownerId, from, to }) {
      void ownerId; void from; void to;
      throw new PrologNotConnectedError('matchTransfers');
    },
    async detectRecurring({ ownerId }) {
      void ownerId;
      throw new PrologNotConnectedError('detectRecurring');
    },
    async ping() {
      return { ok: false };
    },
  };
}
