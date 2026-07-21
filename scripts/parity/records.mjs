// 고정폭 레코드 포맷/파스 — copybook(settle-io.cpy / amort-io.cpy)의 JS 미러.
// copybook 이 SSOT 이며, 레이아웃 변경 시 여기와 gen.mjs 를 함께 갱신하고
// PROGRESS.md 계약 변경 로그에 기재한다. 이 파일 외에 레이아웃을 재정의하지
// 않는다 (gen.mjs 와 parity 하네스가 모두 여기서 import).

export const SETTLE_IN_LEN = 81;
export const SETTLE_OUT_LEN = 51;
export const AMORT_IN_LEN = 67;
export const AMORT_OUT_LEN = 79;

const padL = (s, n) => String(s).padStart(n, '0');
const padR = (s, n) => String(s).padEnd(n, ' ').slice(0, n);

/** SIGN LEADING SEPARATE: 부호 1 + 절대값 zero-fill n */
function signLeading(v, n) {
  const b = BigInt(v);
  const sign = b < 0n ? '-' : '+';
  const abs = (b < 0n ? -b : b).toString();
  return sign + padL(abs, n);
}

/** 숫자 필드가 PIC 폭을 넘으면 조용한 절삭 대신 즉시 거절 (M5 DoD 4 정신) */
function fit(value, width, field) {
  const s = String(value);
  if (s.length > width) {
    throw new RangeError(`${field} 길이 ${s.length} > PIC 폭 ${width}: ${s}`);
  }
  return s;
}

// ── SETTLE-IN-REC: CODE32 DIR1 CUR3 AMT15 NUM15 DEN15 ──────────────────────
export function formatSettleIn(e) {
  fit(e.account_code, 32, 'account_code');
  fit(e.amount_minor, 15, 'amount_minor');
  fit(e.rate_num, 15, 'rate_num');
  fit(e.rate_den, 15, 'rate_den');
  return (
    padR(e.account_code, 32) +
    e.direction +
    padR(e.currency, 3) +
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
    amount_minor: BigInt(line.slice(36, 51)).toString(),
    rate_num: BigInt(line.slice(51, 66)).toString(),
    rate_den: BigInt(line.slice(66, 81)).toString(),
  };
}

// ── SETTLE-OUT-REC: CODE32 BAL(S9(18) sign-lead-sep=19) ────────────────────
export function formatSettleOut(r) {
  fit(BigInt(r.balance_krw) < 0n ? -BigInt(r.balance_krw) : r.balance_krw, 18, 'balance_krw');
  return padR(r.account_code, 32) + signLeading(r.balance_krw, 18);
}

// ── AMORT-IN-REC: ID16 P15 NUM9 DEN9 N3 PAY15 ──────────────────────────────
export function formatAmortIn(a) {
  fit(a.loan_id, 16, 'loan_id');
  fit(a.principal, 15, 'principal');
  fit(a.rate_num, 9, 'rate_num');
  fit(a.rate_den, 9, 'rate_den');
  fit(a.periods, 3, 'periods');
  fit(a.payment, 15, 'payment');
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
    principal: BigInt(line.slice(16, 31)).toString(),
    rate_num: BigInt(line.slice(31, 40)).toString(),
    rate_den: BigInt(line.slice(40, 49)).toString(),
    periods: Number(line.slice(49, 52)),
    payment: BigInt(line.slice(52, 67)).toString(),
  };
}

// ── AMORT-OUT-REC: ID16 PER3 PAY15 INT15 PRIN15 BAL15 ──────────────────────
export function formatAmortOut(loanId, r) {
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
    period: Number(line.slice(16, 19)),
    payment: BigInt(line.slice(19, 34)).toString(),
    interest: BigInt(line.slice(34, 49)).toString(),
    principal: BigInt(line.slice(49, 64)).toString(),
    balance: BigInt(line.slice(64, 79)).toString(),
  };
}
