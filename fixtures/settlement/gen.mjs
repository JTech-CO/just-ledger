// 정산 골든 생성기 (M5). JS 참조 구현(scripts/parity/lib.mjs)이 정본이며,
// 이 스크립트가 고정폭 입력과 기대 출력을 함께 만든다. COBOL 은 동일 입력에서
// 이 기대 출력을 바이트 단위로 재현해야 한다 (INV-7, 차이 0원).
//
// 실행: node fixtures/settlement/gen.mjs  →  settle-*.dat / amort-*.dat 재생성
// (재생성 후 사람이 표본을 검토하고 커밋. 지문/바이트가 회귀 기준이 된다.)

import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  settleReference, amortReference, levelPayment, interestReference,
  deprecReference,
} from '../../scripts/parity/lib.mjs';
import {
  formatSettleIn as settleInLine,
  formatSettleOut as settleOutLine,
  formatAmortIn as amortInLine,
  formatAmortOut as amortOutLine,
  formatInterestIn as interestInLine,
  formatInterestOut as interestOutLine,
  formatReportHeaderIn as reportHeaderLine,
  formatReportDetailIn as reportDetailLine,
  formatReport,
  formatDeprecIn as deprecInLine,
  formatDeprecOut as deprecOutLine,
} from '../../scripts/parity/records.mjs';

const here = dirname(fileURLToPath(import.meta.url));

const padL = (s, n) => String(s).padStart(n, '0');

// ── 마감 정산 픽스처: 다통화 10,000 entry (INV-7 게이트 규모) ──────────────
const RATES = {
  KRW: ['1', '1'],
  USD: ['139125', '100'], // 1391.25 KRW/USD-cent? — cent×1391.25/100 (아래 참조)
  JPY: ['905', '100'], // 9.05 KRW/JPY
  EUR: ['151980', '100'],
};
const CURRENCIES = Object.keys(RATES);

function genSettle(count, seed) {
  let s = seed >>> 0;
  // nextInt: 정수 LCG 원시값 — 금액 유도는 이것만 사용 (float 미경유, INV-4)
  const nextInt = () => (s = (s * 1103515245 + 12345) & 0x7fffffff);
  // rnd: 비금액 선택(통화·계정 인덱스·방향)에만 사용
  const rnd = () => nextInt() / 0x7fffffff;
  const entries = [];
  const ACCOUNTS = 40;
  for (let i = 0; i < count; i += 1) {
    const cur = CURRENCIES[Math.floor(rnd() * CURRENCIES.length)];
    const [num, den] = RATES[cur];
    // 금액은 float 미경유 — 정수 LCG 상태의 나머지 연산으로 직접 유도 (INV-4).
    // 반올림이 실제로 갈리도록 1..9,999,999 전역에 고르게 퍼진다.
    const amount = String(1 + (nextInt() % 9_999_999));
    entries.push({
      account_code: 'ACC.' + padL(String(1 + Math.floor(rnd() * ACCOUNTS)), 4),
      direction: rnd() < 0.5 ? 'D' : 'C',
      currency: cur,
      amount_minor: amount,
      rate_num: num,
      rate_den: den,
    });
  }
  return entries;
}

// 반올림 경계를 겨냥한 소형 케이스 (0.5 정확히 떨어지는 값 포함)
function genSettleBoundary() {
  // den=2 이면 나머지가 정확히 절반인 경우가 잦다 → 은행가 반올림 검증
  return [
    { account_code: 'BND.0001', direction: 'D', currency: 'USD', amount_minor: '5', rate_num: '1', rate_den: '2' }, // 2.5→2
    { account_code: 'BND.0001', direction: 'D', currency: 'USD', amount_minor: '15', rate_num: '1', rate_den: '2' }, // 7.5→8
    { account_code: 'BND.0002', direction: 'D', currency: 'USD', amount_minor: '25', rate_num: '1', rate_den: '2' }, // 12.5→12
    { account_code: 'BND.0002', direction: 'C', currency: 'USD', amount_minor: '35', rate_num: '1', rate_den: '2' }, // 17.5→18
    { account_code: 'BND.0003', direction: 'D', currency: 'JPY', amount_minor: '3', rate_num: '5', rate_den: '2' }, // 7.5→8
  ];
}

function writeSettle(name, entries) {
  const inLines = entries.map(settleInLine);
  const outLines = settleReference(entries).map(settleOutLine);
  writeFileSync(join(here, `settle-${name}.in.dat`), inLines.join('\n') + '\n');
  writeFileSync(join(here, `settle-${name}.expected.dat`), outLines.join('\n') + '\n');
  return { in: inLines.length, out: outLines.length };
}

// ── 상각 픽스처 ────────────────────────────────────────────────────────────
const LOANS = [
  { loan_id: 'LN0001', principal: '1000000', rate_num: '5', rate_den: '1000', periods: '12' },
  { loan_id: 'LN0002', principal: '30000000', rate_num: '35', rate_den: '10000', periods: '36' },
  { loan_id: 'LN0003', principal: '5000000', rate_num: '0', rate_den: '1', periods: '10' }, // 무이자
  { loan_id: 'LN0004', principal: '123456789', rate_num: '291', rate_den: '100000', periods: '60' },
  // 조기 완제 클램프: P=1·i=1/2·n=3 → 1회차에 잔액 0, 이후 0·0·0 행 (copybook 의미론)
  { loan_id: 'LN0005', principal: '1', rate_num: '1', rate_den: '2', periods: '3' },
  // 회차 계약 상한 경계 (AI-PERIODS = 360)
  { loan_id: 'LN0006', principal: '360000000', rate_num: '291', rate_den: '100000', periods: '360' },
];

function writeAmort() {
  const inLines = [];
  const outLines = [];
  for (const a of LOANS) {
    // A(월 납입액)는 JS 참조가 계산해 입력에 실어 준다. COBOL 은 이 A 로 분해만.
    const n = Number(a.periods); // no-float-ok: 회차 수(1..360)는 금액이 아님
    const payment = levelPayment(
      BigInt(a.principal), BigInt(a.rate_num), BigInt(a.rate_den), n,
    ).toString();
    inLines.push(amortInLine({ ...a, payment }));
    const sch = amortReference(a.principal, a.rate_num, a.rate_den, n);
    for (const r of sch) outLines.push(amortOutLine(a.loan_id, r));
  }
  writeFileSync(join(here, 'amort.in.dat'), inLines.join('\n') + '\n');
  writeFileSync(join(here, 'amort.expected.dat'), outLines.join('\n') + '\n');
  return { loans: inLines.length, rows: outLines.length };
}

// ── 이자 배치 픽스처 ────────────────────────────────────────────────────────
// 단리(day-count)와 복리(회차별)를 섞고, 반올림이 실제로 갈리는 0.5 경계와
// 현실적인 예금·연체 케이스를 함께 넣는다. days/basis 는 'S' 에서만, periods 는
// 'C' 에서만 유효(미사용 필드는 0). 부동소수점 미경유(정수·유리수만).
const INTEREST_ROWS = [
  // 연 3% 예금 1년(365/365) → 정확히 3% = 300,000 (깔끔한 정수)
  { account_id: 'DEP.0001', method: 'S', principal: '10000000', rate_num: '3', rate_den: '100', days: '365', basis: '365', periods: '0' },
  // 90일 2.5% actual/365 예금 → 회차 없는 일할, 반올림 발생
  { account_id: 'DEP.0002', method: 'S', principal: '50000000', rate_num: '25', rate_den: '1000', days: '90', basis: '365', periods: '0' },
  // 30/360 basis 로 30일 6% → 반올림 경계 관찰
  { account_id: 'DEP.0003', method: 'S', principal: '1234567', rate_num: '6', rate_den: '100', days: '30', basis: '360', periods: '0' },
  // 0.5 정확히 → 짝수로 내림(2.5→2 아님, 1*1/2=0.5→0)
  { account_id: 'BND.I001', method: 'S', principal: '1', rate_num: '1', rate_den: '2', days: '1', basis: '1', periods: '0' },
  // 1.5→2 (짝수로 올림): 3*1/2
  { account_id: 'BND.I002', method: 'S', principal: '3', rate_num: '1', rate_den: '2', days: '1', basis: '1', periods: '0' },
  // 연 18% 대출 연체 45일(actual/365) — 연체 이자
  { account_id: 'LATE.001', method: 'S', principal: '3000000', rate_num: '18', rate_den: '100', days: '45', basis: '365', periods: '0' },
  // 월복리 1% 12회 — 회차마다 반올림(은행 관행)
  { account_id: 'CMP.0001', method: 'C', principal: '1000000', rate_num: '1', rate_den: '100', days: '0', basis: '0', periods: '12' },
  // 회차당 0.5% 24회 복리
  { account_id: 'CMP.0002', method: 'C', principal: '100000000', rate_num: '5', rate_den: '1000', days: '0', basis: '0', periods: '24' },
  // 복리 0.5 경계: 100*1/2=50 정확 → 1회차 이자 50, 잔액 150
  { account_id: 'CMP.B001', method: 'C', principal: '100', rate_num: '1', rate_den: '2', days: '0', basis: '0', periods: '1' },
  // 복리 조기 소멸: 1*1/2=0.5→0 → 이자 0, 3회차 전부 잔액 1 (반올림 짝수)
  { account_id: 'CMP.B002', method: 'C', principal: '1', rate_num: '1', rate_den: '2', days: '0', basis: '0', periods: '3' },
  // periods 0 → 이자 0 (복리 무회차)
  { account_id: 'CMP.Z000', method: 'C', principal: '777', rate_num: '5', rate_den: '100', days: '0', basis: '0', periods: '0' },
];

function writeInterest() {
  const inLines = INTEREST_ROWS.map(interestInLine);
  const outLines = INTEREST_ROWS.map((r) => interestOutLine(interestReference(r)));
  writeFileSync(join(here, 'interest.in.dat'), inLines.join('\n') + '\n');
  writeFileSync(join(here, 'interest.expected.dat'), outLines.join('\n') + '\n');
  return { rows: inLines.length };
}

// ── 마감 요약 리포트 픽스처 ──────────────────────────────────────────────────
// 한 header + 정렬된 상세 계정(양수·음수·0 잔액 혼합)을 렌더한다. 콤마 그룹핑,
// 부동 부호(+/-), 0 잔액의 "+0", 순합계 누적을 함께 검증한다.
const REPORT_HEADER = { period: '2026-06', title: 'Household Ledger' };
const REPORT_DETAILS = [
  { code: 'ACC.0001', name: 'Checking', balance: '12345678' },
  { code: 'ACC.0002', name: 'Savings', balance: '150000000' },
  { code: 'ACC.0003', name: 'Credit Card', balance: '-3450000' },
  { code: 'ACC.0004', name: 'Cash', balance: '0' },
  { code: 'ACC.0005', name: 'Investment', balance: '987654321' },
];

function writeReport() {
  const inLines = [reportHeaderLine(REPORT_HEADER)];
  for (const d of REPORT_DETAILS) inLines.push(reportDetailLine(d));
  writeFileSync(join(here, 'report.in.dat'), inLines.join('\n') + '\n');
  writeFileSync(join(here, 'report.expected.dat'), formatReport(REPORT_HEADER, REPORT_DETAILS));
  return { rows: REPORT_DETAILS.length };
}

// ── 감가상각 픽스처 ─────────────────────────────────────────────────────────
// 정액법(L)·정률법(D)을 섞고, 반올림 경계·잔존가치 조기 도달(클램프)·마지막
// 회차 잔여 흡수(종료 장부가 = salvage)를 함께 검증한다. 정수·유리수만.
const DEPREC_ASSETS = [
  // 정액법: base 9,000,000 / 5 = 1,800,000 균등, 장부가 10,000,000→1,000,000
  { asset_id: 'AST.0001', method: 'L', cost: '10000000', salvage: '1000000', rate_num: '0', rate_den: '1', periods: '5' },
  // 정액법 반올림: 1,000,000/3 → 333,333, 마지막 회차 잔여 흡수(333,334)
  { asset_id: 'AST.0002', method: 'L', cost: '1000000', salvage: '0', rate_num: '0', rate_den: '1', periods: '3' },
  // 정액법 0.5 경계: base 5 / 2 = round(2.5)=2 (짝수), 마지막 회차 3
  { asset_id: 'AST.B001', method: 'L', cost: '5', salvage: '0', rate_num: '0', rate_den: '1', periods: '2' },
  // 정률법 25%: 매기 round(book*25/100), 잔존가치 하한, 마지막 회차 흡수
  { asset_id: 'AST.0003', method: 'D', cost: '10000000', salvage: '1000000', rate_num: '25', rate_den: '100', periods: '5' },
  // 정률법 조기 도달: 90% → 1회차에 잔존가치 클램프, 이후 상각 0
  { asset_id: 'AST.0004', method: 'D', cost: '1000000', salvage: '500000', rate_num: '90', rate_den: '100', periods: '4' },
];

function writeDeprec() {
  const inLines = [];
  const outLines = [];
  for (const a of DEPREC_ASSETS) {
    inLines.push(deprecInLine(a));
    for (const r of deprecReference(a)) outLines.push(deprecOutLine(a.asset_id, r));
  }
  writeFileSync(join(here, 'deprec.in.dat'), inLines.join('\n') + '\n');
  writeFileSync(join(here, 'deprec.expected.dat'), outLines.join('\n') + '\n');
  return { assets: inLines.length, rows: outLines.length };
}

const boundary = writeSettle('boundary', genSettleBoundary());
const bulk = writeSettle('bulk', genSettle(10000, 20260722));
const amort = writeAmort();
const interest = writeInterest();
const report = writeReport();
const deprec = writeDeprec();
console.log(`settle-boundary: in ${boundary.in} / out ${boundary.out}`);
console.log(`settle-bulk: in ${bulk.in} / out ${bulk.out} (INV-7 규모)`);
console.log(`amort: loans ${amort.loans} / rows ${amort.rows}`);
console.log(`interest: rows ${interest.rows}`);
console.log(`report: detail rows ${report.rows}`);
console.log(`deprec: assets ${deprec.assets} / rows ${deprec.rows}`);
