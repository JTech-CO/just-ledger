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
