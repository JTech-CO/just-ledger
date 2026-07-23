// 상세 패널 (디자인 백서 §2.3-4). 행 선택 시 등장. 분개 내역 + 분류 근거
// (Prolog 규칙명) + 적용된 Lua 스크립트 + 원본 명세서 행을 순서대로 표시한다.
// 데스크톱은 우측 320px 패널, 태블릿 이하는 하단 시트(CSS 로 전환).

import { X } from 'lucide-react';
import Money from '../common/Money.jsx';
import styles from './Inspector.module.css';

/**
 * @param {object} props
 * @param {Object|null} props.txn  선택된 txn (null 이면 패널 미표시)
 * @param {Map<string,string>} props.accountName
 * @param {()=>void} props.onClose
 */
export default function Inspector({ txn, accountName, onClose }) {
  if (!txn) return null;

  return (
    <aside className={styles.panel} aria-label="거래 상세" role="complementary">
      <header className={styles.head}>
        <h2 className={styles.title}>{txn.occurred_on}</h2>
        <button type="button" className={styles.close} aria-label="상세 닫기" onClick={onClose}>
          <X size={16} strokeWidth={1.75} aria-hidden="true" />
        </button>
      </header>

      {txn.memo && <p className={styles.memo}>{txn.memo}</p>}

      <section className={styles.section} aria-label="분개">
        <h3 className={styles.label}>분개</h3>
        <ul className={styles.entries}>
          {txn.entries?.map((e) => (
            <li key={e.id} className={styles.entry} data-entry-id={e.id}>
              <span className={styles.dir} aria-label={e.direction === 'debit' ? '차변' : '대변'}>
                {e.direction === 'debit' ? '차' : '대'}
              </span>
              <span className={styles.account}>{accountName.get(e.account_id) ?? e.account_id}</span>
              <Money
                minor={e.amount_minor}
                currency={e.currency}
                tone={e.direction === 'debit' ? 'debit' : 'credit'}
              />
            </li>
          ))}
        </ul>
      </section>

      {txn.classification && (
        <section className={styles.section} aria-label="분류 근거">
          <h3 className={styles.label}>분류 근거 (Prolog)</h3>
          <p className={styles.reason}>
            <span className="mono">{txn.classification.rule_name}</span>
            {txn.classification.confidence != null && (
              <span className="muted"> · 신뢰도 {txn.classification.confidence}</span>
            )}
          </p>
        </section>
      )}

      {txn.automation && (
        <section className={styles.section} aria-label="자동화 규칙">
          <h3 className={styles.label}>적용된 규칙 (Lua)</h3>
          <p className={styles.reason}><span className="mono">{txn.automation}</span></p>
        </section>
      )}

      {txn.source_line && (
        <section className={styles.section} aria-label="원본 명세서 행">
          <h3 className={styles.label}>원본 명세서</h3>
          <pre className={styles.source}>{txn.source_line}</pre>
        </section>
      )}
    </aside>
  );
}
