// 정산 골든 생성기 (M5). JS 참조 구현(scripts/parity/lib.mjs)이 정본이며,
// 이 스크립트가 고정폭 입력과 기대 출력을 함께 만든다. COBOL 은 동일 입력에서
// 이 기대 출력을 바이트 단위로 재현해야 한다 (INV-7, 차이 0원).
//
// 실행: node fixtures/settlement/gen.mjs  →  settle-*.dat / amort-*.dat 재생성
// (재생성 후 사람이 표본을 검토하고 커밋. 지문/바이트가 회귀 기준이 된다.)

import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { settleReference, amortReference, levelPayment } from '../../scripts/parity/lib.mjs';
import {
  formatSettleIn as settleInLine,
  formatSettleOut as settleOutLine,
  formatAmortIn as amortInLine,
  formatAmortOut as amortOutLine,
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

const boundary = writeSettle('boundary', genSettleBoundary());
const bulk = writeSettle('bulk', genSettle(10000, 20260722));
const amort = writeAmort();
console.log(`settle-boundary: in ${boundary.in} / out ${boundary.out}`);
console.log(`settle-bulk: in ${bulk.in} / out ${bulk.out} (INV-7 규모)`);
console.log(`amort: loans ${amort.loans} / rows ${amort.rows}`);
