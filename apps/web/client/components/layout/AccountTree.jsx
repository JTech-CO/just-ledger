// 사이드바 계정 트리 (디자인 백서 §2.3). 계정 유형별 그룹, 코드는 mono/muted,
// 이름은 sans. 그룹 헤더는 대문자 라벨. GNB 없음 — 좌측 트리가 네비게이션이다.

import styles from './AccountTree.module.css';

const TYPE_LABEL = {
  asset: '자산',
  liability: '부채',
  equity: '자본',
  income: '수익',
  expense: '비용',
};
const TYPE_ORDER = ['asset', 'liability', 'equity', 'income', 'expense'];

/**
 * @param {object} props
 * @param {Array<Object>} props.accounts
 * @param {string|null} props.selectedId
 * @param {(id:string|null)=>void} props.onSelect
 */
export default function AccountTree({ accounts, selectedId, onSelect }) {
  const groups = TYPE_ORDER.map((type) => ({
    type,
    items: accounts.filter((a) => a.type === type && !a.is_closed),
  })).filter((g) => g.items.length > 0);

  return (
    <nav className={styles.tree} aria-label="계정 트리">
      <button
        type="button"
        className={`${styles.all} ${selectedId === null ? styles.selected : ''}`}
        aria-pressed={selectedId === null}
        onClick={() => onSelect(null)}
      >
        전체 계정
      </button>
      {groups.map((g) => (
        <div key={g.type} className={styles.group}>
          <h2 className={styles.groupLabel}>{TYPE_LABEL[g.type] ?? g.type}</h2>
          <ul className={styles.list}>
            {g.items.map((a) => (
              <li key={a.id}>
                <button
                  type="button"
                  className={`${styles.item} ${selectedId === a.id ? styles.selected : ''}`}
                  aria-pressed={selectedId === a.id}
                  onClick={() => onSelect(a.id)}
                >
                  <span className={`${styles.code} mono`}>{a.code}</span>
                  <span className={styles.name}>{a.name}</span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </nav>
  );
}
