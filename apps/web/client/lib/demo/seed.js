// 데모 원장 시드 — GitHub Pages UI 데모 전용. 프로덕션 번들에는 포함되지 않는다
// (vite --mode demo 에서만 별칭으로 끼워진다).
//
// 금액은 전 구간 BigInt/문자열로만 만든다 (INV-4). 난수 대신 인덱스 기반 결정론적
// 변주를 쓴다 — 새로고침해도 같은 원장이 나와야 데모가 설명 가능하다.

const CUR = 'KRW';

/** 데모 계정 — 실제 계정 스키마(account.schema.json)와 같은 형태 */
export const DEMO_ACCOUNTS = [
  { id: 'a-cash', code: '1000', name: '현금', type: 'asset', currency: CUR, parent_id: null, is_closed: false },
  { id: 'a-bank', code: '1100', name: '은행 주거래', type: 'asset', currency: CUR, parent_id: null, is_closed: false },
  { id: 'a-card', code: '2000', name: '신용카드', type: 'liability', currency: CUR, parent_id: null, is_closed: false },
  { id: 'a-salary', code: '4000', name: '급여', type: 'income', currency: CUR, parent_id: null, is_closed: false },
  { id: 'a-food', code: '5000', name: '식비', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'a-home', code: '5100', name: '주거', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'a-trans', code: '5200', name: '교통', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'a-telecom', code: '5300', name: '통신', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'a-subs', code: '5400', name: '구독', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'a-health', code: '5500', name: '의료', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'a-fun', code: '5600', name: '여가', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
];

// 월별 반복 거래 패턴. base 는 최소단위(원) 정수 문자열, step 은 인덱스 변주 폭.
// dr = 차변 계정, cr = 대변 계정.
const MONTHLY = [
  { day: 25, memo: '급여', dr: 'a-bank', cr: 'a-salary', base: 3250000n, step: 0n },
  { day: 1, memo: '월세', dr: 'a-home', cr: 'a-bank', base: 780000n, step: 0n },
  { day: 17, memo: '통신요금', dr: 'a-telecom', cr: 'a-card', base: 46900n, step: 0n },
  { day: 3, memo: '스트리밍 구독', dr: 'a-subs', cr: 'a-card', base: 13500n, step: 0n },
  { day: 8, memo: '음악 구독', dr: 'a-subs', cr: 'a-card', base: 10900n, step: 0n },
  { day: 22, memo: '클라우드 저장소', dr: 'a-subs', cr: 'a-card', base: 2900n, step: 0n },
  { day: 15, memo: '카드대금 결제', dr: 'a-card', cr: 'a-bank', base: 415000n, step: 12000n },
  { day: 11, memo: '약국', dr: 'a-health', cr: 'a-card', base: 12800n, step: 900n },
  { day: 27, memo: '영화', dr: 'a-fun', cr: 'a-card', base: 15000n, step: 1500n },
];

// 잦은 소액 지출 — 한 달에 여러 번. day 목록으로 펼친다.
const FREQUENT = [
  { days: [2, 5, 7, 9, 12, 14, 16, 19, 21, 23, 26, 28], memo: '식료품·외식', dr: 'a-food', cr: 'a-card', base: 9800n, step: 1700n },
  { days: [4, 6, 10, 13, 18, 20, 24, 29], memo: '대중교통', dr: 'a-trans', cr: 'a-cash', base: 1450n, step: 320n },
];

const pad2 = (n) => (n < 10 ? '0' + n : String(n));

/**
 * 인덱스 기반 결정론적 변주 (금액은 BigInt 만 경유).
 * @param {bigint} base @param {bigint} step @param {number} i
 * @returns {string} 최소단위 정수 문자열
 */
function vary(base, step, i) {
  const k = BigInt(i);
  const amt = base + ((k * 7919n) % 23n) * step;
  return amt.toString();
}

/**
 * @param {string} id @param {string} occurredOn @param {string} memo
 * @param {string} drAcc @param {string} crAcc @param {string} minor
 */
function makeTxn(id, occurredOn, memo, drAcc, crAcc, minor) {
  return {
    id,
    occurred_on: occurredOn,
    memo,
    status: 'posted',
    entries: [
      { id: id + '-d', txn_id: id, account_id: drAcc, direction: 'debit', amount_minor: minor, currency: CUR },
      { id: id + '-c', txn_id: id, account_id: crAcc, direction: 'credit', amount_minor: minor, currency: CUR },
    ],
  };
}

/**
 * 결정론적 데모 거래 생성. 최신순(내림차순)으로 반환한다.
 * @param {number} targetRows 목표 행 수 — 필요한 만큼 과거로 거슬러 올라간다
 * @returns {Array<Object>}
 */
export function buildDemoTxns(targetRows = 1500) {
  const perMonth = MONTHLY.length + FREQUENT.reduce((n, f) => n + f.days.length, 0);
  const months = Math.max(1, Math.ceil(targetRows / perMonth));
  const txns = [];
  let seq = 0;

  // 2026-07 에서 과거로 months 개월. (데모 기준일 고정 — 결정론)
  let y = 2026;
  let m = 7;
  for (let mi = 0; mi < months; mi += 1) {
    const ym = `${y}-${pad2(m)}`;
    for (const p of MONTHLY) {
      seq += 1;
      txns.push(makeTxn(`t-${seq}`, `${ym}-${pad2(p.day)}`, p.memo, p.dr, p.cr, vary(p.base, p.step, seq)));
    }
    for (const f of FREQUENT) {
      for (const d of f.days) {
        seq += 1;
        txns.push(makeTxn(`t-${seq}`, `${ym}-${pad2(d)}`, f.memo, f.dr, f.cr, vary(f.base, f.step, seq)));
      }
    }
    m -= 1;
    if (m === 0) {
      m = 12;
      y -= 1;
    }
  }

  txns.sort((a, b) => (a.occurred_on < b.occurred_on ? 1 : a.occurred_on > b.occurred_on ? -1 : 0));
  return txns.slice(0, targetRows);
}

/**
 * 거래에서 계정별 순잔액을 계산한다 (차변 − 대변, 전 과정 BigInt).
 * 실제 시스템의 fn_all_balances 와 같은 부호 규약.
 * @param {Array<Object>} txns
 * @returns {Array<{account_id: string, currency: string, balance_minor: string}>}
 */
export function computeDemoBalances(txns) {
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
