// 사이드바 하단 잔액 요약 (디자인 백서 §4.3). 카드 3개 나열 패턴을 쓰지 않는다.
// 계정 유형별 1행 리스트 + 우측 정렬 금액. 잔액 변화는 채널 수신 시 120ms
// 배경 하이라이트 1회(카운트업 애니메이션 금지) — store.flashKeys 로 표시한다.

import { useEffect } from 'react';
import { useLedgerStore } from '../../store/ledgerStore.js';
import Money from '../common/Money.jsx';
import styles from './BalanceSummary.module.css';

/**
 * @param {object} props
 * @param {Map<string,string>} props.accountName  account_id → "코드 이름"
 */
export default function BalanceSummary({ accountName }) {
  const balances = useLedgerStore((s) => s.balances);
  const flashKeys = useLedgerStore((s) => s.flashKeys);
  const clearFlash = useLedgerStore((s) => s.clearFlash);

  // 하이라이트는 120ms 후 스스로 꺼진다 (§4.3)
  useEffect(() => {
    if (flashKeys.size === 0) return undefined;
    const timers = [...flashKeys].map((key) => setTimeout(() => clearFlash(key), 120));
    return () => timers.forEach(clearTimeout);
  }, [flashKeys, clearFlash]);

  if (balances.size === 0) {
    return <p className={styles.empty}>잔액 없음 (posted 거래가 반영되면 표시됩니다)</p>;
  }

  return (
    <section className={styles.summary} aria-label="잔액 요약">
      <h2 className={styles.title}>잔액</h2>
      <ul className={styles.list}>
        {[...balances.entries()].map(([key, minor]) => {
          const [accountId, currency] = key.split(':');
          const flash = flashKeys.has(key);
          return (
            <li key={key} className={`${styles.row} ${flash ? styles.flash : ''}`}>
              <span className={styles.name}>{accountName.get(accountId) ?? accountId}</span>
              <Money minor={minor} currency={currency} signed />
            </li>
          );
        })}
      </ul>
    </section>
  );
}
