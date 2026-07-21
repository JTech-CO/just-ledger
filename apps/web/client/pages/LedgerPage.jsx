// 원장 페이지 최소판 (M2): 잔액 요약 + 수기 입력 + 원장 표.

import { useEffect } from 'react';
import { useLedgerStore } from '../store/ledgerStore.js';
import LedgerTable from '../components/ledger/LedgerTable.jsx';
import TxnForm from '../components/ledger/TxnForm.jsx';
import IngestPanel from '../components/ledger/IngestPanel.jsx';
import { formatMinor } from '../lib/money.js';

export default function LedgerPage() {
  const { rows, accounts, balances, addTxn, loadAll, lastError, loadFailed } = useLedgerStore();

  useEffect(() => {
    // 실패는 store 가 loadFailed/lastError 로 표면화한다 (조용한 빈 화면 금지)
    loadAll().catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const accountName = new Map(accounts.map((a) => [a.id, `${a.code} ${a.name}`]));

  if (loadFailed) {
    return (
      <main style={{ padding: 'var(--sp-5)' }}>
        <p role="alert" className="negative">{lastError}</p>
        <button type="button" className="primary" onClick={() => loadAll().catch(() => {})}>
          다시 시도
        </button>
      </main>
    );
  }

  return (
    <main style={{ padding: 'var(--sp-5)', display: 'grid', gap: 'var(--sp-5)' }}>
      <section aria-label="잔액 요약">
        <h2>잔액</h2>
        {balances.size === 0 ? (
          <p className="muted">잔액 없음 (posted 거래가 반영되면 표시됩니다)</p>
        ) : (
          <ul>
            {[...balances.entries()].map(([key, minor]) => {
              const [accountId, currency] = key.split(':');
              return (
                <li key={key}>
                  {accountName.get(accountId) ?? accountId}{' '}
                  <span className="mono" data-balance={minor}>{formatMinor(minor)}</span>{' '}
                  <span className="muted">{currency}</span>
                </li>
              );
            })}
          </ul>
        )}
      </section>

      <section aria-label="수기 입력">
        <h2>수기 거래</h2>
        <TxnForm accounts={accounts} onSubmit={addTxn} />
      </section>

      <section aria-label="명세서 업로드">
        <h2>명세서 업로드</h2>
        <IngestPanel accounts={accounts} onDone={() => loadAll().catch(() => {})} />
      </section>

      <section aria-label="원장">
        <h2>원장</h2>
        <LedgerTable rows={rows} accounts={accounts} />
      </section>

      {lastError && <p role="status" className="warning muted">{lastError}</p>}
    </main>
  );
}
