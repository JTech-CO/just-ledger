// 원장 표 — 가상 스크롤(@tanstack/react-virtual). 디자인 백서 §4.3.
//   · 행 높이 고정 34px (내용으로 높이가 변하면 스크롤 계산이 흔들린다)
//   · settled 기간의 행은 편집 컨트롤을 **DOM 에서 제외**(비활성 스타일 아님)
//   · 기간 마지막 행 하단 마감선: settled 는 3px double, 마감 전은 예고선
//   · 금액은 Money 원자(색+부호 병기), BigInt/문자열 경유 (INV-4)
//
// role="table" 시맨틱을 유지해 스크린리더·키보드 조작이 가능하다. 선택/편집은
// 상위(키보드 훅)가 activeIndex·onSelect·onEdit 로 제어한다.

import { forwardRef, useEffect, useRef } from 'react';
import { useVirtualizer } from '@tanstack/react-virtual';
import { Pencil } from 'lucide-react';
import { sumByDirection } from '../../lib/money.js';
import Money from '../common/Money.jsx';
import styles from './LedgerTable.module.css';

const ROW_HEIGHT = 34;

/** 월(YYYY-MM) 추출 — 기간 경계 판정 */
const monthOf = (isoDate) => (typeof isoDate === 'string' ? isoDate.slice(0, 7) : '');

/**
 * @param {object} props
 * @param {Array<Object>} props.rows  txn 행 (occurred_on 정렬 가정)
 * @param {Map<string,string>} props.accountName  account_id → "코드 이름"
 * @param {number} props.activeIndex  키보드 활성 행 (-1 없음)
 * @param {(index:number)=>void} props.onSelect
 * @param {(txn:Object)=>void} [props.onEdit]
 */
export default function LedgerTable({ rows, accountName, activeIndex, onSelect, onEdit }) {
  const parentRef = useRef(null);

  const virtualizer = useVirtualizer({
    count: rows.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => ROW_HEIGHT,
    // 카드 모드(좁은 컨테이너)에서는 행 높이가 34px 가 아니라 52px+ 다. 실제
    // 높이를 측정해 가상화 위치를 정합시킨다(고정 34 가정 시 행이 겹치거나 잘림).
    // 렌더된 행만 측정하므로 10만행에서도 비용은 뷰포트 창에 국한된다.
    measureElement: (el) => el?.getBoundingClientRect().height ?? ROW_HEIGHT,
    overscan: 12,
  });

  // 키보드 j/k 로 활성 행이 바뀌면 뷰포트를 따라가게 스크롤한다(DoD 3). 가상
  // 스크롤에서는 화면 밖 행이 렌더조차 안 되므로, scrollToIndex 없이는 선택 행이
  // 사라져 조작·낭독이 불가능하다. align:'auto' — 이미 보이면 스크롤하지 않는다.
  useEffect(() => {
    if (activeIndex >= 0 && activeIndex < rows.length) {
      virtualizer.scrollToIndex(activeIndex, { align: 'auto' });
    }
  }, [activeIndex, rows.length, virtualizer]);

  // 활성 행 id — 스크린리더가 aria-activedescendant 로 낭독한다
  const activeId = activeIndex >= 0 && activeIndex < rows.length ? `ledger-row-${activeIndex}` : undefined;

  return (
    <div className={styles.wrap} role="table" aria-label="원장" aria-rowcount={rows.length}>
      <div className={styles.head} role="row">
        <span role="columnheader" className={styles.colDate}>날짜</span>
        <span role="columnheader" className={styles.colMemo}>적요</span>
        <span role="columnheader" className={styles.colCounter}>상대처</span>
        <span role="columnheader" className={styles.colAccount}>계정</span>
        <span role="columnheader" className={`${styles.colAmount} ${styles.amountHead}`}>차변</span>
        <span role="columnheader" className={`${styles.colAmount} ${styles.amountHead}`}>대변</span>
        <span role="columnheader" className={styles.colEdit} />
      </div>

      {rows.length === 0 ? (
        <p className={styles.empty}>거래가 없습니다. 아래에서 수기 입력하거나 명세서를 올리세요.</p>
      ) : (
        <div
          ref={parentRef}
          className={styles.scroll}
          tabIndex={0}
          aria-label="원장 스크롤 영역"
          aria-activedescendant={activeId}
        >
          <div className={styles.sizer} style={{ height: `${virtualizer.getTotalSize()}px` }}>
            {virtualizer.getVirtualItems().map((vi) => {
              const t = rows[vi.index];
              const next = rows[vi.index + 1];
              const isPeriodEnd = !next || monthOf(next.occurred_on) !== monthOf(t.occurred_on);
              const settled = t.status === 'settled';
              return (
                <Row
                  key={t.id}
                  ref={virtualizer.measureElement}
                  dataIndex={vi.index}
                  txn={t}
                  rowIndex={vi.index}
                  accountName={accountName}
                  translateY={vi.start}
                  active={vi.index === activeIndex}
                  periodEnd={isPeriodEnd}
                  settled={settled}
                  onSelect={onSelect}
                  onEdit={onEdit}
                />
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

export const Row = forwardRef(function Row(
  { txn, rowIndex, dataIndex, accountName, translateY, active, periodEnd, settled, onSelect, onEdit },
  measureRef,
) {
  let sums;
  try {
    sums = sumByDirection(txn.entries);
  } catch {
    sums = null;
  }
  const first = txn.entries?.[0];
  const counter = first ? (accountName.get(first.account_id) ?? first.account_id) : '';
  const periodClass = periodEnd ? (settled ? styles.periodEndSettled : styles.periodEndPending) : '';

  return (
    <div
      ref={measureRef}
      data-index={dataIndex}
      role="row"
      id={`ledger-row-${rowIndex}`}
      aria-rowindex={rowIndex + 1}
      aria-selected={active}
      data-txn-id={txn.id}
      className={`${styles.row} ${active ? styles.active : ''} ${periodClass}`}
      style={{ transform: `translateY(${translateY}px)` }}
      onClick={() => onSelect(rowIndex)}
    >
      <span role="cell" className={`${styles.colDate} mono`}>{txn.occurred_on}</span>
      <span role="cell" className={styles.colMemo}>{txn.memo || <span className="muted">—</span>}</span>
      <span role="cell" className={styles.colCounter}>{counter}</span>
      <span role="cell" className={`${styles.colAccount} muted`}>
        {txn.entries?.length ?? 0}개 분개
      </span>
      <span role="cell" className={styles.colAmount}>
        {sums ? <Money minor={sums.debit} tone="debit" /> : <span className="negative">오류</span>}
      </span>
      <span role="cell" className={styles.colAmount}>
        {sums ? <Money minor={sums.credit} tone="credit" /> : null}
      </span>
      <span role="cell" className={styles.colEdit}>
        {/* settled 기간은 편집 컨트롤을 렌더링하지 않는다 (DoD 7) */}
        {!settled && onEdit && (
          <button
            type="button"
            className={styles.editBtn}
            aria-label={`${txn.occurred_on} 거래 편집`}
            onClick={(e) => {
              e.stopPropagation();
              onEdit(txn);
            }}
          >
            <Pencil size={16} strokeWidth={1.75} aria-hidden="true" />
          </button>
        )}
      </span>
    </div>
  );
});
