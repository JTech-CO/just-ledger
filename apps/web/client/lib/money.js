// 금액 유틸 — 문자열·BigInt 만 사용한다. Number/parseFloat/toFixed/Math.round 금지 (INV-4).
// 표시 포맷팅도 문자열 연산으로만 한다 (CLAUDE.md 금액 취급 규칙).

/** 계약 moneyMinor 패턴 (부호 허용, 최대 18자리, 선행 0 금지) */
const MONEY_RE = /^(0|-?[1-9][0-9]{0,17})$/;
/** 계약 positiveMinor 패턴 (entry.amount_minor 전용) */
const POSITIVE_RE = /^[1-9][0-9]{0,17}$/;

/** 전각 숫자 → ASCII (IME 입력 대응, §2.2) */
const FULLWIDTH = { '０': '0', '１': '1', '２': '2', '３': '3', '４': '4', '５': '5', '６': '6', '７': '7', '８': '8', '９': '9' };

/** @param {string} s @returns {boolean} */
export const isMoneyMinor = (s) => typeof s === 'string' && MONEY_RE.test(s);

/** @param {string} s @returns {boolean} */
export const isPositiveMinor = (s) => typeof s === 'string' && POSITIVE_RE.test(s);

/**
 * 사용자 입력 → 최소 화폐 단위 정수 문자열. 입력 중에도 float 를 만들지 않는다 (§2.2).
 * 통화기호·천단위 구분자·공백·전각 숫자를 정규화하고, 소수점이 있으면 거부한다
 * (최소 단위 정수 입력만 허용 — KRW 기준. 소수 통화 UI 는 M8 에서 통화별 처리).
 * @param {string} raw
 * @returns {string|null} 정규화된 positiveMinor 문자열, 유효하지 않으면 null
 */
export function normalizeAmountInput(raw) {
  if (typeof raw !== 'string') return null;
  let s = raw.replace(/[０-９]/g, (ch) => FULLWIDTH[ch]);
  s = s.replace(/[\s,₩$€¥원]/g, '');
  if (s === '' || /[.]/.test(s)) return null;
  if (!/^[0-9]+$/.test(s)) return null;
  s = s.replace(/^0+(?=[0-9])/, '');   // 선행 0 제거 ("007" → "7", "0" 유지)
  return isPositiveMinor(s) ? s : null;
}

/**
 * 천단위 구분자 표시 포맷 (문자열 연산만).
 * @param {string} minor moneyMinor 문자열
 * @returns {string} 예: "-1234567" → "-1,234,567"
 */
export function formatMinor(minor) {
  if (!isMoneyMinor(minor)) return minor;
  const neg = minor.startsWith('-');
  const digits = neg ? minor.slice(1) : minor;
  let out = '';
  for (let i = 0; i < digits.length; i += 1) {
    const fromEnd = digits.length - i;
    out += digits[i];
    if (fromEnd > 1 && (fromEnd - 1) % 3 === 0) out += ',';
  }
  return (neg ? '-' : '') + out;
}

/**
 * 금액 합산 (BigInt 경유, 결과는 문자열).
 * @param {...string} xs moneyMinor 문자열들
 * @returns {string}
 */
export function addMinor(...xs) {
  let acc = 0n;
  for (const x of xs) {
    if (!isMoneyMinor(x)) throw new TypeError(`moneyMinor 아님: ${x}`);
    acc += BigInt(x);
  }
  return acc.toString();
}

/**
 * 비교: a < b → -1, a == b → 0, a > b → 1
 * @param {string} a @param {string} b
 */
export function compareMinor(a, b) {
  const x = BigInt(a);
  const y = BigInt(b);
  if (x < y) return -1;
  if (x > y) return 1;
  return 0;
}

/**
 * entries 의 방향별 합계 (LedgerTable 표시용).
 * @param {Array<{direction: 'debit'|'credit', amount_minor: string}>} entries
 * @returns {{debit: string, credit: string}}
 */
export function sumByDirection(entries) {
  let debit = 0n;
  let credit = 0n;
  for (const e of entries) {
    if (!isPositiveMinor(e.amount_minor)) throw new TypeError(`positiveMinor 아님: ${e.amount_minor}`);
    if (e.direction === 'debit') debit += BigInt(e.amount_minor);
    else credit += BigInt(e.amount_minor);
  }
  return { debit: debit.toString(), credit: credit.toString() };
}
