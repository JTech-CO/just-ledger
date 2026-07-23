// 데모용 인메모리 API — GitHub Pages UI 데모 전용. `lib/api.js` 와 **같은 export
// 표면**을 가지며 vite --mode demo 에서 별칭으로 교체된다. 프로덕션 번들에는 없다.
//
// 서버·DB 가 없으므로 원장 규칙은 여기서 흉내 낸다. 특히 통화별 차변합=대변합
// (INV-1)은 실제 시스템에서 PostgreSQL 트리거가 커밋 시점에 강제하는 것이고,
// 이 파일의 검사는 **데모에서 UI 반응을 보여주기 위한 모사**일 뿐이다.
// 금액은 전 구간 문자열/BigInt 로만 다룬다 (INV-4).

import { DEMO_ACCOUNTS, buildDemoTxns, computeDemoBalances } from './seed.js';

const DEFAULT_ROWS = 1500;

let accounts = DEMO_ACCOUNTS.map((a) => ({ ...a }));
let txns = buildDemoTxns(DEFAULT_ROWS);
let seq = 0;

export class ApiError extends Error {
  constructor(status, body) {
    super(body?.message ?? `HTTP ${status}`);
    this.status = status;
    this.body = body;
  }
}

/** 데모에는 오리진이 없다 — 호환을 위한 no-op */
export function setApiBase() {}

/** 행 수를 바꿔 다시 시드한다 (가상 스크롤 시연용) */
export function setDemoRowTarget(n) {
  txns = buildDemoTxns(n);
}

/** 현재 데모 행 수 */
export function demoRowCount() {
  return txns.length;
}

const ok = (v) => Promise.resolve(v);

/** 최소단위 양의 정수 문자열인지 (contracts/common.schema.json#positiveMinor 와 동일 규약) */
function isPositiveMinor(s) {
  return typeof s === 'string' && /^[1-9][0-9]{0,17}$/.test(s);
}

/**
 * 범용 호출부 — 실제 api() 와 시그니처를 맞춘다. 데모에서 지원하지 않는 경로는
 * 조용히 성공시키지 않고 명시적으로 거절한다.
 */
export function api(path, opts = {}) {
  const method = opts.method ?? 'GET';
  if (path === '/api/accounts' && method === 'GET') return listAccounts();
  if (path === '/api/accounts' && method === 'POST') return createAccount(opts.body);
  if (path.startsWith('/api/txns') && method === 'GET') return listTxns('');
  if (path === '/api/txns' && method === 'POST') return createTxn(opts.body);
  if (path === '/api/balances') return listBalances();
  if (path.startsWith('/api/balances/period')) return listPeriodTotals('');
  return Promise.reject(new ApiError(501, { message: `데모에서는 지원하지 않는 경로입니다: ${method} ${path}` }));
}

export const listAccounts = () => ok(accounts.map((a) => ({ ...a })));

export function createAccount(body) {
  if (!body?.code || !body?.name || !body?.type || !body?.currency) {
    return Promise.reject(new ApiError(400, { message: '필수 항목(code·name·type·currency)이 빠졌습니다' }));
  }
  if (!/^[A-Z]{3}$/.test(body.currency)) {
    return Promise.reject(new ApiError(400, { message: '통화는 대문자 3자리여야 합니다' }));
  }
  if (accounts.some((a) => a.code === body.code)) {
    return Promise.reject(new ApiError(409, { message: `이미 있는 계정 코드입니다: ${body.code}` }));
  }
  seq += 1;
  const acc = {
    id: `a-demo-${seq}`,
    code: body.code,
    name: body.name,
    type: body.type,
    currency: body.currency,
    parent_id: body.parent_id ?? null,
    is_closed: false,
  };
  accounts = [...accounts, acc];
  return ok({ ...acc });
}

// 데모 서버는 한도를 두지 않고 전량을 돌려준다 — 가상 스크롤을 실제로 태우기 위함
// (실제 API 는 limit 기본 100, 최대 500).
export const listTxns = () => ok(txns);

export function createTxn(body) {
  const entries = Array.isArray(body?.entries) ? body.entries : [];
  if (entries.length < 2) {
    return Promise.reject(new ApiError(400, { message: '분개는 2줄 이상이어야 합니다' }));
  }
  for (const e of entries) {
    if (!isPositiveMinor(e.amount_minor)) {
      return Promise.reject(new ApiError(400, { message: '금액은 최소단위 양의 정수여야 합니다' }));
    }
    if (e.direction !== 'debit' && e.direction !== 'credit') {
      return Promise.reject(new ApiError(400, { message: 'direction 은 debit|credit 만 허용됩니다' }));
    }
    if (!accounts.some((a) => a.id === e.account_id)) {
      return Promise.reject(new ApiError(400, { message: '알 수 없는 계정입니다' }));
    }
  }
  // INV-1 모사: 통화별 차변합 = 대변합
  /** @type {Map<string, bigint>} */
  const diff = new Map();
  for (const e of entries) {
    const cur = diff.get(e.currency) ?? 0n;
    const v = BigInt(e.amount_minor);
    diff.set(e.currency, e.direction === 'debit' ? cur + v : cur - v);
  }
  for (const [currency, v] of diff) {
    if (v !== 0n) {
      return Promise.reject(
        new ApiError(422, { message: `대차가 맞지 않습니다 (${currency}) — 차변 합과 대변 합이 같아야 합니다` }),
      );
    }
  }

  seq += 1;
  const id = `t-demo-${seq}`;
  const txn = {
    id,
    occurred_on: body.occurred_on,
    memo: body.memo ?? '',
    status: body.status ?? 'posted',
    entries: entries.map((e, i) => ({
      id: `${id}-${i}`,
      txn_id: id,
      account_id: e.account_id,
      direction: e.direction,
      amount_minor: e.amount_minor,
      currency: e.currency,
    })),
  };
  txns = [txn, ...txns];
  return ok({ ...txn });
}

export const listBalances = () => ok(computeDemoBalances(txns));

export function listPeriodTotals() {
  /** @type {Map<string, {debit: bigint, credit: bigint}>} */
  const byMonth = new Map();
  for (const t of txns) {
    const key = t.occurred_on.slice(0, 7);
    const cur = byMonth.get(key) ?? { debit: 0n, credit: 0n };
    for (const e of t.entries) {
      const v = BigInt(e.amount_minor);
      if (e.direction === 'debit') cur.debit += v;
      else cur.credit += v;
    }
    byMonth.set(key, cur);
  }
  return ok(
    [...byMonth.entries()]
      .sort((a, b) => (a[0] < b[0] ? 1 : -1))
      .map(([period, v]) => ({
        period,
        currency: 'KRW',
        debit_minor: v.debit.toString(),
        credit_minor: v.credit.toString(),
      })),
  );
}
