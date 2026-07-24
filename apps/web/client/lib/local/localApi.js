// 로컬 앱 API — `lib/api.js` 와 같은 export 표면을 IndexedDB 로 구현한다.
// vite --mode app 에서 별칭으로 api.js 를 대체한다. 데이터가 이 기기에 영속된다.
//
// 검증(복식부기·금액 규율)은 lib/ledgerCore.js 한 곳에서만 한다 — 데모(mockApi)와 공유.
// 서버가 정본이라는 사실은 변하지 않는다: 이 앱은 오프라인 단일 사용자용 재현이다.

import {
  LedgerError,
  validateAccountBody,
  validateTxnBody,
  computeBalances,
  periodTotals,
} from '../ledgerCore.js';
import * as idb from './idb.js';
import { DEMO_ACCOUNTS, buildDemoTxns } from '../demo/seed.js';

export { LedgerError as ApiError };

/** 데모/실서버와 시그니처만 맞춘 no-op */
export function setApiBase() {}

// 안정적인 로컬 ID (crypto.randomUUID 우선, 폴백은 카운터+시각 문자열)
let counter = 0;
function newId(prefix) {
  counter += 1;
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return `${prefix}-${crypto.randomUUID()}`;
  return `${prefix}-${counter}-${Date.now().toString(36)}`;
}

export async function listAccounts() {
  const accounts = await idb.getAll('accounts');
  return accounts.sort((a, b) => (a.code < b.code ? -1 : a.code > b.code ? 1 : 0));
}

export async function createAccount(body) {
  const existing = await idb.getAll('accounts');
  const norm = validateAccountBody(existing, body);
  const acc = { id: newId('a'), ...norm };
  await idb.put('accounts', acc);
  return acc;
}

export async function listTxns() {
  const txns = await idb.getAll('txns');
  // 최신 발생일 우선, 같은 날은 입력 역순(seq 내림차순)
  return txns.sort((a, b) => {
    if (a.occurred_on !== b.occurred_on) return a.occurred_on < b.occurred_on ? 1 : -1;
    return (b._seq ?? 0) - (a._seq ?? 0);
  });
}

export async function createTxn(body) {
  const accounts = await idb.getAll('accounts');
  const norm = validateTxnBody(accounts, body);
  const id = newId('t');
  counter += 1;
  const txn = {
    id,
    _seq: counter,
    occurred_on: norm.occurred_on,
    memo: norm.memo,
    status: norm.status,
    entries: norm.entries.map((e, i) => ({ id: `${id}-${i}`, txn_id: id, ...e })),
  };
  await idb.put('txns', txn);
  return txn;
}

export async function listBalances() {
  const txns = await idb.getAll('txns');
  return computeBalances(txns);
}

export async function listPeriodTotals() {
  const txns = await idb.getAll('txns');
  return periodTotals(txns);
}

/** 범용 호출부 — 실제 api() 와 시그니처를 맞춘다 */
export async function api(path, opts = {}) {
  const method = opts.method ?? 'GET';
  if (path === '/api/accounts' && method === 'GET') return listAccounts();
  if (path === '/api/accounts' && method === 'POST') return createAccount(opts.body);
  if (path.startsWith('/api/txns') && method === 'GET') return listTxns();
  if (path === '/api/txns' && method === 'POST') return createTxn(opts.body);
  if (path === '/api/balances') return listBalances();
  if (path.startsWith('/api/balances/period')) return listPeriodTotals();
  throw new LedgerError(501, `로컬 앱에서 지원하지 않는 경로입니다: ${method} ${path}`);
}

// ── 데이터 관리 (로컬 앱 전용) ──────────────────────────────────────────────

/** 계정·거래가 하나라도 있는지 (첫 실행 안내용) */
export async function isEmpty() {
  const [accounts, txns] = await Promise.all([idb.getAll('accounts'), idb.getAll('txns')]);
  return accounts.length === 0 && txns.length === 0;
}

/** 샘플 계정 + 소량 거래를 채운다(빈 장부에서 둘러보기용) */
export async function seedSample() {
  const accounts = DEMO_ACCOUNTS.map((a) => ({ ...a }));
  const txns = buildDemoTxns(120).map((t, i) => ({ ...t, _seq: i + 1 }));
  await idb.replaceAll({ accounts, txns });
}

/** 전체를 JSON 직렬화 (백업/내보내기). 금액은 문자열 그대로 보존된다. */
export async function exportData() {
  const [accounts, txns] = await Promise.all([idb.getAll('accounts'), idb.getAll('txns')]);
  return JSON.stringify({ app: 'just-ledger-local', version: 1, accounts, txns }, null, 2);
}

/** JSON 을 검증 후 전체 교체 (가져오기). 잘못된 파일은 되돌리지 않고 거절한다. */
export async function importData(text) {
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new LedgerError(400, '가져오기 실패 — JSON 파일이 아닙니다');
  }
  if (parsed?.app !== 'just-ledger-local' || !Array.isArray(parsed.accounts) || !Array.isArray(parsed.txns)) {
    throw new LedgerError(400, '가져오기 실패 — just-ledger 내보내기 파일이 아닙니다');
  }
  // 무결성 재검증: 가져온 거래가 복식부기·금액 규율을 지키는지 다시 확인한다
  for (const t of parsed.txns) {
    validateTxnBody(parsed.accounts, t);
  }
  await idb.replaceAll({ accounts: parsed.accounts, txns: parsed.txns });
}

/** 전체 삭제 (빈 장부로) */
export async function resetData() {
  await idb.clearStores(['accounts', 'txns', 'meta']);
}
