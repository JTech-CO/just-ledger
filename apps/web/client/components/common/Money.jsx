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
 * @param {'debit'|'credit'|'neutral'} [props.tone='neutral']
 *   차변(자산↑)=positive, 대변(지출↑)=negative 색. neutral 은 색 없음.
 * @param {boolean} [props.signed=false]  부호를 명시 표기(합계·증감 표시)
 */
export default function Money({ minor, currency, tone = 'neutral', signed = false }) {
  const toneClass =
    tone === 'debit' ? styles.debit : tone === 'credit' ? styles.credit : '';
  const negative = typeof minor === 'string' && minor.startsWith('-');
  // 부호: 음수는 항상 '−', signed 이면 양수도 '+' (색과 무관하게 방향을 드러낸다)
  const sign = negative ? '−' : signed ? '+' : '';
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
