// 고정폭 레코드 포맷/파스 — copybook(settle-io.cpy / amort-io.cpy)의 JS 미러.
// copybook 이 SSOT 이며, 레이아웃 변경 시 여기와 gen.mjs 를 함께 갱신하고
// PROGRESS.md 계약 변경 로그에 기재한다. 이 파일 외에 레이아웃을 재정의하지
// 않는다 (gen.mjs 와 parity 하네스가 모두 여기서 import).
//
// 검증 규칙은 Go 미러(services/worker/settlement/records.go)와 의미가 같아야
// 한다 — 어느 한쪽만 느슨하면 그 쪽으로 골든 오염이 지나간다.

export const SETTLE_IN_LEN = 81;
export const SETTLE_OUT_LEN = 51;
export const AMORT_IN_LEN = 67;
export const AMORT_OUT_LEN = 79;
export const INTEREST_IN_LEN = 63;
export const INTEREST_OUT_LEN = 62;
export const DEPREC_IN_LEN = 68;
export const DEPREC_OUT_LEN = 64;

/** 감가상각 회차 계약 상한 (copybook DI-PERIODS 1..360) */
export const DEPREC_MAX_PERIODS = 360;

/** 상각 회차 계약 상한 (copybook AI-PERIODS 1..360) */
export const AMORT_MAX_PERIODS = 360;

const padL = (s, n) => String(s).padStart(n, '0');
const padR = (s, n) => String(s).padEnd(n, ' ');

/** SIGN LEADING SEPARATE: 부호 1 + 절대값 zero-fill n */
function signLeading(v, n) {
  const b = BigInt(v);
  const sign = b < 0n ? '-' : '+';
  const abs = (b < 0n ? -b : b).toString();
  fitDigits(abs, n, 'signLeading');
  return sign + padL(abs, n);
}

/** 숫자 필드: 비어 있지 않은 [0-9]+ 이고 PIC 폭 이내 (Go digits 미러) */
function fitDigits(value, width, field) {
  const s = String(value);
  if (!/^[0-9]+$/.test(s)) {
    throw new RangeError(`${field}: 숫자가 아님 ${JSON.stringify(s)}`);
  }
  if (s.length > width) {
    throw new RangeError(`${field} 길이 ${s.length} > PIC 폭 ${width}: ${s}`);
  }
  return s;
}

/** 문자 필드: 출력 가능 ASCII 만, PIC 폭 이내 (Go alnum 미러) */
function fitText(value, width, field) {
  const s = String(value);
  if (s.length > width) {
    throw new RangeError(`${field} 길이 ${s.length} > PIC 폭 ${width}: ${s}`);
  }
  if (!/^[\x20-\x7e]*$/.test(s)) {
    throw new RangeError(`${field}: 고정폭 레코드에 비ASCII/제어문자 ${JSON.stringify(s)}`);
  }
  return s;
}

/** 파스 측: 고정폭 숫자 슬라이스 — 전부 숫자여야 함 (공백→0 침묵 수용 금지) */
function sliceDigits(line, from, to, field) {
  const s = line.slice(from, to);
  if (!/^[0-9]+$/.test(s)) {
    throw new RangeError(`${field}: 숫자 필드가 아님 ${JSON.stringify(s)}`);
  }
  return BigInt(s).toString();
}

// ── SETTLE-IN-REC: CODE32 DIR1 CUR3 AMT15 NUM15 DEN15 ──────────────────────
export function formatSettleIn(e) {
  fitText(e.account_code, 32, 'account_code');
  if (e.direction !== 'D' && e.direction !== 'C') {
    throw new RangeError(`direction: ${JSON.stringify(e.direction)} (D|C 만 허용)`);
  }
  if (!/^[A-Z]{3}$/.test(e.currency)) {
    throw new RangeError(`currency: ${JSON.stringify(e.currency)} ([A-Z]{3} 만 허용)`);
  }
  fitDigits(e.amount_minor, 15, 'amount_minor');
  fitDigits(e.rate_num, 15, 'rate_num');
  fitDigits(e.rate_den, 15, 'rate_den');
  if (BigInt(e.rate_den) === 0n) throw new RangeError('rate_den: 0 은 허용되지 않음');
  return (
    padR(e.account_code, 32) +
    e.direction +
    e.currency +
    padL(e.amount_minor, 15) +
    padL(e.rate_num, 15) +
    padL(e.rate_den, 15)
  );
}

export function parseSettleIn(line) {
  if (line.length !== SETTLE_IN_LEN) {
    throw new RangeError(`SETTLE-IN 레코드 길이 ${line.length} != ${SETTLE_IN_LEN}`);
  }
  return {
    account_code: line.slice(0, 32).trimEnd(),
    direction: line.slice(32, 33),
    currency: line.slice(33, 36).trimEnd(),
    amount_minor: sliceDigits(line, 36, 51, 'amount_minor'),
    rate_num: sliceDigits(line, 51, 66, 'rate_num'),
    rate_den: sliceDigits(line, 66, 81, 'rate_den'),
  };
}

// ── SETTLE-OUT-REC: CODE32 BAL(S9(18) sign-lead-sep=19) ────────────────────
export function formatSettleOut(r) {
  fitText(r.account_code, 32, 'account_code');
  return padR(r.account_code, 32) + signLeading(r.balance_krw, 18);
}

// ── AMORT-IN-REC: ID16 P15 NUM9 DEN9 N3 PAY15 ──────────────────────────────
export function formatAmortIn(a) {
  fitText(a.loan_id, 16, 'loan_id');
  fitDigits(a.principal, 15, 'principal');
  fitDigits(a.rate_num, 9, 'rate_num');
  fitDigits(a.rate_den, 9, 'rate_den');
  if (BigInt(a.rate_den) === 0n) throw new RangeError('rate_den: 0 은 허용되지 않음');
  fitDigits(a.periods, 3, 'periods');
  const n = Number(a.periods);
  if (n < 1 || n > AMORT_MAX_PERIODS) {
    throw new RangeError(`periods: ${a.periods} (1..${AMORT_MAX_PERIODS} 만 허용)`);
  }
  fitDigits(a.payment, 15, 'payment');
  return (
    padR(a.loan_id, 16) +
    padL(a.principal, 15) +
    padL(a.rate_num, 9) +
    padL(a.rate_den, 9) +
    padL(a.periods, 3) +
    padL(a.payment, 15)
  );
}

export function parseAmortIn(line) {
  if (line.length !== AMORT_IN_LEN) {
    throw new RangeError(`AMORT-IN 레코드 길이 ${line.length} != ${AMORT_IN_LEN}`);
  }
  return {
    loan_id: line.slice(0, 16).trimEnd(),
    principal: sliceDigits(line, 16, 31, 'principal'),
    rate_num: sliceDigits(line, 31, 40, 'rate_num'),
    rate_den: sliceDigits(line, 40, 49, 'rate_den'),
    periods: Number(sliceDigits(line, 49, 52, 'periods')),
    payment: sliceDigits(line, 52, 67, 'payment'),
  };
}

// ── AMORT-OUT-REC: ID16 PER3 PAY15 INT15 PRIN15 BAL15 ──────────────────────
export function formatAmortOut(loanId, r) {
  fitText(loanId, 16, 'loan_id');
  fitDigits(r.period, 3, 'period');
  fitDigits(r.payment, 15, 'payment');
  fitDigits(r.interest, 15, 'interest');
  fitDigits(r.principal, 15, 'principal');
  fitDigits(r.balance, 15, 'balance');
  return (
    padR(loanId, 16) +
    padL(r.period, 3) +
    padL(r.payment, 15) +
    padL(r.interest, 15) +
    padL(r.principal, 15) +
    padL(r.balance, 15)
  );
}

export function parseAmortOut(line) {
  if (line.length !== AMORT_OUT_LEN) {
    throw new RangeError(`AMORT-OUT 레코드 길이 ${line.length} != ${AMORT_OUT_LEN}`);
  }
  return {
    loan_id: line.slice(0, 16).trimEnd(),
    period: Number(sliceDigits(line, 16, 19, 'period')),
    payment: sliceDigits(line, 19, 34, 'payment'),
    interest: sliceDigits(line, 34, 49, 'interest'),
    principal: sliceDigits(line, 49, 64, 'principal'),
    balance: sliceDigits(line, 64, 79, 'balance'),
  };
}

// ── INTEREST-IN-REC: ID16 METHOD1 P15 NUM9 DEN9 DAYS5 BASIS5 PER3 ──────────
export function formatInterestIn(r) {
  fitText(r.account_id, 16, 'account_id');
  if (r.method !== 'S' && r.method !== 'C') {
    throw new RangeError(`method: ${JSON.stringify(r.method)} (S|C 만 허용)`);
  }
  fitDigits(r.principal, 15, 'principal');
  fitDigits(r.rate_num, 9, 'rate_num');
  fitDigits(r.rate_den, 9, 'rate_den');
  if (BigInt(r.rate_den) === 0n) throw new RangeError('rate_den: 0 은 허용되지 않음');
  fitDigits(r.days, 5, 'days');
  fitDigits(r.basis, 5, 'basis');
  if (r.method === 'S' && BigInt(r.basis) === 0n) {
    throw new RangeError('basis: simple 이자에 0 은 허용되지 않음');
  }
  fitDigits(r.periods, 3, 'periods');
  return (
    padR(r.account_id, 16) +
    r.method +
    padL(r.principal, 15) +
    padL(r.rate_num, 9) +
    padL(r.rate_den, 9) +
    padL(r.days, 5) +
    padL(r.basis, 5) +
    padL(r.periods, 3)
  );
}

export function parseInterestIn(line) {
  if (line.length !== INTEREST_IN_LEN) {
    throw new RangeError(`INTEREST-IN 레코드 길이 ${line.length} != ${INTEREST_IN_LEN}`);
  }
  return {
    account_id: line.slice(0, 16).trimEnd(),
    method: line.slice(16, 17),
    principal: sliceDigits(line, 17, 32, 'principal'),
    rate_num: sliceDigits(line, 32, 41, 'rate_num'),
    rate_den: sliceDigits(line, 41, 50, 'rate_den'),
    days: sliceDigits(line, 50, 55, 'days'),
    basis: sliceDigits(line, 55, 60, 'basis'),
    periods: sliceDigits(line, 60, 63, 'periods'),
  };
}

// ── INTEREST-OUT-REC: ID16 METHOD1 P15 INT15 BAL15 ────────────────────────
export function formatInterestOut(r) {
  fitText(r.account_id, 16, 'account_id');
  if (r.method !== 'S' && r.method !== 'C') {
    throw new RangeError(`method: ${JSON.stringify(r.method)} (S|C 만 허용)`);
  }
  fitDigits(r.principal, 15, 'principal');
  fitDigits(r.interest, 15, 'interest');
  fitDigits(r.balance, 15, 'balance');
  return (
    padR(r.account_id, 16) +
    r.method +
    padL(r.principal, 15) +
    padL(r.interest, 15) +
    padL(r.balance, 15)
  );
}

export function parseInterestOut(line) {
  if (line.length !== INTEREST_OUT_LEN) {
    throw new RangeError(`INTEREST-OUT 레코드 길이 ${line.length} != ${INTEREST_OUT_LEN}`);
  }
  return {
    account_id: line.slice(0, 16).trimEnd(),
    method: line.slice(16, 17),
    principal: sliceDigits(line, 17, 32, 'principal'),
    interest: sliceDigits(line, 32, 47, 'interest'),
    balance: sliceDigits(line, 47, 62, 'balance'),
  };
}

// ── DEPREC-IN-REC: ID16 METHOD1 COST15 SALVAGE15 NUM9 DEN9 PER3 ───────────
export function formatDeprecIn(r) {
  fitText(r.asset_id, 16, 'asset_id');
  if (r.method !== 'L' && r.method !== 'D') {
    throw new RangeError(`method: ${JSON.stringify(r.method)} (L|D 만 허용)`);
  }
  fitDigits(r.cost, 15, 'cost');
  fitDigits(r.salvage, 15, 'salvage');
  if (BigInt(r.salvage) > BigInt(r.cost)) {
    throw new RangeError('salvage > cost 는 허용되지 않음');
  }
  fitDigits(r.rate_num, 9, 'rate_num');
  fitDigits(r.rate_den, 9, 'rate_den');
  if (r.method === 'D' && BigInt(r.rate_den) === 0n) {
    throw new RangeError('rate_den: 정률법에 0 은 허용되지 않음');
  }
  fitDigits(r.periods, 3, 'periods');
  const n = Number(r.periods);
  if (n < 1 || n > DEPREC_MAX_PERIODS) {
    throw new RangeError(`periods: ${r.periods} (1..${DEPREC_MAX_PERIODS} 만 허용)`);
  }
  return (
    padR(r.asset_id, 16) +
    r.method +
    padL(r.cost, 15) +
    padL(r.salvage, 15) +
    padL(r.rate_num, 9) +
    padL(r.rate_den, 9) +
    padL(r.periods, 3)
  );
}

export function parseDeprecIn(line) {
  if (line.length !== DEPREC_IN_LEN) {
    throw new RangeError(`DEPREC-IN 레코드 길이 ${line.length} != ${DEPREC_IN_LEN}`);
  }
  return {
    asset_id: line.slice(0, 16).trimEnd(),
    method: line.slice(16, 17),
    cost: sliceDigits(line, 17, 32, 'cost'),
    salvage: sliceDigits(line, 32, 47, 'salvage'),
    rate_num: sliceDigits(line, 47, 56, 'rate_num'),
    rate_den: sliceDigits(line, 56, 65, 'rate_den'),
    periods: Number(sliceDigits(line, 65, 68, 'periods')),
  };
}

// ── DEPREC-OUT-REC: ID16 PER3 DEPREC15 ACCUM15 BOOK15 ─────────────────────
export function formatDeprecOut(assetId, r) {
  fitText(assetId, 16, 'asset_id');
  fitDigits(r.period, 3, 'period');
  fitDigits(r.deprec, 15, 'deprec');
  fitDigits(r.accum, 15, 'accum');
  fitDigits(r.book, 15, 'book');
  return (
    padR(assetId, 16) +
    padL(r.period, 3) +
    padL(r.deprec, 15) +
    padL(r.accum, 15) +
    padL(r.book, 15)
  );
}

export function parseDeprecOut(line) {
  if (line.length !== DEPREC_OUT_LEN) {
    throw new RangeError(`DEPREC-OUT 레코드 길이 ${line.length} != ${DEPREC_OUT_LEN}`);
  }
  return {
    asset_id: line.slice(0, 16).trimEnd(),
    period: Number(sliceDigits(line, 16, 19, 'period')),
    deprec: sliceDigits(line, 19, 34, 'deprec'),
    accum: sliceDigits(line, 34, 49, 'accum'),
    book: sliceDigits(line, 49, 64, 'book'),
  };
}

// ── 마감 요약 리포트 (report.cbl) ─────────────────────────────────────────
// 입력은 header/detail 레코드(report-io.cpy), 출력은 고정폭 텍스트 문서.
// COBOL 의 numeric-edited 렌더링(콤마 그룹핑·부동 부호·zero-suppress)을
// 문자열 연산으로 1:1 재현한다 (부동소수점 미경유, 금액은 BigInt 만).
export const REPORT_IN_DETAIL_LEN = 76; // 'D' 레코드 길이 (header 는 48, READ 시 공백 채움)
export const REPORT_WIDTH = 86; // 렌더 줄 폭

/** 세 자리마다 콤마 (COBOL Z-suppress + 콤마 삽입 의미론과 동일). */
function groupThousands(digits) {
  let out = '';
  let c = 0;
  for (let i = digits.length - 1; i >= 0; i -= 1) {
    out = digits[i] + out;
    c += 1;
    if (c % 3 === 0 && i > 0) out = ',' + out;
  }
  return out;
}

/** PIC +++,...,++9 (폭 27) 미러: 부동 부호·콤마·우측정렬. 0 이상은 '+'. */
function editSignedAmount(v) {
  const b = BigInt(v);
  const neg = b < 0n;
  const abs = (neg ? -b : b).toString();
  const body = (neg ? '-' : '+') + groupThousands(abs);
  if (body.length > 27) {
    throw new RangeError(`net balance 폭 ${body.length} > 27`);
  }
  return body.padStart(27, ' ');
}

/** PIC ZZZ,ZZ9 (폭 7) 미러: zero-suppress·콤마·우측정렬. */
function editCount(n) {
  const g = groupThousands(String(n));
  if (g.length > 7) throw new RangeError(`account count 폭 ${g.length} > 7`);
  return g.padStart(7, ' ');
}

/** 'H' 헤더 레코드 (period 7 + title 40). 와이어 길이 48. */
export function formatReportHeaderIn(h) {
  fitText(h.period, 7, 'period');
  fitText(h.title, 40, 'title');
  return 'H' + padR(h.period, 7) + padR(h.title, 40);
}

/** 'D' 상세 레코드 (code 32 + name 24 + balance S9(18) sign-lead = 19). 길이 76. */
export function formatReportDetailIn(d) {
  fitText(d.code, 32, 'code');
  fitText(d.name, 24, 'name');
  return 'D' + padR(d.code, 32) + padR(d.name, 24) + signLeading(d.balance, 18);
}

/**
 * 렌더된 리포트 텍스트 (report.cbl stdout 의 바이트 단위 미러).
 * @param {{period: string, title: string}} header
 * @param {Array<{code: string, name: string, balance: string}>} details
 * @returns {string} 개행 종료된 다중행 문서
 */
export function formatReport(header, details) {
  const W = REPORT_WIDTH;
  const ruleD = '='.repeat(W);
  const ruleS = '-'.repeat(W);
  const period = padR(fitText(header.period, 7, 'period'), 7);
  const title = padR(fitText(header.title, 40, 'title'), 40);
  const lines = [];
  lines.push(ruleD);
  lines.push(padR('  JUST-LEDGER SETTLEMENT SUMMARY', W));
  lines.push('  Period ' + period + '   ' + title + ' '.repeat(27));
  lines.push(ruleD);
  lines.push(
    '  ' + padR('ACCOUNT CODE', 32) + ' ' + padR('ACCOUNT NAME', 24) +
    '        BALANCE (KRW MINOR)',
  );
  lines.push(ruleS);
  let total = 0n;
  for (const d of details) {
    const bal = BigInt(d.balance);
    total += bal;
    const code = padR(fitText(d.code, 32, 'code'), 32);
    const name = padR(fitText(d.name, 24, 'name'), 24);
    lines.push('  ' + code + ' ' + name + editSignedAmount(bal));
  }
  // COBOL 의 S9(18) 범위 초과는 edited move 에서 절삭되므로 사전 거절.
  const LIM = 999999999999999999n;
  if (total > LIM || total < -LIM) {
    throw new RangeError('net total 이 S9(18) 을 초과');
  }
  lines.push(ruleS);
  lines.push(
    '  ACCOUNTS: ' + editCount(details.length) + ' '.repeat(30) +
    'NET TOTAL' + ' ' + editSignedAmount(total),
  );
  lines.push(ruleD);
  return lines.join('\n') + '\n';
}
