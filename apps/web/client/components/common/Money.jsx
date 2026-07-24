// 금액 표시 원자 (디자인 백서 §4.3). 색은 direction 으로만 결정하되
// **부호를 항상 병기**한다 — 색각 이상·흑백 인쇄에서도 차변/대변이 읽혀야 한다.
// 통화 기호는 --text-muted, 숫자 본체는 --text 명도로 분리해 숫자가 먼저 읽힌다.
// 금액은 문자열/BigInt 만 경유한다 (INV-4 — money.js formatMinor).

import { formatMinor } from '../../lib/money.js';
import styles from './Money.module.css';

const SYMBOL = { KRW: '₩', USD: '$', JPY: '¥', EUR: '€' };

/**
 * @param {object} props
 * @param {string} props.minor  moneyMinor 문자열
 * @param {string} [props.currency]  통화 코드 (기호 표시)
 * @param {'debit'|'credit'|'signed'|'neutral'} [props.tone='neutral']
 *   debit=positive(초록), credit=negative(빨강). signed 는 값의 부호로 색을
 *   정한다(양수 초록·음수 빨강·0 무색 — 잔액 표시용). neutral 은 색 없음.
 * @param {boolean} [props.signed=false]  부호를 명시 표기(합계·증감 표시)
 */
export default function Money({ minor, currency, tone = 'neutral', signed = false }) {
  const negative = typeof minor === 'string' && minor.startsWith('-');
  const zero = minor === '0';
  let toneClass = '';
  if (tone === 'debit') toneClass = styles.debit;
  else if (tone === 'credit') toneClass = styles.credit;
  else if (tone === 'signed') toneClass = zero ? '' : negative ? styles.credit : styles.debit;
  // 부호: 음수는 항상 '−', signed 이면 양수도 '+' (색과 무관하게 방향을 드러낸다).
  // 0 은 부호를 붙이지 않는다.
  const sign = negative ? '−' : signed && !zero ? '+' : '';
  const body = formatMinor(negative ? minor.slice(1) : minor);

  return (
    <span className={`${styles.money} ${toneClass}`} data-amount={minor}>
      {currency && <span className={styles.symbol} aria-hidden="true">{SYMBOL[currency] ?? currency}</span>}
      <span className={styles.sign} aria-hidden={sign === ''}>{sign}</span>
      <span className={styles.digits}>{body}</span>
      {currency && <span className={styles.srCurrency}>{currency}</span>}
    </span>
  );
}
