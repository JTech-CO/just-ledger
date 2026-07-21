// 정산 JS 참조 구현 (INV-7 의 정본). 전 과정 BigInt — 부동소수점 0 경유 (INV-4).
// COBOL 은 이 결과를 바이트 단위로 재현해야 하며, 차이 1원이라도 나면 마감 불가.
//
// 반올림은 은행가 반올림(round-half-to-even, COBOL ROUNDED MODE IS NEAREST-EVEN)
// 하나만 정본으로 삼는다. 다른 반올림을 어디에도 만들지 않는다 (CLAUDE.md).

/**
 * 유리수 num/den 을 은행가 반올림으로 정수화한다 (부호 안전).
 * @param {bigint} num @param {bigint} den (den > 0)
 * @returns {bigint}
 */
export function roundHalfEven(num, den) {
  if (den <= 0n) throw new RangeError('den > 0 이어야 합니다');
  const neg = num < 0n;
  const a = neg ? -num : num;
  let q = a / den;
  const r = a % den;
  const twice = r * 2n;
  if (twice > den) {
    q += 1n;
  } else if (twice === den) {
    // 정확히 절반 — 짝수로 (q 가 홀수면 올림)
    if (q % 2n === 1n) q += 1n;
  }
  return neg ? -q : q;
}

/**
 * 통화 금액을 KRW 최소단위로 환산 (amount × num / den, 은행가 반올림).
 * @param {bigint} amountMinor 부호 있는 최소단위 정수
 * @param {bigint} rateNum @param {bigint} rateDen
 * @returns {bigint}
 */
export function convertToKrw(amountMinor, rateNum, rateDen) {
  return roundHalfEven(amountMinor * rateNum, rateDen);
}

/**
 * 마감 정산 참조: entries → 계정별 KRW 순잔액 (차변 +, 대변 -).
 * @param {Array<{account_code: string, direction: 'D'|'C', currency: string,
 *   amount_minor: string, rate_num: string, rate_den: string}>} entries
 * @returns {Array<{account_code: string, balance_krw: string}>} account_code 오름차순
 */
export function settleReference(entries) {
  /** @type {Map<string, bigint>} */
  const bal = new Map();
  for (const e of entries) {
    const krw = convertToKrw(BigInt(e.amount_minor), BigInt(e.rate_num), BigInt(e.rate_den));
    const signed = e.direction === 'D' ? krw : -krw;
    bal.set(e.account_code, (bal.get(e.account_code) ?? 0n) + signed);
  }
  return [...bal.entries()]
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .map(([account_code, v]) => ({ account_code, balance_krw: v.toString() }));
}

/**
 * 원리금 균등 월 납입액 A = round_half_even( P·num·(den+num)^n, den·((den+num)^n - den^n) ).
 * 유리수를 BigInt 로 정확히 전개한 뒤 한 번만 반올림한다.
 * @param {bigint} principal @param {bigint} num @param {bigint} den @param {number} n
 * @returns {bigint}
 */
export function levelPayment(principal, num, den, n) {
  if (num === 0n) {
    // 무이자: 원금 균등 (마지막 회차가 잔여 흡수)
    return roundHalfEven(principal, BigInt(n));
  }
  const base = den + num; // (1+i) 의 분자
  const basePow = base ** BigInt(n);
  const denPow = den ** BigInt(n);
  const numerator = principal * num * basePow;
  const denominator = den * (basePow - denPow);
  return roundHalfEven(numerator, denominator);
}

/**
 * 상각 스케줄 참조. 각 회차 이자 = round_half_even(balance·num, den),
 * 원금 = A - 이자. 마지막 회차는 잔여를 흡수해 종료 잔액 0 (DoD 2).
 * @returns {Array<{period: number, payment: string, interest: string,
 *   principal: string, balance: string}>}
 */
export function amortReference(principal, num, den, n) {
  const P = BigInt(principal);
  const N = BigInt(num);
  const D = BigInt(den);
  const A = levelPayment(P, N, D, n);
  const rows = [];
  let balance = P;
  for (let k = 1; k <= n; k += 1) {
    const interest = roundHalfEven(balance * N, D);
    let princ;
    let payment;
    if (k === n) {
      // 마지막 회차: 잔여 원금 전액 흡수
      princ = balance;
      payment = princ + interest;
    } else {
      princ = A - interest;
      payment = A;
    }
    balance -= princ;
    rows.push({
      period: k,
      payment: payment.toString(),
      interest: interest.toString(),
      principal: princ.toString(),
      balance: balance.toString(),
    });
  }
  return rows;
}
