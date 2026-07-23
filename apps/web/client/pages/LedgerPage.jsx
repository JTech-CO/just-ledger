// 원장 페이지 (M8). 3열 셸 + 가상 스크롤 원장 + 상세 패널 + 키보드 완주 +
// 실시간 채널. 상태·훅을 여기서 모으고, 표시는 하위 컴포넌트에 위임한다.

import { useEffect, useMemo, useRef, useState } from 'react';
import { useLedgerStore } from '../store/ledgerStore.js';
import { useTheme } from '../hooks/useTheme.js';
import { useLedgerKeyboard } from '../hooks/useLedgerKeyboard.js';
import { useLedgerSocket } from '../hooks/useLedgerSocket.js';
import AppShell from '../components/layout/AppShell.jsx';
import Topbar from '../components/layout/Topbar.jsx';
import AccountTree from '../components/layout/AccountTree.jsx';
import BalanceSummary from '../components/layout/BalanceSummary.jsx';
import LedgerTable from '../components/ledger/LedgerTable.jsx';
import Inspector from '../components/ledger/Inspector.jsx';
import TxnForm from '../components/ledger/TxnForm.jsx';
import IngestPanel from '../components/ledger/IngestPanel.jsx';
import { sumByDirection, addMinor } from '../lib/money.js';
import Money from '../components/common/Money.jsx';
import styles from './LedgerPage.module.css';

const monthOf = (d) => (typeof d === 'string' ? d.slice(0, 7) : '');

/**
 * @param {object} [props]
 * @param {{url:string, token:string, ownerId:string}} [props.socket]  실시간 연결 정보(없으면 비활성)
 */
export default function LedgerPage({ socket }) {
  const { rows, accounts, addTxn, loadAll, lastError, loadFailed, isSettled, socketConnected } =
    useLedgerStore();
  const { theme, toggle } = useTheme();

  const [query, setQuery] = useState('');
  const [period, setPeriod] = useState('');
  const [selectedAccount, setSelectedAccount] = useState(null);
  const [activeIndex, setActiveIndex] = useState(-1);
  const [detailTxn, setDetailTxn] = useState(null);
  const searchRef = useRef(null);

  useEffect(() => {
    loadAll().catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 실시간 채널 — 연결 정보가 있을 때만. 수신은 store.applyRealtime 단일 진입점.
  useLedgerSocket({
    url: socket?.url,
    token: socket?.token,
    ownerId: socket?.ownerId,
    enabled: Boolean(socket),
  });

  const accountName = useMemo(
    () => new Map(accounts.map((a) => [a.id, `${a.code} ${a.name}`])),
    [accounts],
  );

  const periods = useMemo(() => {
    const set = new Set(rows.map((t) => monthOf(t.occurred_on)).filter(Boolean));
    return [...set].sort().reverse();
  }, [rows]);

  // 필터: 기간·계정·검색어. 금액은 절대 숨기지 않으므로 행 자체를 거른다.
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return rows.filter((t) => {
      if (period && monthOf(t.occurred_on) !== period) return false;
      if (selectedAccount && !t.entries?.some((e) => e.account_id === selectedAccount)) return false;
      if (q) {
        const hay = `${t.memo ?? ''} ${t.occurred_on}`.toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
  }, [rows, period, selectedAccount, query]);

  // 합계 — BigInt 문자열 (INV-4)
  const totals = useMemo(() => {
    let debit = '0';
    let credit = '0';
    for (const t of filtered) {
      try {
        const s = sumByDirection(t.entries);
        debit = addMinor(debit, s.debit);
        credit = addMinor(credit, s.credit);
      } catch {
        /* 비정상 분개 행은 합계에서 제외 */
      }
    }
    return { debit, credit };
  }, [filtered]);

  const activeTxn = activeIndex >= 0 ? filtered[activeIndex] : null;

  useLedgerKeyboard({
    count: filtered.length,
    activeIndex,
    setActiveIndex,
    onEnter: () => activeTxn && setDetailTxn(activeTxn),
    // 편집 컨트롤은 settled 가 아닌 행에만 존재한다(DoD 7). 편집 UPDATE API 는
    // 후속이므로 지금은 상세를 열어 원본을 확인하게 한다.
    onEdit: () => activeTxn && activeTxn.status !== 'settled' && setDetailTxn(activeTxn),
    onSearch: () => searchRef.current?.focus(),
    onEscape: () => {
      setDetailTxn(null);
      searchRef.current?.blur();
    },
  });

  if (loadFailed) {
    return (
      <main className={styles.errorPage}>
        <p role="alert" className="negative">{lastError}</p>
        <button type="button" className="primary" onClick={() => loadAll().catch(() => {})}>
          다시 시도
        </button>
      </main>
    );
  }

  const topbar = (
    <Topbar
      ref={searchRef}
      period={period}
      periods={['', ...periods]}
      onPeriod={setPeriod}
      query={query}
      onQuery={setQuery}
      theme={theme}
      onToggleTheme={toggle}
    />
  );

  const sidebar = (
    <>
      <AccountTree accounts={accounts} selectedId={selectedAccount} onSelect={setSelectedAccount} />
      <BalanceSummary accountName={accountName} />
    </>
  );

  const main = (
    <>
      {socket && !socketConnected && (
        <p className={styles.offline} role="status">실시간 연결 끊김 — 잔액이 최신이 아닐 수 있습니다</p>
      )}
      <div className={styles.tableArea}>
        <LedgerTable
          rows={filtered}
          accountName={accountName}
          activeIndex={activeIndex}
          onSelect={(i) => {
            setActiveIndex(i);
            setDetailTxn(filtered[i]);
          }}
          onEdit={isSettled ? undefined : (t) => setDetailTxn(t)}
        />
      </div>

      {/* 합계 행 = 이 화면의 푸터(§2.3). sticky 하단 고정. */}
      <div className={styles.totals} role="row" aria-label="합계">
        <span className={styles.totalsLabel}>합계 ({filtered.length}건)</span>
        <Money minor={totals.debit} tone="debit" />
        <Money minor={totals.credit} tone="credit" />
      </div>

      {/* settled 기간에는 수기 입력 폼을 렌더링하지 않는다 (DoD 7) */}
      {!isSettled && (
        <section className={styles.entry} aria-label="수기 거래">
          <h2 className={styles.entryTitle}>수기 거래</h2>
          <TxnForm accounts={accounts} onSubmit={addTxn} />
        </section>
      )}

      <section className={styles.entry} aria-label="명세서 업로드">
        <h2 className={styles.entryTitle}>명세서 업로드</h2>
        <IngestPanel accounts={accounts} onDone={() => loadAll().catch(() => {})} />
      </section>

      {lastError && <p role="status" className={`${styles.notice} muted`}>{lastError}</p>}
    </>
  );

  return (
    <AppShell
      topbar={topbar}
      sidebar={sidebar}
      main={main}
      inspector={
        detailTxn && (
          <Inspector txn={detailTxn} accountName={accountName} onClose={() => setDetailTxn(null)} />
        )
      }
    />
  );
}
