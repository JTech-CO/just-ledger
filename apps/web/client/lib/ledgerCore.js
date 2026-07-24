// 클라이언트 측 원장 규칙 — 데모(인메모리)와 로컬 앱(IndexedDB)이 **공유**한다.
// 서버가 없는 두 모드에서 복식부기(차변합=대변합)·금액 규율을 흉내 내기 위한 것이며,
// 정본은 어디까지나 서버 계층(PostgreSQL 트리거·COBOL·Prolog)이다. 이 파일은 그
// 정본을 대체하지 않고, 오프라인에서 같은 규칙을 한 곳에서만 재현한다(두 벌이면 갈라진다).
//
// 금액은 전 구간 BigInt/문자열로만 다룬다 (INV-4). Number/parseFloat/toFixed 미사용.

export class LedgerError extends Error {
  /** @param {number} status @param {string} message */
  constructor(status, message) {
    super(message);
    this.name = 'LedgerError';
    this.status = status;
  }
}

/** 최소단위 양의 정수 문자열인지 (contracts/common.schema.json#positiveMinor 규약) */
export function isPositiveMinor(s) {
  return typeof s === 'string' && /^[1-9][0-9]{0,17}$/.test(s);
}

const ACCOUNT_TYPES = new Set(['asset', 'liability', 'equity', 'income', 'expense']);

/**
 * 계정 생성 입력 검증 → 정규화된 계정(라이터가 id 를 채운다).
 * @param {Array<{code:string}>} existing
 * @param {any} body
 * @returns {{code:string,name:string,type:string,currency:string,parent_id:string|null,is_closed:boolean}}
 */
export function validateAccountBody(existing, body) {
  if (!body?.code || !body?.name || !body?.type || !body?.currency) {
    throw new LedgerError(400, '필수 항목(code·name·type·currency)이 빠졌습니다');
  }
  if (!ACCOUNT_TYPES.has(body.type)) {
    throw new LedgerError(400, 'type 은 asset|liability|equity|income|expense 만 허용됩니다');
  }
  if (!/^[A-Z]{3}$/.test(body.currency)) {
    throw new LedgerError(400, '통화는 대문자 3자리여야 합니다 (예: KRW)');
  }
  if (existing.some((a) => a.code === body.code)) {
    throw new LedgerError(409, `이미 있는 계정 코드입니다: ${body.code}`);
  }
  return {
    code: body.code,
    name: body.name,
    type: body.type,
    currency: body.currency,
    parent_id: body.parent_id ?? null,
    is_closed: false,
  };
}

/**
 * 거래 생성 입력 검증 → 정규화된 분개. 통화별 차변합=대변합(INV-1)을 강제한다.
 * @param {Array<{id:string}>} accounts
 * @param {any} body
 * @returns {{occurred_on:string,memo:string,status:string,entries:Array<object>}}
 */
export function validateTxnBody(accounts, body) {
  const entries = Array.isArray(body?.entries) ? body.entries : [];
  if (entries.length < 2) {
    throw new LedgerError(400, '분개는 2줄 이상이어야 합니다 (복식부기)');
  }
  if (!body.occurred_on || !/^\d{4}-\d{2}-\d{2}$/.test(body.occurred_on)) {
    throw new LedgerError(400, '날짜(occurred_on)는 YYYY-MM-DD 형식이어야 합니다');
  }
  const known = new Set(accounts.map((a) => a.id));
  for (const e of entries) {
    if (!isPositiveMinor(e.amount_minor)) {
      throw new LedgerError(400, '금액은 최소단위 양의 정수 문자열이어야 합니다 (부호는 차/대변으로)');
    }
    if (e.direction !== 'debit' && e.direction !== 'credit') {
      throw new LedgerError(400, 'direction 은 debit|credit 만 허용됩니다');
    }
    if (!known.has(e.account_id)) {
      throw new LedgerError(400, '알 수 없는 계정이 분개에 있습니다');
    }
    if (!/^[A-Z]{3}$/.test(e.currency ?? '')) {
      throw new LedgerError(400, '분개 통화는 대문자 3자리여야 합니다');
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
      throw new LedgerError(422, `대차가 맞지 않습니다 (${currency}) — 차변 합과 대변 합이 같아야 합니다`);
    }
  }
  return {
    occurred_on: body.occurred_on,
    memo: body.memo ?? '',
    status: body.status ?? 'posted',
    entries: entries.map((e) => ({
      account_id: e.account_id,
      direction: e.direction,
      amount_minor: e.amount_minor,
      currency: e.currency,
    })),
  };
}

/**
 * 계정별 순잔액 (차변 − 대변, 전 과정 BigInt). 서버 fn_all_balances 와 같은 부호 규약.
 * @param {Array<{entries:Array<{account_id:string,direction:string,amount_minor:string,currency:string}>}>} txns
 * @returns {Array<{account_id:string, currency:string, balance_minor:string}>}
 */
export function computeBalances(txns) {
  /** @type {Map<string, bigint>} */
  const net = new Map();
  for (const t of txns) {
    for (const e of t.entries) {
      const key = `${e.account_id}:${e.currency}`;
      const cur = net.get(key) ?? 0n;
      const v = BigInt(e.amount_minor);
      net.set(key, e.direction === 'debit' ? cur + v : cur - v);
    }
  }
  return [...net.entries()].map(([key, v]) => {
    const idx = key.lastIndexOf(':');
    return { account_id: key.slice(0, idx), currency: key.slice(idx + 1), balance_minor: v.toString() };
  });
}

/**
 * 월별 차변·대변 합계 (최신월 우선). 금액 문자열.
 * @param {Array<{occurred_on:string, entries:Array<object>}>} txns
 */
export function periodTotals(txns) {
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
  return [...byMonth.entries()]
    .sort((a, b) => (a[0] < b[0] ? 1 : -1))
    .map(([period, v]) => ({
      period,
      currency: 'KRW',
      debit_minor: v.debit.toString(),
      credit_minor: v.credit.toString(),
    }));
}
