// 데모용 인메모리 API — GitHub Pages 체험 데모 전용. `lib/api.js` 와 **같은 export
// 표면**을 가지며 vite --mode demo 에서 별칭으로 교체된다. 프로덕션 번들에는 없다.
//
// 원장 규칙(복식부기·금액 규율)은 lib/ledgerCore.js 한 곳에서만 검증한다 — 로컬 앱과
// 공유(두 벌이면 갈라진다). 서버(PostgreSQL 트리거 등)가 정본이라는 사실은 변하지 않는다.
// 금액은 전 구간 문자열/BigInt (INV-4). 데모 데이터는 인메모리라 새로고침 시 초기화된다.

import {
  LedgerError,
  validateAccountBody,
  validateTxnBody,
  computeBalances,
  periodTotals,
} from '../ledgerCore.js';
import { PROFILES } from './seed.js';

export { LedgerError as ApiError };

let profile = 'household';
let accounts = PROFILES.household.accounts.map((a) => ({ ...a }));
let txns = PROFILES.household.build(PROFILES.household.defaultRows);
let seq = 0;

/** 데모에는 오리진이 없다 — 호환을 위한 no-op */
export function setApiBase() {}

/** 데모 프로파일 전환 — 계정·거래를 통째로 갈아끼운다(가계 ↔ 회사). */
export function setDemoProfile(name) {
  const p = PROFILES[name] ?? PROFILES.household;
  profile = PROFILES[name] ? name : 'household';
  accounts = p.accounts.map((a) => ({ ...a }));
  txns = p.build(p.defaultRows);
}

/** 현재 프로파일 이름 */
export function demoProfile() {
  return profile;
}

const ok = (v) => Promise.resolve(v);

export const listAccounts = () => ok(accounts.map((a) => ({ ...a })));

export function createAccount(body) {
  try {
    const norm = validateAccountBody(accounts, body);
    seq += 1;
    const acc = { id: `a-demo-${seq}`, ...norm };
    accounts = [...accounts, acc];
    return ok({ ...acc });
  } catch (e) {
    return Promise.reject(e);
  }
}

// 데모 서버는 한도를 두지 않고 전량을 돌려준다 — 가상 스크롤을 실제로 태우기 위함
// (실제 API 는 limit 기본 100, 최대 500).
export const listTxns = () => ok(txns);

export function createTxn(body) {
  try {
    const norm = validateTxnBody(accounts, body);
    seq += 1;
    const id = `t-demo-${seq}`;
    const txn = {
      id,
      occurred_on: norm.occurred_on,
      memo: norm.memo,
      status: norm.status,
      entries: norm.entries.map((e, i) => ({ id: `${id}-${i}`, txn_id: id, ...e })),
    };
    txns = [txn, ...txns];
    return ok({ ...txn });
  } catch (e) {
    return Promise.reject(e);
  }
}

export const listBalances = () => ok(computeBalances(txns));

export const listPeriodTotals = () => ok(periodTotals(txns));

/** 범용 호출부 — 실제 api() 와 시그니처를 맞춘다 */
export function api(path, opts = {}) {
  const method = opts.method ?? 'GET';
  if (path === '/api/accounts' && method === 'GET') return listAccounts();
  if (path === '/api/accounts' && method === 'POST') return createAccount(opts.body);
  if (path.startsWith('/api/txns') && method === 'GET') return listTxns('');
  if (path === '/api/txns' && method === 'POST') return createTxn(opts.body);
  if (path === '/api/balances') return listBalances();
  if (path.startsWith('/api/balances/period')) return listPeriodTotals('');
  return Promise.reject(new LedgerError(501, `데모에서는 지원하지 않는 경로입니다: ${method} ${path}`));
}
