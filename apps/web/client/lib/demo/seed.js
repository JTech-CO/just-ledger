// 데모 원장 시드 — GitHub Pages 데모 전용(프로덕션 번들에는 없다).
//
// 두 프로파일:
//   · household(가계)   — 몇 년치 개인 가계부, 기본 1,500건.
//   · company(중소기업) — 십수 년치 회사 장부, 기본 100,000건.
// 회사 프로파일은 span(개월 수)을 고정하고 월별 밀도를 높여 100,000건을 넣어도
// 연도가 과거로 폭주하지 않게 한다(가계 패턴을 그대로 늘리면 1700년대까지 간다).
//
// 금액은 전 구간 BigInt/문자열로만 만든다 (INV-4). 난수 대신 인덱스 기반 결정론적
// 변주를 쓴다 — 새로고침해도 같은 원장이 나와야 데모가 설명 가능하다.
// 기준월은 2026-07 고정(Date.now 미사용 — 결정론).

const CUR = 'KRW';
const ANCHOR_Y = 2026;
const ANCHOR_M = 7;

const pad2 = (n) => (n < 10 ? '0' + n : String(n));

/** 결정론적 변주 (금액은 BigInt 만 경유). base + (idx*소수 % 37)*step */
function vary(base, step, idx) {
  return (base + ((BigInt(idx) * 7919n) % 37n) * step).toString();
}

function mkTxn(id, occurredOn, memo, drAcc, crAcc, minor) {
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

/** 해당 월의 영업일(월~금) 목록. Date.UTC(명시 인자) — 결정론적. */
function businessDays(y, m) {
  const days = [];
  const dim = new Date(Date.UTC(y, m, 0)).getUTCDate();
  for (let d = 1; d <= dim; d += 1) {
    const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
    if (dow !== 0 && dow !== 6) days.push(d);
  }
  return days;
}

/**
 * 공통 생성 엔진. 월별 고정 항목 + 영업일에 분산되는 일별 항목으로 채운다.
 * span(months)을 고정하고 월별 목표량으로 밀도를 조절해 연도 폭주를 막는다.
 * @param {{monthlyFixed:Array, dailyPool:Array, months:number, targetRows:number}} spec
 */
function buildLedger({ monthlyFixed, dailyPool, months, targetRows }) {
  const fixedPerMonth = monthlyFixed.length; // 최댓값(everyMonths 로 실제는 더 적을 수 있음)
  const perMonth = Math.max(fixedPerMonth, Math.ceil(targetRows / months));
  const out = [];
  let seq = 0;
  let y = ANCHOR_Y;
  let m = ANCHOR_M;

  for (let mi = 0; mi < months && out.length < targetRows; mi += 1) {
    const ym = `${y}-${pad2(m)}`;
    let inMonth = 0;

    for (const f of monthlyFixed) {
      if (out.length >= targetRows) break;
      // 분기·연 단위 항목(everyMonths)은 해당 주기에만
      if (f.everyMonths && mi % f.everyMonths !== (f.offset ?? 0)) continue;
      seq += 1;
      inMonth += 1;
      out.push(mkTxn(`t-${seq}`, `${ym}-${pad2(f.day)}`, f.memo, f.dr, f.cr, vary(f.base, f.step, seq)));
    }

    const bdays = businessDays(y, m);
    const dailyThisMonth = Math.max(0, perMonth - inMonth);
    for (let i = 0; i < dailyThisMonth && out.length < targetRows; i += 1) {
      const pat = dailyPool[i % dailyPool.length];
      const day = bdays[i % bdays.length];
      seq += 1;
      out.push(mkTxn(`t-${seq}`, `${ym}-${pad2(day)}`, pat.memo, pat.dr, pat.cr, vary(pat.base, pat.step, seq)));
    }

    m -= 1;
    if (m === 0) {
      m = 12;
      y -= 1;
    }
  }

  // 최신 발생일 우선
  out.sort((a, b) => (a.occurred_on < b.occurred_on ? 1 : a.occurred_on > b.occurred_on ? -1 : b.id < a.id ? -1 : 1));
  return out.slice(0, targetRows);
}

// ── 가계(household) 프로파일 ────────────────────────────────────────────────

export const HOUSEHOLD_ACCOUNTS = [
  { id: 'h-cash', code: '1000', name: '현금', type: 'asset', currency: CUR, parent_id: null, is_closed: false },
  { id: 'h-bank', code: '1100', name: '은행 주거래', type: 'asset', currency: CUR, parent_id: null, is_closed: false },
  { id: 'h-card', code: '2000', name: '신용카드', type: 'liability', currency: CUR, parent_id: null, is_closed: false },
  { id: 'h-salary', code: '4000', name: '급여', type: 'income', currency: CUR, parent_id: null, is_closed: false },
  { id: 'h-food', code: '5000', name: '식비', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'h-home', code: '5100', name: '주거', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'h-trans', code: '5200', name: '교통', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'h-tel', code: '5300', name: '통신', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'h-subs', code: '5400', name: '구독', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'h-med', code: '5500', name: '의료', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'h-fun', code: '5600', name: '여가', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'h-cloth', code: '5700', name: '의류', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'h-life', code: '5800', name: '생활용품', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
];

const HOUSEHOLD_MONTHLY = [
  { day: 25, memo: '급여', dr: 'h-bank', cr: 'h-salary', base: 3250000n, step: 0n },
  { day: 1, memo: '월세', dr: 'h-home', cr: 'h-bank', base: 780000n, step: 0n },
  { day: 1, memo: '관리비', dr: 'h-home', cr: 'h-bank', base: 145000n, step: 8000n },
  { day: 15, memo: '카드대금 결제', dr: 'h-card', cr: 'h-bank', base: 620000n, step: 35000n },
  { day: 17, memo: '통신요금', dr: 'h-tel', cr: 'h-card', base: 46900n, step: 0n },
  { day: 3, memo: '영상 구독', dr: 'h-subs', cr: 'h-card', base: 13500n, step: 0n },
  { day: 8, memo: '음악 구독', dr: 'h-subs', cr: 'h-card', base: 10900n, step: 0n },
  { day: 22, memo: '클라우드 저장소', dr: 'h-subs', cr: 'h-card', base: 2900n, step: 0n },
  { day: 14, memo: '실손보험', dr: 'h-med', cr: 'h-bank', base: 38000n, step: 0n },
];

const HOUSEHOLD_DAILY = [
  { memo: '식료품', dr: 'h-food', cr: 'h-card', base: 23800n, step: 4200n },
  { memo: '외식', dr: 'h-food', cr: 'h-card', base: 15400n, step: 6300n },
  { memo: '카페', dr: 'h-food', cr: 'h-card', base: 4800n, step: 900n },
  { memo: '편의점', dr: 'h-food', cr: 'h-cash', base: 6300n, step: 1400n },
  { memo: '대중교통', dr: 'h-trans', cr: 'h-cash', base: 1450n, step: 320n },
  { memo: '택시', dr: 'h-trans', cr: 'h-card', base: 8900n, step: 2100n },
  { memo: '주유', dr: 'h-trans', cr: 'h-card', base: 62000n, step: 8000n },
  { memo: '약국', dr: 'h-med', cr: 'h-card', base: 12800n, step: 900n },
  { memo: '영화', dr: 'h-fun', cr: 'h-card', base: 15000n, step: 1500n },
  { memo: '서점', dr: 'h-fun', cr: 'h-card', base: 18500n, step: 3400n },
  { memo: '의류', dr: 'h-cloth', cr: 'h-card', base: 47000n, step: 12000n },
  { memo: '생활용품', dr: 'h-life', cr: 'h-card', base: 16200n, step: 3100n },
];

/** 가계 원장 — 기본 1,500건(약 3년치). */
export function buildHousehold(targetRows = 1500) {
  return buildLedger({
    monthlyFixed: HOUSEHOLD_MONTHLY,
    dailyPool: HOUSEHOLD_DAILY,
    months: 40,
    targetRows,
  });
}

// ── 회사(company, 중소기업) 프로파일 ────────────────────────────────────────

export const COMPANY_ACCOUNTS = [
  { id: 'c-cash', code: '1010', name: '현금', type: 'asset', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-bank', code: '1020', name: '보통예금', type: 'asset', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-ar', code: '1080', name: '외상매출금', type: 'asset', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-equip', code: '1500', name: '비품', type: 'asset', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-ap', code: '2010', name: '외상매입금', type: 'liability', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-loan', code: '2600', name: '단기차입금', type: 'liability', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-sales', code: '4010', name: '상품매출', type: 'income', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-service', code: '4020', name: '용역매출', type: 'income', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-cogs', code: '5010', name: '상품매입', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-salary', code: '5110', name: '급여', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-welfare', code: '5120', name: '복리후생비', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-rent', code: '5210', name: '임차료', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-util', code: '5220', name: '수도광열비', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-tel', code: '5230', name: '통신비', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-office', code: '5240', name: '사무용품비', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-supply', code: '5250', name: '소모품비', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-ent', code: '5260', name: '접대비', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-ad', code: '5270', name: '광고선전비', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-travel', code: '5280', name: '여비교통비', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-fee', code: '5290', name: '지급수수료', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-tax', code: '5300', name: '세금과공과', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-insurance', code: '5310', name: '보험료', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-depr', code: '5320', name: '감가상각비', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-interest', code: '5330', name: '이자비용', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
  { id: 'c-car', code: '5340', name: '차량유지비', type: 'expense', currency: CUR, parent_id: null, is_closed: false },
];

const COMPANY_MONTHLY = [
  // 급여 — 직원 8명(대표 포함), 각기 다른 금액
  { day: 25, memo: '급여지급 · 대표', dr: 'c-salary', cr: 'c-bank', base: 5500000n, step: 0n },
  { day: 25, memo: '급여지급 · 부장', dr: 'c-salary', cr: 'c-bank', base: 4200000n, step: 0n },
  { day: 25, memo: '급여지급 · 과장', dr: 'c-salary', cr: 'c-bank', base: 3800000n, step: 0n },
  { day: 25, memo: '급여지급 · 대리', dr: 'c-salary', cr: 'c-bank', base: 3500000n, step: 0n },
  { day: 25, memo: '급여지급 · 사원A', dr: 'c-salary', cr: 'c-bank', base: 3000000n, step: 0n },
  { day: 25, memo: '급여지급 · 사원B', dr: 'c-salary', cr: 'c-bank', base: 2800000n, step: 0n },
  { day: 25, memo: '급여지급 · 사원C', dr: 'c-salary', cr: 'c-bank', base: 2600000n, step: 0n },
  { day: 25, memo: '급여지급 · 인턴', dr: 'c-salary', cr: 'c-bank', base: 2100000n, step: 0n },
  { day: 10, memo: '4대보험', dr: 'c-welfare', cr: 'c-bank', base: 2850000n, step: 40000n },
  { day: 5, memo: '사무실 임차료', dr: 'c-rent', cr: 'c-bank', base: 3200000n, step: 0n },
  { day: 16, memo: '수도광열비', dr: 'c-util', cr: 'c-bank', base: 480000n, step: 60000n },
  { day: 17, memo: '통신·인터넷', dr: 'c-tel', cr: 'c-bank', base: 264000n, step: 12000n },
  { day: 20, memo: '단체보험료', dr: 'c-insurance', cr: 'c-bank', base: 340000n, step: 0n },
  { day: 28, memo: '광고선전비', dr: 'c-ad', cr: 'c-bank', base: 1500000n, step: 250000n },
  { day: 26, memo: '차입금 이자', dr: 'c-interest', cr: 'c-bank', base: 375000n, step: 15000n },
  { day: 1, memo: '감가상각비', dr: 'c-depr', cr: 'c-equip', base: 520000n, step: 0n },
  { day: 12, memo: '기장·세무 수수료', dr: 'c-fee', cr: 'c-bank', base: 180000n, step: 20000n },
  // 분기 부가가치세, 연 법인세
  { day: 25, memo: '부가가치세 납부', dr: 'c-tax', cr: 'c-bank', base: 4200000n, step: 400000n, everyMonths: 3, offset: 0 },
  { day: 3, memo: '법인세 납부', dr: 'c-tax', cr: 'c-bank', base: 8500000n, step: 900000n, everyMonths: 12, offset: 2 },
];

const COMPANY_DAILY = [
  { memo: '상품매출 · 현금', dr: 'c-bank', cr: 'c-sales', base: 340000n, step: 85000n },
  { memo: '상품매출 · 카드', dr: 'c-ar', cr: 'c-sales', base: 520000n, step: 120000n },
  { memo: '상품매출 · 외상', dr: 'c-ar', cr: 'c-sales', base: 780000n, step: 160000n },
  { memo: '용역매출', dr: 'c-ar', cr: 'c-service', base: 1200000n, step: 300000n },
  { memo: '상품매입 · 외상', dr: 'c-cogs', cr: 'c-ap', base: 430000n, step: 90000n },
  { memo: '상품매입 · 현금', dr: 'c-cogs', cr: 'c-bank', base: 210000n, step: 45000n },
  { memo: '매입대금 지급', dr: 'c-ap', cr: 'c-bank', base: 650000n, step: 120000n },
  { memo: '매출대금 회수', dr: 'c-bank', cr: 'c-ar', base: 700000n, step: 140000n },
  { memo: '사무용품 구입', dr: 'c-office', cr: 'c-bank', base: 38000n, step: 9000n },
  { memo: '소모품 구입', dr: 'c-supply', cr: 'c-bank', base: 52000n, step: 11000n },
  { memo: '거래처 접대', dr: 'c-ent', cr: 'c-bank', base: 120000n, step: 35000n },
  { memo: '여비교통비', dr: 'c-travel', cr: 'c-cash', base: 24000n, step: 8000n },
  { memo: '차량 유지비', dr: 'c-car', cr: 'c-bank', base: 88000n, step: 22000n },
  { memo: '운반비', dr: 'c-fee', cr: 'c-cash', base: 14000n, step: 3000n },
];

/** 회사 원장 — 기본 100,000건(약 14년치). span 고정으로 연도 폭주 없음. */
export function buildCompany(targetRows = 100000) {
  return buildLedger({
    monthlyFixed: COMPANY_MONTHLY,
    dailyPool: COMPANY_DAILY,
    months: 168, // 14년
    targetRows,
  });
}

// ── 프로파일 레지스트리 ─────────────────────────────────────────────────────

export const PROFILES = {
  household: { accounts: HOUSEHOLD_ACCOUNTS, build: buildHousehold, defaultRows: 1500 },
  company: { accounts: COMPANY_ACCOUNTS, build: buildCompany, defaultRows: 100000 },
};

// 하위 호환 (localApi.seedSample 등) — 가계 프로파일이 기본 샘플.
export const DEMO_ACCOUNTS = HOUSEHOLD_ACCOUNTS;
export const buildDemoTxns = buildHousehold;

/**
 * 거래에서 계정별 순잔액을 계산한다 (차변 − 대변, 전 과정 BigInt).
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
