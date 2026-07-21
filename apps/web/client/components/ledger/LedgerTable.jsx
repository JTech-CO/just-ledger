// 원장 표 최소판 (M2). 가상 스크롤·마감선·Inspector 는 M8.
// 금액 셀은 mono + tabular-nums (§5.2), 합계는 BigInt 문자열 연산 (INV-4).

import { formatMinor, sumByDirection } from '../../lib/money.js';

/**
 * @param {{ rows: Array<Object>, accounts: Array<Object> }} props
 */
export default function LedgerTable({ rows, accounts }) {
  const accountName = new Map(accounts.map((a) => [a.id, `${a.code} ${a.name}`]));

  return (
    <table aria-label="원장">
      <thead>
        <tr>
          <th scope="col">날짜</th>
          <th scope="col">적요</th>
          <th scope="col">분개</th>
          <th scope="col">상태</th>
          <th scope="col" className="amount">차변</th>
          <th scope="col" className="amount">대변</th>
        </tr>
      </thead>
      <tbody>
        {rows.length === 0 && (
          <tr>
            <td colSpan={6} className="muted">거래가 없습니다. 아래에서 수기 입력하세요.</td>
          </tr>
        )}
        {rows.map((t) => {
          // 비정상 데이터 1행이 표 전체를 죽이지 않도록 행 단위로 격리한다.
          let sums;
          try {
            sums = sumByDirection(t.entries);
          } catch {
            return (
              <tr key={t.id} data-txn-id={t.id}>
                <td className="mono">{t.occurred_on}</td>
                <td colSpan={5} className="negative">비정상 분개 데이터 (검사 필요)</td>
              </tr>
            );
          }
          return (
            <tr key={t.id} data-txn-id={t.id}>
              <td className="mono">{t.occurred_on}</td>
              <td>{t.memo || <span className="muted">—</span>}</td>
              <td className="muted">
                {t.entries.map((e) => (
                  <div key={e.id} data-entry-id={e.id}>
                    {e.direction === 'debit' ? '차' : '대'} {accountName.get(e.account_id) ?? e.account_id}{' '}
                    <span className="mono" data-amount={e.amount_minor}>{formatMinor(e.amount_minor)}</span>
                  </div>
                ))}
              </td>
              <td>{t.status}</td>
              <td className="amount mono positive">{formatMinor(sums.debit)}</td>
              <td className="amount mono negative">{formatMinor(sums.credit)}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
